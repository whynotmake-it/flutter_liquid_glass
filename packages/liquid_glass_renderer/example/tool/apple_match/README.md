# Apple liquid-glass matching

This directory is an executable, deterministic scorecard for matching
`liquid_glass_renderer` to a pinned official iOS 27 SwiftUI control. It does
not use screenshot “vibe checks,” private `_UIViewGlass`, or private uniforms.
The optional transparency experiment sweeps Apple's Settings value without
changing the public SwiftUI reference control.

The training profile is `toolbar_capsule`. Its Apple reference is an actual
SwiftUI `Button` using the public `.buttonStyle(.glass)` API. The API signature
was verified in the installed SwiftUI SDK interface:

```swift
@available(iOS 26.0, *)
extension PrimitiveButtonStyle where Self == GlassButtonStyle {
  public static var glass: GlassButtonStyle { get }
  public static func glass(_ glass: Glass) -> Self
}
```

An iOS 27 SDK/runtime is still required for the official capture. A capture
from iOS 26 or older must never be placed in `references/`.

## Layout

- `scenes/`: shared JSON schema and deterministic A/B/C/D scene.
- `apple/`: dependency-free native SwiftUI app, direct `swiftc` build, and
  pinned-simulator capture driver.
- `flutter/`: standalone Flutter capture target using
  `liquid_glass_renderer`, Impeller/Metal, and Flutter GPU.
- `compare/`: OpenCV/NumPy alignment, residual, signed radial-flow,
  directional 2–20 px exterior-shadow annulus, gradient-sharpness, specular,
  tint metrics, and tests.
- `settings/`: baseline and bounded deterministic search space.
- `references/`: immutable, named Apple capture sets. Replacement requires
  `FORCE_REFERENCE=1`.
- `out/`: ignored candidates, diagnostics, and scorecards.

## Reproducible setup

Requirements:

- Xcode with the iOS 27 SDK and accepted Xcode license.
- Flutter 3.47.1.
- `agent-device >= 0.14.0`.
- Python 3 with packages pinned by `compare/requirements.txt`.

```bash
cd packages/liquid_glass_renderer/example/tool/apple_match
export DEVELOPER_DIR=/Applications/Xcode-27.0.0-Beta.5.app/Contents/Developer
export FLUTTER_BIN="$HOME/fvm/versions/3.47.1/bin/flutter"
python3 -m venv compare/.venv
compare/.venv/bin/pip install -r compare/requirements.txt
export IOS_27_UDID="$(compare/.venv/bin/python pin_simulator.py)"
agent-device devices --platform ios
```

The simulator name is pinned to `AppleMatch-iPhone17Pro-iOS27`; the script
prints its exact UDID. Captures are portrait, 402×874 logical points at 3×,
light appearance, Reduce Motion enabled, and Reduce Transparency off. The
scene JSON records the remaining geometry and transparency metadata.

## Tests

Run comparator/schema tests before trusting any optimization:

```bash
PYTHONPATH=compare python3 -m unittest discover -s compare/tests -v
cd flutter
"$FLUTTER_BIN" pub get
"$(dirname "$FLUTTER_BIN")/dart" format --output=none --set-exit-if-changed lib test
"$FLUTTER_BIN" analyze
"$FLUTTER_BIN" test
cd ..
```

The tests prove that an exact synthetic match beats blur/light/tint
perturbations and that each parameter family changes its intended decomposed
metric. Once iOS 27 is installed and licensed, type-check/build the native app:

```bash
bash apple/test.sh
bash apple/build.sh
```

## One-command capture and bounded search

```bash
IOS_27_UDID="$IOS_27_UDID" compare/.venv/bin/python run.py
```

This validates the scene, freezes Apple A/B/C/D references if absent, captures
the baseline Flutter candidate, evaluates at most 24 deterministic combinations
of thickness, blur, light angle, and light intensity, and writes:

- `out/baseline/scorecard.json`
- `out/best/scorecard.json`
- `out/best/settings.json`
- `out/summary.json`
- `out/best/signed_diff_x4.png`
- `out/best/signed_radial_flow.png`
- `out/best/gradient_profile.png`

Every scorecard exposes component errors, weights, normalization thresholds,
alignment, inputs, and exact settings. The tab bar is not optimized in this
slice; if added, it must remain a holdout.

