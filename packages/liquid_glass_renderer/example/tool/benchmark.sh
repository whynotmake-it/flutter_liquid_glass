#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLE_DIR="$(dirname "$SCRIPT_DIR")"
RESULT_DIR="${LIQUID_GLASS_BENCHMARK_RESULT_DIR:-$EXAMPLE_DIR/build/benchmark}"
TRACE_SECONDS="${LIQUID_GLASS_BENCHMARK_TRACE_SECONDS:-60s}"
TRACE_RETRY_SECONDS="${LIQUID_GLASS_BENCHMARK_TRACE_RETRY_SECONDS:-60s}"
TRACE_STOP_TIMEOUT="${LIQUID_GLASS_BENCHMARK_TRACE_STOP_TIMEOUT:-60}"
TRACE_TEMPLATE="${LIQUID_GLASS_BENCHMARK_TRACE_TEMPLATE:-Game Performance}"
REQUIRE_NATIVE_TRACE="${LIQUID_GLASS_BENCHMARK_REQUIRE_NATIVE_TRACE:-true}"
CAPTURE_NATIVE_TRACE="${LIQUID_GLASS_BENCHMARK_CAPTURE_NATIVE_TRACE:-true}"
WARMUP_SECONDS="${LIQUID_GLASS_BENCHMARK_WARMUP_SECONDS:-6}"
MEASURE_SECONDS="${LIQUID_GLASS_BENCHMARK_MEASURE_SECONDS:-8}"
TRACE_WINDOW_SECONDS="${LIQUID_GLASS_BENCHMARK_TRACE_WINDOW_SECONDS:-$((MEASURE_SECONDS * 2 + 5))}"
REPETITIONS="${LIQUID_GLASS_BENCHMARK_REPETITIONS:-3}"
ENFORCE_THRESHOLDS="${LIQUID_GLASS_BENCHMARK_ENFORCE:-false}"
SKIP_BUILD="${LIQUID_GLASS_BENCHMARK_SKIP_BUILD:-false}"
SCENARIOS="${LIQUID_GLASS_BENCHMARK_SCENARIOS:-baselineMotion staticSingle translatedSingle ancestorTranslatedLayer scaledRotatedSingle grouped4Motion grouped8Motion grouped16Motion independent16Motion independent16SharedBackdrop sparse16Motion relativeBlendMotion dynamicBlend16 resizeAnimated layerChurn largeStatic largeResize fakeStatic fakeLarge}"
FLUTTER_BIN="${LIQUID_GLASS_FLUTTER_BIN:-flutter}"
DART_BIN="${LIQUID_GLASS_DART_BIN:-dart}"
APP_EXECUTABLE="${LIQUID_GLASS_BENCHMARK_EXECUTABLE:-$EXAMPLE_DIR/build/macos/Build/Products/Profile/liquid_glass_renderer_example.app/Contents/MacOS/liquid_glass_renderer_example}"
NOTIFICATION_WAITER="$RESULT_DIR/trace_notification_waiter"

command -v "$FLUTTER_BIN" >/dev/null || { echo "flutter is required" >&2; exit 1; }
command -v "$DART_BIN" >/dev/null || { echo "dart is required" >&2; exit 1; }
command -v xcrun >/dev/null || { echo "Xcode command-line tools are required" >&2; exit 1; }

rm -rf "$RESULT_DIR"
mkdir -p "$RESULT_DIR/traces" "$RESULT_DIR/logs"
cd "$EXAMPLE_DIR"

ACTIVE_RUN_PID=""
ACTIVE_TRACE_PID=""
ACTIVE_NOTIFICATION_PID=""

terminate_tree() {
  local parent_pid="$1"
  local child_pid
  while read -r child_pid; do
    [[ -n "$child_pid" ]] && terminate_tree "$child_pid"
  done < <(pgrep -P "$parent_pid" || true)
  kill -TERM "$parent_pid" 2>/dev/null || true
}

cleanup() {
  if [[ -n "$ACTIVE_TRACE_PID" ]]; then
    stop_trace_process "$ACTIVE_TRACE_PID"
  fi
  if [[ -n "$ACTIVE_RUN_PID" ]]; then
    terminate_tree "$ACTIVE_RUN_PID"
    wait "$ACTIVE_RUN_PID" 2>/dev/null || true
  fi
  if [[ -n "$ACTIVE_NOTIFICATION_PID" ]]; then
    kill -TERM "$ACTIVE_NOTIFICATION_PID" 2>/dev/null || true
    wait "$ACTIVE_NOTIFICATION_PID" 2>/dev/null || true
  fi
}

trap cleanup EXIT
trap 'exit 130' INT TERM

