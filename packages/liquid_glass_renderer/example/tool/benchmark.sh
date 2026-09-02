#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLE_DIR="$(dirname "$SCRIPT_DIR")"
RESULT_DIR="${LIQUID_GLASS_BENCHMARK_RESULT_DIR:-$EXAMPLE_DIR/build/benchmark}"
TRACE_SECONDS="${LIQUID_GLASS_BENCHMARK_TRACE_SECONDS:-60s}"
TRACE_RETRY_SECONDS="${LIQUID_GLASS_BENCHMARK_TRACE_RETRY_SECONDS:-60s}"
TRACE_STOP_TIMEOUT="${LIQUID_GLASS_BENCHMARK_TRACE_STOP_TIMEOUT:-60}"
# xctrace finalization is not a bounded operation: a 5 s / 3 s-window Metal
# System Trace of the sixteen-independent-layer workload takes ~5.5 minutes to
# finalize on an idle machine, while simpler scenarios finish in seconds. The
# watchdog deadline must therefore be generous; killing a slow-but-healthy
# finalization discards an otherwise valid trace.
TRACE_FINALIZE_TIMEOUT="${LIQUID_GLASS_BENCHMARK_TRACE_FINALIZE_TIMEOUT:-600}"
# Attaching the Metal data source routinely takes 20-40 s on an idle machine
# before xctrace prints its start banner or posts the tracing-started
# notification. A short start timeout followed by a force kill wedges the
# daemon-side session and starves the next recording, so the start budget must
# exceed the worst observed attach latency by a wide margin.
TRACE_START_TIMEOUT="${LIQUID_GLASS_BENCHMARK_TRACE_START_TIMEOUT:-180}"
# A failed attempt can leave the Instruments daemon tearing down its session
# while the next recording is already starting; the new recording then
# captures nothing. Give the daemon a moment before retrying.
TRACE_ATTEMPT_COOLDOWN="${LIQUID_GLASS_BENCHMARK_TRACE_ATTEMPT_COOLDOWN:-30}"
TRACE_TEMPLATE="${LIQUID_GLASS_BENCHMARK_TRACE_TEMPLATE:-Metal System Trace}"
# Comma-separated Instruments to record instead of a template. The full Metal
# System Trace template also samples GPU hardware counters, and that event
# rate overwhelms the kdebug buffer on dense workloads: exported intervals
# then silently thin out and GPU busy under-reports by a session-varying
# factor. Recording only the two instruments the parser reads keeps capture
# complete. Set LIQUID_GLASS_BENCHMARK_TRACE_INSTRUMENTS= (empty) to use the
# template instead.
TRACE_INSTRUMENTS="${LIQUID_GLASS_BENCHMARK_TRACE_INSTRUMENTS-GPU,Metal Application,Metal Resource Events}"
REQUIRE_NATIVE_TRACE="${LIQUID_GLASS_BENCHMARK_REQUIRE_NATIVE_TRACE:-true}"
CAPTURE_NATIVE_TRACE="${LIQUID_GLASS_BENCHMARK_CAPTURE_NATIVE_TRACE:-true}"
WARMUP_SECONDS="${LIQUID_GLASS_BENCHMARK_WARMUP_SECONDS:-6}"
MEASURE_SECONDS="${LIQUID_GLASS_BENCHMARK_MEASURE_SECONDS:-8}"
TRACE_MEASURE_MILLISECONDS="${LIQUID_GLASS_BENCHMARK_TRACE_MEASURE_MILLISECONDS:-500}"
# xctrace's windowed mode can silently truncate an 8 s recording to the first
# ~1 s on macOS 26, before the post-attach workload begins.  Keep the complete
# trace by default; callers may opt into a bounded window when they have
# measured that the selected instrument set preserves the workload overlap.
TRACE_WINDOW_SECONDS="${LIQUID_GLASS_BENCHMARK_TRACE_WINDOW_SECONDS:-0}"
# Short, high-density traces can attach more reliably to the already-warmed
# workload than to a notification gate that starts after recording begins.
# Keep the gate as the default for longer/low-density probes.
TRACE_WAIT_FOR_READY="${LIQUID_GLASS_BENCHMARK_TRACE_WAIT_FOR_READY:-true}"
REPETITIONS="${LIQUID_GLASS_BENCHMARK_REPETITIONS:-3}"
ENFORCE_THRESHOLDS="${LIQUID_GLASS_BENCHMARK_ENFORCE:-false}"
SKIP_BUILD="${LIQUID_GLASS_BENCHMARK_SKIP_BUILD:-false}"
SCENARIOS="${LIQUID_GLASS_BENCHMARK_SCENARIOS:-baselineMotion staticSingle realLightingOnly fakeLightingOnly realBlurOnly fakeBlurOnly realHighBlurOnly fakeHighBlurOnly realSaturationOnly fakeSaturationOnly realBlurSaturation fakeBlurSaturation realToolbarMaterial fakeToolbarMaterial realToFakeTransition translatedSingle ancestorTranslatedLayer scaledRotatedSingle grouped4Motion fakeGrouped4Motion fakeUngrouped4Motion grouped8Motion grouped16Motion independent4Motion independent8Motion independent16Motion independent16SharedBackdrop sparse16Motion relativeBlendMotion dynamicBlend16 resizeAnimated layerChurn largeStatic largeResize largeShrinkSettled fakeStatic fakeLarge}"
# Metal tracing is opt-in for on-demand attribution: the kdebug rolling
# buffer retains a fixed event count, not a fixed duration, so xctrace GPU
# capture density varies per run by design and cannot gate. Default runs
# therefore collect no traces; set LIQUID_GLASS_BENCHMARK_TRACE_SCENARIOS to
# trace specific scenarios. The parser's uniformity check remains as trace
# QA: rejected captures report GPU data as unavailable with the reason.
TRACE_SCENARIOS="${LIQUID_GLASS_BENCHMARK_TRACE_SCENARIOS:-}"
FLUTTER_BIN="${LIQUID_GLASS_FLUTTER_BIN:-flutter}"
DART_BIN="${LIQUID_GLASS_DART_BIN:-dart}"
APP_EXECUTABLE="${LIQUID_GLASS_BENCHMARK_EXECUTABLE:-$EXAMPLE_DIR/build/macos/Build/Products/Profile/liquid_glass_renderer_example.app/Contents/MacOS/liquid_glass_renderer_example}"

