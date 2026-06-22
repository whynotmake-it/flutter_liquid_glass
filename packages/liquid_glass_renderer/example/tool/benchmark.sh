#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLE_DIR="$(dirname "$SCRIPT_DIR")"
RESULT_DIR="$EXAMPLE_DIR/build/benchmark"
TRACE_SECONDS="${LIQUID_GLASS_BENCHMARK_TRACE_SECONDS:-18s}"
WARMUP_SECONDS="${LIQUID_GLASS_BENCHMARK_WARMUP_SECONDS:-6}"
MEASURE_SECONDS="${LIQUID_GLASS_BENCHMARK_MEASURE_SECONDS:-8}"
ENFORCE_THRESHOLDS="${LIQUID_GLASS_BENCHMARK_ENFORCE:-false}"
SCENARIOS="${LIQUID_GLASS_BENCHMARK_SCENARIOS:-baselineMotion staticSingle translatedSingle scaledRotatedSingle shared16Motion resizeChurn layerChurn largeStatic largeResize fakeStatic fakeLarge}"
FLUTTER_BIN="${LIQUID_GLASS_FLUTTER_BIN:-flutter}"
DART_BIN="${LIQUID_GLASS_DART_BIN:-dart}"

command -v "$FLUTTER_BIN" >/dev/null || { echo "flutter is required" >&2; exit 1; }
command -v "$DART_BIN" >/dev/null || { echo "dart is required" >&2; exit 1; }
command -v xcrun >/dev/null || { echo "Xcode command-line tools are required" >&2; exit 1; }

mkdir -p "$RESULT_DIR/traces" "$RESULT_DIR/logs"
cd "$EXAMPLE_DIR"

run_scenario() {
  local scenario="$1"
  local drive_log="$RESULT_DIR/logs/$scenario.log"
  local trace_path="$RESULT_DIR/traces/$scenario.trace"
  local trace_log="$RESULT_DIR/logs/$scenario.xctrace.log"
  local run_pid app_pid trace_pid benchmark_json
  local renderer_args=(--enable-impeller --enable-flutter-gpu)

  if [[ "$scenario" == fake* ]]; then
    renderer_args=(--no-enable-impeller)
  fi

  rm -rf "$trace_path" \
    "$RESULT_DIR/traces/$scenario.toc.xml" \
    "$RESULT_DIR/traces/$scenario.gpu.xml"
  "$FLUTTER_BIN" run \
    --target=integration_test/benchmark_test.dart \
    --profile \
    "${renderer_args[@]}" \
    --dart-define="LIQUID_GLASS_BENCHMARK_SCENARIO=$scenario" \
    --dart-define="LIQUID_GLASS_BENCHMARK_WARMUP_SECONDS=$WARMUP_SECONDS" \
    --dart-define="LIQUID_GLASS_BENCHMARK_MEASURE_SECONDS=$MEASURE_SECONDS" \
    -d macos >"$drive_log" 2>&1 &
  run_pid=$!

  app_pid=""
  for _ in $(seq 1 240); do
    app_pid="$(pgrep -n -x liquid_glass_renderer_example || true)"
    [[ -n "$app_pid" ]] && break
    kill -0 "$run_pid" 2>/dev/null || break
    sleep 0.25
  done

  trace_pid=""
  if [[ -n "$app_pid" ]]; then
    xcrun xctrace record \
      --template 'Metal System Trace' \
      --attach "$app_pid" \
      --time-limit "$TRACE_SECONDS" \
      --output "$trace_path" >"$trace_log" 2>&1 &
    trace_pid=$!
  else
    printf 'App PID was not found; Metal trace was not recorded.\n' >"$trace_log"
  fi

  benchmark_json=""
  for _ in $(seq 1 240); do
    benchmark_json="$(sed -n 's/^flutter: LIQUID_GLASS_BENCHMARK_JSON://p' "$drive_log" | tail -1)"
    [[ -n "$benchmark_json" ]] && break
    kill -0 "$run_pid" 2>/dev/null || break
    sleep 0.25
  done

  local drive_status=0
  if [[ -n "$benchmark_json" ]]; then
    printf '%s\n' "$benchmark_json" >"$RESULT_DIR/$scenario.json"
  else
    drive_status=1
  fi
  kill "$run_pid" 2>/dev/null || true
  wait "$run_pid" || true
  if [[ -n "$trace_pid" ]]; then
    kill -INT "$trace_pid" 2>/dev/null || true
    (
      sleep 20
      kill -TERM "$trace_pid" 2>/dev/null || true
      sleep 5
      kill -KILL "$trace_pid" 2>/dev/null || true
    ) &
    local trace_watchdog_pid=$!
    wait "$trace_pid" || true
    kill "$trace_watchdog_pid" 2>/dev/null || true
  fi
  if [[ "$drive_status" -ne 0 ]]; then
    tail -100 "$drive_log" >&2
    return "$drive_status"
  fi

  if [[ -d "$trace_path" ]]; then
    xcrun xctrace export \
      --input "$trace_path" \
      --toc \
      --output "$RESULT_DIR/traces/$scenario.toc.xml" >>"$trace_log" 2>&1 || true
    xcrun xctrace export \
      --input "$trace_path" \
      --xpath '/trace-toc/run[@number="1"]/data/table[@schema="metal-gpu-intervals"]' \
      --output "$RESULT_DIR/traces/$scenario.gpu.xml" >>"$trace_log" 2>&1 || true
  fi
}

for scenario in $SCENARIOS; do
  echo "Benchmarking $scenario"
  run_scenario "$scenario"
done

"$DART_BIN" run tool/parse_benchmark_results.dart \
  --input "$RESULT_DIR" \
  --markdown "$RESULT_DIR/summary.md" \
  --json "$RESULT_DIR/summary.json" \
  --enforce "$ENFORCE_THRESHOLDS"

cat "$RESULT_DIR/summary.md"
