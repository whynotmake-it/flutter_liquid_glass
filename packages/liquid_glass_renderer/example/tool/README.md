# Native macOS benchmark harness

Run `./tool/benchmark.sh` from the example directory. The harness builds one
dedicated profile executable, then runs every scenario three times in two fresh
processes per repetition: an uninstrumented process for frame and Mach-memory
metrics, then an identical process to which Instruments attaches for Metal tracing.
This avoids Instruments memory inflation and provides repeatability evidence.

See [PERFORMANCE_AUDIT.md](PERFORMANCE_AUDIT.md) for the prioritized,
benchmark-driven optimization backlog.

The harness records three complementary sources:

- Flutter engine frame build/raster/total timings.
- Mach task memory (`phys_footprint`, resident, peak resident, internal,
  compressed, and virtual bytes) sampled by a native Swift timer every 100 ms.
  Samples cross the platform channel only after measurement. `phys_footprint` is the
  primary memory metric because it includes native and graphics allocations
  omitted by Dart heap telemetry.
- An Instruments Game Performance trace attached to the exact PID of a
  dedicated trace process after its warmup. A pre-registered Darwin
  notification opens the measurement gate only after recording starts. Since
  Xcode 26 initializes Metal streams lazily, the target emits repeated exact
  intervals; the parser accepts only a full interval with overlapping target
  GPU work. This template exposes the Metal GPU/resource tables. Xcode 26.4 has
  also been observed hanging after reaching the time limit while saving both
  `Game Performance` and `Game Performance Overview`; this is treated as a
  trace failure, never as zero GPU use. GPU busy is filtered to the
  target PID and clipped to the accepted interval. Metal allocation/free events
  are counted only inside it; raw traces preserve labels, lifetimes, and native
  backtraces for deeper attribution.

Artifacts are written to `build/benchmark`: raw scenario JSON, exported Metal
GPU and resource-allocation XML, `.trace` bundles, trace-table-of-contents XML,
logs, and a combined Markdown/JSON summary. The summary computes process GPU
busy time by unioning overlapping vertex/fragment intervals, so parallel
channels are not double-counted. A trace failure is retained as a log and is
never silently converted to a zero GPU value; Metal counters depend on the
runner's hardware and Instruments permissions.
Portable CI output calls this GPU execution/busy time rather than "GPU cycles":
Apple's raw Metal counter profiles are not supported on every Apple Silicon
device or hosted runner. The complete trace remains available for supported
local counter profiles.

## Scenarios and attribution

- `baselineMotion`: identical animated content without glass.
- `staticSingle`: retained texture cost without geometry invalidation.
- `translatedSingle`: moving glass and geometry rebuild cost.
- `ancestorTranslatedLayer`: moves the complete layer and verifies that its
  local geometry matte is reused.
- `scaledRotatedSingle`: transform correctness and non-axis-aligned work.
- `grouped4Motion`, `grouped8Motion`, and `grouped16Motion`: a constant-total-
  area ladder for blend-group shader scaling.
- `independent16Motion`: sixteen own layers for grouped-versus-independent cost.
- `sparse16Motion`: sixteen equal shapes spread across the viewport.
- `relativeBlendMotion`: relative translation and non-uniform stretch inside a
  blend group, covering the transform regression seen in the example.
- `dynamicBlend16`: animates blend radius across a sixteen-shape group.
- `resizeAnimated`: continuous resizing through the renderer's internal
  grow-only, physical-pixel-bucketed matte heuristic.
- `layerChurn`: repeated renderer/layer creation and disposal; growth isolated
  here implicates lifecycle retention.
- `largeStatic`: steady-state native cost of a 2048×2048 Flutter-GPU matte.
- `largeResize`: 1024–2048 animated matte growth, designed to expose in-flight
  Metal texture allocation spikes and delayed retirement.
- `fakeStatic` and `fakeLarge`: FakeGlass on Impeller, providing a baseline and
  a 2048×2048 stress case without the Flutter-GPU geometry pass.

Use environment variables to shorten or focus local runs, for example:

```sh
LIQUID_GLASS_BENCHMARK_SCENARIOS="baselineMotion resizeAnimated scaledRotatedSingle" \
LIQUID_GLASS_BENCHMARK_MEASURE_SECONDS=20 \
./tool/benchmark.sh
```

Set `LIQUID_GLASS_FLUTTER_BIN` and `LIQUID_GLASS_DART_BIN` to absolute SDK
paths when the system SDK is not the repository's Flutter 3.44+ SDK. Set
`LIQUID_GLASS_BENCHMARK_TRACE_TEMPLATE` to override the default Xcode
`Game Performance` template. Set `LIQUID_GLASS_BENCHMARK_REPETITIONS` to
override the default three repetitions. Set
`LIQUID_GLASS_BENCHMARK_CAPTURE_NATIVE_TRACE=false` for a diagnostic
frame/native-memory-only run when validating an `xctrace` failure; CI must not
use this escape hatch. Set `LIQUID_GLASS_BENCHMARK_ENFORCE=true` to fail when any scenario's p99 raster
time exceeds 16.67 ms, retained native footprint exceeds 64 MB, or one native
memory sample grows by more than 64 MB. CI enforces these gates after
preserving the raw reports and traces.

CI uploads the complete trace bundles. Compare motion deltas against
`baselineMotion`; FakeGlass scenarios compare against `fakeStatic`. Compare
`resizeAnimated` with `layerChurn` before attributing a spike.
Hosted runners vary, so the summary reports medians and coefficients of
variation for raster p95, GPU busy, and peak footprint. PR decisions should
compare base and head on the same runner; historical absolutes are supporting
evidence only.
