# Tooling audit disposition

Reviewed 2026-10-05 on `devin/1791188458-converge-tooling`, starting at
`35c42744e`. This records the previous convergence commits plus the
2026-10-05 follow-up. The original audit was committed in
`d691a470f` and describes the pre-convergence code, not today's call graph.

Paths in the table are relative to
`packages/liquid_glass_renderer/example/`. Finding numbers follow the row
order of [the original audit](tooling-audit.md).

## Verdicts

All twelve findings identify real issues in the audited revision. Two need
an explicit scope qualification: scene roles belong to analysis rather than
Flutter rendering, and Metal-only CI is a coverage boundary, not itself a
broken benchmark.

| # | Original finding | Verdict and current disposition | Current evidence |
| --- | --- | --- | --- |
| 1 | Flutter loses merge, clear, tint, and roles semantics | Correct for rendering and analysis as a whole. Flutter now parses the second shape, container spacing, variant and tint, and renders both shapes in one blend group. Python keeps roles for metric dispatch; Flutter does not need to paint roles. Mapping/widget tests cover these contracts, not fresh native visual equivalence. | `tool/apple_match/flutter/lib/{scene,scene_view}.dart`; `flutter/test/scene_test.dart`; `compare/apple_match/scene.py` |
| 2 | Historical tint fits do not reproduce adaptive shipped models | Correct. Fits are preserved under `settings/historical/` and no longer advertised as current presets. Baselines are manual search inputs, not migrations of those fits or regenerated shipped-model evidence. | `tool/apple_match/settings/historical/README.md`; `tool/apple_match/README.md`; renderer `lib/src/liquid_glass_appearance.dart` |
| 3 | Dead search axes and inherited optical defaults | Correct. Python and Flutter enforce the shared settings-key contract, and fit stages reject unsupported axes. This follow-up makes both baselines complete material vectors, pinning the four previously inherited optical defaults to their current values. Scene-dependent appearance defaults remain intentional. Redundant filtering after strict stage validation is removed. | `tool/apple_match/settings/{contract,baseline,fake_glass_baseline}.json`; `compare/apple_match/hotloop/evaluate.py`; `hotloop_staged.py`; Python/Dart scene tests |
| 4 | A-D assumptions exclude palette/tint probes | Correct. The comparison CLI dispatches by scene metric family and probe roles, and color metrics support palette and hue/complement scenes. The staged fitter and stage diagnostics remain explicitly scorecard-only; they do not now optimize every color look. Fitter preflight rejects unsupported families before loading images, replacing output, or launching a session. | `tool/apple_match/compare/apple_match/{cli,scene,solid_color}.py`; `hotloop_staged.py`; `stage_metrics.py`; `compare/tests/test_fit_preflight.py` |
| 5 | Wrong default reference conditions and ignored baseline seed | Correct. The fitter uses the committed baseline and Reduce Motion-off reference family by default. This follow-up validates provenance and rejects stages changing refraction axes against Reduce Motion-on references, including explicit reference overrides. A checkout still needs its Git LFS image assets. | `tool/apple_match/hotloop_staged.py`; `settings/baseline.json`; `compare/tests/test_fit_preflight.py`; `references/ios27-iphone17pro-reduce-motion-off/slider-000/toolbar_capsule/metadata.json` |
| 6 | Historical measurements are not fully replayable | Correct and not recoverable from code changes alone. Historical results are labeled as such; unavailable temporary captures, external builds, and traces are not recreated or replaced with synthetic evidence. This remains an evidence-recovery limitation, not a claim that all numbers were rerun. | `tool/results/README.md`; original audit's reference/result inventory |
| 7 | Android failures enter aggregates and cache stays stale | Correct. Both headline aggregations exclude non-`ok` runs and report failures separately. This follow-up completes A/B cache invalidation: SHA-256 covers run JSON, trace, memory input, parent metadata, and both analyzer sources. Legacy/corrupt caches miss, and failed analysis is retried. Offline tests cover these paths; device trace metrics were not validated. | `tool/android_{ab,gpu_bench}_analyze.py`; `tool/tests/test_android_bench.py` |
| 8 | A/B thermal timeout and scenario contract differ | Correct. A thermal timeout writes `failed:thermal` and returns before launching or capturing. The A/B runner expands and validates suites through `bench_scenes.sh`. Offline tests cover the gate and Pixel/explicit/invalid scene resolution. | `tool/android_ab_bench.py`; `tool/bench_scenes.sh`; `tool/tests/test_android_bench.py` |
| 9 | Natural reruns destroy existing evidence | Correct. Metal results and fitter output require explicit overwrite permission. Loupe capture stages and validates before moving an old reference to a backup and publishing the new one. This session did not overwrite results or recapture references. | `tool/benchmark.sh`; `tool/apple_match/hotloop_staged.py`; `tool/apple_match/apple/capture_loupe.sh` |
| 10 | Duplicate CI parsing and incomplete smoke success | Correct for duplicate parsing and completeness. Metal parses once; the runner supplies expected scenes and requires completeness even with performance enforcement disabled. Parser tests cover absent scenes and failures. CI remains Metal-only and is not a base-vs-PR performance comparison; Pixel runs remain manual. | repo `.github/workflows/benchmark.yaml`; `tool/benchmark.sh`; `tool/parse_benchmark_results.dart`; `test/benchmark_parser_test.dart` |
| 11 | Loupe/sweep provenance weaker than standard captures | Correct. Loupe uses scene-declared probes, runtime discovery, shared frame validation and checksum/stability provenance. Sweep reuse validates those contracts and slider conditions for both capture types, uses the shared slider helper, and exits unsuccessfully for failed checkpoints. No fresh simulator sweep was run here. | `tool/apple_match/apple/{capture_loupe,capture_slider_sweep,set_transparency_slider}.sh`; `reference_provenance.py`; `validate_probe_frame.py` |
| 12 | Historical instructions masquerade as current tools/settings | Correct. Current READMEs point to the supported entry points, one fitter, settings contract and archived fits. Historical reports/design proposals are labeled rather than rewritten into evidence for current behavior. The audit index now distinguishes the original snapshot from this disposition. | `tool/README.md`; `tool/apple_match/{README,MODEL_DESIGN}.md`; `tool/results/README.md`; `plans/README.md` |

