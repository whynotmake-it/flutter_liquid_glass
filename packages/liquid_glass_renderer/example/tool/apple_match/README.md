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
- `write_metric_ledger.py`: rescoring utility that rebuilds the full numeric
  ledger from retained A/B/C/D captures without rerunning Flutter.

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

For the current looks audit, regenerate the detailed per-row report (including
black/white luminance, refraction flow and boundary curvature) with:

```bash
compare/.venv/bin/python3 write_metric_ledger.py
```

The annotated image index and generated ledger are under
`out/annotated-comparisons/iterations/`; the tracked summary and evidence
status are in [`FULL_REPORT.md`](FULL_REPORT.md).

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

The current fitter keeps the exact baseline tint RGB as one shared material
vector and searches only the documented per-position scalars `tintAlpha` and
`frost`. It emits a structural constraint audit in
`out/transparency-sweep/summary.json`; any drift in tint, geometry, or another
material field fails the run rather than being misreported as a two-scalar fit.
`frost` is a provisional transmission control, not a claim that Apple's
blurred/unblurred blend is solved. Exact scores, diagnostics, and absolute
evidence paths are in `out/transparency-sweep/summary.json`; the same summary
is linked from `out/approved-renderer/wall_report.json`.

The older fixed-blur-mix curve below is retained as historical evidence only.
Visual inspection still shows an upper-end limitation that aggregate scores
understate: Apple's glass becomes nearly opaque while the candidate retains
visible RGB grid structure. That residual remains outside the current
looks-first lighting/refraction work.

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

## Historical verified iOS 27 result

The checked reference set was captured from:

- Xcode 27.0 beta 5 (`27A5237l`)
- iOS 27.0 simulator runtime `24A5408d`
- runtime identifier `com.apple.CoreSimulator.SimRuntime.iOS-27-0`
- iPhone 17 Pro simulator `DB4F41F3-1C36-476D-B775-AFDC3686C75B`
- portrait, light appearance, large content size, Reduce Motion enabled,
  Reduce Transparency disabled

The pre-redesign baseline scored **52.2076**. The best of the 24 fixed candidates scored
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
The add button opens the example loupe composition: Flutter paints a
`RawMagnifier` backdrop first, then the ordinary liquid-glass layer applies its
edge refraction and lighting without magnifying filtered shader pixels.

The current pinned toolbar run (canonical settings, after removing the
center-relative affine lens and the unused legacy shader path) scores
**91.7814** overall under the corrected paired A/B optical-flow metric. Its
four probe captures and diagnostics are in
`out/visual-current-source/`, including the black-background `C_1.png` and
white-background `D_1.png` lighting checks. The geometry field retains the
validated circular-cap profile; the oval SDF now uses Flutter Impeller's
bounded Newton solve to avoid a center pinhole.

The loupe reference is intentionally a background magnifier, so it is now a
separate example-composition fit rather than an ordinary-refraction baseline.
The example should magnify the painted backdrop before handing it to the
ordinary liquid-glass shader; the shader itself must not scale its filtered
sample, which only magnifies pixels. The old fair-S0+10 comparison is retired
because it treated Apple's intentional magnification as a renderer defect.
`refractionSpread` continues to mean SDF profile reach, and the earlier
shader-level affine experiment remains historical evidence only.

When the pinned simulator is available, run the loupe example-composition
seed scan with:

```bash
IOS_27_UDID="$IOS_27_UDID" compare/.venv/bin/python seed_scan.py \
  --scene-id loupe --out out/loupe-seed-scan-effective
```

The scan validates `metadata.json` against the pinned runtime/UDID and emits
`summary.json`, `reference_metadata.json`, `scan.json`, and
`best/scorecard.json`. For the loupe it evaluates the only effective material
axes (`thickness` and `edgeRefraction`); `_MatchLoupe`-forced clear settings
are recorded as overrides rather than falsely searched. It records the
`RawMagnifier` composition and never applies shader-level zoom. The historical
shader-level S0 is retired; this result is composition evidence for the example
loupe.