## Fast iteration loop (hot reload)

```bash
IOS_27_UDID="$IOS_27_UDID" compare/.venv/bin/python optimize.py \
  --scene scenes/toolbar_capsule.json --max-iters 8
```

`optimize.py` keeps one persistent Flutter session alive on the simulator and
runs online coordinate descent: it writes a candidate settings JSON into the
app sandbox, triggers hot reload (SIGUSR1), waits for the app to report a
settled frame, screenshots the four probes, and computes the scalar loss
`100 - score` against the pinned Apple reference. Each iteration evaluates the
one-step neighborhood of the current point (previous/next value per axis) and
moves to the best candidate; it stops when no neighbor improves or
`--max-iters` is reached. One app launch amortizes over all evaluations, so an
eval costs seconds instead of a full build/install/launch cycle. Measured on
the pinned simulator: ~156 s one-time startup, then ~3.0 s per evaluation
(mean; hot reload itself is ~80 ms) versus ~40 s per candidate for the
restart-based loop.

Determinism and caches: the app re-reads the candidate file on hot reload and
applies it to a persistent render subtree — normal widget updates invalidate
settings/shape state, while re-keying the subtree per candidate would churn
GPU geometry textures and eventually drop the simulator connection. The
runner only accepts a settle whose echoed serial matches the request; if a
reload is dropped it retries once and escalates to a single hot restart
(SIGUSR2), recording `reloadMode` per probe, and re-resolves the app container
paths afterwards (a restart can reinstall the app and rotate the container).
Screenshots are single frames after a fixed settle countdown; re-validate any
winner with `run.py` (3-frame median) before trusting it.

References stay immutable: the optimizer never captures SwiftUI references and
refuses to run when the reference set's pinned UDID does not match
`--udid`/`IOS_27_UDID`. Recapture only via `bash apple/capture.sh` with
`FORCE_REFERENCE=1` or `python3 run.py`.

Outputs: `out/optimize/summary.json` (best params/loss, full history, per-eval
timings), `out/optimize/best/` (best probe captures, settings, and a full
comparator scorecard with diagnostics), `out/optimize/last/` (most recent
eval's captures). Failure modes: `SettleTimeout` (reload+restart both failed
to produce a settled frame — inspect the simulator), readiness timeout
(build/toolchain issue — check the flutter run log tail in the error), and
missing/mismatched reference errors (recapture references first).

### Staged optimizer and escalation contract

`hotloop_staged.py` runs the full token-free local loop in one persistent
Flutter session. Its ordered stages are registration, shape, refraction,
fixed-sigma blur mix/MTF, tint/color, and independent bright/dark rim fitting.
The blur controls mean `blurMix=0` is sharp, `blurMix=1` is fully blurred at
the fixed `blur` sigma, and intermediate values linearly mix those images.
Bright and dark rims each have independent RGB color, width, and intensity.

```bash
IOS_27_UDID="$IOS_27_UDID" compare/.venv/bin/python hotloop_staged.py \
  --baseline settings/preapproved_renderer_baseline.json \
  --stages blurMtf,tintColor,highlight \
  --out out/approved-renderer
```

If improvement remains below `--wall-threshold` for
`--wall-consecutive` stages, the process writes `wall_report.json` and exits
with status 42. The report includes the current best settings and score,
per-component residuals, parameters at search-range edges, stage summaries,
and absolute diagnostic image paths. An agent may autonomously adjust minor
fit parameters and search bounds after reviewing that evidence. A new public
API or shader model beyond the approved fixed-blur mix and dual-rim model is a
major change and requires user sign-off before implementation.

The original fixed-blur-mix search retained `blur=6, blurMix=1` at the default
Settings position. That was only a single-point result, not a rejection of the
mix mechanism.

### Liquid Glass transparency sweep

`transparency_sweep.py` captures the same toolbar scene and all four probes at
Settings positions 0, 0.25, 0.5, 0.75, and 1. Each reference is the median of
three frames. Key discovery found the Settings slider's backing default, so the
reproducible control method is:

```bash
xcrun simctl spawn "$IOS_27_UDID" defaults write \
  com.apple.UIKit UIViewGlassTintAmount -float 0.5
xcrun simctl spawn "$IOS_27_UDID" defaults write \
  com.apple.UIKit UIViewGlassEverEditedInSettings -bool YES
```

