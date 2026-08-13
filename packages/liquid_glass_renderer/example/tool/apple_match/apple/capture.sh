#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${IOS_27_UDID:?Set IOS_27_UDID to the pinned iOS 27 simulator UDID}"
: "${REFERENCE_SET:=ios27-iphone17pro-light}"
: "${CAPTURE_FRAMES:=3}"
: "${SCENE_ID:=toolbar_capsule}"
: "${LIQUID_GLASS_TINT_POSITION:=}"
: "${LIQUID_GLASS_TINT_CONTROL_METHOD:=}"
export SCENE_ID CAPTURE_FRAMES IOS_27_UDID
export LIQUID_GLASS_TINT_POSITION LIQUID_GLASS_TINT_CONTROL_METHOD
SCENE="$ROOT/scenes/$SCENE_ID.json"
[[ -f "$SCENE" ]] || { echo "Unknown scene: $SCENE_ID" >&2; exit 2; }
OUT="$ROOT/references/$REFERENCE_SET/$SCENE_ID"
API="SwiftUI PrimitiveButtonStyle.glass"
[[ "$SCENE_ID" == "tab_bar_holdout" ]] && API="SwiftUI TabView system tab bar"
export APPLE_MATCH_API="$API"

if [[ -d "$OUT" && "${FORCE_REFERENCE:-0}" != "1" ]]; then
  echo "Pinned reference exists at $OUT; set FORCE_REFERENCE=1 to replace it." >&2
  exit 3
fi
if [[ -d "$OUT" && "${FORCE_REFERENCE:-0}" == "1" ]]; then
  rm -rf "$OUT"
fi

"$ROOT/apple/build.sh"
mkdir -p "$OUT"
mkdir -p "$OUT/frames"
xcrun simctl boot "$IOS_27_UDID" 2>/dev/null || true
xcrun simctl bootstatus "$IOS_27_UDID" -b
xcrun simctl install "$IOS_27_UDID" "$ROOT/apple/build/AppleMatch.app"
xcrun simctl ui "$IOS_27_UDID" appearance light
xcrun simctl ui "$IOS_27_UDID" content_size large
xcrun simctl ui "$IOS_27_UDID" increase_contrast disabled
xcrun simctl spawn "$IOS_27_UDID" defaults write com.apple.Accessibility \
  ReduceMotionEnabled -bool YES
xcrun simctl spawn "$IOS_27_UDID" defaults write com.apple.Accessibility \
  ReduceTransparencyEnabled -bool NO
xcrun simctl terminate "$IOS_27_UDID" com.apple.Preferences >/dev/null 2>&1 || true
xcrun simctl terminate "$IOS_27_UDID" com.callstack.agentdevice.runner >/dev/null 2>&1 || true

screenshot_frame() {
  local probe="$1"
  local destination="$2"
  local attempt
  for attempt in $(seq 1 12); do
    xcrun simctl io "$IOS_27_UDID" screenshot "$destination"
    if python3 - "$probe" "$destination" <<'PY'
import cv2
import sys

expected = {
    "A": (0, 0, 255),
    "B": (0, 0, 255),
    "C": (0, 0, 0),
    "D": (255, 255, 255),
}[sys.argv[1]]
image = cv2.imread(sys.argv[2], cv2.IMREAD_COLOR)
pixel = tuple(int(value) for value in image[5, 5])
probe = sys.argv[1]
if probe in "AB":
    valid = pixel == expected
elif probe == "C":
    valid = max(pixel) <= 16
else:
    valid = min(pixel) >= 239
raise SystemExit(0 if valid else 1)
PY
    then
      return
    fi
    sleep 1
  done
  echo "Apple frame never reached expected $probe background." >&2
  return 5
}

for probe in A B C D; do
  xcrun simctl terminate "$IOS_27_UDID" com.apple.Preferences >/dev/null 2>&1 || true
  xcrun simctl launch --terminate-running-process "$IOS_27_UDID" \
    dev.liquidglass.applematch --args --scene-id "$SCENE_ID" --probe "$probe"
  sleep 1
  for frame in $(seq 1 "$CAPTURE_FRAMES"); do
    screenshot_frame "$probe" "$OUT/frames/${probe}_$frame.png"
    sleep 0.1
  done
  xcrun simctl terminate "$IOS_27_UDID" dev.liquidglass.applematch
  sleep 0.5
  python3 "$ROOT/compare/median_frames.py" "$OUT/$probe.png" \
    "$OUT"/frames/"${probe}"_*.png
done

python3 - "$OUT/metadata.json" <<'PY'
import json
import os
import sys
from pathlib import Path

raw = os.environ.get("LIQUID_GLASS_TINT_POSITION", "")
position = float(raw) if raw else None
Path(sys.argv[1]).write_text(
    json.dumps(
        {
            "runtime": "iOS 27.0 (24A5408d)",
            "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
            "udid": os.environ["IOS_27_UDID"],
            "device": "iPhone 17 Pro",
            "orientation": "portrait",
            "appearance": "light",
            "reduceMotion": True,
            "medianFrameCount": int(os.environ.get("CAPTURE_FRAMES", "3")),
            "reduceTransparency": False,
            "liquidGlassTintPosition": position,
            "liquidGlassTintControlMethod": os.environ.get(
                "LIQUID_GLASS_TINT_CONTROL_METHOD", ""
            ),
            "api": os.environ["APPLE_MATCH_API"],
            "scene": os.environ["SCENE_ID"],
        },
        indent=2,
    )
    + "\n"
)
PY
echo "$OUT"
