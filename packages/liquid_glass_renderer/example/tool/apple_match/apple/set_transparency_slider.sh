#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${IOS_27_UDID:?Set IOS_27_UDID to the pinned iOS 27 simulator UDID}"
: "${DEVELOPER_DIR:=/Applications/Xcode-27.0.0-Beta.5.app/Contents/Developer}"
export DEVELOPER_DIR

POSITION="${1:?Usage: set_transparency_slider.sh <0...1>}"
python3 - "$POSITION" <<'PY'
import sys

position = float(sys.argv[1])
if not 0.0 <= position <= 1.0:
    raise SystemExit("slider position must be between 0 and 1")
PY

# Settings → Appearance → Liquid Glass "Tint Amount" writes this UIKit default.
# XCUITest adjust(toNormalizedSliderPosition:) cannot hit exact percents
# (0.25 landed at 34) and a failed test then spent ~10 minutes in simctl diagnose.
xcrun simctl spawn "$IOS_27_UDID" defaults write com.apple.UIKit \
  UIViewGlassTintAmount -float "$POSITION"
xcrun simctl spawn "$IOS_27_UDID" defaults write com.apple.UIKit \
  UIViewGlassEverEditedInSettings -bool YES

ACTUAL="$(xcrun simctl spawn "$IOS_27_UDID" defaults read com.apple.UIKit UIViewGlassTintAmount)"
python3 - "$POSITION" "$ACTUAL" <<'PY'
import sys

wanted = float(sys.argv[1])
actual = float(sys.argv[2])
if abs(wanted - actual) > 0.001:
    raise SystemExit(f"UIViewGlassTintAmount readback {actual} != {wanted}")
PY

# Fresh processes pick the default up at launch. capture.sh relaunches AppleMatch.
xcrun simctl terminate "$IOS_27_UDID" com.apple.Preferences >/dev/null 2>&1 || true
xcrun simctl terminate "$IOS_27_UDID" dev.liquidglass.applematch >/dev/null 2>&1 || true

echo "LIQUID_GLASS_TINT_POSITION=$POSITION"
echo "LIQUID_GLASS_TINT_CONTROL_METHOD=simctl defaults write com.apple.UIKit UIViewGlassTintAmount"