## Converged responsibilities

- One shared benchmark target: `integration_test/benchmark_test.dart`.
  One scene registry: `tool/bench_scenes.sh`, used by Metal, Pixel and A/B
  runners. Platform-specific acquisition and analysis remain separate because
  Metal command-buffer timings, Android power rails and iOS impact indexes
  are not interchangeable measurements.
- One matching scene/settings contract, one Flutter scene renderer for both
  one-shot capture and persistent sessions, and one staged fitter.
- One comparison entry point dispatches scorecard versus solid-color metrics.
  Rim, stage and crop diagnostics retain distinct responsibilities; they are
  not duplicate optimizers.
- Apple static and loupe acquisition share one driver: `apple/capture.sh`
  owns the capture lifecycle and its `--loupe` mode holds the active long
  press; `apple/capture_loupe.sh` is a compatibility wrapper. They share
  validation, slider control, median-image production and provenance rather
  than duplicating those rules.

## Verification and limits

Offline checks completed before test pruning (counts below are historical):

- Android contract suite: 20 tests pass without adb or a real Perfetto
  processor. Includes cache invalidation, failure exclusion/retry, thermal
  rejection, and scene resolution.
- Matching Python suite: 61 tests run, successful with one online smoke
  skipped. Uses synthetic/unit fixtures, not a new native reference comparison.
- Flutter example benchmark parser: 25 tests pass.
- Flutter matching scene/session tests: 21 passed before the additional
  baseline test; the updated scene suite then passed all 11 tests.
- Matching Flutter analysis reports no issues; changed Python compiles;
  JSON inputs parse; whitespace checks pass.

Verification logs are local, ephemeral artifacts:
`/tmp/android-bench-verify.33DlX6/` and
`/tmp/apple-match-followup.IeoVqV/`. They are not committed benchmark evidence.

The matching `compare/.venv` has site-packages but no `bin/python` in this
checkout. Verification reused the matching Python 3.9 system interpreter with
those site-packages on `PYTHONPATH`; it did not install dependencies.

A direct check of the default reference failed safely because `A.png` is a
131-byte Git LFS pointer, not the image described by its SHA-256 manifest.
The tracked metadata and LFS pointer agree on the expected asset hash; no
download was attempted. Fetching available LFS assets is different from
recovering the untracked historical evidence in finding 6.

No fresh native Apple capture, on-device Android measurement, visual fit,
golden regeneration, or benchmark run was performed. Flutter scene/widget
tests can use the renderer's GPU fallback and are not GPU visual proof.
These limits do not turn offline contract tests into performance evidence.
