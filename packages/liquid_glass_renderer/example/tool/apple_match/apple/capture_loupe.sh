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
#   SCENE_ID        loupe scene (default loupe; loupe_dark for dark appearance)
#   REFERENCE_SET   reference directory name (default ios27-iphone17pro-light)
#   CAPTURE_FRAMES  frames medianed per probe (default 3)
#   FORCE_REFERENCE 1 = replace an existing pinned reference
#   LOUPE_TOUCH_X / LOUPE_TOUCH_Y  long-press point in logical pt
#   LOUPE_HOLD_MS   long-press duration (default 4500)
#   REDUCE_MOTION   1 (default, historical references) or 0; see capture.sh
#   CAPTURE_SETTLE_SECONDS  wait after each launch before verifying the probe
#   LOUPE_CAPTURE_DELAY     wait between long-press start and screenshot

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${IOS_27_UDID:?Set IOS_27_UDID to the pinned iOS 27 simulator UDID}"
: "${REDUCE_MOTION:=1}"
case "$REDUCE_MOTION" in
  1) REDUCE_MOTION_DEFAULT=YES
     : "${REFERENCE_SET:=ios27-iphone17pro-light}"
     : "${CAPTURE_SETTLE_SECONDS:=1.8}"
     : "${LOUPE_CAPTURE_DELAY:=1.5}" ;;
  0) REDUCE_MOTION_DEFAULT=NO
     : "${REFERENCE_SET:=ios27-iphone17pro-reduce-motion-off/loupe}"
     : "${CAPTURE_SETTLE_SECONDS:=4}"
     : "${LOUPE_CAPTURE_DELAY:=2.5}" ;;
  *) echo "REDUCE_MOTION must be 0 or 1" >&2; exit 2 ;;
esac
export REDUCE_MOTION CAPTURE_SETTLE_SECONDS LOUPE_CAPTURE_DELAY
: "${CAPTURE_FRAMES:=3}"
: "${LOUPE_TOUCH_X:=201}"
: "${LOUPE_TOUCH_Y:=620}"
: "${LOUPE_HOLD_MS:=4500}"
: "${SCENE_ID:=loupe}"

# agent-device keys its session state by process cwd; pin every call to one
# directory and one named session so open/longpress/close always agree.
AD_SESSION="applematch-loupe"
cd "$ROOT"

SCENE="$ROOT/scenes/$SCENE_ID.json"
[[ -f "$SCENE" ]] || { echo "Unknown scene: $SCENE_ID" >&2; exit 2; }
APPEARANCE="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["appearance"])' "$SCENE")"
export APPEARANCE
FINAL_OUT="$ROOT/references/$REFERENCE_SET/$SCENE_ID"
if [[ -n "${CAPTURE_PROBES:-}" ]]; then
  echo "CAPTURE_PROBES subsets are not valid Apple references; capture the full scene." >&2
  exit 2
fi
CAPTURE_PROBES="$(python3 - "$SCENE" <<'PY'
import json
import sys

scene = json.load(open(sys.argv[1]))
print(" ".join(probe["id"] for probe in scene["probes"]))
PY
)"
export CAPTURE_PROBES SCENE_ID LOUPE_TOUCH_X LOUPE_TOUCH_Y LOUPE_HOLD_MS

if [[ -d "$FINAL_OUT" && "${FORCE_REFERENCE:-0}" != "1" ]]; then
  echo "Pinned reference exists at $FINAL_OUT; set FORCE_REFERENCE=1 to replace it." >&2
  exit 3
fi

"$ROOT/apple/build.sh"
STAGING_PARENT="$ROOT/references/.staging"
mkdir -p "$STAGING_PARENT"
OUT="$(mktemp -d "$STAGING_PARENT/${SCENE_ID}.XXXXXX")"
TEMP_OUT="$(mktemp -d "$STAGING_PARENT/${SCENE_ID}.loupe-temp.XXXXXX")"
mkdir -p "$OUT/frames"
xcrun simctl boot "$IOS_27_UDID" 2>/dev/null || true
xcrun simctl bootstatus "$IOS_27_UDID" -b
# System processes read accessibility defaults at startup; reboot before any
# other setting or install, as in capture.sh.
PREVIOUS_REDUCE_MOTION="$(xcrun simctl spawn "$IOS_27_UDID" defaults read \
  com.apple.Accessibility ReduceMotionEnabled 2>/dev/null || echo unset)"
