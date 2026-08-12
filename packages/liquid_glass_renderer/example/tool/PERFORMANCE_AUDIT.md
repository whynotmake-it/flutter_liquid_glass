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
- Ancestor motion no longer rebuilds `ImageFilter.shader`. Flutter copies
  float uniforms at filter creation (`ReusableFragmentShader::as_image_filter`)
  but keeps sampler bindings live, so the filter-to-matte affine mapping is a
  persistent 2×1 RGBA32F texture updated during compositing. That keeps the
  layer's `RepaintBoundary` intact and avoids the delayed-disposal spike from
  Flutter issue #138627. Apple's Liquid Glass uses the same idea: a persistent
  `glassBackground` filter graph whose SDF/parameter inputs are live layers
  (`CASDFLayer` / `SDFPortalLayer`), not rebuilt CAFilters.
- Blend groups and shapes no longer push empty `alwaysNeedsAddToScene`
  tracking layers. The layer's compositing hook polls relative transforms, so
  ancestor motion does not cross the repaint boundary, while in-layer motion
  still rebuilds geometry. Independent layers also skip unused glow tickers,
  empty shadow render objects, and generic `ClipPath` in favor of Impeller's
  specialized clip layers.
- Geometry renderers share one frame-scoped `HostBuffer`, reuse a packed
  uniform `ByteData`, and keep the color attachment on `LoadAction.dontCare`
  because the full-screen quad writes every pixel.
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

Compare `independent16Motion` and `ancestorTranslatedLayer` against the
2026-08-11 medians on the same runner. The live coordinate texture should drop
raster time and peak footprint if native filter churn was the remaining cost.
If those scenarios are still far from `grouped16Motion` / `staticSingle`:

1. **Cull sparse shape layers.** Compare dense and window-spanning layouts at
   1/2/4/8/16 shapes. Add conservative AABB rejection or spatial bins only if
   the spread/dense delta confirms SDF evaluation is the bottleneck.
2. **Share the blurred backdrop.** Each independent layer still runs its own
   `ImageFilter.compose(blur, shader)` even when `BackdropKey` shares the
   capture. A single downsample/blur sampled by every glass is how Apple
   amortizes `CABackdropLayer`. Flutter cannot bind an arbitrary GPU texture
   as the ImageFilter input, so this needs an engine-level or layer-tree
   structure change.
3. **Evaluate singular-shape specialization last.** A one-shape pipeline removes
   loop and group-marker overhead, but static geometry is already cached and the
   final backdrop/refraction pass may dominate. Measure dynamic oval, rounded
   rectangle, and superellipse cases separately before adding shader variants.

## Required comparisons

- `baselineMotion` versus `ancestorTranslatedLayer`
- `translatedSingle` versus `scaledRotatedSingle`
- `independent16Motion` versus `grouped16Motion` (filter reuse vs shared pass)
- fake 1/4/8/16 shape ladders with blur-only, saturation-only, and combined
  filtering, both grouped and ungrouped
- dense versus sparse 1/2/4/8/16 real shapes at constant total shape area
- small and 1024→2048 resizing under the internal bucketing heuristic

All scenarios, including fake glass, run on Impeller so backend startup and
process baselines remain comparable. Attribute deltas within the same scenario
family; fake glass intentionally bypasses only the Flutter-GPU geometry pass.
