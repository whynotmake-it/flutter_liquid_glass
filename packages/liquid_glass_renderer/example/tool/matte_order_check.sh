#!/usr/bin/env bash
#
# Runs the matte-order validator (LIQUID_GLASS_VALIDATE_MATTE_ORDER) over the
# animating benchmark scenes on macOS and fails if any captured frame samples a
# matte that was rewritten before that frame was rasterized (magenta pixels).
#
# CI runs this from .github/workflows/benchmark.yaml. For an Android device,
# see tool/README.md: build and launch the app with the same compile-time flag
# and watch the `LIQUID_GLASS_MATTE_ORDER:<scene>:<captured>:<framesWithMagenta>`
# lines (logcat); fail when framesWithMagenta is non-zero.
#
# Env:
#   LIQUID_GLASS_MATTE_ORDER_SCENARIOS  scenes to check (space separated)
#   LIQUID_GLASS_BENCHMARK_WARMUP_SECONDS  default 1
#   LIQUID_GLASS_BENCHMARK_MEASURE_SECONDS default 2
#   LIQUID_GLASS_FLUTTER_BIN            default flutter

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLE_DIR="$(dirname "$SCRIPT_DIR")"
cd "$EXAMPLE_DIR"

FLUTTER_BIN="${LIQUID_GLASS_FLUTTER_BIN:-flutter}"
SCENARIOS="${LIQUID_GLASS_MATTE_ORDER_SCENARIOS:-resizeAnimated pxSheetResize pxButtonStretch pxBlend5Motion}"
WARMUP_SECONDS="${LIQUID_GLASS_BENCHMARK_WARMUP_SECONDS:-1}"
MEASURE_SECONDS="${LIQUID_GLASS_BENCHMARK_MEASURE_SECONDS:-2}"
APP_EXECUTABLE="${LIQUID_GLASS_BENCHMARK_EXECUTABLE:-$EXAMPLE_DIR/build/macos/Build/Products/Profile/liquid_glass_renderer_example.app/Contents/MacOS/liquid_glass_renderer_example}"
LOG_DIR="${LIQUID_GLASS_MATTE_ORDER_LOG_DIR:-$EXAMPLE_DIR/build/matte-order}"

echo "Building profile benchmark executable with the matte-order validator"
"$FLUTTER_BIN" build macos \
  --profile \
  --target=integration_test/benchmark_test.dart \
  --dart-define=LIQUID_GLASS_VALIDATE_MATTE_ORDER=true

if [[ ! -x "$APP_EXECUTABLE" ]]; then
  printf 'Benchmark executable was not found at %s\n' "$APP_EXECUTABLE" >&2
  exit 1
fi

mkdir -p "$LOG_DIR"

status=0
for scenario in $SCENARIOS; do
  log="$LOG_DIR/$scenario.log"
  : >"$log"
  echo "Checking matte order: $scenario"
  env \
    FLUTTER_ENGINE_SWITCHES=3 \
    FLUTTER_ENGINE_SWITCH_1=enable-dart-profiling=true \
    FLUTTER_ENGINE_SWITCH_2=enable-impeller=true \
    FLUTTER_ENGINE_SWITCH_3=enable-flutter-gpu=true \
    LIQUID_GLASS_BENCHMARK_SCENARIO="$scenario" \
    LIQUID_GLASS_BENCHMARK_WARMUP_SECONDS="$WARMUP_SECONDS" \
    LIQUID_GLASS_BENCHMARK_MEASURE_SECONDS="$MEASURE_SECONDS" \
    LIQUID_GLASS_BENCHMARK_REPETITION=1 \
    "$APP_EXECUTABLE" >"$log" 2>&1 &
  app_pid=$!

  line=""
  for _ in $(seq 1 240); do
    if grep -q '^LIQUID_GLASS_MATTE_ORDER:' "$log"; then break; fi
    kill -0 "$app_pid" 2>/dev/null || break
    sleep 0.5
  done
  kill -TERM "$app_pid" 2>/dev/null || true
  wait "$app_pid" 2>/dev/null || true
  # Read after the process stops: on failure the app prints and exits at once,
  # so the last poll can race its exit.
  line="$(grep -m1 '^LIQUID_GLASS_MATTE_ORDER:' "$log" || true)"

  if [[ -z "$line" ]]; then
    printf 'No matte-order report for %s; see %s\n' "$scenario" "$log" >&2
    tail -50 "$log" >&2 || true
    status=1
    continue
  fi
  printf '%s\n' "$line"
  frames_with_magenta="$(printf '%s' "$line" | cut -d: -f4)"
  if [[ "$frames_with_magenta" != "0" ]]; then
    printf '%s sampled a matte rewritten out of order in %s frames\n' \
      "$scenario" "$frames_with_magenta" >&2
    status=1
  fi
done

if ((status != 0)); then
  printf 'Matte-order validation failed.\n' >&2
fi
exit "$status"
