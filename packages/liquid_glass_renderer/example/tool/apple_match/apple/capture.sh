#!/usr/bin/env bash
set -euo pipefail

# Capture pinned iOS 27 simulator references. Default mode captures static
# SwiftUI scenes with simctl screenshots; --loupe holds a text-selection
# long-press with agent-device while capturing the loupe scene. Options and
# reference layout are documented in ../README.md.

LOUPE=0
if [[ "${1:-}" == --loupe ]]; then
  LOUPE=1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${IOS_27_UDID:?Set IOS_27_UDID to the pinned iOS 27 simulator UDID}"
# REDUCE_MOTION=1 reproduces the historical references. Reduce Motion also
# removes Liquid Glass lensing, so REDUCE_MOTION=0 captures the full effect
# and relies on CAPTURE_SETTLE_SECONDS (plus the frame-stability gate in
# reference_provenance.py) to exclude launch and materialization animation.
: "${REDUCE_MOTION:=1}"
case "$REDUCE_MOTION" in
  1) REDUCE_MOTION_DEFAULT=YES
     if (( LOUPE )); then
       : "${REFERENCE_SET:=ios27-iphone17pro-light}"
       : "${CAPTURE_SETTLE_SECONDS:=1.8}"
       : "${LOUPE_CAPTURE_DELAY:=1.5}"
     else
       : "${REFERENCE_SET:=ios27-iphone17pro-ground-truth-v2/slider-000}"
       : "${CAPTURE_SETTLE_SECONDS:=1}"
     fi ;;
  0) REDUCE_MOTION_DEFAULT=NO
     : "${CAPTURE_SETTLE_SECONDS:=4}"
     if (( LOUPE )); then
       : "${REFERENCE_SET:=ios27-iphone17pro-reduce-motion-off/loupe}"
       : "${LOUPE_CAPTURE_DELAY:=2.5}"
     else
       : "${REFERENCE_SET:=ios27-iphone17pro-reduce-motion-off/slider-000}"
     fi ;;
  *) echo "REDUCE_MOTION must be 0 or 1" >&2; exit 2 ;;
esac
: "${CAPTURE_FRAMES:=3}"
: "${LIQUID_GLASS_TINT_CONTROL_METHOD:=simctl defaults write com.apple.UIKit UIViewGlassTintAmount}"
if (( LOUPE )); then
  : "${SCENE_ID:=loupe}"
  : "${LOUPE_TOUCH_X:=201}"
  : "${LOUPE_TOUCH_Y:=620}"
  : "${LOUPE_HOLD_MS:=4500}"
  export CAPTURE_SETTLE_SECONDS LOUPE_CAPTURE_DELAY \
    LOUPE_TOUCH_X LOUPE_TOUCH_Y LOUPE_HOLD_MS
else
  : "${SCENE_ID:=toolbar_capsule}"
  : "${CAPTURE_FRAME_DELAY:=0.25}"
  : "${LIQUID_GLASS_TINT_POSITION:?Set the exact Liquid Glass slider position (0...1)}"
fi
export SCENE_ID CAPTURE_FRAMES IOS_27_UDID REDUCE_MOTION
export LIQUID_GLASS_TINT_CONTROL_METHOD
SCENE="$ROOT/scenes/$SCENE_ID.json"
[[ -f "$SCENE" ]] || { echo "Unknown scene: $SCENE_ID" >&2; exit 2; }
# Most scenes use the canonical A/B/C/D roles, but isolated color-transfer
# scenes can declare one full-face solid probe per hue. Apple references must
# always capture the complete declared set; use host_capture.sh for subsets.
if [[ -n "${CAPTURE_PROBES:-}" ]]; then
  echo "CAPTURE_PROBES subsets are not valid Apple references; use host_capture.sh" >&2
  exit 2
