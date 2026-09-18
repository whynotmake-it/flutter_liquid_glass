# Native macOS benchmark harness

Run `./tool/benchmark.sh` from the example directory. The harness builds one
dedicated profile executable, then runs every scenario three times in a fresh
uninstrumented process per repetition for frame and Mach-memory metrics.
A failing scenario run is recorded in the summary and the harness continues
with the remaining scenarios instead of aborting.

See [PERFORMANCE_AUDIT.md](PERFORMANCE_AUDIT.md) for the prioritized,
benchmark-driven optimization backlog. See
[RENDERER_REVIEW_GUIDE.md](RENDERER_REVIEW_GUIDE.md) for the current renderer
diagram and the step-by-step stacked-PR review path. See
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

## Android GPU power harness (Pixel)

Frame time alone hides GPU load: a scene can hold 120 Hz while the GPU sits
at 100% just inside the frame budget, which still heats the phone and drains
the battery. This harness records the SoC GPU power rail
(`power.S2S_VDD_GPU_uws`, cumulative µW·s) as the ground-truth energy metric,
plus GPU-memory, CPU, display, DDR, and pack (`VBATT`) rails, GPU frequency
residency, per-UID GPU busy time, and Flutter raster percentiles.

It targets a Google Pixel 10 (PowerVR DXT, Impeller/Vulkan). Run it from the
example directory after creating the local analyzer venv once:

```sh
python3 -m venv tool/.venv-android-bench
tool/.venv-android-bench/bin/pip install perfetto
```

Default scenario family (app-like scrolling chrome plus a few existing
baselines), three interleaved repetitions, 5 s warmup / 20 s measure:

```sh
./tool/android_gpu_bench.sh scenarios --serial 58080DLCR001DP
```

Both subcommands take `--pin PIN` (default `172839`). Before the session
the harness sends `KEYCODE_WAKEUP` only (never `KEYCODE_POWER` / sleep).
If `dumpsys window` still reports `isKeyguardShowing=true`, it swipes up
and types the PIN. Each scenario launch also passes
`--ez trace-systrace true` so Impeller/Flutter timeline slices land in
the Perfetto trace (`atrace_apps` includes the example package). After
`MEASURE_BEGIN`, a Flutter `SUMMARY` with `frameCount` below 50% of
`measure_s × 100` is marked `failed:no-frames` and skipped by the
analyzer.

Isolation scenarios (same scrolling list + top bar + bottom pill as
`appScrollReal` unless noted):

- `appScrollRealSharedKey` — two `LiquidGlassLayer`s, stack wrapped in
  `BackdropGroup`, both layers `useBackdropGroup: true`
- `appScrollPlainBlurSharedKey` — `BackdropGroup` +
  `BackdropFilter.grouped` on both chrome pieces
- `appScrollPlainBlurCompose` — blur composed with a passthrough
  runtime-effect shader (`example/shaders/passthrough.frag`)
- `appScrollPlainBlurColor` — blur composed with a mild saturation
  `ColorFilter.matrix` (fake-glass filter shape)
- `appScrollRealNoFrost` — real glass with `frost: 0` (shader-only
  backdrop filter, no blur)
- `appScrollRealTopOnly` / `appScrollPlainBlurTopOnly` — top bar only
- `appScrollRealPillOnly` — bottom pill only
- `appIdlePlainBlur` / `appIdleFake` — idle variants of plain blur and
  fake
- `appScrollRealTabsStatic` — `appScrollRealTabs` with a stationary
  indicator (control for blend-group geometry rebuild)
- `appScrollPassthroughOnly` / `appScrollPassthroughTopOnly` —
  runtime-effect backdrop filter alone (no blur)
- `appScrollPlainBlurNestedPassthrough` /
  `appScrollPlainBlurNestedColor` — outer blur `BackdropFilter` whose
  child is a second `BackdropFilter` (`BlendMode.src`)
