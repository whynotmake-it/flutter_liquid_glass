# Performance audit

This is the prioritized backlog for the native benchmark harness. Every change
should be compared against the relevant control scenario on the same runner;
visual output and native `phys_footprint` remain regression gates.

## Current measured state (2026-08-11)

A stabilized three-repetition macOS profile run used profile-mode
Impeller/Metal and native Mach `phys_footprint` sampling. A separate rolling
Metal System Trace validated exact, process-filtered GPU attribution.

- Right-sizing each Flutter GPU uniform host buffer removed about 66 MB from
  the sixteen-independent-layer case and reduced raster p95 from roughly
  12.05 ms to 6.82 ms in matched runs.
- Sixteen independent animated layers still use about 588 MB peak native
  footprint, versus about 365 MB for one static glass. Their latest raster p95
  median is 6.57 ms, with a 19.2% CV and one 8.95 ms outlier, so this workload
  is not yet a reliable production result.
- Sixteen shapes in one layer remain dramatically cheaper (about 386 MB and
  1.59 ms raster p95 in the matched run). Sharing only the backdrop capture
  across sixteen independent layers barely changed memory, attributing the
  remaining growth to per-layer Flutter/Metal filter state.
- A validated static-single Metal trace used an exact 0.897 s target-process
  window: 1,512 GPU intervals, 162.8 ms unioned busy time (18.1%), and 0.64 ms
  interval p95. The enforced parser accepted the trace with no missing-data
  fallback.

These results support prioritizing independent-layer filter/driver state. The
geometry matte is small after host-buffer right-sizing, and shared backdrop
capture does not account for the remaining per-layer footprint.

## Implemented in the API audit

- Whole-layer ancestor transforms reuse the local geometry matte. The
  `ancestorTranslatedLayer` scenario distinguishes this fast path from moving
  a shape relative to its layer.
- Fake glass composes blur, saturation, and tint into one backdrop-filter pass
  instead of nesting blur and saturation captures.
- Static benchmark scenarios no longer rebuild under the global animation
  controller.
- `BackdropKey` sharing is explicit, opt-in, supported by both rendering paths,
  and independent from liquid geometry blend groups.
- Geometry mattes grow in 64-physical-pixel buckets and retain their high-water
  allocation, while larger backdrop-filter bounds use non-retaining buckets.
  Native controls showed that replacing a matte during rotation reintroduced a
  167.5 MB step, while exact saveLayer bounds churned every frame. The policy is
  differentiated internally rather than exposed in the consumer API.
- Metal GPU intervals are PID-filtered and clipped to at least 450 ms of exact
  overlap between a timestamped app workload interval and Xcode's retained
  rolling timeline. Allocation/free events are counted only inside that
  interval; peak-live/retained labels are withheld until cross-window resource
  identities and lifetimes can be matched correctly.
- Mach memory/frame metrics and Metal traces run in separate fresh processes;
  combined collection made Instruments add and reclaim roughly 160–180 MB in
  the target, creating false native-memory spikes.
- Frame timing uses real engine vsync in a dedicated profile entry point. Mach
  sampling runs on a native timer, followed by a five-second cooldown whose
  final-window median and slope determine whether memory actually settled.
- Scenarios run three times by default. Enforced results require the requested
  count and reject raster/GPU/footprint coefficients of variation above 15%.
- The final runtime-effect shader uses a fixed half-pixel edge feather because
  Flutter runtime effects do not expose `fwidth`, including under Impeller.
  This removes derivative work but can reduce edge stability under local
  scaling; transformed visual cases remain a regression gate.

## Next measurements

1. **Cull sparse shape layers.** Compare dense and window-spanning layouts at
   1/2/4/8/16 shapes. Add conservative AABB rejection or spatial bins only if
   the spread/dense delta confirms SDF evaluation is the bottleneck.
2. **Cache real-path filters and transformed clip paths.** Benchmark a static
   layer repainted by unrelated foreground animation, then cache by settings
   and geometry revision if raster CPU/allocation remains material.
3. **Reuse uniform packing buffers.** A fixed `ByteData`/`Float32List` staging
   buffer can reduce Dart allocation during 16-shape stretch churn.
4. **Evaluate singular-shape specialization last.** A one-shape pipeline removes
   loop and group-marker overhead, but static geometry is already cached and the
   final backdrop/refraction pass may dominate. Measure dynamic oval, rounded
   rectangle, and superellipse cases separately before adding shader variants.

## Required comparisons

- `baselineMotion` versus `ancestorTranslatedLayer`
- `translatedSingle` versus `scaledRotatedSingle`
- fake 1/4/8/16 shape ladders with blur-only, saturation-only, and combined
  filtering, both grouped and ungrouped