command -v "$FLUTTER_BIN" >/dev/null || { echo "flutter is required" >&2; exit 1; }
command -v "$DART_BIN" >/dev/null || { echo "dart is required" >&2; exit 1; }
command -v xcrun >/dev/null || { echo "Xcode command-line tools are required" >&2; exit 1; }

rm -rf "$RESULT_DIR"
mkdir -p "$RESULT_DIR/traces" "$RESULT_DIR/logs"
RESULT_DIR="$(cd "$RESULT_DIR" && pwd)"
NOTIFICATION_WAITER="$RESULT_DIR/trace_notification_waiter"
cd "$EXAMPLE_DIR"

ACTIVE_RUN_PID=""
ACTIVE_TRACE_PID=""
ACTIVE_NOTIFICATION_PID=""
ACTIVE_TRACE_WATCHDOG_PID=""

terminate_tree() {
  local parent_pid="$1"
  local child_pid
  while read -r child_pid; do
    [[ -n "$child_pid" ]] && terminate_tree "$child_pid"
  done < <(pgrep -P "$parent_pid" || true)
  kill -TERM "$parent_pid" 2>/dev/null || true
}

cleanup() {
  if [[ -n "$ACTIVE_TRACE_WATCHDOG_PID" ]]; then
    kill -TERM "$ACTIVE_TRACE_WATCHDOG_PID" 2>/dev/null || true
    wait "$ACTIVE_TRACE_WATCHDOG_PID" 2>/dev/null || true
  fi
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
  kill -0 "$pid" 2>/dev/null
}

log_has_runtime_failure() {
  local log_file="$1"
  [[ -f "$log_file" ]] && grep -Eq \
    '══╡ EXCEPTION CAUGHT|Unhandled exception:|\[ERROR:flutter/runtime/|Dart Error:' \
    "$log_file"
}

start_trace_watchdog() {
  local trace_pid="$1"
  local deadline_seconds="$2"
  local trace_log="$3"
  (
    sleep "$deadline_seconds"
    if process_is_running "$trace_pid"; then
      printf 'xctrace exceeded its %ss wall-clock deadline; terminating finalization.\n' \
        "$deadline_seconds" >>"$trace_log"
      kill -TERM "$trace_pid" 2>/dev/null || true
      sleep 5
      if process_is_running "$trace_pid"; then
        kill -KILL "$trace_pid" 2>/dev/null || true
      fi
    fi
  ) &
  ACTIVE_TRACE_WATCHDOG_PID=$!
}

