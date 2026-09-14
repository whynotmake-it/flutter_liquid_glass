#!/usr/bin/env bash
set -euo pipefail

# Capture pinned iOS 27 simulator references for the text-selection loupe
# scene. Unlike capture.sh (static SwiftUI controls), the loupe only exists
# during an active text-selection long-press, so this driver holds the press
# with agent-device while simctl screenshots the settled loupe.
#
# Required env:
#   IOS_27_UDID  UDID of the pinned iOS 27 simulator
# Optional env:
#   REFERENCE_SET   reference directory name (default ios27-iphone17pro-light)
#   CAPTURE_FRAMES  frames medianed per probe (default 3)
#   FORCE_REFERENCE 1 = replace an existing pinned reference
#   LOUPE_TOUCH_X / LOUPE_TOUCH_Y  long-press point in logical pt
#   LOUPE_HOLD_MS   long-press duration (default 4500)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${IOS_27_UDID:?Set IOS_27_UDID to the pinned iOS 27 simulator UDID}"
: "${REFERENCE_SET:=ios27-iphone17pro-light}"
: "${CAPTURE_FRAMES:=3}"
: "${LOUPE_TOUCH_X:=201}"
: "${LOUPE_TOUCH_Y:=620}"
: "${LOUPE_HOLD_MS:=4500}"
: "${DEVELOPER_DIR:=/Applications/Xcode-27.0.0-Beta.5.app/Contents/Developer}"
export DEVELOPER_DIR
SCENE_ID="loupe"
export SCENE_ID

# agent-device keys its session state by process cwd; pin every call to one
# directory and one named session so open/longpress/close always agree.
AD_SESSION="applematch-loupe"
cd "$ROOT"

SCENE="$ROOT/scenes/$SCENE_ID.json"
[[ -f "$SCENE" ]] || { echo "Unknown scene: $SCENE_ID" >&2; exit 2; }
OUT="$ROOT/references/$REFERENCE_SET/$SCENE_ID"
API="iOS 27 system text-selection loupe (UITextView long-press)"
export APPLE_MATCH_API="$API"

if [[ -d "$OUT" && "${FORCE_REFERENCE:-0}" != "1" ]]; then
  echo "Pinned reference exists at $OUT; set FORCE_REFERENCE=1 to replace it." >&2
  exit 3
fi
if [[ -d "$OUT" && "${FORCE_REFERENCE:-0}" == "1" ]]; then
  rm -rf "$OUT"
fi

"$ROOT/apple/build.sh"
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
cleanup() {
  agent-device close --platform ios --udid "$IOS_27_UDID" \
    --session "$AD_SESSION" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Screenshot the probe background and verify its corner pixel matches the
# expected probe before any gesture runs (same contract as capture.sh).
verify_background() {
  local probe="$1" destination="$2" attempt
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

# True when the loupe region deviates from the un-pressed reference frame.
loupe_present() {
  local candidate="$1" reference="$2"
  python3 - "$candidate" "$reference" <<'PY'
import cv2
import numpy as np
import sys

candidate = cv2.imread(sys.argv[1], cv2.IMREAD_GRAYSCALE).astype(int)
reference = cv2.imread(sys.argv[2], cv2.IMREAD_GRAYSCALE).astype(int)
# Loupe capsule region in device pixels (logical ~x142-260, y500-590).
region_c = candidate[1480:1800, 400:820]
region_r = reference[1480:1800, 400:820]
mean_abs_diff = float(np.abs(region_c - region_r).mean())
raise SystemExit(0 if mean_abs_diff > 1.5 else 1)
PY
}

for probe in A B C D; do
  xcrun simctl launch --terminate-running-process "$IOS_27_UDID" \
    dev.liquidglass.applematch --args --scene-id "$SCENE_ID" --probe "$probe"
  sleep 1.8
  verify_background "$probe" "$OUT/bg_$probe.png"

  frame=1
  attempt=1
  while (( frame <= CAPTURE_FRAMES )); do
    agent-device open dev.liquidglass.applematch --platform ios \
      --udid "$IOS_27_UDID" --relaunch --session "$AD_SESSION" \
      --launch-args=--scene-id --launch-args="$SCENE_ID" \
      --launch-args=--probe --launch-args="$probe" >/dev/null 2>&1
    sleep 1.8
    verify_background "$probe" "$OUT/bg_$probe.png"

    agent-device longpress "$LOUPE_TOUCH_X" "$LOUPE_TOUCH_Y" "$LOUPE_HOLD_MS" \
      --platform ios --udid "$IOS_27_UDID" --session "$AD_SESSION" \
      >/dev/null 2>&1 &
    local_lp_pid=$!
    sleep 1.5
    candidate="$OUT/frames/${probe}_${frame}_try${attempt}.png"
    xcrun simctl io "$IOS_27_UDID" screenshot "$candidate"
    wait "$local_lp_pid" || true

    if loupe_present "$candidate" "$OUT/bg_$probe.png"; then
      mv "$candidate" "$OUT/frames/${probe}_${frame}.png"
      frame=$((frame + 1))
      attempt=1
      sleep 0.3
    else
      attempt=$((attempt + 1))
      if (( attempt > 5 )); then
        echo "Loupe never appeared for probe $probe frame $frame." >&2
        exit 6
      fi
      sleep 1
    fi
  done

  xcrun simctl terminate "$IOS_27_UDID" dev.liquidglass.applematch \
    >/dev/null 2>&1 || true
  sleep 0.5
  python3 "$ROOT/compare/median_frames.py" "$OUT/$probe.png" \
    "$OUT"/frames/"${probe}"_[0-9].png
done

python3 - "$OUT/metadata.json" <<'PY'
import json
import os
import sys
from pathlib import Path

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
            "api": os.environ["APPLE_MATCH_API"],
            "scene": os.environ["SCENE_ID"],
            "touchPoint": [
                float(os.environ.get("LOUPE_TOUCH_X", "201")),
                float(os.environ.get("LOUPE_TOUCH_Y", "620")),
            ],
        },
        indent=2,
    )
    + "\n"
)
PY
echo "$OUT"