`apple/set_transparency_slider.sh` writes and reads back both values. This
unsupported defaults key is used only to automate the simulator Settings
experiment; the reference app itself still renders the public
`.buttonStyle(.glass)` control. Run the full capture and hot-reload fit with:

```bash
IOS_27_UDID="$IOS_27_UDID" python3 transparency_sweep.py --force-reference
```

With fixed blur sigma 6, the fitted `(blurMix, glassAlpha, neutral tint)` curve
was `(0.75, 0.54, 235)`, `(0.95, 0.50, 255)`,
`(1.00, 0.62, 247)`, `(0.95, 0.80, 227)`, and
`(1.00, 0.86, 227)`. The 0.05 dip at position 0.75 is one fine-search step and
falls within the fit tolerance: blur mix rises from 0.75 and saturates near 1,
while overlay alpha rises strongly across the upper slider range. The sweep
therefore supports the fixed-blur mix path and supersedes the earlier
single-position rejection. Exact scores, diagnostics, and absolute evidence
paths are in `out/transparency-sweep/summary.json`; the same summary is linked
from `out/approved-renderer/wall_report.json`.

Visual inspection still shows a material upper-end limitation that the
aggregate score understates: at position 1 Apple's glass is nearly opaque,
while the fitted candidate retains visible RGB grid structure. The sweep
supports a rising, saturating blur mix, but the current neutral tint/alpha
response is not a complete model of the Settings slider.

Independent bright/dark rim fitting retained zero intensity for both rims. The
ordinary directional light moved from 0 to 0.2 and raised the revised highlight
stage from 74.7990 to 74.9471. Under the same revised rim-aware metric, the
overall score moved from 90.6251 to 90.7511.

### Frozen-RI generalization experiment

`small_capsule` (150×70 requested) and `large_capsule` (290×125 requested)
are additional official `.buttonStyle(.glass)` scenes. `tab_bar_holdout` is a
public SwiftUI `TabView` system tab bar and is never fitted. Capture references
with:

```bash
for scene in small_capsule large_capsule tab_bar_holdout; do
  FORCE_REFERENCE=1 SCENE_ID="$scene" bash apple/capture.sh
done
```

Then fit only size/corner geometry and per-control thickness while freezing
`refractiveIndex=1.08`, `shapeProfile=roundedRectangle`, and the toolbar
appearance settings:

```bash
IOS_27_UDID="$IOS_27_UDID" compare/.venv/bin/python generalization.py
```

The bounded fit found:

- toolbar: height 94, thickness 6; shape/flow/combined errors
  0.00860 / 0.04437 / 0.03246
- small capsule: height 63, thickness 8; 0.00823 / 0.09341 / 0.06606
- large capsule: height 118, thickness 6; 0.01160 / 0.02955 / 0.04421
- unfitted tab-bar holdout score 33.4020

Geometry generalized, and the large capsule's optical errors were comparable
to the toolbar, but the small capsule's flow and combined errors were more than
1.5× the toolbar errors. The frozen-RI/profile hypothesis is therefore
rejected for the complete control set. Thickness is discrete in this sample
(8 for the small control, 6 for medium and large), not linear with size.

## Verified iOS 27 result

The checked reference set was captured from:

- Xcode 27.0 beta 5 (`27A5237l`)
- iOS 27.0 simulator runtime `24A5408d`
- runtime identifier `com.apple.CoreSimulator.SimRuntime.iOS-27-0`
- iPhone 17 Pro simulator `DB4F41F3-1C36-476D-B775-AFDC3686C75B`
- portrait, light appearance, large content size, Reduce Motion enabled,
  Reduce Transparency disabled

The baseline scored **52.2076**. The best of the 24 fixed candidates scored
**85.8822**, an absolute gain of **33.6746** and a relative gain of
**64.5013% ± 0.0000%** across three identical captured frames. Best settings:

```json
{
  "thickness": 28.0,
  "blur": 6.0,
  "lightAngle": 1.5707963267948966,
  "lightIntensity": 0.25,
  "ambientStrength": 0.0,
  "glassAlpha": 0.53,
  "refractiveIndex": 1.2,
  "saturation": 1.5
}
```

