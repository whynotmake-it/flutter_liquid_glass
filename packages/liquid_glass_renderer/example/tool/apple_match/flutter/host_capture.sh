#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${SETTINGS_FILE:=$ROOT/settings/baseline.json}"
: "${SCENE_FILE:=$ROOT/scenes/toolbar_capsule.json}"
: "${CANDIDATE_OUT:=$ROOT/out/host-candidates/baseline}"
: "${FLUTTER_BIN:=$HOME/fvm/versions/3.47.1/bin/flutter}"
: "${CAPTURE_PROBES:=$(python3 -c 'import json,sys; print(" ".join(p["id"] for p in json.load(open(sys.argv[1]))["probes"]))' "$SCENE_FILE")}"
: "${CAPTURE_DPR:=}"
: "${HOST_CAPTURE_FAKE:=false}"

if [[ ! -x "$FLUTTER_BIN" ]]; then
  echo "Flutter 3.47.1 not found at $FLUTTER_BIN; set FLUTTER_BIN explicitly." >&2
  exit 4
fi

# Flutter's asset compiler historically keyed the runtime-effect cache on the
# top-level .frag file and ignored changes in its #include'd .glsl files. That
# makes a host golden silently execute stale shader code during fitting. Keep
# a digest of every renderer shader source and invalidate only this generated
# capture app when any source changes. The marker lives under ignored `out/`;
# no source or user data is removed.
SHADER_ROOT="$ROOT/../../../lib/assets/shaders"
PACKAGE_ROOT="$ROOT/../../../"
SHADER_MARKER="$ROOT/out/.host_shader_sources.sha256"
if command -v shasum >/dev/null 2>&1; then
  digest() { shasum "$@"; }
else
  digest() { sha1sum "$@"; }
fi
shader_digest="$({
  find "$SHADER_ROOT" -type f \( -name '*.frag' -o -name '*.glsl' \) -print | sort
} | while IFS= read -r shader; do
  digest "$shader"
done | digest | awk '{print $1}')"
if [[ ! -f "$SHADER_MARKER" ]] || [[ "$(<"$SHADER_MARKER")" != "$shader_digest" ]]; then
  # The path dependency has its own generated unit-test asset bundle. Cleaning
  # only the capture app leaves that package-level shader binary stale, so
  # invalidate both build roots when an include changes.
  (
    cd "$ROOT/flutter"
    "$FLUTTER_BIN" clean
  )
  (
    cd "$PACKAGE_ROOT"
    "$FLUTTER_BIN" clean
  )
  mkdir -p "$(dirname "$SHADER_MARKER")"
  printf '%s\n' "$shader_digest" > "$SHADER_MARKER"
fi

(
  cd "$ROOT/flutter"
  "$FLUTTER_BIN" test \
    --enable-impeller \
    --enable-flutter-gpu \
    --update-goldens \
    --dart-define="HOST_CAPTURE_SCENE=$SCENE_FILE" \
    --dart-define="HOST_CAPTURE_SETTINGS=$SETTINGS_FILE" \
    --dart-define="HOST_CAPTURE_OUT=$CANDIDATE_OUT" \
    --dart-define="HOST_CAPTURE_PROBES=$CAPTURE_PROBES" \
    --dart-define="HOST_CAPTURE_DPR=$CAPTURE_DPR" \
    --dart-define="HOST_CAPTURE_FAKE=$HOST_CAPTURE_FAKE" \
    test/host_capture_test.dart
)

echo "$CANDIDATE_OUT"
