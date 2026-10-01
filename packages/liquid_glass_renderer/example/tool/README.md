# Example tooling

Run everything from the `example/` directory with Flutter 3.47.1 (Impeller
only).

| Path | What it is |
| --- | --- |
| `bench_scenes.sh` | The benchmark scene registry: suites shared by both runners. |
| `benchmark.sh` | Metal runner (macOS profile build). |
| `android_gpu_bench.sh` | Android runner (Pixel 10, power rails in mW). |
| `android_ab_bench.py` | Android A/B runner: installed arms interleaved, analyzed by `android_ab_analyze.py`. |
| `bench_analyze.sh` | One analyzer entry point for either runner's result directory. |
| `ios_power/` | iPhone Instruments power/Metal traces of an installed build. |
| `apple_match/` | Visual matching against iOS 27 references ([README](apple_match/README.md)). |
| `results/` | Committed benchmark and matching write-ups. |
| `RENDERER_REVIEW_GUIDE.md` | Renderer invariants and how to run the device suites. |

## Scenes

Both runners build `integration_test/benchmark_test.dart`; every scene is a
value of its `BenchmarkScenario` enum. `bench_scenes.sh` groups them into
suites, and both runners accept a suite or a list of scene names and reject
unknown names:

- `core` (default for both): the app-like scrolling chrome and idle scenes,
  plus `baselineMotion`, `realToolbarMaterial` and `fakeToolbarMaterial`.
- `app`: only the app-like scenes.
- `micro`: renderer microbenchmarks, one cost axis per scene.
- `all`: every scene in the enum.

Each scene logs `LIQUID_GLASS_BENCHMARK_MEASURE_BEGIN:<scene>` and `..._END`
around its measure window, and a `LIQUID_GLASS_BENCHMARK_SUMMARY:` (Android)
or `LIQUID_GLASS_BENCHMARK_JSON:` (Metal) line that the analyzers read.

### A/B builds

`LIQUID_GLASS_BENCHMARK_DART_DEFINES="A=1 B=2"` passes `--dart-define`s to
the build on both runners.

## Metal (macOS)

```sh
./tool/benchmark.sh                                    # core, 3 repetitions
LIQUID_GLASS_BENCHMARK_SCENARIOS=micro ./tool/benchmark.sh
LIQUID_GLASS_BENCHMARK_SCENARIOS="grouped4Motion largeResize" \
  LIQUID_GLASS_BENCHMARK_REPETITIONS=1 ./tool/benchmark.sh
```

It builds one profile executable, then runs each scene in a fresh process per
repetition and records Flutter frame timings, Mach task memory
(`phys_footprint` is the primary memory metric) and in-process Metal
command-buffer GPU time per frame. Keep the display awake: the embedder stops
delivering vsync when it sleeps. Results go to `build/benchmark/`. Other
knobs (`..._WARMUP_SECONDS`, `..._MEASURE_SECONDS`, `..._SKIP_BUILD`,
`..._ENFORCE`, opt-in xctrace via `..._TRACE_SCENARIOS`) are documented at the
top of `benchmark.sh`.

## Android (Pixel 10)

```sh
python3 -m venv tool/.venv-android-bench
tool/.venv-android-bench/bin/pip install perfetto
./tool/android_gpu_bench.sh scenarios                              # core
./tool/android_gpu_bench.sh scenarios --scenarios micro --repetitions 1
./tool/android_gpu_bench.sh measure --package com.example.app \
  --seconds 30 --label scroll --scroll                                # any app
```

It builds a profile APK once (`--skip-build` reuses it), pins the device,
waits for a thermal gate before every run and records a Perfetto trace per
run: the GPU power rail (`power.S2S_VDD_GPU_uws`) as the ground-truth energy
metric, plus GPU memory, DDR, CPU, display and battery rails, GPU frequency
residency, per-UID GPU time and Flutter raster percentiles. Both subcommands
take `--pin PIN` for the lock screen. Results go to
`build/android_gpu_bench/<timestamp>/`.


**A/B between builds.** Build one profile APK of `integration_test/benchmark_test.dart`
per arm, each with its own `applicationId` (set it in the local, gitignored
`android/app/build.gradle.kts`), install them, then:

```sh
tool/.venv-android-bench/bin/python tool/android_ab_bench.py --out build/android-ab/reuse \
  --arms on=com.example.bench.on,off=com.example.bench.off \
  --scenarios "pxButtonStretch pxPillStretch pxBlend5Motion resizeAnimated pxSheetResize pxMultiLayer" \
  --reps 4 --max-skin 31.5
tool/bench_analyze.sh build/android-ab/reuse
```

Arms run interleaved, reversed every other repetition, behind a thermal gate. The
summary adds GPU Mcycles/frame and mJ/frame, the UI `PAINT` slice, UI GC ms/s,
peak and median PSS+GPU (in-app `smaps_rollup` every 50 ms plus the process GPU
memory) and rail groups in mW (GPU, GPU-mem, CPU, DDR, SoC = their sum). The
`pixel` suite in `bench_scenes.sh` lists the scenes. `ANDROID_SERIAL` and
`UNLOCK_PIN` come from the environment.
## Results

Both runners write `summary.md` and `summary.json` into their result
directory. Re-analyze a directory, for example after copying it off a
machine, with:

```sh
./tool/bench_analyze.sh build/benchmark
./tool/bench_analyze.sh build/android_gpu_bench/20260930_120000   # mW columns
```

Write-ups worth keeping go to `results/`. Some older write-ups there name
probe scenes that have since been removed (`appScrollRealTopOnly`,
`appScrollRealPillOnly`, the passthrough and sigma arms); they are in git
history.

## iOS power (iPhone)

```sh
IOS_UDID=<xctrace udid> DEVICECTL_ID=<devicectl id> BUNDLE=com.example.app \
  LAUNCH_ENV='{"GLASS_BENCH":"MODE"}' \
  tool/ios_power/ios_power_bench.sh power NEW_REAL:real NEW_FAKE:fake OFF:off
python3 tool/ios_power/parse_power_trace.py \
  build/ios_power_bench/traces/NEW_REAL_r1_power.trace
```

iOS has no per-rail milliwatts; `parse_power_trace.py` prints Apple's
power-impact indexes, so compare them between labels only.