wait_for_log() {
  local file="$1"
  local pattern="$2"
  local timeout_seconds="$3"
  local iterations=$((timeout_seconds * 10))
  local index
  for ((index = 0; index < iterations; index++)); do
    [[ -f "$file" ]] && grep -Fq "$pattern" "$file" && return 0
    sleep 0.1
  done
  return 1
}

wait_for_file() {
  local file="$1"
  local timeout_seconds="$2"
  local iterations=$((timeout_seconds * 10))
  local index
  for ((index = 0; index < iterations; index++)); do
    [[ -f "$file" ]] && return 0
    sleep 0.1
  done
  return 1
}

process_is_running() {
  local pid="$1"
  local state
  state="$(ps -p "$pid" -o state= 2>/dev/null | tr -d '[:space:]')"
  [[ -n "$state" && "$state" != Z* ]]
}

terminate_existing_benchmark_targets() {
  pkill -TERM -x liquid_glass_renderer_example 2>/dev/null || true
  for _ in $(seq 1 20); do
    pgrep -x liquid_glass_renderer_example >/dev/null 2>&1 || return 0
    sleep 0.1
  done
  pkill -KILL -x liquid_glass_renderer_example 2>/dev/null || true
  for _ in $(seq 1 20); do
    pgrep -x liquid_glass_renderer_example >/dev/null 2>&1 || return 0
    sleep 0.1
  done
  printf 'Could not terminate an existing benchmark target.\n' >&2
  return 1
}

stop_trace_process() {
  local pid="$1"
  local iterations=$((TRACE_STOP_TIMEOUT * 10))
  local index
  kill -INT "$pid" 2>/dev/null || true
  for ((index = 0; index < iterations; index++)); do
    process_is_running "$pid" || break
    sleep 0.1
  done
  if process_is_running "$pid"; then
    kill -TERM "$pid" 2>/dev/null || true
    for ((index = 0; index < 50; index++)); do
      process_is_running "$pid" || break
      sleep 0.1
    done
  fi
  if process_is_running "$pid"; then
    kill -KILL "$pid" 2>/dev/null || true
  fi
  wait "$pid" 2>/dev/null || true
  ACTIVE_TRACE_PID=""
}