xcrun simctl spawn "$IOS_27_UDID" defaults write com.apple.Accessibility \
  ReduceMotionEnabled -bool "$REDUCE_MOTION_DEFAULT"
if [[ "$PREVIOUS_REDUCE_MOTION" != "$REDUCE_MOTION" ]]; then
  xcrun simctl shutdown "$IOS_27_UDID"
  # shutdown can return before the device stops; booting early races it.
  while ! xcrun simctl list devices | grep "$IOS_27_UDID" | grep -q "(Shutdown)"; do
    sleep 1
  done
  xcrun simctl boot "$IOS_27_UDID"
  xcrun simctl bootstatus "$IOS_27_UDID" -b
  sleep 5
fi
REDUCE_MOTION_READBACK="$(xcrun simctl spawn "$IOS_27_UDID" defaults read \
  com.apple.Accessibility ReduceMotionEnabled)"
if [[ "$REDUCE_MOTION_READBACK" != "$REDUCE_MOTION" ]]; then
  echo "declared Reduce Motion $REDUCE_MOTION != readback $REDUCE_MOTION_READBACK" >&2
  exit 4
fi
if [[ -n "${LIQUID_GLASS_TINT_POSITION:-}" ]]; then
  python3 - "$LIQUID_GLASS_TINT_POSITION" <<'PY'
import sys

position = float(sys.argv[1])
if not 0.0 <= position <= 1.0:
    raise SystemExit("slider position must be between 0 and 1")
PY
  xcrun simctl spawn "$IOS_27_UDID" defaults write com.apple.UIKit \
    UIViewGlassTintAmount -float "$LIQUID_GLASS_TINT_POSITION"
  xcrun simctl spawn "$IOS_27_UDID" defaults write com.apple.UIKit \
    UIViewGlassEverEditedInSettings -bool YES
  : "${LIQUID_GLASS_TINT_CONTROL_METHOD:=simctl defaults write com.apple.UIKit UIViewGlassTintAmount}"
else
  : "${LIQUID_GLASS_TINT_CONTROL_METHOD:=simctl defaults read com.apple.UIKit UIViewGlassTintAmount}"
fi
LIQUID_GLASS_TINT_READBACK="$(xcrun simctl spawn "$IOS_27_UDID" defaults read \
  com.apple.UIKit UIViewGlassTintAmount)"
: "${LIQUID_GLASS_TINT_POSITION:=$LIQUID_GLASS_TINT_READBACK}"
python3 - "$LIQUID_GLASS_TINT_POSITION" "$LIQUID_GLASS_TINT_READBACK" <<'PY'
import sys

declared = float(sys.argv[1])
actual = float(sys.argv[2])
if abs(declared - actual) > 0.001:
    raise SystemExit(
        f"declared Liquid Glass Tint Amount {declared} != readback {actual}"
    )
PY
export LIQUID_GLASS_TINT_POSITION LIQUID_GLASS_TINT_READBACK
: "${LIQUID_GLASS_TINT_CONTROL_METHOD:=simctl defaults write com.apple.UIKit UIViewGlassTintAmount}"
export LIQUID_GLASS_TINT_CONTROL_METHOD
xcrun simctl install "$IOS_27_UDID" "$ROOT/apple/build/AppleMatch.app"
xcrun simctl ui "$IOS_27_UDID" appearance "$APPEARANCE"
xcrun simctl ui "$IOS_27_UDID" content_size large
xcrun simctl ui "$IOS_27_UDID" increase_contrast disabled
xcrun simctl spawn "$IOS_27_UDID" defaults write com.apple.Accessibility \
  ReduceTransparencyEnabled -bool NO
cleanup() {
  agent-device close --platform ios --udid "$IOS_27_UDID" \
    --session "$AD_SESSION" >/dev/null 2>&1 || true
  if [[ -n "${TEMP_OUT:-}" && -d "$TEMP_OUT" ]]; then
    rm -rf "$TEMP_OUT"
  fi
}
trap cleanup EXIT

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

