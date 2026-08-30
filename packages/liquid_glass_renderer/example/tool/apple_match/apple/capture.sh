#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${IOS_27_UDID:?Set IOS_27_UDID to the pinned iOS 27 simulator UDID}"
: "${REFERENCE_SET:=ios27-iphone17pro-ground-truth-v2/slider-000}"
: "${CAPTURE_FRAMES:=3}"
: "${CAPTURE_FRAME_DELAY:=0.25}"
: "${SCENE_ID:=toolbar_capsule}"
: "${LIQUID_GLASS_TINT_POSITION:?Set the exact Liquid Glass slider position (0...1)}"
: "${LIQUID_GLASS_TINT_CONTROL_METHOD:=simctl defaults write com.apple.UIKit UIViewGlassTintAmount}"
: "${DEVELOPER_DIR:=/Applications/Xcode-27.0.0-Beta.5.app/Contents/Developer}"
export DEVELOPER_DIR
export SCENE_ID CAPTURE_FRAMES IOS_27_UDID
export LIQUID_GLASS_TINT_POSITION LIQUID_GLASS_TINT_CONTROL_METHOD
SCENE="$ROOT/scenes/$SCENE_ID.json"
[[ -f "$SCENE" ]] || { echo "Unknown scene: $SCENE_ID" >&2; exit 2; }
# Most scenes use the canonical A/B/C/D roles, but isolated color-transfer
# scenes can declare one full-face solid probe per hue. Apple references must
# always capture the complete declared set; use host_capture.sh for subsets.
if [[ -n "${CAPTURE_PROBES:-}" ]]; then
  echo "CAPTURE_PROBES subsets are not valid Apple references; use host_capture.sh" >&2
  exit 2
fi
if [[ -z "${CAPTURE_PROBES:-}" ]]; then
  CAPTURE_PROBES="$(python3 - "$SCENE" <<'PY'
import json
import sys
scene = json.load(open(sys.argv[1]))
print(" ".join(probe["id"] for probe in scene["probes"]))
PY
)"
fi
export CAPTURE_PROBES
FINAL_OUT="$ROOT/references/$REFERENCE_SET/$SCENE_ID"
API="SwiftUI PrimitiveButtonStyle.glass"
[[ "$SCENE_ID" == "tab_bar_holdout" ]] && API="SwiftUI TabView system tab bar"
[[ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["profile"])' "$SCENE")" == "material_shape" ]] && API="SwiftUI View.glassEffect(_:in:)"
APPEARANCE="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["appearance"])' "$SCENE")"
ACTUAL_TINT_POSITION=""
xcrun simctl spawn "$IOS_27_UDID" defaults write com.apple.UIKit \
  UIViewGlassTintAmount -float "$LIQUID_GLASS_TINT_POSITION"
xcrun simctl spawn "$IOS_27_UDID" defaults write com.apple.UIKit \
  UIViewGlassEverEditedInSettings -bool YES
ACTUAL_TINT_POSITION="$(xcrun simctl spawn "$IOS_27_UDID" defaults read \
  com.apple.UIKit UIViewGlassTintAmount)"
python3 - "$LIQUID_GLASS_TINT_POSITION" "$ACTUAL_TINT_POSITION" <<'PY'
import sys

declared = float(sys.argv[1])
actual = float(sys.argv[2])
if abs(declared - actual) > 0.001:
    raise SystemExit(
        f"declared Liquid Glass Tint Amount {declared} != readback {actual}"
    )
PY
export APPLE_MATCH_API="$API" APPEARANCE ACTUAL_TINT_POSITION

if [[ -d "$FINAL_OUT" && "${FORCE_REFERENCE:-0}" != "1" ]]; then
  echo "Pinned reference exists at $FINAL_OUT; set FORCE_REFERENCE=1 to replace it." >&2
  exit 3
fi
STAGING_PARENT="$ROOT/references/.staging"
mkdir -p "$STAGING_PARENT"
OUT="$(mktemp -d "$STAGING_PARENT/${SCENE_ID}.XXXXXX")"

"$ROOT/apple/build.sh"
mkdir -p "$OUT/frames"
xcrun simctl boot "$IOS_27_UDID" 2>/dev/null || true
xcrun simctl bootstatus "$IOS_27_UDID" -b
xcrun simctl install "$IOS_27_UDID" "$ROOT/apple/build/AppleMatch.app"
xcrun simctl ui "$IOS_27_UDID" appearance "$APPEARANCE"
xcrun simctl ui "$IOS_27_UDID" content_size large
xcrun simctl ui "$IOS_27_UDID" increase_contrast disabled
xcrun simctl spawn "$IOS_27_UDID" defaults write com.apple.Accessibility \
  ReduceMotionEnabled -bool YES
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

for probe in $CAPTURE_PROBES; do
  xcrun simctl launch --terminate-running-process "$IOS_27_UDID" \
    dev.liquidglass.applematch --args --scene-id "$SCENE_ID" --probe "$probe"
  sleep 1
  for frame in $(seq 1 "$CAPTURE_FRAMES"); do
    screenshot_frame "$probe" "$OUT/frames/${probe}_$frame.png"
    sleep "$CAPTURE_FRAME_DELAY"
  done
  xcrun simctl terminate "$IOS_27_UDID" dev.liquidglass.applematch
  sleep 0.5
  python3 "$ROOT/compare/median_frames.py" "$OUT/$probe.png" \
    "$OUT"/frames/"${probe}"_*.png
done

RUNTIME_LABEL="$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; r=next(x for x in json.load(sys.stdin)["runtimes"] if x["identifier"]=="com.apple.CoreSimulator.SimRuntime.iOS-27-0"); print("{} ({})".format(r["name"], r["buildversion"]))')"
python3 "$ROOT/reference_provenance.py" "$OUT" "$SCENE" \
  --source "$ROOT/apple/Sources/AppleMatchApp.swift" \
  --capture-script "$ROOT/apple/capture.sh" \
  --write \
  --runtime "$RUNTIME_LABEL" \
  --runtime-identifier "com.apple.CoreSimulator.SimRuntime.iOS-27-0" \
  --udid "$IOS_27_UDID" \
  --device "iPhone 17 Pro" \
  --appearance "$APPEARANCE" \
  --slider "$LIQUID_GLASS_TINT_POSITION" \
  --slider-readback "$ACTUAL_TINT_POSITION" \
  --slider-method "$LIQUID_GLASS_TINT_CONTROL_METHOD" \
  --frames "$CAPTURE_FRAMES"

mkdir -p "$(dirname "$FINAL_OUT")"
if [[ -d "$FINAL_OUT" ]]; then
  mv "$FINAL_OUT" "${FINAL_OUT}.replaced-$(date -u +%Y%m%dT%H%M%SZ)"
fi
mv "$OUT" "$FINAL_OUT"
echo "$FINAL_OUT"