capture_trace_attempt() {
  local scenario="$1"
  local time_limit="$2"
  local trace_path="$3"
  local trace_drive_log="$4"
  local trace_log="$5"
  local run_key="$6"
  local repetition="$7"
  local toc_path="$RESULT_DIR/traces/$run_key.toc.xml"
  local notification_name="com.example.liquidGlassRenderer.xctrace.$$.${repetition}"
  local notification_ready="$RESULT_DIR/logs/$run_key.notification-ready"
  local notification_received="$RESULT_DIR/logs/$run_key.notification-received"
  local notification_gate="$RESULT_DIR/logs/$run_key.notification-gate"
  local trace_pid trace_run_pid
  local trace_duration_seconds="${time_limit%s}"
  local -a trace_window_args=()
  if ((TRACE_WINDOW_SECONDS > 0)); then
    trace_window_args=(--window "${TRACE_WINDOW_SECONDS}s")
  fi
  if [[ ! "$trace_duration_seconds" =~ ^[0-9]+$ ]]; then
    printf 'Trace duration must use whole seconds, for example 60s.\n' >&2
    return 1
  fi

  terminate_existing_benchmark_targets
  rm -rf "$trace_path" "$toc_path"
  rm -f "$trace_drive_log" "$notification_ready" "$notification_received" "$notification_gate"
  env \
    FLUTTER_ENGINE_SWITCHES=3 \
    FLUTTER_ENGINE_SWITCH_1=enable-dart-profiling=true \
    FLUTTER_ENGINE_SWITCH_2=enable-impeller=true \
    FLUTTER_ENGINE_SWITCH_3=enable-flutter-gpu=true \
    LIQUID_GLASS_BENCHMARK_SCENARIO="$scenario" \
    LIQUID_GLASS_BENCHMARK_WARMUP_SECONDS="$WARMUP_SECONDS" \
    LIQUID_GLASS_BENCHMARK_MEASURE_SECONDS="$MEASURE_SECONDS" \
    LIQUID_GLASS_BENCHMARK_REPETITION="$repetition" \
    LIQUID_GLASS_BENCHMARK_TRACE_RUN=1 \
    LIQUID_GLASS_BENCHMARK_TRACE_START_GATE="$notification_gate" \
    "$APP_EXECUTABLE" >"$trace_drive_log" 2>&1 &
  trace_run_pid=$!
  ACTIVE_RUN_PID="$trace_run_pid"
  if ! wait_for_log \
    "$trace_drive_log" \
    "LIQUID_GLASS_BENCHMARK_TRACE_READY:$scenario" \
    60; then
    printf 'Target did not reach its post-warmup trace gate.\n' >>"$trace_log"
    terminate_existing_benchmark_targets
    return 1
  fi

  "$NOTIFICATION_WAITER" \
    "$notification_name" \
    "$notification_ready" \
    "$notification_received" >>"$trace_log" 2>&1 &
  ACTIVE_NOTIFICATION_PID=$!
  if ! wait_for_file "$notification_ready" 5; then
    printf 'Could not register for xctrace readiness notification.\n' >>"$trace_log"
    return 1
  fi

  xcrun xctrace record \
    --template "$TRACE_TEMPLATE" \
    --time-limit "$time_limit" \
    "${trace_window_args[@]}" \
    --no-prompt \
    --notify-tracing-started "$notification_name" \
    --output "$trace_path" \
    --attach "$trace_run_pid" >>"$trace_log" 2>&1 &
  trace_pid=$!
  ACTIVE_TRACE_PID="$trace_pid"

  if ! wait_for_log "$trace_log" 'Ctrl-C to stop the recording' 20; then
    printf 'xctrace did not report a started recording.\n' >>"$trace_log"
    stop_trace_process "$trace_pid"
    return 1
  fi
  if ! wait_for_file "$notification_received" 20; then
    printf 'xctrace did not post its tracing-started notification.\n' >>"$trace_log"
    stop_trace_process "$trace_pid"
    return 1
  fi
  # xctrace posts its notification just before it finishes resolving the
  # attached process. Open the app gate only after both native readiness
  # signals are present so a short benchmark cannot exit during that race.
  : >"$notification_gate"
  for _ in $(seq 1 $(((trace_duration_seconds + TRACE_STOP_TIMEOUT) * 10))); do
    process_is_running "$trace_pid" || break
    sleep 0.1
  done
  if process_is_running "$trace_pid"; then
    printf 'xctrace did not stop after its %s time limit.\n' "$time_limit" >>"$trace_log"
    stop_trace_process "$trace_pid"
    return 1
  fi
  wait "$trace_pid" 2>/dev/null || true
  ACTIVE_TRACE_PID=""
  terminate_existing_benchmark_targets
  wait "$trace_run_pid" 2>/dev/null || true
  ACTIVE_RUN_PID=""
  wait "$ACTIVE_NOTIFICATION_PID" 2>/dev/null || true
  ACTIVE_NOTIFICATION_PID=""

  if [[ ! -d "$trace_path" ]]; then
    printf 'xctrace did not create a trace document.\n' >>"$trace_log"
    return 1
  fi
  if ! xcrun xctrace export \
    --input "$trace_path" \
    --toc \
    --output "$toc_path" >>"$trace_log" 2>&1; then
    printf 'xctrace created an unreadable trace document.\n' >>"$trace_log"
    return 1
  fi
  [[ -s "$toc_path" ]]
}

capture_metrics_attempt() {
  local scenario="$1"
  local drive_log="$2"
  local run_key="$3"
  local repetition="$4"
  local run_pid benchmark_json

  : >"$drive_log"
  env \
    FLUTTER_ENGINE_SWITCHES=3 \
    FLUTTER_ENGINE_SWITCH_1=enable-dart-profiling=true \
    FLUTTER_ENGINE_SWITCH_2=enable-impeller=true \
    FLUTTER_ENGINE_SWITCH_3=enable-flutter-gpu=true \
    LIQUID_GLASS_BENCHMARK_SCENARIO="$scenario" \
    LIQUID_GLASS_BENCHMARK_WARMUP_SECONDS="$WARMUP_SECONDS" \
    LIQUID_GLASS_BENCHMARK_MEASURE_SECONDS="$MEASURE_SECONDS" \
    LIQUID_GLASS_BENCHMARK_REPETITION="$repetition" \
    "$APP_EXECUTABLE" >"$drive_log" 2>&1 &
  run_pid=$!
  ACTIVE_RUN_PID="$run_pid"

  benchmark_json=""
  for _ in $(seq 1 240); do
    benchmark_json="$(sed -n 's/^.*LIQUID_GLASS_BENCHMARK_JSON://p' "$drive_log" | tail -1)"
    [[ -n "$benchmark_json" ]] && break
    kill -0 "$run_pid" 2>/dev/null || break
    sleep 0.25
  done

  terminate_tree "$run_pid"
  wait "$run_pid" 2>/dev/null || true
  ACTIVE_RUN_PID=""
  if [[ -z "$benchmark_json" ]]; then
    return 1
  fi
  printf '%s\n' "$benchmark_json" >"$RESULT_DIR/$run_key.json"
}

