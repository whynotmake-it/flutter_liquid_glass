# Example tooling audit

Audited at `5e82cdb88`, 2026-10-03.

This is the pre-convergence snapshot. See the
[current disposition](tooling-audit-disposition.md) for per-finding verdicts,
implemented changes and remaining verification/evidence limits.

Paths in this document are relative to
`packages/liquid_glass_renderer/example/`, unless explicitly prefixed with
`repo:`. "Used" means a checked-in caller or documented manual command exists;
it does not mean someone recently executed it. No external usage telemetry
exists. A manual diagnostic is not dead just because CI does not invoke it.

## Findings

| Priority | Finding and evidence | Impact | Effort / fix risk / confidence |
| --- | --- | --- | --- |
| P1 | `tool/apple_match/flutter/lib/scene.dart:18-46` drops `mergeShape`, `containerSpacing`, `glassVariant`, `glassTint`, and `roles`; `scene_view.dart:144-174` has no merge branch. Swift renders both shapes at `apple/Sources/AppleMatchApp.swift:70-82`. | All five native merge scenes become a single Flutter shape. Clear/tint semantics must be supplied separately and can silently disagree with the scene. | M / medium: shared scene contract / high |
| P1 | `settings/tint-model-*.json` select `ios27Light`/`ios27Dark` but keep direct-model saturation/gamma/vibrancy fits. `flutter/lib/scene_view.dart:29-37` applies them, and `lib/src/liquid_glass_appearance.dart:130-142` documents these as relative adjustments on adaptive models. | They do not reproduce the shipped iOS 27 models. Cleaning unknown keys alone does not fix the look. | M / medium: archive before migration / high |
| P1 | `compare/apple_match/hotloop/evaluate.py:31-84` accepts removed rim controls; `flutter/lib/scene_view.dart:12-13` delegates material parsing to `LiquidGlassSettings.fromJson`, which ignores them. `hotloop_staged.py:34-193` still searches them. | Flat search axes can be reported as fitting evidence; missing current fields pick up changing constructor defaults. | M / medium / high |
| P1 | `compare/apple_match/cli.py:21-50`, `hotloop/evaluate.py:24,203-210,375`, and `stage_metrics.py:343-357` assume A-D; solid-palette scenes have 14 probes and tint scenes have K/L/N/H/W/B/O. | The nominal unified compare/fit path cannot evaluate every fitted look. `solid_color_metrics.py:36-39` additionally requires `roles.palette`, absent from tint scenes. | M / medium / high |
| P1 | `hotloop_staged.py:32-33,452,476` pins Reduce Motion-on ground truth and an ignored `out/` baseline. `run.py:84,91,105` defaults to that older reference family too. | A fresh checkout has no default hot-loop seed; fitting refraction against the default target omits Apple's lensing. | S-M / low / high |
| P1 | `tool/results/` cites missing ignored `apple_match/out/`, deleted `/tmp/pixel_glass`, absent `~/Developer/flgb-tools`, and deleted external ClickUp builds. | Existing prose/numbers are not equivalent to replayable evidence. Do not promise all historical measurements can be regenerated from HEAD. | L / high: recovery may be impossible / high for checked locations |
| P1 | Pixel analyzers use different contracts. `android_gpu_bench_analyze.py:674-679` groups failures into headline medians; `android_ab_analyze.py:212-219` indefinitely reuses a cache keyed only by directory name. | A failed run can contaminate one summary; replacing a trace or fixing the other analyzer need not update its result. | M / medium: frozen historical summaries / high |
| P2 | `android_ab_bench.py:89-92` returns after its cooling timeout even if hot; `:281,287` splits scenario strings without `bench_scenes.sh` validation. | Hot measurements are still marked `ok`; `--scenarios pixel` is treated as a literal scenario, unlike the two shell runners. | S / low / high |
| P2 | `benchmark.sh:71` unconditionally removes the result directory; `hotloop_staged.py:484` removes its output tree. Loupe recapture removes old references before successful capture (`apple/capture_loupe.sh:63-65`). | Re-running the natural command can destroy the very evidence the audit needs preserved. Ordinary `apple/capture.sh` already uses staging and backup instead. | S-M / low / high |
| P2 | `benchmark.yaml` runs only Metal and re-parses a summary already written by `benchmark.sh`. Smoke uses `--enforce false`; Dart completeness checks only observed scenarios (`parse_benchmark_results.dart:1114-1119`). | CI is not a Pixel pipeline or a baseline-vs-PR performance comparison. Smoke can exit successfully with recorded failures, and a wholly absent expected scene is not detectable from the input alone. | M / low / high |
| P2 | Loupe references use a weaker metadata path (`capture_loupe.sh:207-254`), hard-coded runtime, and no shared checksum/stability manifest. Sweep skips loupe captures after checking two metadata fields (`capture_slider_sweep.sh:85-94`). | A claimed validated sweep is not uniformly provenance-checked; partial sweeps also end successfully after logged failures. | M / medium: old metadata must stay historical / high |
| P2 | Current instructions name missing tools and old parameters. Examples: `results/apple-match-report.md:192`, `results/performance-audit.md:506,729`; `MODEL_DESIGN.md:27-53`. | Historical exploration reads as current operating instructions. The matching README incorrectly says its JSONs reproduce shipped fits and that hotloop uses `stages.json`. | S / low / high |

