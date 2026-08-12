# Native macOS benchmark harness

Run `./tool/benchmark.sh` from the example directory. The harness builds one
dedicated profile executable, then runs every scenario three times in a fresh
uninstrumented process per repetition for frame and Mach-memory metrics.
A failing scenario run is recorded in the summary and the harness continues
with the remaining scenarios instead of aborting.

See [PERFORMANCE_AUDIT.md](PERFORMANCE_AUDIT.md) for the prioritized,
benchmark-driven optimization backlog. See
[apple_match/README.md](apple_match/README.md) for the Apple-matching
scorecard plan.

Every run records three sources, none of which needs Instruments:

- Flutter engine frame build/raster/total timings.
- Mach task memory (`phys_footprint`, resident, peak resident, internal,
  compressed, and virtual bytes) sampled by a native Swift timer every 100 ms.
  Samples cross the platform channel only after measurement. `phys_footprint` is the
  primary memory metric because it includes native and graphics allocations
  omitted by Dart heap telemetry.
- In-process GPU timing: the Runner interposes Metal command-buffer creation
  and reads each completed buffer's `gpuStartTime`/`gpuEndTime` (full-precision
  doubles straight from Metal). GPU busy for a measure window is the union of
  those execution spans — concurrent buffers are never double-counted, though
  idle gaps inside a single buffer's span count as busy, a slight but
  run-stable overcount. Per-frame GPU time (busy ÷ rendered frames) is the
  comparison metric because it is refresh-rate invariant. The channel covers
  every submitted buffer (Impeller rendering, Flutter GPU geometry, backdrop
  filters) with no kernel event buffer to overflow, which is why it replaces
  xctrace in the gate path; it stays informational until its noise floor is
  calibrated (see `_inProcessGpuFrameCvLimit` in the parser). On a non-Metal
  host the channel degrades to "unavailable" and never fails the run.

Runs require the display to stay awake: when it sleeps, the macOS embedder
stops delivering vsync and the app silently stops rendering.

Artifacts are written to `build/benchmark`: raw scenario JSON, logs, any
opt-in trace exports, and a combined Markdown/JSON summary.

## Appendix: opt-in xctrace attribution

Instruments Metal System Traces are opt-in, on-demand attribution tooling
(disabled by default; set `LIQUID_GLASS_BENCHMARK_TRACE_SCENARIOS` to record
specific scenarios). Traced GPU busy, per-frame GPU time, and Metal
allocation metrics are informational only and are never enforced: the kdebug
rolling buffer retains a fixed event count, not a fixed duration, so capture
density varies per run by design and cannot gate. A traced run attaches to
the exact PID of a dedicated post-warmup process while the target
continuously emits timestamped adjacent half-second workload intervals, each
ending with its rendered frame count and its in-process GPU busy time in
microseconds. The parser intersects the logged intervals with the retained
timeline, PID-filters GPU busy, and clips it to those windows; ProMotion
varies the refresh rate under tracing, so per-frame GPU time is the
comparable metric whenever frame counts exist.

As trace QA, the parser verifies capture uniformity before showing traced
GPU numbers: a complete capture emits a near-constant number of GPU
intervals per frame because every frame issues the same render passes.
The GPU instrument emits ~6,600 interval events/s on the
sixteen-independent-layer workload, saturating the kernel kdebug buffer
(one saturated recording retained only 2.576 s of a 60 s trace). The
check divides each frame-counted half-second window's clipped interval
count by its frame count and rejects the capture when the per-frame
coefficient of variation exceeds 30% or any window retained zero
intervals while others retained some. Calibrated on historical
artifacts, the known-unsound sixteen-layer capture scores CV 1.05
while historically consistent grouped16Motion captures score
0.18-0.24. A run needs at least three frame-counted windows for the
check. A rejected or unverifiable capture reports its GPU metrics as
unavailable with the reason in the summary, never as zero.

