#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${IOS_27_UDID:?Set IOS_27_UDID to the pinned iOS 27 simulator UDID}"
: "${SETTINGS_FILE:=$ROOT/settings/baseline.json}"
: "${CANDIDATE_OUT:=$ROOT/out/candidates/baseline}"
: "${CAPTURE_FRAMES:=3}"
: "${FLUTTER_BIN:=$HOME/fvm/versions/3.47.1/bin/flutter}"
: "${PREPARE_APP:=1}"

if [[ ! -x "$FLUTTER_BIN" ]]; then
  echo "Flutter 3.47.1 not found at $FLUTTER_BIN; set FLUTTER_BIN explicitly." >&2
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
  sleep 2
}

screenshot_frame() {
  local probe="$1"
  local destination="$2"
  local attempt
  for attempt in 1 2 3 4 5 6; do
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
raise SystemExit(0 if pixel == expected else 1)
PY
    then
      return
    fi
    sleep 1
  done
  echo "Flutter frame never reached the expected $probe background." >&2
  return 5
}

if [[ "$PREPARE_APP" == "1" ]]; then
  (
    cd "$ROOT/flutter"
    build_defines=("--dart-define=SCENE_B64=$SCENE_B64")
    if [[ -n "${LIQUID_GLASS_GEOMETRY_AA_HALF_WIDTH:-}" ]]; then
      build_defines+=(
        "--dart-define=LIQUID_GLASS_GEOMETRY_AA_HALF_WIDTH=$LIQUID_GLASS_GEOMETRY_AA_HALF_WIDTH"
      )
    fi
    if [[ "${LIQUID_GLASS_DISABLE_CANVAS_CONTOUR:-0}" == "1" ]]; then
      build_defines+=(
        "--dart-define=LIQUID_GLASS_DISABLE_CANVAS_CONTOUR=true"
      )
    fi
    "$FLUTTER_BIN" build ios --simulator --debug \
      "${build_defines[@]}"
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
    screenshot_frame "$probe" "$CANDIDATE_OUT/frames/${probe}_$frame.png"
    sleep 0.1
  done
  xcrun simctl terminate "$IOS_27_UDID" \
    dev.liquidglass.appleMatchFlutter 2>/dev/null || true
  python3 "$ROOT/compare/median_frames.py" "$CANDIDATE_OUT/$probe.png" \
    "$CANDIDATE_OUT"/frames/"${probe}"_*.png
done
cp "$SETTINGS_FILE" "$CANDIDATE_OUT/settings.json"
echo "$CANDIDATE_OUT"