The core Flutter profile target, native sampling, scene fixtures, image metrics,
and trace QA have genuine uses. Convergence should remove duplicate orchestration
and stale inputs, not replace working measurements with a smaller but weaker test.

## Current call graph

```text
repo:.github/workflows/benchmark.yaml
  -> tool/benchmark.sh -> integration_test/benchmark_test.dart
     -> macos/Runner/MainFlutterWindow.swift benchmark channel
     -> tool/trace_notification_waiter.c (optional xctrace handshake)
     -> tool/parse_benchmark_results.dart -> summary + GITHUB_OUTPUT
  -> tool/parse_benchmark_results.dart again

tool/android_gpu_bench.sh -> bench_scenes.sh -> same Dart target
  -> Android MainActivity intent/channel -> Perfetto + sysfs + logcat
  -> android_gpu_bench_analyze.py
tool/android_ab_bench.py -> installed arms of the same Dart target
  -> its own capture/config/thermal logic -> run.json + trace
tool/bench_analyze.sh -> metadata-based dispatch to either Pixel analyzer
  or the Dart Metal parser

apple/capture_ground_truth_matrix.sh -> apple/capture.sh
apple/capture_slider_sweep.sh -> set_transparency_slider.sh
  -> apple/capture.sh OR apple/capture_loupe.sh
apple/capture.sh -> apple/build.sh -> AppleMatchApp + SceneModel
  -> validate_probe_frame.py -> median_frames.py -> reference_provenance.py
apple/capture_loupe.sh -> build.sh + agent-device -> median_frames.py
  -> its own, incomplete metadata writer

run.py -> flutter/capture.sh -> Flutter MatchApp -> apple_match.cli
hotloop_staged.py -> hotloop/{session,evaluate,optimize}
  -> Flutter SessionApp -> score_images (not apple_match.cli)
flutter/host_capture.sh -> flutter/test/host_capture_test.dart
  -> MatchSceneView -> PNGs
manual compare/report commands -> cli, stage_metrics, solid_color_metrics,
  rim_report, zoom_atlas
```

## Entry point inventory

### Benchmark and ancillary tools