Traced artifacts include exported Metal GPU and resource-allocation XML,
`.trace` bundles, and trace-table-of-contents XML. The summary computes
traced GPU busy time by unioning overlapping vertex/fragment intervals, so
parallel channels are not double-counted. A trace failure is retained as a
log and is never silently converted to a zero GPU value; Metal counters
depend on the runner's hardware and Instruments permissions.
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
- `independent4Motion`, `independent8Motion`, and `independent16Motion`: a
  constant-per-layer-area ladder of own-layer grids for per-layer GPU cost.
  When traces are collected on demand, the lower rungs keep the traced event
  rate below the kdebug saturation threshold, so their captures pass the
  uniformity check; the sixteen-layer rung is expected to report GPU as
  unavailable on saturated captures while raster and footprint gates still
  apply.
- `independent16SharedBackdrop`: the same sixteen own layers sharing one
  backdrop capture, isolating per-layer geometry from repeated backdrop cost.
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
paths when the system SDK is not the repository's Flutter 3.44.x SDK. Set
`LIQUID_GLASS_BENCHMARK_TRACE_TEMPLATE` to override the default Xcode
`Metal System Trace` template. The native trace uses 500 ms workload
windows by default; override this with
`LIQUID_GLASS_BENCHMARK_TRACE_MEASURE_MILLISECONDS`. Set
`LIQUID_GLASS_BENCHMARK_REPETITIONS` to
override the default three repetitions. `xctrace` finalization is unbounded:
a short rolling trace of the sixteen-independent-layer workload can take more
than five minutes to save on an idle machine. A wall-clock watchdog terminates
`xctrace` only after the recording time limit plus
`LIQUID_GLASS_BENCHMARK_TRACE_FINALIZE_TIMEOUT` (default 600 s); a fired
watchdog fails the attempt and is retried in a fresh process, never treated
as a successful empty trace. Attaching the Metal data source routinely takes
20-40 s before `xctrace` reports a started recording, so the start banner and
tracing-started notification share
`LIQUID_GLASS_BENCHMARK_TRACE_START_TIMEOUT` (default 180 s); killing
`xctrace` during attach wedges the daemon-side session and starves the next
recording, which is why the budget is generous and a failed attempt waits
`LIQUID_GLASS_BENCHMARK_TRACE_ATTEMPT_COOLDOWN` (default 30 s) before the
retry. A trace whose Metal GPU interval table has no rows is likewise
rejected and retried: a wedged Instruments data source (for example after a
force-terminated recording) still saves a well-formed but empty bundle, which
must never pass validation. Keep the default 60 s recording limit and 21 s
rolling window for traced runs: the retained timeline shrinks with kdebug
event density, and the sixteen-independent-layer workload retains only about
0.1 s of a 3 s rolling window — far below the 450 ms alignment floor — while
the default window retains about 18 s of the same recording. GPU intervals
are measured by their own duration column, never the CPU-to-GPU start
latency column that shares the same serialized element name. Set
`LIQUID_GLASS_BENCHMARK_CAPTURE_NATIVE_TRACE=false` for a diagnostic
frame/native-memory-only run when validating an `xctrace` failure; CI must not
use this escape hatch. Set `LIQUID_GLASS_BENCHMARK_ENFORCE=true` to fail when
any scenario's p99 raster time exceeds 16.67 ms, retained native footprint
exceeds 64 MB, one native memory sample grows by more than 64 MB, the
three-repetition raster-p95 or footprint-peak CV exceeds 15%, or a scenario
run fails or is missing repetitions. Pre-measurement and cooldown memory
stability are reported as informational metadata and never gate. CI enforces
these gates after preserving the raw reports.

Compare motion deltas against
`baselineMotion`; FakeGlass scenarios compare against `fakeStatic`. Compare
`resizeAnimated` with `layerChurn` before attributing a spike.
Hosted runners vary, so the summary reports medians and coefficients of
variation for raster p95, in-process GPU per-frame time, and peak footprint;
only the raster and footprint CVs gate until the GPU channel is calibrated. The summary also lists every rejected GPU capture and
its reason under "GPU capture soundness", memory-unstable runs under
"Memory stability", and failed scenario runs under "Scenario failures". PR
decisions should compare base and head on the same runner;
historical absolutes are supporting evidence only.