To probe the shared profile-reach control across recovered geometries, run the
focused grid (it freshly renders every toolbar candidate):

```bash
IOS_27_UDID="$IOS_27_UDID" compare/.venv/bin/python spread_grid.py \
  --out out/spread-grid-current --repetitions 2
```

The grid is diagnostic and should only promote a value if it improves the
small capsule and preserves toolbar/large scores; the current pinned run is
recorded as a rejected experiment in `out/spread-grid-current/summary.json`.

For the stronger coupled probe, use `coupled_spread_scan.py`; it scans the
same shared spread axis while selecting thickness independently per geometry
and preserves every candidate's A-D capture:

```bash
IOS_27_UDID="$IOS_27_UDID" compare/.venv/bin/python coupled_spread_scan.py \
  --out out/coupled-spread-scan --repetitions 1
```

To attribute the remaining capsule residual to an existing shared material
control, run one bounded axis at a time. Every candidate is freshly rendered
for all three capsule scenes and preserves A-D captures plus diagnostics:

```bash
IOS_27_UDID="$IOS_27_UDID" compare/.venv/bin/python material_attribution_scan.py \
  --axis frost --out out/material-attribution-frost
```

Supported axes are `frost`, `transmissionGamma`, `edgeRefraction`, `vibrancy`,
`tintAlpha`, and `chromaticAberration`. The latter includes `0`, which selects
the final shader's one-backdrop-sample path, and the authoritative `.005`
default. The fast path is selected from the requested CA and displacement
magnitude, not CA alone, so large-refraction surfaces retain three-channel
sampling even at the same CA value. Retain an axis only when its summary clears
the documented 10%/20% small-error attribution thresholds and the cross-scene
regression checks;
sub-threshold movement is not a renderer change.

The canonical transparency-vector smoke is in
`out/transparency-shared-vector-smoke/`: positions 0/.5/1 share one material
vector, with only monotonic `tintAlpha` and `frost` scalars allowed to vary.

Focused settings, shader-source, harness, and example smoke/YAML tests are
green. The native Flutter GPU tests require an Impeller-enabled device and
cannot run in this headless environment. We are intentionally deferring the
expensive macOS/Android benchmark suite until the visual settings and example
workflow are stable; tab/capsule holdout scorecards and the final performance
audit remain hard gates before calling this production-ready.

## Current redesign evidence (2026-08-25)

The historical staged-search notes above describe the pre-redesign harness.
The current renderer and harness use the following Apple-layer mapping; this
table is the contract for new changes:

| Apple layer/effect | Current implementation | Evidence/constraint |
| --- | --- | --- |
| `CASDFElementLayer` / `CASDFOutputEffect` | One shared SDF geometry matte and displacement field | Same geometry pass; no extra capture |
| `CABackdropLayer.glassBackground` | Final shader displacement sample, frost, saturation, gamma, and vibrancy | `frost` is compositor blur; smaller controls receive a derived size-normalized sigma |
| Opposite `CASDFGlassHighlightEffect` lobes | Paired directional highlight and opposite-light response from the displacement normal | Controlled by the single `highlight` lobe |
| Dielectric silhouette/absorption | SDF-derived dark contour in the final shader | `contourStrength` and `contourWidth` share the same profile |
| `vibrantColorMatrix` | `saturation`, `transmissionGamma`, and `vibrancy` | No independent face-fill or inner-shadow workaround knobs |
| iOS 27 tint amount | `tint` alpha plus the documented transparency sweep scalars | Slider positions must share one vector and vary at most two scalars |
| Text-selection loupe | Flutter `RawMagnifier` paints the backdrop first, then ordinary glass | Example/harness composition only; no shader-level zoom |

The evidence ledger below is intentionally explicit about what is and is not a
final gate. Scores use the corrected paired A/B optical-flow metric.