`agent-device 0.17.5` was verified and its workflow/settings/debugging/macOS
guidance was followed. Its Xcode 27 runner selected a physical-device
provisioning path on this host, so the noninteractive capture driver uses the
documented public `xcrun simctl` launch and screenshot commands instead. No
private glass API or private uniforms are used.

## Interpretation and limitations

`score = 100 × (1 − weighted normalized error)`. The components are combined
appearance (30%), signed radial-flow residual (25%), edge/gradient sharpness
(15%), black-probe specular residual (15%), and white-probe tint residual
(15%). Higher is better. This is a deterministic engineering score, not a
claim of perceptual identity.

Simulator-to-physical-device equivalence is **pending** until the same probe is
captured on a real iOS 27 device. Do not claim device equivalence from these
simulator references. Three-frame temporal uncertainty is emitted in each
scorecard; this run produced identical frames and therefore a measured interval
of zero, which does not cover simulator-to-device variation.

### Geometry AA diagnostic

The geometry pass keeps Flutter's centered half-pixel coverage by default. For
the contour-registration experiment only, rebuild the capture target with the
compile-time value expressed in thousandths:

```sh
flutter run --dart-define=LIQUID_GLASS_GEOMETRY_AA_HALF_WIDTH=375
```

Sweep `250`, `375`, and `500` with shape, lighting, and shadows frozen. This is
an internal rasterization probe, not a public material setting; accept a
change only if it improves the black/white outside-boundary samples and the
global shape/direct metrics across held-out sizes and both Metal/GLES.

The toolbar-capsule sweep on the pinned iOS 27 simulator (canonical settings,
three-frame medians) measured scores **94.0696** (0.25), **94.1121** (0.375),
and **94.0862** (0.5). The differences are not material, and the default
Flutter-parity 0.5 remains selected; 0.375 is retained only as a diagnostic
variant, not as a renderer behavior change.

Generated build products, virtual environments, caches, and candidate output
are ignored. Only small, deliberately reviewed reference/evidence PNGs should
be versioned. No production renderer or shader changes are required by the
harness itself.
# Renderer redesign status (2026-08-25)

The shipped renderer now uses a unified material vector: `tint`, `thickness`,
`edgeRefraction`, `refractionSpread`, `frost`, `chromaticAberration`,
`saturation`, `transmissionGamma`, `vibrancy`, `highlight`, `contourStrength`,
and `contourWidth`. The geometry pass keeps the existing SDF/refraction field,
adds a profile-reach scalar for loupe controls, and shares a displacement codec
scale with the final pass. No pass, texture, or per-frame CPU solve was added.

The example can be launched with:

```bash
cd packages/liquid_glass_renderer/example
fvm flutter run -d macos -t lib/basic_app.dart
```

The deterministic grid mode used by screenshots/tests is:

```bash
fvm flutter run -d macos -t lib/basic_app.dart \
  --dart-define=LIQUID_GLASS_EXAMPLE_TEST_BACKGROUND=true \
  --dart-define=LIQUID_GLASS_EXAMPLE_TEST_BLUR=0
```

The sidebar exposes the unified controls and image/black/white/grid
backgrounds. Presets are scalar YAML files under the app documents directory;
`ios27-toolbar-light.yaml` and `neutral-default.yaml` are seeded on first run.

The first post-profile pinned toolbar run (shape-relative reach and canonical
settings) scored **91.3253** overall; the refraction stage improved its flow
objective from 9.5324 to 8.8824. Its four probe captures and diagnostics are in
`out/redesign-refraction/stages/refraction/best/`, including
`holdout_comparison.png` and `solid_lighting_comparison.png`.

The earlier 72-seed loupe scan is retained as a pre-redesign record at
`out/loupe-seed-scan-pre-redesign-full/`; it scored 10.1461 but used the old
toolbar geometry, so it is not a valid loupe gate. A corrected-shape post-fit
smoke scan is in `out/loupe-seed-scan-post-redesign-8-correct-shape/` (8/72
seeds, best 8.6626). A full fair loupe rerun and the system text-selection
loupe integration remain required before claiming the +10 loupe gate.

Focused GPU/shader/settings tests and the example smoke/YAML test are green.
The full melos non-golden suite still has headless layer-tree failures, and
the macOS/Android performance audit plus tab/capsule holdout scorecards are
not yet complete. Those remain hard gates before calling this
production-ready.