stop_trace_watchdog() {
  if [[ -z "$ACTIVE_TRACE_WATCHDOG_PID" ]]; then
    return
  fi
  kill -TERM "$ACTIVE_TRACE_WATCHDOG_PID" 2>/dev/null || true
  wait "$ACTIVE_TRACE_WATCHDOG_PID" 2>/dev/null || true
  ACTIVE_TRACE_WATCHDOG_PID=""
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
  local trace_start_gate="$notification_received"
  if [[ "$TRACE_WAIT_FOR_READY" != true ]]; then
    trace_start_gate=""
  fi
  env \
    FLUTTER_ENGINE_SWITCHES=3 \
    FLUTTER_ENGINE_SWITCH_1=enable-dart-profiling=true \
    FLUTTER_ENGINE_SWITCH_2=enable-impeller=true \
    FLUTTER_ENGINE_SWITCH_3=enable-flutter-gpu=true \
    LIQUID_GLASS_BENCHMARK_SCENARIO="$scenario" \
    LIQUID_GLASS_BENCHMARK_WARMUP_SECONDS="$WARMUP_SECONDS" \
    LIQUID_GLASS_BENCHMARK_MEASURE_SECONDS="$MEASURE_SECONDS" \
    LIQUID_GLASS_BENCHMARK_TRACE_MEASURE_MILLISECONDS="$TRACE_MEASURE_MILLISECONDS" \
    LIQUID_GLASS_BENCHMARK_REPETITION="$repetition" \
    LIQUID_GLASS_BENCHMARK_TRACE_RUN=1 \
    LIQUID_GLASS_BENCHMARK_TRACE_START_GATE="$trace_start_gate" \
    "$APP_EXECUTABLE" >"$trace_drive_log" 2>&1 &
  trace_run_pid=$!
  ACTIVE_RUN_PID="$trace_run_pid"

  "$NOTIFICATION_WAITER" \
    "$notification_name" \
    "$notification_ready" \
    "$notification_received" >>"$trace_log" 2>&1 &
  ACTIVE_NOTIFICATION_PID=$!
  if ! wait_for_file "$notification_ready" 5; then
    printf 'Could not register for xctrace readiness notification.\n' >>"$trace_log"
    return 1
  fi

  # In prewarmed mode the app has already completed its normal warmup and
  # entered the repeating half-second workload before Instruments attaches.
  # This avoids spending a one-second high-density trace on process startup.
  if [[ "$TRACE_WAIT_FOR_READY" != true ]] && ! wait_for_log \
    "$trace_drive_log" \
    "LIQUID_GLASS_BENCHMARK_MEASURE_BEGIN:$scenario:" \
    "$TRACE_START_TIMEOUT"; then
    printf 'Target did not enter the prewarmed trace workload within %ss.\n' \
      "$TRACE_START_TIMEOUT" >>"$trace_log"
    return 1
  fi

  local -a trace_source_args=()
  if [[ -n "$TRACE_INSTRUMENTS" ]]; then
    local -a instruments=()
    local instrument
    IFS=',' read -ra instruments <<< "$TRACE_INSTRUMENTS"
    for instrument in "${instruments[@]}"; do
      trace_source_args+=(--instrument "$instrument")
    done
  else
    trace_source_args=(--template "$TRACE_TEMPLATE")
  fi

  xcrun xctrace record \
    "${trace_source_args[@]}" \
    --time-limit "$time_limit" \
    "${trace_window_args[@]}" \
    --no-prompt \
    --notify-tracing-started "$notification_name" \
    --output "$trace_path" \
    --attach "$trace_run_pid" >>"$trace_log" 2>&1 &
  trace_pid=$!
  ACTIVE_TRACE_PID="$trace_pid"

  if ! wait_for_log \
    "$trace_log" \
    'Ctrl-C to stop the recording' \
    "$TRACE_START_TIMEOUT"; then
    printf 'xctrace did not report a started recording within %ss.\n' \
      "$TRACE_START_TIMEOUT" >>"$trace_log"
    stop_trace_process "$trace_pid"
    return 1
  fi
  if [[ "$TRACE_WAIT_FOR_READY" == true ]] && ! wait_for_file "$notification_received" "$TRACE_START_TIMEOUT"; then
    printf 'xctrace did not post its tracing-started notification within %ss.\n' \
      "$TRACE_START_TIMEOUT" >>"$trace_log"
    stop_trace_process "$trace_pid"
    return 1
  fi
  # The gated mode starts the expensive scene only after Instruments attaches;
  # the short prewarmed mode intentionally reuses the workload that began
  # after its normal warmup, avoiding a long attach-to-first-frame gap.
  if [[ "$TRACE_WAIT_FOR_READY" == true ]] && ! wait_for_log \
    "$trace_drive_log" \
    "LIQUID_GLASS_BENCHMARK_TRACE_READY:$scenario" \
    "$TRACE_START_TIMEOUT"; then
    printf 'Target did not pass the trace start gate within %ss.\n' \
      "$TRACE_START_TIMEOUT" >>"$trace_log"
    stop_trace_process "$trace_pid"
    return 1
  fi
  if ! wait_for_log \
    "$trace_drive_log" \
    "LIQUID_GLASS_BENCHMARK_MEASURE_BEGIN:$scenario:" \
    "$TRACE_START_TIMEOUT"; then
    printf 'Target did not begin its post-warmup trace workload.\n' \
      >>"$trace_log"
    stop_trace_process "$trace_pid"
    return 1
  fi
  start_trace_watchdog \
    "$trace_pid" \
    "$((trace_duration_seconds + TRACE_FINALIZE_TIMEOUT))" \
    "$trace_log"
  local trace_status=0
  wait "$trace_pid" 2>/dev/null || trace_status=$?
  stop_trace_watchdog
  ACTIVE_TRACE_PID=""
  terminate_existing_benchmark_targets
  wait "$trace_run_pid" 2>/dev/null || true
  ACTIVE_RUN_PID=""
  wait "$ACTIVE_NOTIFICATION_PID" 2>/dev/null || true
  ACTIVE_NOTIFICATION_PID=""
  if log_has_runtime_failure "$trace_drive_log"; then
    printf 'Target logged a Flutter/Dart runtime failure during tracing.\n' \
      >>"$trace_log"
    return 1
  fi
  if ((trace_status != 0)); then
    printf 'xctrace exited unsuccessfully with status %s.\n' "$trace_status" >>"$trace_log"
    return 1
  fi

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
  if [[ ! -s "$toc_path" ]]; then
    printf 'xctrace created an empty table of contents.\n' >>"$trace_log"
    return 1
  fi
  # A wedged Instruments data source (for example after a force-terminated
  # recording) still produces a well-formed bundle and TOC, but every table is
  # empty. Treat a trace with no Metal GPU intervals as a failed attempt so it
  # is retried in a fresh process instead of yielding an empty export.
  # The xpath must address the table node itself: a trace TOC only declares
  # table schemas, so selecting .../row matches nothing even in a healthy
  # trace, while exporting the table node streams its data rows.
  local gpu_row_count
  gpu_row_count="$(
    xcrun xctrace export \
      --input "$trace_path" \
      --xpath '/trace-toc/run[@number="1"]/data/table[@schema="metal-gpu-intervals"]' \
      2>>"$trace_log" | grep -c '<row>' || true
  )"
  if ((gpu_row_count == 0)); then
    printf 'xctrace recorded no Metal GPU intervals; the trace contains no data.\n' \
      >>"$trace_log"
    return 1
  fi
}

