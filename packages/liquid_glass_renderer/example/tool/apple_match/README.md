# Apple liquid-glass matching

This directory is an executable, deterministic scorecard for matching
`liquid_glass_renderer` to a pinned official iOS 27 SwiftUI control. It does
not use screenshot “vibe checks,” private `_UIViewGlass`, private uniforms, or
Apple's Liquid Glass transparency slider.

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
  gradient-sharpness, specular, tint metrics, and tests.
- `settings/`: baseline and bounded deterministic search space.
- `references/`: immutable, named Apple capture sets. Replacement requires
  `FORCE_REFERENCE=1`.
- `out/`: ignored candidates, diagnostics, and scorecards.

## Reproducible setup

Requirements:

- Xcode with the iOS 27 SDK and accepted Xcode license.
- Flutter 3.44.1.
- `agent-device >= 0.14.0`.
- Python 3 with packages pinned by `compare/requirements.txt`.

```bash
cd packages/liquid_glass_renderer/example/tool/apple_match
export DEVELOPER_DIR=/Applications/Xcode-27.0.0-Beta.5.app/Contents/Developer
export FLUTTER_BIN="$HOME/fvm/versions/3.44.1/bin/flutter"
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
cd compare
PYTHONPATH=. python3 -m unittest discover -s tests -v
cd ../flutter
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

Generated build products, virtual environments, caches, and candidate output
are ignored. Only small, deliberately reviewed reference/evidence PNGs should
be versioned. No production renderer or shader changes are required by the
harness itself.