| Entry | Function | Checked-in caller / status |
| --- | --- | --- |
| `tool/benchmark.sh` | Builds one macOS profile app, fresh process per scene/repetition; frame/Mach-memory/command-buffer GPU measurements; optional separate xctrace runs. | Both benchmark workflow jobs, tool README. Active canonical Metal runner. |
| `tool/android_gpu_bench.sh scenarios` | Builds/installs one profile APK, pins display, thermal gate, scenarios, Perfetto/sysfs/logcat/screenshot, automatic analysis. | Tool README, optimization log. Active single-arm Pixel runner. |
| `tool/android_gpu_bench.sh measure` | Measures any installed package, optionally scrolling with adb swipes; no deterministic renderer scene or in-app window handshake. | Tool README only. Manual external-app diagnostic, not equivalent to scenario results. |
| `tool/android_ab_bench.py` | Installed package arms, reversible interleaving, thermal/skin gate, resume by `run.json`, chunks and Perfetto. Does not build, validate scenes, or auto-analyze. | README, `bench_analyze.sh` documentation, Pixel campaign methods. Active manual A/B path; no CI caller. |
| `tool/android_gpu_bench_analyze.py --out` | Legacy single-arm traces, rails, sysfs, frame summaries, raster slice profiles. | Android shell runner and `bench_analyze.sh`. Used; not dead. |
| `tool/android_ab_analyze.py RESULT_DIR` | A/B medians/ranges/CVs, Mcycles/frame, mJ/frame, PAINT, GC, combined PSS+GPU. | `bench_analyze.sh`, README names it. Used; not the same metric set as the single-arm analyzer. |
| `tool/bench_analyze.sh RESULT_DIR` | Guesses format from `meta.json` containing `arms` or `serial`; otherwise Dart Metal parser. | README and A/B runner usage comment. Used dispatcher; extra arguments go only to Metal. |
| `tool/parse_benchmark_results.dart` | Metal report/trace parser; frame/native-memory gates, summary JSON/Markdown, GitHub step output. | Metal runner, workflow (twice), `test/benchmark_parser_test.dart`, dispatcher. Active, covered by fixtures. |
| `tool/bench_scenes.sh` | Sourced registry: `bench_all_scenes`, `bench_resolve_scenes`; app/core/micro/pixel/all suites. Enum is source of valid names. | Both shell runners, NOT Python A/B runner. Live library, not executable measurement entry. |
| `integration_test/benchmark_test.dart main()` | Standalone profile application, not an integration_test test case. 79 enum scenes, warmup, stability sampling, measure window, chunked Android output, full JSON, trace loop. | Both shell builds and manually built A/B APKs. Keep one target. |
| `tool/trace_notification_waiter.c` | Darwin notification to readiness files so Instruments can attach before measured workload. | Compiled by Metal runner even when no trace requested. Live only for optional tracing. |
| `tool/ios_power/ios_power_bench.sh power` / `metal` | Attaches Instruments to any installed iOS app; labels/modes and external app hook; USB and thermal gate. | Manual README command; historical iPhone/ClickUp report. No renderer benchmark-channel implementation on iOS. |
| `tool/ios_power/ios_thermal_probe.sh` | Short all-process Metal trace, extracts thermal state. | iOS power runner; also manually callable. Not dead. |
| `tool/ios_power/parse_power_trace.py` | Power Profiler XML exports and duration-weighted impact indexes/system metadata, not mW; no Metal-GPU parser. | README manual command. Needed for historical Power Profiler evidence. |
| `tool/crop_readme_screenshots.py SOURCE TARGET` | Crops captured example scenes into README JPEGs. | Usage comment in `test/readme_screenshots_test.dart`. Manual screenshot publishing; keep outside both pipelines. |
| `tool/results/glass-research/refraction-ab/ramp_decode.py DIR W H` | Inverts saved horizontal/vertical sawtooth captures and prints displacement bins/tone fits. Executes on import. | Its local report only. Historical measurement recipe, not a generic benchmark or fitter. |
| `repo:.github/workflows/benchmark.yaml` | PR smoke without performance label; full Metal run with label or workflow_dispatch; uploads results and comments. | GitHub events. No Pixel job, no base-branch comparison despite fetch-depth 0. |

### Matching capture and fitting tools