- `appScrollPlainBlurSigma4` / `appScrollPlainBlurSigma20` — σ=4
  (no Impeller downsample) vs σ=20 (1/4 downsample)
- `appScrollMatrixDownsamplePassthrough` — compose a 0.25 scale
  `ImageFilter.matrix` with the passthrough shader
- `appScrollTwoSaveLayers` — opaque chrome in `RepaintBoundary` +
  `Opacity(0.99)` (saveLayer, no backdrop readback)
- `appScrollColorFilterOnly` — saturation `ColorFilter` backdrop
  filter alone

`summary.md` / `summary.json` include a per-run raster-thread slice
profile (top 25 slice names by duration, with count/frame and mean µs)
from the app raster thread. The thread is the one whose name contains
`raster` / `io.flutter.raster`, or — when Pixel omits thread names —
the thread that emits `Rasterizer::DoDraw`. The Markdown appendix
prints repetition 1 of every scenario. Profile atrace includes engine
raster / `Canvas::saveLayer` / `QueueSubmit`; Impeller pass names such
as `FlipBackdrop` / `EntityPass` / `RuntimeEffectContents` are not
present in these traces.

A short smoke on the same device:

```sh
./tool/android_gpu_bench.sh scenarios \
  --serial 58080DLCR001DP \
  --scenarios "appScrollOpaque appScrollPlainBlur appScrollReal" \
  --repetitions 1 --warmup 3 --measure 8
```

Reuse an already-built profile APK with `--skip-build`. Artifacts land in
`build/android_gpu_bench/<timestamp>/` (`summary.md`, `summary.json`, and a
per-run folder with the Perfetto trace, sysfs snapshots, logcat, and the
Flutter `LIQUID_GLASS_BENCHMARK_SUMMARY` JSON).

Generic capture of any foreground app (for example ClickUp), with optional
synthetic scrolling:

```sh
./tool/android_gpu_bench.sh measure \
  --serial 58080DLCR001DP \
  --package com.clickup.app \
  --seconds 30 \
  --label clickup_scroll \
  --scroll
```

The harness pins 120 Hz, sets brightness to 128 (manual), and keeps the
screen awake, then restores the previous settings on exit (including Ctrl-C).
USB charging pollutes `/sys/class/power_supply/battery/current_now`, so that
sample is informational only. Power rails are SoC-level: put the phone in
airplane mode and do-not-disturb, and avoid other foreground apps, or
background work will leak into GPU/CPU/VBATT. Repetitions are interleaved
(`rep1` of every scenario, then `rep2`, …) so thermal drift is not confused
with a scenario effect.

## iOS power harness (iPhone, xctrace)

`ios_power/` records Instruments sessions of an installed build with the same
discipline as the Android harness: one launch per label, a thermal gate before
every run, USB only (xctrace cannot attach over Wi-Fi), interleaved labels.

```sh
IOS_UDID=<xctrace udid> DEVICECTL_ID=<devicectl id> BUNDLE=com.example.app \
  LAUNCH_ENV='{"GLASS_BENCH":"MODE"}' \
  tool/ios_power/ios_power_bench.sh power NEW_REAL:real NEW_FAKE:fake OFF:off
python3 tool/ios_power/parse_power_trace.py build/ios_power_bench/traces/NEW_REAL_r1_power.trace
```

- `power` uses the Power Profiler template. `parse_power_trace.py` prints
  duration-weighted means of Apple's per-process power-impact indexes (CPU,
  GPU, display, networking; unitless, ~1 Hz), CPU instructions/s, system frame
  rate, thermal state, charging state and battery drain %/h. There is no
  per-rail milliwatt reading on iOS; compare indexes between labels only.
- `metal` uses the Metal System Trace template; open the `.trace` in
  Instruments or export `metal-gpu-intervals` /
  `displayed-surfaces-per-second` with `xcrun xctrace export --xpath`.
- The app has to drive itself during the recorded window (navigate, scroll)
  from `LAUNCH_ENV` or a `TRIGGER_DEST` file in its Documents container; the
  harness never touches the UI. `ios_thermal_probe.sh` is the gate
  (`COOL_TO=Nominal` for stricter runs).