- dense versus sparse 1/2/4/8/16 real shapes at constant total shape area
- small and 1024→2048 resizing under the internal bucketing heuristic

All scenarios, including fake glass, run on Impeller so backend startup and
process baselines remain comparable. Attribute deltas within the same scenario
family; fake glass intentionally bypasses only the Flutter-GPU geometry pass.

## Current redesign audit status (2026-08-25)

Platform smoke gates currently pass with Flutter 3.47.1:

- `flutter build apk --debug` succeeds with Android Impeller and Flutter GPU
  manifest flags enabled.
- `flutter build macos --profile` succeeds with the macOS Impeller and Flutter
  GPU plist flags enabled.
- The focused example widget/YAML/loupe tests and the full non-golden workflow
  pass.

The final performance ratio is intentionally still open. Existing three-run
artifacts are useful historical controls, but they were captured across
different renderer/perf revisions and cannot be presented as a clean
before/after pair for the final state. A final same-runner macOS profile
comparison is required before claiming the ≤5% gate; the Android build is a
platform smoke check, not a substitute for that timing evidence.

The macOS build initially failed because the generated workspace omitted
`Pods/Pods.xcodeproj`; Xcode consequently never produced the
`path_provider_foundation` framework imported by the generated plugin
registrant. Regenerating the workspace with `pod install` restored that project
reference, and a clean Xcode-derived-data Profile build passed. This is a build
integration repair, not a renderer change.

## 2026-08-25 renderer optimization experiments (rejected)

Two focused measurements evaluated candidates; neither is part of the current
renderer and neither is the final gate audit.

- A conservative smooth-union AABB lower bound was evaluated to skip exact
  superellipse evaluation only when `boxLowerBound >= currentDistance + blend`.
  Its first implementation used an unsigned inside-box distance; after fixing
  that correctness issue, there was still no valid end-to-end proof of a win.
  The cull was reverted and its grouped timings are historical only.
- A shared coordinate atlas replaced one 2×1 texture overwrite per animated
  layer with one overwrite per atlas page. The valid three-repetition
  independent16 run produced raster p95 5.20/5.23/5.28 ms (median 5.23 ms,
  CV 0.7%), peak footprints 1036.9/1047.8/1055.5 MB (median 1047.8 MB,
  CV 0.9%), and about 97,269 command-buffer submissions in the one completed
  retry. The pre-atlas focused control was about 111,760 submissions and
  1,061 MB peak. This is a meaningful attribution signal, not a passed ≤5%
  before/after gate. Raster p95 did not improve and the atlas introduced extra
  reader lifecycle/per-frame preparation work, so it was reverted.

The atlas implementation and its focused identity/row test were removed from
the current renderer; no atlas texture, reader registry, or coordinate-row
uniform remains in shipped code.

The focused no-trace audit in `build/benchmark-final-focused-current` measured
median per-run raster means of 1.27 ms (`baselineMotion`), 1.36 ms
(`grouped16Motion`), 3.33 ms (`independent16Motion`), and 1.48 ms
(`layerChurn`); corresponding median raster p95 values were 1.53, 1.91, 5.28,
and 2.08 ms. All four scenario families exceeded the repeatability limit, so
these values are diagnostic only. Independent16 peak footprint remained
approximately 0.93–1.12 GB, and no final ≤5% before/after claim is made.

The transparency harness now enforces the same no-hidden-work discipline for
material fitting: baseline tint RGB is copied exactly, and only `tintAlpha`
and `frost` may vary by slider position. Its structural constraint audit is
recorded alongside the fit scorecards.

## SDF and shader-branch decision (2026-08-26)

Flutter 3.47.1's Impeller `uber_sdf.frag` renders rounded superellipses with
the same six-step bounded superellipse solve used by this package. It also
branches for RSE octant selection and the circular-arc versus superellipse
section. Therefore a branchless rewrite is not an optimization assumption:
per-fragment branches may diverge, while evaluating both sides of a `mix`
can cost more. Keep the branches that select the mathematically required
piecewise SDF.

In the shipped geometry shader, `hasFaceSpread` is a draw-uniform fast path,
but it only avoids the extra `halfMinor` bookkeeping in `sceneSample`; both
paths still evaluate each shape once. The zero-chromatic-aberration path and
coverage early returns avoid texture/downstream work and are the more credible
fast paths. The SDF matte is persistent and is rebuilt only when geometry or
settings are dirty, so no SDF bottleneck claim is justified without a targeted
geometry-pass A/B measurement.
