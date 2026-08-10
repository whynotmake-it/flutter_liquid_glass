# Performance audit

This is the prioritized backlog for the native benchmark harness. Every change
should be compared against the relevant control scenario on the same runner;
visual output and native `phys_footprint` remain regression gates.

## Current measured state (2026-08-11)

A three-repetition macOS profile run used a six-second warmup and eight-second
measurement on Impeller/Metal. The complete report is in
`../build/benchmark-current-long/summary.md`.

- Sixteen independent glass layers are the clearest current bottleneck:
  raster p95 was 14.51–45.37 ms and native footprint was 654.5–667.8 MB
  (660.8 MB median, 1.0% CV). All three repetitions exceeded or approached the
  16.67 ms frame budget at p99.
- Sixteen shapes in one blend group used 392.1–472.2 MB (455.3 MB median) and
  had a 6.58 ms median raster p95. Grouping therefore saves about 205 MB of
  peak native footprint versus sixteen independent layers in this run.
- A static single glass used a 369.8 MB median peak footprint; animated resize
  used 391.1 MB. Sparse sixteen-shape glass used 409.4 MB median but had one
  454.0 MB outlier.
- Frame p95 CV remains 49.8–88.6% across these scenarios, so absolute raster
  medians are directional and must not gate CI yet. Footprint is much more
  repeatable for the glass workloads (1.0–9.6% CV); the no-glass control had a
  159.1 MB one-sample outlier and is not a reliable absolute memory baseline.
- Native GPU attribution is still unavailable. On this local Xcode 26.4 host,
  both `Game Performance` and `Game Performance Overview` reach their bounded
  time limit and then hang while saving an attached trace. The harness fails
  closed; it does not report missing GPU intervals as zero.

These results support prioritizing independent-layer and per-layer texture
cost. They do not yet distinguish geometry-pass work from backdrop/filter work;
that causal split requires a successfully exported, PID-filtered Metal trace.

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
- Metal GPU intervals are PID-filtered and clipped to a complete signpost
  interval. Repeated intervals adapt to Xcode 26's lazy Metal stream without a
  machine-specific sleep. Allocation/free events are counted only inside that
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