run_scenario() {
  local scenario="$1"
  local repetition="$2"
  local run_key="$scenario.r$repetition"
  local drive_log="$RESULT_DIR/logs/$run_key.log"
  local retry_drive_log="$RESULT_DIR/logs/$run_key.retry.log"
  local trace_drive_log="$RESULT_DIR/logs/$run_key.trace-app.log"
  local trace_path="$RESULT_DIR/traces/$run_key.trace"
  local trace_log="$RESULT_DIR/logs/$run_key.xctrace.log"

  rm -rf "$trace_path" \
    "$RESULT_DIR/traces/$run_key.toc.xml" \
    "$RESULT_DIR/traces/$run_key.gpu.xml" \
    "$RESULT_DIR/traces/$run_key.metal-resources.xml" \
    "$RESULT_DIR/traces/$run_key.signposts.xml"
  if ! capture_metrics_attempt "$scenario" "$drive_log" "$run_key" "$repetition"; then
    printf 'Initial frame/memory pass failed; retrying in a fresh process.\n' >&2
    if ! capture_metrics_attempt "$scenario" "$retry_drive_log" "$run_key" "$repetition"; then
      tail -100 "$drive_log" >&2
      tail -100 "$retry_drive_log" >&2
      return 1
    fi
  fi

  # Instruments substantially perturbs Mach phys_footprint on this
  # workload. Record GPU activity in a fresh, identical profile process so the
  # JSON above remains an uninstrumented memory and frame-timing measurement.
  local trace_valid=false
  if [[ "$CAPTURE_NATIVE_TRACE" == true ]]; then
    : >"$trace_log"
    if capture_trace_attempt \
      "$scenario" \
      "$TRACE_SECONDS" \
      "$trace_path" \
      "$trace_drive_log" \
      "$trace_log" \
      "$run_key" \
      "$repetition"; then
      trace_valid=true
    else
      printf 'Initial trace was invalid; retrying with a fresh process.\n' >>"$trace_log"
      if capture_trace_attempt \
        "$scenario" \
        "$TRACE_RETRY_SECONDS" \
        "$trace_path" \
        "$trace_drive_log" \
        "$trace_log" \
        "$run_key" \
        "$repetition"; then
        trace_valid=true
      fi
    fi
  fi

  if [[ "$trace_valid" == true ]]; then
    xcrun xctrace export \
      --input "$trace_path" \
      --xpath '/trace-toc/run[@number="1"]/data/table[@schema="metal-gpu-intervals"]' \
      --output "$RESULT_DIR/traces/$run_key.gpu.xml" >>"$trace_log" 2>&1 || true
    xcrun xctrace export \
      --input "$trace_path" \
      --xpath '/trace-toc/run[@number="1"]/data/table[@schema="metal-resource-allocations"]' \
      --output "$RESULT_DIR/traces/$run_key.metal-resources.xml" >>"$trace_log" 2>&1 || true
    xcrun xctrace export \
      --input "$trace_path" \
      --xpath '/trace-toc/run[@number="1"]/data/table[@schema="os-signpost" and @category="PointsOfInterest"]' \
      --output "$RESULT_DIR/traces/$run_key.signposts.xml" >>"$trace_log" 2>&1 || true
  elif [[ "$CAPTURE_NATIVE_TRACE" == true && "$REQUIRE_NATIVE_TRACE" == true ]]; then
    tail -100 "$trace_log" >&2
    return 1
  fi
}

if [[ "$SKIP_BUILD" != true ]]; then
  echo "Building profile benchmark executable"
  "$FLUTTER_BIN" build macos \
    --profile \
    --target=integration_test/benchmark_test.dart
fi
if [[ ! -x "$APP_EXECUTABLE" ]]; then
  printf 'Benchmark executable was not found at %s\n' "$APP_EXECUTABLE" >&2
  exit 1
fi
xcrun clang "$SCRIPT_DIR/trace_notification_waiter.c" \
  -o "$NOTIFICATION_WAITER"

for repetition in $(seq 1 "$REPETITIONS"); do
  for scenario in $SCENARIOS; do
    echo "Benchmarking $scenario (repetition $repetition/$REPETITIONS)"
    run_scenario "$scenario" "$repetition"
  done
done

"$DART_BIN" run tool/parse_benchmark_results.dart \
  --input "$RESULT_DIR" \
  --markdown "$RESULT_DIR/summary.md" \
  --json "$RESULT_DIR/summary.json" \
  --minimum-repetitions "$REPETITIONS" \
  --enforce "$ENFORCE_THRESHOLDS"

cat "$RESULT_DIR/summary.md"