| Scene/capture | Current score | Evidence |
| --- | ---: | --- |
| Toolbar | 91.7814 | `out/metric-ab-audit/toolbar/scorecard.json` |
| Small capsule (shared vector) | 85.2647 | `out/generalization-toolbar-vector/small_capsule/final/scorecard.json` (historical standalone fit: 86.3452) |
| Large capsule (shared vector) | 89.4927 | `out/generalization-toolbar-vector/large_capsule/final/scorecard.json` (historical standalone fit: 80.6343) |
| Tab-bar holdout | 43.0289 | `out/generalization-ab-geometry-1/tab_bar_holdout/final/scorecard.json` |
| Loupe | 13.5557 | `out/loupe-scorecard-effective/final/scorecard.json` (fresh pinned iOS 27; pre-shader `RawMagnifier`) |

The small-control fit uses the same material vector as the toolbar and derives
its lower frost sigma from rendered height; it does not add a public knob or a
render pass. The tab holdout includes deterministic harness-only foreground
content because Apple's `TabView` reference contains icons, labels, and a
selection treatment; shipped callers still provide their own child content.

### Surviving settings and evidence policy

`LiquidGlassSettings` intentionally exposes only the following material axes:

| Setting | Meaning | Required evidence before changing/removing |
| --- | --- | --- |
| `visibility` | Transition multiplier | API utility; not a material-fit axis |
| `tint` | Unified material color/transparency | Toolbar + at least one capsule/holdout |
| `thickness` | Optical profile depth | Toolbar + small/large capsule fits |
| `edgeRefraction` | Peak rim displacement in logical pixels | Toolbar + small/large capsule fits |
| `refractionSpread` | SDF profile reach, never backdrop zoom | At least two non-loupe scenes |
| `frost` | Backdrop softening radius | Toolbar + small capsule; size normalization is internal |
| `chromaticAberration` | Wavelength separation at the rim | Retain only after two-scene improvement |
| `saturation` | Transmitted backdrop saturation | Toolbar + capsule/holdout |
| `transmissionGamma` | Display-referred transmission curve | Toolbar + capsule/holdout |
| `vibrancy` | Backdrop-aware chroma lift | Toolbar + capsule/holdout |
| `highlight` | Paired directional highlight lobe | Black/white toolbar + capsule |
| `contourStrength` | Dark dielectric contour strength | White-background toolbar + capsule |
| `contourWidth` | Contour width in logical pixels | White-background toolbar + capsule |

Legacy names (`blurMix`, `glassAlpha`, `refractiveIndex`, independent rim RGB
triplets, and `innerShadow*`) are harness compatibility inputs only and are not
part of shipped `lib/src`.

### Escalation contract

The goal is not production-ready until the pinned iOS 27 evidence and the
performance audit are complete. A visual change may be accepted only when it
improves the relevant decomposed metric in at least two scenes, remains within
the shared-vector transparency rule, and does not add a pass, texture, backdrop
capture, or per-frame CPU solve. If a score improves while a black/white
lighting residual worsens, keep the residual visible and do not hide it in a
new independent shader weight. Simulator service failures are infrastructure
blockers; never close unrelated simulators or weaken the pinned-device gate.

### Annotating comparison images

Images posted from the harness should identify panel provenance and candidate
settings. The deterministic overlay preserves source pixels and adds only a
metadata header and panel labels:

```bash
python3 annotate_comparison.py \
  --input out/<run>/holdout_comparison.png \
  --output out/<run>/holdout_comparison-annotated.png \
  --title 'small_capsule comparison' \
  --subtitle 'frost=7; score=85.2647; combined=.063668' \
  --label 'APPLE GROUND TRUTH' \
  --label 'FLUTTER CANDIDATE' \
  --label 'DIFF / RESIDUAL'
```

The left panel is always labeled explicitly as the Apple ground truth; never
rely on panel order alone when sharing a comparison.

The current parameter-by-parameter report and annotated iteration index are in
[`FULL_REPORT.md`](FULL_REPORT.md).
