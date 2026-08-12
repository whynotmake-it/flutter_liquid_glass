#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${IOS_27_UDID:?Set IOS_27_UDID to the pinned iOS 27 simulator UDID}"
: "${REFERENCE_SET:=ios27-iphone17pro-light}"
: "${CAPTURE_FRAMES:=3}"
OUT="$ROOT/references/$REFERENCE_SET/toolbar_capsule"

if [[ -d "$OUT" && "${FORCE_REFERENCE:-0}" != "1" ]]; then
  echo "Pinned reference exists at $OUT; set FORCE_REFERENCE=1 to replace it." >&2
  exit 3
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

for probe in A B C D; do
  xcrun simctl launch --terminate-running-process "$IOS_27_UDID" \
    dev.liquidglass.applematch --args --probe "$probe"
  sleep 1
  for frame in $(seq 1 "$CAPTURE_FRAMES"); do
    xcrun simctl io "$IOS_27_UDID" screenshot \
      "$OUT/frames/${probe}_$frame.png"
    sleep 0.1
  done
  xcrun simctl terminate "$IOS_27_UDID" dev.liquidglass.applematch
  python3 "$ROOT/compare/median_frames.py" "$OUT/$probe.png" \
    "$OUT"/frames/"${probe}"_*.png
done

cat > "$OUT/metadata.json" <<EOF
{
  "runtime": "iOS 27.0 (24A5408d)",
  "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
  "udid": "$IOS_27_UDID",
  "device": "iPhone 17 Pro",
  "orientation": "portrait",
  "appearance": "light",
  "reduceMotion": true,
  "medianFrameCount": $CAPTURE_FRAMES,
  "reduceTransparency": false,
  "api": "SwiftUI PrimitiveButtonStyle.glass"
}
EOF
echo "$OUT"
