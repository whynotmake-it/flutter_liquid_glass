# Shared-layer performance optimization

Measured on macOS in profile mode with Flutter 3.47.1 and Impeller/Metal.
Each comparison scenario used a fresh process, a 2 s warm-up, a 4 s measure
window, and three repetitions. Native Metal attribution used an 8 s focused
trace and the benchmark's exact workload-window intersection.

## Retained changes

Uniform translation of every geometry node in a `LiquidGlassLayer` now reuses
the persistent Flutter-GPU SDF matte. The renderer accepts the fast path only
when:

- every registered geometry render object is the same;
- each geometry node's matte revision is unchanged (paint-only metadata may
  refresh without invalidating it);
- every geometry transform differs by the same translation; and
- the aggregate bounds moved by exactly that translation.

Scale, rotation, resize, visibility/material changes, and relative shape
motion continue to rebuild the matte. The translated matte bounds and material
center update normally, so Flutter snapshots a conventional native image
filter rather than observing mutable filter inputs.

Geometry nodes now carry a monotonic matte revision. Translation validation
compares that integer instead of deeply comparing every shape and updates
reusable transform snapshots in place. Visibility crossing zero increments
the revision because it changes SDF participation; tint, nonzero visibility,
shadow, and child-paint metadata do not. A Flutter-engine microbenchmark of the
removed operations measured 16-shape deep equality at 735.8 ns versus 5.7 ns
for revision equality, and `Matrix4.clone()` at 14.3 ns versus 6.8 ns for
`setFrom`. This sub-microsecond saving is intentionally not claimed from noisy
whole-frame percentiles.

Multi-shape geometry rebuilds now test a conservative transformed AABB lower
bound before evaluating each expensive exact SDF. If the lower bound is beyond
the current smooth-union support, that primitive mathematically cannot change
the result and is skipped. Evaluation order, exact SDFs, material contributor
selection, and visible pixels remain unchanged. This is especially useful for
continuous superellipses, whose exact Flutter-matched SDF contains a six-step
transcendental solve.

## Before and after

Medians from three repetitions:

| Scenario | Raster p95 before → after | GPU/frame before → after | Peak footprint before → after |
|---|---:|---:|---:|
| `grouped4Motion` | 1.94 → 2.14 ms | 2.04 → 1.41 ms (-30.9%) | 453.1 → 418.5 MB |
| `grouped8Motion` | 1.87 → 2.13 ms | 2.12 → 1.43 ms (-32.5%) | 458.4 → 441.4 MB |
| `grouped16Motion` | 1.87 → 2.11 ms | 2.54 → 1.41 ms (-44.5%) | 464.3 → 423.3 MB |
| `independent16Motion` | 7.71 → 7.71 ms | 6.91 → 6.49 ms | 888.1 → 887.2 MB |

The independent control's baseline GPU CV was 11.8%, so its 6.1% movement is
not attributed to this shared-layer-only change. Grouped GPU CV after the
change was 0.9–3.0%. The grouped raster p95 increase (0.20–0.26 ms) is retained
as an explicit tradeoff: eliminating a large GPU pass is worthwhile for the
target path. Revision validation removes most avoidable Dart work from that
check, although whole-frame p95 remains around 2.1–2.2 ms on this host.

## Dynamic SDF rebuild results

The bounds-culling A/B used the same Flutter 3.47.1 profile executable shape,
fresh processes, 2 s warm-up, 4 s measurement, and three repetitions per
scenario. Medians:

| Scenario | Raster p95 before → after | GPU/frame before → after | Peak footprint before → after |
|---|---:|---:|---:|
| `dynamicBlend16` | 1.83 → 1.79 ms | 3.60 → 3.08 ms (-14.4%) | 452.6 → 435.7 MB |
| `sparse16Motion` | 1.80 → 1.77 ms | 3.76 → 2.88 ms (-23.4%) | 440.9 → 441.1 MB |
| `relativeBlendMotion` | 1.90 → 1.89 ms | 1.66 → 1.67 ms | 435.5 → 439.8 MB |
| `resizeAnimated` | 1.80 → 1.76 ms | 1.84 → 1.84 ms | 621.4 → 620.2 MB |

The two-shape and single-shape resize controls remain effectively unchanged,
as expected. The gain grows with the number of exact SDF evaluations that can
be disproved by cheap bounds.

The final retained matrix also recorded 1.41 ms/frame for uniformly translated
16-shape glass, 1.49 ms for per-shape color, 1.59 ms for animated per-shape
visibility, 6.91 ms for sixteen independent filters, 4.41 ms for sixteen
independent filters sharing a backdrop key, and 1.80 ms for a 2048-square
static surface. All three-run p99 raster, retention, allocation-step, and
repeatability gates passed.

## Metal attribution

The retained candidate produced valid, process-filtered Metal traces:

| Scenario | Traced GPU/frame | Traced GPU busy | Interval p95 |
|---|---:|---:|---:|
| `grouped16Motion` | 1.39 ms | 16.8% | 0.33 ms |
| `realBlurOnly` | 1.28 ms | 15.4% | 0.33 ms |
| `realLightingOnly` | 0.96 ms | 11.5% | 0.33 ms |

Blur therefore adds about 0.32 ms/frame over the lighting-only control on this
machine, but does not dominate the complete remaining cost. The final material
and compositor path still accounts for most of the retained ~1.4 ms/frame.

## Rejected experiments

Additional deliberately aggressive experiments were measured and removed:

1. A translation-only final-shader permutation removed one coordinate-texture
   read and general affine math. It regressed grouped GPU time from ~1.41 to
   ~1.55 ms/frame and added another runtime shader/pipeline with no visual
   benefit.
2. Keeping the native filter snapshot stable while mutating its coordinate
   texture held grouped GPU near ~1.55 ms/frame but increased grouped fresh-
   process footprint to about 600 MB. This unpredictable compositor retention
   is unacceptable.
3. A uniform identity-color-transfer branch removed `pow`, saturation, and
   vibrancy arithmetic, but its predicates made the focused path slightly
   slower: 1.05 versus 1.03 ms/frame across five long runs. It was removed.
4. A final-pass interior-UV branch and duplicate-contour algebra reduction were
   indistinguishable in five-run A/B measurements (grouped 1.43 versus 1.42
   ms/frame; toolbar 1.23 versus 1.23). They were removed rather than retained
   on source-level operation counts alone.
5. An L-infinity AABB bound avoided a square root but culled fewer exact SDFs.
   It measured 3.28 ms/frame on `dynamicBlend16`, slower than the retained
   Euclidean bound's 3.08 ms, and was removed.

Sparse-group partitioning was not implemented. The final sparse grouped case
cost 2.88 ms/frame, while sixteen independent layers sharing a backdrop key
still cost 4.41 ms/frame and 6.19 ms raster p95. On this workload, saved empty
pixels do not repay sixteen compositor filters/passes; conservative in-pass
culling captures the useful geometry saving without that penalty.

## Stretch and glow audit

`RawLiquidStretch` remains a single compositor transform. Its transform now
pins the edge opposite the drag direction, removing the old right/down bias
without adding a draw or layer. Opposite-direction extent is covered by a
regression test. `GlassGlow` is an independent optional canvas draw and is not
present in the grouped benchmark; folding it into the glass shader would add
work to every glass fragment, so no speculative change was retained.
