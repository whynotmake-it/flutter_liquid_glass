#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${SETTINGS_FILE:=$ROOT/settings/baseline.json}"
: "${SCENE_FILE:=$ROOT/scenes/toolbar_capsule.json}"
: "${CANDIDATE_OUT:=$ROOT/out/host-candidates/baseline}"
: "${FLUTTER_BIN:=$HOME/fvm/versions/3.47.1/bin/flutter}"

if [[ ! -x "$FLUTTER_BIN" ]]; then
  echo "Flutter 3.47.1 not found at $FLUTTER_BIN; set FLUTTER_BIN explicitly." >&2
  exit 4
fi

for probe in A B C D; do
  "$FLUTTER_BIN" test \
    --enable-impeller \
    --enable-flutter-gpu \
    --update-goldens \
    --dart-define="HOST_CAPTURE_SCENE=$SCENE_FILE" \
    --dart-define="HOST_CAPTURE_SETTINGS=$SETTINGS_FILE" \
    --dart-define="HOST_CAPTURE_OUT=$CANDIDATE_OUT" \
    --dart-define="HOST_CAPTURE_PROBE=$probe" \
    test/host_capture_test.dart
done

echo "$CANDIDATE_OUT"
