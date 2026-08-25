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
