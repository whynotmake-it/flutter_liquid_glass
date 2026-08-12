#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${IOS_27_UDID:?Set IOS_27_UDID to the pinned iOS 27 simulator UDID}"
: "${SETTINGS_FILE:=$ROOT/settings/baseline.json}"
: "${CANDIDATE_OUT:=$ROOT/out/candidates/baseline}"
: "${CAPTURE_FRAMES:=3}"
: "${FLUTTER_BIN:=$HOME/fvm/versions/3.44.1/bin/flutter}"
: "${PREPARE_APP:=1}"

if [[ ! -x "$FLUTTER_BIN" ]]; then
  echo "Flutter 3.44.1 not found at $FLUTTER_BIN; set FLUTTER_BIN explicitly." >&2
  exit 4
fi
export PATH="$ROOT/compat/bin:$PATH"

SCENE_B64="$(python3 -c 'import base64,sys; print(base64.b64encode(open(sys.argv[1],"rb").read()).decode())' "$ROOT/scenes/toolbar_capsule.json")"
SETTINGS_B64="$(python3 -c 'import base64,sys; print(base64.b64encode(open(sys.argv[1],"rb").read()).decode())' "$SETTINGS_FILE")"

mkdir -p "$CANDIDATE_OUT"
mkdir -p "$CANDIDATE_OUT/frames"
launch_flutter() {
  local probe="$1"
  local launch_output
  launch_output="$(xcrun simctl launch --terminate-running-process "$IOS_27_UDID" \
    dev.liquidglass.appleMatchFlutter --args \
    --enable-impeller --enable-flutter-gpu \
    --probe "$probe" --settings-b64 "$SETTINGS_B64")"
  pid="${launch_output##*: }"
  sleep 1.5
}

if [[ "$PREPARE_APP" == "1" ]]; then
  (
    cd "$ROOT/flutter"
    "$FLUTTER_BIN" build ios --simulator --debug \
      --dart-define="SCENE_B64=$SCENE_B64"
  )
  xcrun simctl shutdown "$IOS_27_UDID" 2>/dev/null || true
  xcrun simctl boot "$IOS_27_UDID"
  xcrun simctl bootstatus "$IOS_27_UDID" -b
  xcrun simctl install "$IOS_27_UDID" \
    "$ROOT/flutter/build/ios/iphonesimulator/Runner.app"
fi
for probe in A B C D; do
  launch_flutter "$probe"
  if ! kill -0 "$pid" 2>/dev/null; then
    launch_flutter "$probe"
  fi
  kill -0 "$pid"
  for frame in $(seq 1 "$CAPTURE_FRAMES"); do
    if ! kill -0 "$pid" 2>/dev/null; then
      launch_flutter "$probe"
      kill -0 "$pid"
    fi
    xcrun simctl io "$IOS_27_UDID" screenshot \
      "$CANDIDATE_OUT/frames/${probe}_$frame.png"
    sleep 0.1
  done
  xcrun simctl terminate "$IOS_27_UDID" \
    dev.liquidglass.appleMatchFlutter 2>/dev/null || true
  python3 "$ROOT/compare/median_frames.py" "$CANDIDATE_OUT/$probe.png" \
    "$CANDIDATE_OUT"/frames/"${probe}"_*.png
done
cp "$SETTINGS_FILE" "$CANDIDATE_OUT/settings.json"
echo "$CANDIDATE_OUT"