fi
CAPTURE_PROBES="$(python3 - "$SCENE" <<'PY'
import json
import sys
scene = json.load(open(sys.argv[1]))
print(" ".join(probe["id"] for probe in scene["probes"]))
PY
)"
export CAPTURE_PROBES
APPEARANCE="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["appearance"])' "$SCENE")"
export APPEARANCE LIQUID_GLASS_TINT_POSITION
FINAL_OUT="$ROOT/references/$REFERENCE_SET/$SCENE_ID"
# Refuse before touching the device or building when the pinned destination
# already exists.
if [[ -d "$FINAL_OUT" && "${FORCE_REFERENCE:-0}" != "1" ]]; then
  echo "Pinned reference exists at $FINAL_OUT; set FORCE_REFERENCE=1 to replace it." >&2
  exit 3
fi
STAGING_PARENT="$ROOT/references/.staging"
mkdir -p "$STAGING_PARENT"
OUT="$(mktemp -d "$STAGING_PARENT/${SCENE_ID}.XXXXXX")"
mkdir -p "$OUT/frames"

if (( LOUPE )); then
  # agent-device keys its session state by process cwd; pin every call to one
  # directory and one named session so open/longpress/close always agree.
  AD_SESSION="applematch-loupe"
  cd "$ROOT"
  TEMP_OUT="$(mktemp -d "$STAGING_PARENT/${SCENE_ID}.loupe-temp.XXXXXX")"
  cleanup() {
    agent-device close --platform ios --udid "$IOS_27_UDID" \
      --session "$AD_SESSION" >/dev/null 2>&1 || true
    if [[ -n "${TEMP_OUT:-}" && -d "$TEMP_OUT" ]]; then
      rm -rf "$TEMP_OUT"
    fi
  }
  trap cleanup EXIT
fi

"$ROOT/apple/build.sh"
# Slider defaults live inside the simulated device, so a cold pinned device must
# be booted before they are written or read; otherwise a clean capture fails
# unless another process happens to have launched the simulator first.
xcrun simctl boot "$IOS_27_UDID" 2>/dev/null || true
xcrun simctl bootstatus "$IOS_27_UDID" -b
# Accessibility defaults are read by system processes at startup, so a changed
# Reduce Motion value only takes effect for glass rendering after a reboot.
# Reboot before any other defaults write or app install: both can be lost
# when the device shuts down immediately after them.
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
  SLIDER_OUTPUT="$(bash "$ROOT/apple/set_transparency_slider.sh" \
    "$LIQUID_GLASS_TINT_POSITION")"
else
  SLIDER_OUTPUT="$(bash "$ROOT/apple/set_transparency_slider.sh" --read)"
fi
while IFS='=' read -r key value; do
  case "$key" in
    LIQUID_GLASS_TINT_POSITION) LIQUID_GLASS_TINT_POSITION="$value" ;;
    LIQUID_GLASS_TINT_READBACK) LIQUID_GLASS_TINT_READBACK="$value" ;;
    LIQUID_GLASS_TINT_CONTROL_METHOD) LIQUID_GLASS_TINT_CONTROL_METHOD="$value" ;;
  esac
done <<<"$SLIDER_OUTPUT"
: "${LIQUID_GLASS_TINT_READBACK:?Slider helper did not report a readback}"
export LIQUID_GLASS_TINT_POSITION LIQUID_GLASS_TINT_READBACK \
  LIQUID_GLASS_TINT_CONTROL_METHOD
xcrun simctl install "$IOS_27_UDID" "$ROOT/apple/build/AppleMatch.app"
xcrun simctl ui "$IOS_27_UDID" appearance "$APPEARANCE"
xcrun simctl ui "$IOS_27_UDID" content_size large
xcrun simctl ui "$IOS_27_UDID" increase_contrast disabled
xcrun simctl spawn "$IOS_27_UDID" defaults write com.apple.Accessibility \
  ReduceTransparencyEnabled -bool NO
