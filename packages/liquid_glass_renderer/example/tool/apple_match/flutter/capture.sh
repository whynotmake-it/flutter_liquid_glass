#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${IOS_27_UDID:?Set IOS_27_UDID to the pinned iOS 27 simulator UDID}"
: "${SETTINGS_FILE:=$ROOT/settings/baseline.json}"
: "${CANDIDATE_OUT:=$ROOT/out/candidates/baseline}"
: "${CAPTURE_FRAMES:=3}"
: "${CAPTURE_LAUNCH_SETTLE_SECONDS:=4}"
: "${FLUTTER_BIN:=$HOME/fvm/versions/3.47.1/bin/flutter}"
: "${PREPARE_APP:=1}"
: "${SCENE_ID:=toolbar_capsule}"
: "${SCENE_FILE:=$ROOT/scenes/$SCENE_ID.json}"

if [[ ! -x "$FLUTTER_BIN" ]]; then
  echo "Flutter 3.47.1 not found at $FLUTTER_BIN; set FLUTTER_BIN explicitly." >&2
  exit 4
fi
export PATH="$ROOT/compat/bin:$PATH"

[[ -f "$SCENE_FILE" ]] || { echo "Unknown scene: $SCENE_FILE" >&2; exit 2; }
SCENE_B64="$(python3 -c 'import base64,sys; print(base64.b64encode(open(sys.argv[1],"rb").read()).decode())' "$SCENE_FILE")"
SETTINGS_B64="$(python3 -c 'import base64,sys; print(base64.b64encode(open(sys.argv[1],"rb").read()).decode())' "$SETTINGS_FILE")"
APPEARANCE="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["appearance"])' "$SCENE_FILE")"

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
  # A solid-white launch screen satisfies the D probe's background check before
  # the Flutter surface or shader exists. Give the one-shot path a fixed launch
  # settle window; the persistent hot loop uses its explicit settled-frame IPC
  # instead and does not pay this delay per candidate.
  sleep "$CAPTURE_LAUNCH_SETTLE_SECONDS"
}

screenshot_frame() {
  local probe="$1"
  local destination="$2"
  local attempt
  for attempt in 1 2 3 4 5 6; do
    xcrun simctl io "$IOS_27_UDID" screenshot "$destination"
    if python3 "$ROOT/validate_probe_frame.py" "$SCENE_FILE" "$probe" "$destination"
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
  # Never shut down a simulator here: it may be hosting unrelated user work.
  # Reuse the pinned device if it is already booted; boot is idempotent for the
  # capture's purposes and is scoped to IOS_27_UDID only.
  xcrun simctl boot "$IOS_27_UDID" 2>/dev/null || true
  xcrun simctl bootstatus "$IOS_27_UDID" -b
  xcrun simctl install "$IOS_27_UDID" \
    "$ROOT/flutter/build/ios/iphonesimulator/Runner.app"
fi
xcrun simctl ui "$IOS_27_UDID" appearance "$APPEARANCE"
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
python3 - "$CANDIDATE_OUT/metadata.json" "$SCENE_FILE" <<'PY'
import json
import os
import sys
from pathlib import Path

scene = json.loads(Path(sys.argv[2]).read_text())
Path(sys.argv[1]).write_text(
    json.dumps(
        {
            "scene": scene["id"],
            "shapeKind": scene["shape"]["kind"],
            "appearance": scene["appearance"],
            "captureType": "pinned iOS simulator Flutter candidate",
            "captureEncoding": "SDR tone-mapped 8-bit PNG",
            "medianFrameCount": int(os.environ.get("CAPTURE_FRAMES", "3")),
        },
        indent=2,
    )
    + "\n"
)
PY
echo "$CANDIDATE_OUT"
