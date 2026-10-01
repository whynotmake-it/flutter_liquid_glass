# Apple liquid-glass matching

Matches `liquid_glass_renderer` against pinned iOS 27 captures of public
SwiftUI glass (`.buttonStyle(.glass)`, the system tab bar, the loupe). No
private API. The pipeline has four steps: capture Apple, render ours, compare,
crop.

## Layout

| Path | Step |
| --- | --- |
| `scenes/` | Scene JSON (geometry, canvas, probes A–D) shared by both sides; `schema.json` validates them. |
| `apple/` | SwiftUI capture app and the pinned-simulator capture scripts. |
| `references/` | Immutable Apple capture sets. Replacing one needs `FORCE_REFERENCE=1`. |
| `flutter/` | Standalone Flutter capture target for the same scenes (its own package). |
| `../../test/bottom_bar_match_test.dart` | Captures the example's tab bar, loupe and toolbar at iPhone 17 Pro size. |
| `compare/` | Python metrics package (`apple_match`), CLI and tests. |
| `settings/` | Renderer settings the fits start from or ended at. |
| `results/` (in `../results/`) | `apple-match-report.md`, the full write-up. |
| `MODEL_DESIGN.md` | How the glass model maps to Apple's layers. |
| `out/` | Ignored candidates, scores and atlases. |

## Setup

Xcode with the iOS 27 SDK, Flutter 3.47.1, `agent-device >= 0.14.0`, Python 3:

```sh
cd packages/liquid_glass_renderer/example/tool/apple_match
python3 -m venv compare/.venv
compare/.venv/bin/pip install -r compare/requirements.txt pillow
export IOS_27_UDID="$(compare/.venv/bin/python pin_simulator.py)"
PYTHONPATH=compare compare/.venv/bin/python -m unittest discover -s compare/tests
(cd flutter && flutter pub get && flutter analyze && flutter test)
```

The simulator is pinned to `AppleMatch-iPhone17Pro-iOS27`: portrait,
402 × 874 pt at 3×, Reduce Transparency off. Reduce Motion removes lensing,
so fit refraction only against references with `"reduceMotion": false` in
their `metadata.json`.

`REDUCE_MOTION=0` (for `apple/capture.sh` and `apple/capture_loupe.sh`)
captures with Reduce Motion disabled, waits `CAPTURE_SETTLE_SECONDS`
(default 4) after each launch, and writes to
`references/ios27-iphone17pro-reduce-motion-off/slider-000` (loupe:
`references/ios27-iphone17pro-reduce-motion-off/loupe`). Changing the value
reboots the target simulator so system processes pick it up.
`apple/capture_slider_sweep.sh` repeats those captures across the Liquid Glass
slider (Settings → Appearance → Liquid Glass) into `slider-000` … `slider-100`;
every `metadata.json` records the declared and read-back slider value.

Material scenes may set `"glassVariant": "clear"` for `.glassEffect(.clear)`.
`material_capsule_toolbar_size_dark` is a `.regular` material capsule at the
toolbar button's measured glass rect (224×94 at 89,390), which separates the
`.glass` button style from size when compared with `toolbar_capsule_dark`.

```bash
REDUCE_MOTION=0 LIQUID_GLASS_TINT_POSITION=0 SCENE_ID=toolbar_capsule \
  bash apple/capture.sh
```

## 1. Capture Apple references

```sh
bash apple/build.sh
REDUCE_MOTION=0 SCENE_ID=toolbar_capsule bash apple/capture.sh
bash apple/capture_loupe.sh
bash apple/capture_ground_truth_matrix.sh   # the ground-truth scene matrix
```

Each capture is validated frame by frame (`validate_probe_frame.py`) and
checked for provenance (`reference_provenance.py`, `audit_ground_truth.py`).
`LIQUID_GLASS_TINT_POSITION` sets the Liquid Glass transparency slider
(`apple/set_transparency_slider.sh`).

## 2. Render ours

The fast path renders the scene through macOS Impeller and Flutter GPU, with
no simulator:

```sh
SETTINGS_FILE="$PWD/settings/baseline.json" \
CANDIDATE_OUT="$PWD/out/candidates/baseline" \
SCENE_FILE="$PWD/scenes/toolbar_capsule.json" \
bash flutter/host_capture.sh
```

`flutter/capture.sh` does the same on the pinned simulator; use it to confirm
a host result before trusting it. For the example app's bottom bar:

```sh
cd ../..   # example/
flutter test --enable-impeller --enable-flutter-gpu \
  --dart-define=BOTTOM_BAR_MATCH_OUT=/tmp/bottom-bar-match \
  test/bottom_bar_match_test.dart
```

## 3. Compare

```sh
PYTHONPATH=compare compare/.venv/bin/python -m apple_match.cli --host-capture \
  --reference references/ios27-iphone17pro-light/toolbar_capsule \
  --candidate out/candidates/baseline --output out/score \
  --settings out/candidates/baseline/settings.json \
  --scene scenes/toolbar_capsule.json
compare/.venv/bin/python solid_color_metrics.py --help   # color transfer
compare/.venv/bin/python rim_report.py --help            # rim, glint, face
```

`run.py` does capture, render and compare in one go on the simulator.
`hotloop_staged.py` searches settings stage by stage (`settings/stages.json`:
shape, refraction, tint, highlight, outline, blur) with one persistent
Flutter session.

## 4. Crops

```sh
compare/.venv/bin/python zoom_atlas.py --zoom 5 --stage lighting \
  --reference references/ios27-iphone17pro-light/toolbar_capsule \
  --candidate out/candidates/baseline --scene scenes/toolbar_capsule.json \
  --output out/atlas-lighting.png --title "toolbar, lighting"
```

Apple and ours side by side, whole probes plus magnified crops of the
corner, rim, face and highlight.

## Settings

- `baseline.json`, `fake_glass_baseline.json`, `stages.json`: search inputs.
- `fit-lighting-v2-*.json`: the lighting fits (toolbar, material, dark).
- `color-model-{light,dark}.json`, `tint-model-*.json`: the color and tint
  fits.
- `loupe-clear-axes.json`: the loupe search space.

The shipped values live in the renderer's presets; these files reproduce the
fits that produced them.

## On-device A/B

`lib/glint_ab_main.dart` shows iOS's own glass (a `UIGlassEffect` platform
view) next to ours over the same Flutter content, on an iOS 26+ device:
`flutter run -t lib/glint_ab_main.dart`.