screenshot_frame() {
  local probe="$1"
  local destination="$2"
  local attempt
  for attempt in $(seq 1 12); do
    xcrun simctl io "$IOS_27_UDID" screenshot "$destination"
    if python3 "$ROOT/validate_probe_frame.py" "$SCENE" "$probe" "$destination"
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

# Acquires one loupe frame: relaunch, settle, long-press, screenshot, then
# validate the probe background and the loupe region against the un-pressed
# reference. Exits 6 after five failed attempts, as the inline loop did.
capture_loupe_frame() {
  local probe="$1" frame="$2" background="$3" destination="$4"
  local attempt=1 local_lp_pid candidate
  while (( attempt <= 5 )); do
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
      mv "$candidate" "$destination"
      sleep 0.3
      return
    fi
    attempt=$((attempt + 1))
    if (( attempt > 5 )); then
      echo "Loupe never appeared for probe $probe frame $frame." >&2
      exit 6
    fi
    sleep 1
  done
}

for probe in $CAPTURE_PROBES; do
  xcrun simctl launch --terminate-running-process "$IOS_27_UDID" \
    dev.liquidglass.applematch --args --scene-id "$SCENE_ID" --probe "$probe"
  sleep "$CAPTURE_SETTLE_SECONDS"
  if (( LOUPE )); then
    xcrun simctl io "$IOS_27_UDID" screenshot "$TEMP_OUT/bg_$probe.png"
  fi
  for frame in $(seq 1 "$CAPTURE_FRAMES"); do
    if (( LOUPE )); then
      capture_loupe_frame "$probe" "$frame" "$TEMP_OUT/bg_$probe.png" \
        "$OUT/frames/${probe}_${frame}.png"
    else
      screenshot_frame "$probe" "$OUT/frames/${probe}_$frame.png"
      sleep "$CAPTURE_FRAME_DELAY"
    fi
  done
  if (( LOUPE )); then
    xcrun simctl terminate "$IOS_27_UDID" dev.liquidglass.applematch \
      >/dev/null 2>&1 || true
  else
    xcrun simctl terminate "$IOS_27_UDID" dev.liquidglass.applematch
  fi
  sleep 0.5
  python3 "$ROOT/compare/median_frames.py" "$OUT/$probe.png" \
    "$OUT"/frames/"${probe}"_*.png
done

RUNTIME="$(python3 - "$IOS_27_UDID" "$(xcrun simctl list devices -j)" \
  "$(xcrun simctl list runtimes -j)" <<'PY'
import json
import sys

udid, devices, runtimes = sys.argv[1:]
identifier = next(
    runtime for runtime, entries in json.loads(devices)["devices"].items()
    if any(device["udid"] == udid for device in entries)
)
runtime = next(item for item in json.loads(runtimes)["runtimes"]
               if item["identifier"] == identifier)
print(identifier, "{} ({})".format(runtime["name"], runtime["buildversion"]))
PY
)"
read -r RUNTIME_IDENTIFIER RUNTIME_LABEL <<<"$RUNTIME"
provenance=(
  python3 "$ROOT/reference_provenance.py" "$OUT" "$SCENE"
  --source "$ROOT/apple/Sources/AppleMatchApp.swift"
  --capture-script "$ROOT/apple/capture.sh"
)
"${provenance[@]}" \
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
if (( LOUPE )); then
  python3 - "$OUT/metadata.json" <<'PY'
import json
import os
import sys
from pathlib import Path

path = Path(sys.argv[1])
metadata = json.loads(path.read_text())
metadata.update(
    loupeCaptureDelaySeconds=float(os.environ["LOUPE_CAPTURE_DELAY"]),
    touchPoint=[float(os.environ[key]) for key in ("LOUPE_TOUCH_X", "LOUPE_TOUCH_Y")],
)
path.write_text(json.dumps(metadata, indent=2) + "\n")
PY
  "${provenance[@]}"
fi

mkdir -p "$(dirname "$FINAL_OUT")"
if [[ -d "$FINAL_OUT" ]]; then
  mv "$FINAL_OUT" "${FINAL_OUT}.replaced-$(date -u +%Y%m%dT%H%M%SZ)"
fi
mv "$OUT" "$FINAL_OUT"
echo "$FINAL_OUT"