| Entry | Function | Checked-in caller / status |
| --- | --- | --- |
| `apple_match/apple/build.sh` | Direct swiftc simulator app build, packages all scenes, codesigns; requires iOS 27 SDK. | Both Apple capture scripts and README. Live helper. |
| `apple_match/apple/test.sh` | Offline Swift scene-decoder tests on five fixtures. | Manual entry; no workflow caller found. Keep and extend to all scene profiles. |
| `apple_match/apple/Sources/AppleMatchApp.swift` | Native app entry: button/material/tab/loupe/merge-pair scene profiles. | `build.sh`. Live native ground-truth producer. |
| `apple_match/apple/capture.sh` | Complete scene probes, three-frame medians, background validation and rich provenance, staged reference replacement. Defaults Reduce Motion ON. | `run.py`, matrix/sweep wrappers, README. Live reference producer. |
| `apple_match/apple/capture_loupe.sh` | Long-press native text selection with agent-device, verifies loupe presence, medians/backgrounds, custom metadata. | Sweep and README. Necessary distinct acquisition behavior; duplicated plumbing. |
| `apple_match/apple/capture_ground_truth_matrix.sh` | Hard-coded 13-case Reduce Motion-on matrix at 0/.5/1 plus source-vector/background checks. | README only. Historical matrix, not coverage of today's fits. |
| `apple_match/apple/capture_slider_sweep.sh` | Reduce Motion-off material/loupe batch, default 0/.25/.5/.75/1, skips/retries based on metadata. | README only. Current manual acquisition batch; does not include .45/.55 or merges/tints by default. |
| `apple_match/apple/set_transparency_slider.sh POSITION` | Writes/readbacks UIKit Tint Amount default; terminates only capture app. | Sweep/loupe and README. `capture.sh` duplicates its implementation. |
| `apple_match/pin_simulator.py` | Locates/boots a specific existing simulator; refuses to create one. | README. Fresh-machine setup fails unless that UDID/name already exists. |
| `apple_match/validate_probe_frame.py SCENE PROBE PNG` | Scene-aware background-pixel validation. | Standard Apple and Flutter simulator captures, provenance metadata, tests. Loupe duplicates simpler validation instead. |
| `apple_match/reference_provenance.py` | Writes/checks scene/API/condition metadata, source hashes, PNG hashes and stability. Recorded source hashes intentionally need not equal current sources. | Standard Apple capture, matrix, stage/atlas commands, tests. Not called by generic comparator or hotloop. |
| `apple_match/audit_ground_truth.py --reference-root` | Hard-coded historical matrix plus same-source/runtime and cross-slider background checks; writes audit JSON. | Matrix and README. Missing modern coverage; useful validations worth retaining internally. |
| `apple_match/compare/median_frames.py OUTPUT INPUT...` | Pixelwise rounded median, dimension checks. | Three capture scripts. Keep one implementation. |
| `apple_match/flutter/capture.sh` | Debug simulator build/install (optional), launch each scene-declared probe, validate, median, settings and small metadata. | `run.py`, README. Works for dynamic probe IDs, but PREPARE_APP=0 trusts whatever scene is already installed. |
| `apple_match/flutter/host_capture.sh` | Host GPU golden capture, shader-source digest invalidation, configurable probe/DPR/fake; calls one test for its probe list. | README; host fitting calibration report. Active fast manual render path. |
| `apple_match/flutter/lib/main.dart` | One-shot `MatchApp` with launch args or persistent `SessionApp` with sandbox IPC. | Simulator capture and hotloop. Both use `MatchSceneView`. |
| `apple_match/run.py` | Toolbar-only, per-launch staged candidate lists, baseline/final comparison and holdouts. | README only. Superseded orchestration, but not safe to delete claimed evidence with it. |
| `apple_match/hotloop_staged.py` | Persistent simulator coordinate-descent with many historical stage-specific losses, wall detection and best evidence. | README; optimize unit tests import two functions. Used but defaults and search contract are stale. |
| `apple_match/compat/bin/lipo` | Forwards lipo operations, splits multi-architecture verify requests for Xcode 27 compatibility. | Capture/hotloop prepend compat/bin to PATH. Keep conditional on actually needed toolchain, not blanket removal. |