- Xcode 26.0 `xctrace export` segfaults intermittently; the scripts retry.

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
- `resizeAnimated`: continuous resizing with immutable, physical-pixel-bucketed
  matte generations. Unchanged geometry reuses its existing matte.
- `layerChurn`: repeated renderer/layer creation and disposal; growth isolated
  here implicates lifecycle retention.
- `largeStatic`: steady-state native cost of a 2048×2048 Flutter-GPU matte.
- `largeResize`: 1024–2048 animated matte growth, designed to expose in-flight
  Metal texture allocation spikes and delayed retirement.
- `largeShrinkSettled`: grows one matte to 2048×2048, shrinks it to 256×256
  before measurement, and isolates whether a high-water geometry allocation
  is released without continuous resize churn.
- `fakeStatic` and `fakeLarge`: FakeGlass on Impeller, providing a baseline and
  a 2048×2048 stress case without the Flutter-GPU geometry pass.
- `realLightingOnly` / `fakeLightingOnly`, `realBlurOnly` / `fakeBlurOnly`,
  and `realHighBlurOnly` / `fakeHighBlurOnly` isolate lighting and native blur
  costs at sigma 15 and sigma 40. The high-blur pair tests whether a fixed,
  strongly blurred source is viable for mixing over the sharp backdrop.
  `realSaturationOnly` / `fakeSaturationOnly`, and `realBlurSaturation` /
  `fakeBlurSaturation`: moving, same-settings pairs that attribute FakeGlass
  lighting, backdrop blur, saturation, and composed-filter costs directly.
- `realToolbarMaterial` / `fakeToolbarMaterial`: the moving Basic App default
  iOS 27 toolbar preset, including its blur, tint, saturation, and lighting.
- `realToFakeTransition`: mounts the real toolbar material, then switches the
  same layer to fake before measurement. It catches real geometry or coordinate
  textures retained by mode switching and is the focused Metal-resource trace
  scenario for measurement contamination.
- `grouped4Motion`, `fakeGrouped4Motion`, and `fakeUngrouped4Motion`: the
  four-shape real renderer, the fake renderer with one shared backdrop
  capture, and the historical independent-capture case. This
  separates retained shape lighting from the dominant multi-shape backdrop
  cost.

Use environment variables to shorten or focus local runs, for example:

```sh
LIQUID_GLASS_BENCHMARK_SCENARIOS="baselineMotion resizeAnimated scaledRotatedSingle" \
LIQUID_GLASS_BENCHMARK_MEASURE_SECONDS=20 \
./tool/benchmark.sh
```

Set `LIQUID_GLASS_FLUTTER_BIN` and `LIQUID_GLASS_DART_BIN` to absolute SDK
paths when the system SDK is not the repository's Flutter 3.47.x SDK. Set
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
must never pass validation. Keep the default 60 s recording limit for traced
runs. The script omits xctrace's rolling `--window` by default
(`LIQUID_GLASS_BENCHMARK_TRACE_WINDOW_SECONDS=0`): on macOS 26 a 21 s window
can truncate an 8 s recording to a roughly 1 s timeline that ends before the
gated workload begins. Set a positive window only after validating that the
selected Instruments set preserves overlap; an empty
`LIQUID_GLASS_BENCHMARK_TRACE_SCENARIOS` remains the opt-out/default that keeps
tracing disabled. GPU intervals
are measured by their own duration column, never the CPU-to-GPU start
latency column that shares the same serialized element name. Set
`LIQUID_GLASS_BENCHMARK_TRACE_WAIT_FOR_READY=false` for a short, high-density
probe: the harness waits for the app's normal post-warmup measurement marker
before attaching xctrace, then retains only traces that pass the same overlap
and intervals-per-frame checks. This mode improves attachment timing but does
not make independent16 traces inherently reliable; rejected captures remain
unavailable. Set
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