capture_metrics_attempt() {
  local scenario="$1"
  local drive_log="$2"
  local run_key="$3"
  local repetition="$4"
  local run_pid benchmark_json

  # An interrupted caller or a previous failed attempt can leave a target
  # alive long enough to emit a late JSON report into the next run's log.
  # Always establish a single fresh target before collecting frame timings.
  terminate_existing_benchmark_targets
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
  if log_has_runtime_failure "$drive_log"; then
    printf 'Target logged a Flutter/Dart runtime failure; rejecting its timings.\n' \
      >>"$drive_log"
    return 1
  fi
  if [[ -z "$benchmark_json" ]]; then
    return 1
  fi
  # A target can finish its native-memory channel without ever delivering a
  # frame (for example while a stale window is being torn down).  Such a JSON
  # envelope is not a measurement and must be retried, never included as a
  # zero-valued repetition in the summary.
  if [[ "$benchmark_json" == *'"frames":[]'* ]]; then
    printf 'Target produced zero frames; treating the measurement as failed.\n' \
      >>"$drive_log"
    return 1
  fi
  # Memory stability flags flow through as informational metadata; an
  # unstable run is annotated in the summary, never discarded.
  printf '%s\n' "$benchmark_json" >"$RESULT_DIR/$run_key.json"
}

