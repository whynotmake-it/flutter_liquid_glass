# Native macOS benchmark harness

Run `./tool/benchmark.sh` from the example directory. Every scenario runs in a
fresh profile-mode macOS process with Impeller and Flutter GPU enabled.

The harness records three complementary sources:

- Flutter engine frame build/raster/total timings.
- Mach task memory (`phys_footprint`, resident, peak resident, internal,
  compressed, and virtual bytes) sampled every 100 ms. `phys_footprint` is the
  primary memory metric because it includes native and graphics allocations
  omitted by Dart heap telemetry.
- An Instruments Metal System Trace attached to the Runner process. The app
  emits a `LiquidGlassBenchmark` signpost around the measured interval so GPU
  work can be correlated in Instruments. The automated GPU-busy calculation
  uses the app process's observed Metal interval span; the per-scenario warmup
  runs the same workload to keep that comparison representative.

Artifacts are written to `build/benchmark`: raw scenario JSON, exported Metal
GPU interval XML, `.trace` bundles, trace-table-of-contents XML, logs, and a
combined Markdown/JSON summary. The summary computes process GPU busy time by
unioning overlapping vertex/fragment intervals, so parallel channels are not
double-counted. A trace failure is retained as a log and is never
silently converted to a zero GPU value; Metal counters depend on the runner's
hardware and Instruments permissions.

## Scenarios and attribution

- `baselineMotion`: identical animated content without glass.
- `staticSingle`: retained texture cost without geometry invalidation.
- `translatedSingle`: moving glass and geometry rebuild cost.
- `scaledRotatedSingle`: transform correctness and non-axis-aligned work.
- `shared16Motion`: worst supported blend-group shader loop.
- `resizeChurn`: repeated render-target reallocations; growth implicates GPU
  texture retirement/allocation rather than ordinary frame rendering.
- `layerChurn`: repeated renderer/layer creation and disposal; growth isolated
  here implicates lifecycle retention.
- `largeStatic`: steady-state native cost of a 2048×2048 Flutter-GPU matte.
- `largeResize`: 1024–2048 animated matte growth, designed to expose in-flight
  Metal texture allocation spikes and delayed retirement.
- `fakeStatic` and `fakeLarge`: FakeGlass on Skia, providing a backend-specific
  baseline and a 2048×2048 stress case without Flutter GPU.

Use environment variables to shorten or focus local runs, for example:

```sh
LIQUID_GLASS_BENCHMARK_SCENARIOS="baselineMotion resizeChurn" \
LIQUID_GLASS_BENCHMARK_MEASURE_SECONDS=20 \
./tool/benchmark.sh
```

Set `LIQUID_GLASS_FLUTTER_BIN` and `LIQUID_GLASS_DART_BIN` to absolute SDK
paths when the system SDK is not the repository's Flutter 3.44+ SDK. Set
`LIQUID_GLASS_BENCHMARK_ENFORCE=true` to fail when the large-surface p99 raster
time exceeds 16.67 ms, retained native footprint exceeds 64 MB, or a resize
sample allocates more than 64 MB. CI enforces these gates after preserving the
raw reports and traces.

CI uploads the complete trace bundles. Compare deltas against
`baselineMotion`; FakeGlass scenarios compare against `fakeStatic` because Skia
and Impeller have different process baselines. Compare `resizeChurn` with
`layerChurn` before attributing a spike. Hosted runners can vary, so investigate
sustained memory growth and large within-run deltas before small absolute
differences.