for probe in $CAPTURE_PROBES; do
  xcrun simctl launch --terminate-running-process "$IOS_27_UDID" \
    dev.liquidglass.applematch --args --scene-id "$SCENE_ID" --probe "$probe"
  sleep "$CAPTURE_SETTLE_SECONDS"
  background="$TEMP_OUT/bg_$probe.png"
  xcrun simctl io "$IOS_27_UDID" screenshot "$background"

  frame=1
  attempt=1
  while (( frame <= CAPTURE_FRAMES )); do
    agent-device open dev.liquidglass.applematch --platform ios \
      --udid "$IOS_27_UDID" --relaunch --session "$AD_SESSION" \
      --launch-args=--scene-id --launch-args="$SCENE_ID" \
      --launch-args=--probe --launch-args="$probe" >/dev/null 2>&1
    sleep "$CAPTURE_SETTLE_SECONDS"

    agent-device longpress "$LOUPE_TOUCH_X" "$LOUPE_TOUCH_Y" "$LOUPE_HOLD_MS" \
      --platform ios --udid "$IOS_27_UDID" --session "$AD_SESSION" \
      >/dev/null 2>&1 &
    local_lp_pid=$!
    sleep "$LOUPE_CAPTURE_DELAY"
    candidate="$TEMP_OUT/${probe}_${frame}_try${attempt}.png"
    xcrun simctl io "$IOS_27_UDID" screenshot "$candidate"
    wait "$local_lp_pid" || true

    if python3 "$ROOT/validate_probe_frame.py" "$SCENE" "$probe" "$candidate" \
      && loupe_present "$candidate" "$background"; then
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
    "$OUT"/frames/"${probe}"_*.png
done

RUNTIME_IDENTIFIER="$(xcrun simctl list devices -j | python3 -c '
import json
import sys

devices = json.load(sys.stdin)["devices"]
print(next(
    runtime
    for runtime, runtime_devices in devices.items()
    for device in runtime_devices
    if device["udid"] == sys.argv[1]
))
' "$IOS_27_UDID")"
RUNTIME_LABEL="$(xcrun simctl list runtimes -j | python3 -c '
import json
import sys

runtime = next(
    item for item in json.load(sys.stdin)["runtimes"]
    if item["identifier"] == sys.argv[1]
)
print("{} ({})".format(runtime["name"], runtime["buildversion"]))
' "$RUNTIME_IDENTIFIER")"
python3 "$ROOT/reference_provenance.py" "$OUT" "$SCENE" \
  --source "$ROOT/apple/Sources/AppleMatchApp.swift" \
  --capture-script "$ROOT/apple/capture_loupe.sh" \
  --write \
  --runtime "$RUNTIME_LABEL" \
  --runtime-identifier "$RUNTIME_IDENTIFIER" \
  --udid "$IOS_27_UDID" \
  --device "iPhone 17 Pro" \
  --appearance "$APPEARANCE" \
  --slider "$LIQUID_GLASS_TINT_POSITION" \
  --slider-readback "$LIQUID_GLASS_TINT_READBACK" \
  --slider-method "$LIQUID_GLASS_TINT_CONTROL_METHOD" \
  --frames "$CAPTURE_FRAMES" \
  --reduce-motion "$REDUCE_MOTION" \
  --settle-seconds "$CAPTURE_SETTLE_SECONDS"

python3 - "$OUT/metadata.json" <<'PY'
import json
import os
import sys
from pathlib import Path

Path(sys.argv[1]).write_text(
    json.dumps(
        {
            **json.loads(Path(sys.argv[1]).read_text()),
            "loupeCaptureDelaySeconds": float(os.environ["LOUPE_CAPTURE_DELAY"]),
            "touchPoint": [
                float(os.environ["LOUPE_TOUCH_X"]),
                float(os.environ["LOUPE_TOUCH_Y"]),
            ],
        },
        indent=2,
    ) + "\n"
)
PY

python3 "$ROOT/reference_provenance.py" "$OUT" "$SCENE" \
  --source "$ROOT/apple/Sources/AppleMatchApp.swift" \
  --capture-script "$ROOT/apple/capture_loupe.sh"

mkdir -p "$(dirname "$FINAL_OUT")"
if [[ -d "$FINAL_OUT" ]]; then
  mv "$FINAL_OUT" "${FINAL_OUT}.replaced-$(date -u +%Y%m%dT%H%M%SZ)"
fi
mv "$OUT" "$FINAL_OUT"
echo "$FINAL_OUT"