SCENARIO_FAIL_REASON=""

run_scenario() {
  local scenario="$1"
  local repetition="$2"
  local run_key="$scenario.r$repetition"
  local drive_log="$RESULT_DIR/logs/$run_key.log"
  local retry_drive_log="$RESULT_DIR/logs/$run_key.retry.log"
  local trace_drive_log="$RESULT_DIR/logs/$run_key.trace-app.log"
  local trace_path="$RESULT_DIR/traces/$run_key.trace"
  local trace_log="$RESULT_DIR/logs/$run_key.xctrace.log"
  local capture_this_trace=false
  for traced_scenario in $TRACE_SCENARIOS; do
    if [[ "$traced_scenario" == "$scenario" ]]; then
      capture_this_trace=true
      break
    fi
  done

  rm -rf "$trace_path" \
    "$RESULT_DIR/traces/$run_key.toc.xml" \
    "$RESULT_DIR/traces/$run_key.gpu.xml" \
    "$RESULT_DIR/traces/$run_key.metal-resources.xml" \
    "$RESULT_DIR/traces/$run_key.signposts.xml"
  SCENARIO_FAIL_REASON=""
  if ! capture_metrics_attempt "$scenario" "$drive_log" "$run_key" "$repetition"; then
    printf 'Initial frame/memory pass failed; retrying in a fresh process.\n' >&2
    if ! capture_metrics_attempt "$scenario" "$retry_drive_log" "$run_key" "$repetition"; then
      SCENARIO_FAIL_REASON="frame/memory pass failed in two fresh processes"
      tail -100 "$drive_log" >&2
      tail -100 "$retry_drive_log" >&2
      return 1
    fi
  fi

  # Instruments substantially perturbs Mach phys_footprint on this
  # workload. Record GPU activity in a fresh, identical profile process so the
  # JSON above remains an uninstrumented memory and frame-timing measurement.
  local trace_valid=false
  if [[ "$CAPTURE_NATIVE_TRACE" == true && "$capture_this_trace" == true ]]; then
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
      printf 'Initial trace was invalid; retrying with a fresh process after a %ss cooldown.\n' \
        "$TRACE_ATTEMPT_COOLDOWN" >>"$trace_log"
      sleep "$TRACE_ATTEMPT_COOLDOWN"
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
  elif [[ "$CAPTURE_NATIVE_TRACE" == true && "$capture_this_trace" == true && "$REQUIRE_NATIVE_TRACE" == true ]]; then
    SCENARIO_FAIL_REASON="native trace capture failed in two fresh processes"
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

# A failing scenario (including the known-flaky native-memory cooldown path
# on the sixteen-independent-layer workload) is recorded and reported in the
# summary; it must never abort the remaining scenarios or suppress it.
mkdir -p "$RESULT_DIR/failures"
for repetition in $(seq 1 "$REPETITIONS"); do
  for scenario in $SCENARIOS; do
    echo "Benchmarking $scenario (repetition $repetition/$REPETITIONS)"
    if ! run_scenario "$scenario" "$repetition"; then
      printf 'Scenario %s (repetition %s) failed; continuing.\n' \
        "$scenario" "$repetition" >&2
      printf '%s\n' "${SCENARIO_FAIL_REASON:-unknown failure; see logs}" \
        >"$RESULT_DIR/failures/$scenario.r$repetition.txt"
    fi
  done
done

"$DART_BIN" run tool/parse_benchmark_results.dart \
  --input "$RESULT_DIR" \
  --markdown "$RESULT_DIR/summary.md" \
  --json "$RESULT_DIR/summary.json" \
  --minimum-repetitions "$REPETITIONS" \
  --enforce "$ENFORCE_THRESHOLDS"

cat "$RESULT_DIR/summary.md"