### Matching analysis and explicit capture tests

| Entry | Function | Checked-in caller / status |
| --- | --- | --- |
| `python -m apple_match.cli` | A-D scorecard, registration, temporal score and diagnostics, optional host exclusions. | `run.py`, README and comparator tests. Live legacy scoring contract. |
| `apple_match/stage_metrics.py` | A-D stage decomposition, geometry masks, flow/color/emission/transmission, explicit known blur-mixture residual. Validates rich provenance. | Imports from palette/atlas/audit, unit tests; manual CLI. Keep objective diagnostics. |
| `apple_match/solid_color_metrics.py` | Full-face palette transmission/color metrics with black-emission removal and guards. | README manual command and tests. Not an optimizer and not yet tint-role compatible. |
| `apple_match/rim_report.py` | Rim SDF-angle/distance metrics and reference/candidate panels, C/D or explicit palette probes, compact mode. | README manual command; imports `apple_match.rim`. Keep rim measurements. |
| `apple_match/zoom_atlas.py` | Scene-aware crops/diff atlas for refraction/color/lighting with adjacent JSON manifest. | README manual command and tests. Overlaps rim report's presentation, not its measurements. |
| `flutter/test/host_capture_test.dart` | Requested scene/probe PNGs, real/fake readiness checks; skips without HOST_CAPTURE defines. | `host_capture.sh`. Canonical host capture; uses update-goldens to write arbitrary output. |
| `flutter/test/appearance_blend_capture_test.dart` | Fixed Colors merge, real/fake, DPR 2/3, optional grid. | Manual define `APPEARANCE_BLEND_CAPTURE_OUT`; skipped otherwise. Valuable interpolation regression, NOT Apple merge ground truth. |
| `flutter/test/per_shape_capture_test.dart` | Default light/dark, manual color axes, merged appearance/visibility atlas. | Manual `PER_SHAPE_CAPTURE_OUT`; skipped otherwise. Covers behavior not replaced by Apple's single-shape cases. |
| `flutter/test/fake_edge_capture_test.dart` | Real/fake, four shape families, light/dark, DPR 1/2/3, no-backdrop and flat variants. | Manual `FAKE_EDGE_CAPTURE_OUT`; skipped otherwise. Edge QA, not a fitting pipeline. |
| `flutter/test/scene_test.dart`, `session_test.dart` | Offline scene/settings mapping and IPC/settle tests. | Flutter test/Melos test discovery. Keep and extend. |
| `apple_match/compare/tests/test_*.py` (8 files) | Schema, comparator, optimizer/IPC, provenance, stage, palette, atlas; online smoke gated by APPLE_MATCH_SMOKE. | README unittest discover. 48 tests, one skip in this audit. No fit-snapshot or complete cross-profile rendering gate. |
| `test/bottom_bar_match_test.dart` | Example tab/controls/loupe snapshots at iPhone dimensions with loaded fonts. | README manual `BOTTOM_BAR_MATCH_OUT`; otherwise skips. App composition QA, not the shared native scene renderer. |
| `test/readme_screenshots_test.dart` | Example screenshots for published README crops. | Flutter/Melos discovery with opt-in output. Do not confuse with Apple references. |
| `test/benchmark_parser_test.dart` | Synthetic Metal/parser fixtures, failures, retained memory, time-window/resource parsing. | Flutter/Melos discovery. Keep; Pixel analyzers have no analogous checked-in test suite. |

The remaining Python library files are reached by imports:
`compare/apple_match/{metrics,rim,schema}.py`,
`hotloop/{__init__,session,evaluate,optimize}.py`. `coordinate_descent` is used
by hotloop; `spsa_descent` has test/export references but no current production
caller. These are implementation modules, not additional public commands.
