#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_DIR="$(cd "$EXAMPLE_DIR/../../.." && pwd)"
PKG="com.example.liquid_glass_renderer_example"
ACTIVITY="$PKG/.MainActivity"
DEFAULT_SCENARIOS="appScrollOpaque appScrollPlainBlur appScrollFake appScrollReal appScrollRealOneLayer appScrollRealShadow appScrollRealTabs appScrollFakeShadow appIdleReal appIdleOpaque baselineMotion realToolbarMaterial fakeToolbarMaterial"
SERIAL="${ANDROID_SERIAL:-58080DLCR001DP}"
REPETITIONS=3
WARMUP=5
MEASURE=20
SKIP_BUILD=0
OUT_DIR=""
SCENARIOS="$DEFAULT_SCENARIOS"
MEASURE_PACKAGE=""
MEASURE_SECONDS=30
MEASURE_LABEL="foreground"
MEASURE_SCROLL=0
UNLOCK_PIN="${UNLOCK_PIN:-172839}"
ADB=(adb)

usage() {
  cat <<'EOF'
Usage:
  android_gpu_bench.sh scenarios [--serial SERIAL] [--scenarios "a b c"]
      [--repetitions N] [--warmup S] [--measure S] [--skip-build] [--out DIR]
      [--pin PIN]
  android_gpu_bench.sh measure --package PKG --seconds S --label NAME
      [--serial SERIAL] [--scroll] [--out DIR] [--pin PIN]
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

adb_s() {
  "${ADB[@]}" "$@"
}

strip_cr() {
  tr -d '\r'
}

timestamp() {
  date +%Y%m%d_%H%M%S
}

host_now() {
  date +%s
}

find_flutter() {
  if [[ -x "$REPO_DIR/.fvm/flutter_sdk/bin/flutter" ]]; then
    echo "$REPO_DIR/.fvm/flutter_sdk/bin/flutter"
    return
  fi
  if command -v fvm >/dev/null 2>&1; then
    echo "fvm flutter"
    return
  fi
  command -v flutter >/dev/null 2>&1 || die "flutter is required (fvm in the repo)"
  echo flutter
}

ANALYZER_PY="$SCRIPT_DIR/android_gpu_bench_analyze.py"
VENV_PY="$SCRIPT_DIR/.venv-android-bench/bin/python"

run_analyzer() {
  local out="$1"
  if [[ -x "$VENV_PY" ]]; then
    "$VENV_PY" "$ANALYZER_PY" --out "$out"
  else
    python3 "$ANALYZER_PY" --out "$out"
  fi
}

ORIG_PEAK=""
ORIG_MIN=""
ORIG_BRIGHTNESS=""
ORIG_BRIGHTNESS_MODE=""
ORIG_STAY_ON=""
DEVICE_PINNED=0

restore_device() {
  if [[ "$DEVICE_PINNED" -ne 1 ]]; then
    return
  fi
  echo "Restoring device display/power settings..."
  adb_s shell settings put system peak_refresh_rate "$ORIG_PEAK" || true
  adb_s shell settings put system min_refresh_rate "$ORIG_MIN" || true
  adb_s shell settings put system screen_brightness_mode "$ORIG_BRIGHTNESS_MODE" || true
  adb_s shell settings put system screen_brightness "$ORIG_BRIGHTNESS" || true
  if [[ -n "$ORIG_STAY_ON" ]]; then
    adb_s shell settings put global stay_on_while_plugged_in "$ORIG_STAY_ON" || true
  fi
  adb_s shell svc power stayon false || true
  DEVICE_PINNED=0
}

is_keyguard_showing() {
  local count
  count="$(adb_s shell dumpsys window | strip_cr | grep -c 'isKeyguardShowing=true' || true)"
  [[ "${count:-0}" -gt 0 ]]
}

tap_pin_keypad() {
  # Pixel 10 lock-screen keypad (1080x2424). input text does not reach it.
  local pin="$1"
  local -A keys=(
    [1]="266 1170" [2]="540 1170" [3]="814 1170"
    [4]="266 1423" [5]="540 1423" [6]="814 1423"
    [7]="266 1676" [8]="540 1676" [9]="814 1676"
    [0]="540 1929"
  )
  local i digit
  for ((i = 0; i < ${#pin}; i++)); do
    digit="${pin:i:1}"
    if [[ -n "${keys[$digit]:-}" ]]; then
      # shellcheck disable=SC2086
      adb_s shell input tap ${keys[$digit]} || true
      sleep 0.12
    fi
  done
}

unlock_if_needed() {
  # Never send KEYCODE_POWER / sleep. Wake only. stayon first so we are
  # not typing the PIN into an AOD / doze frame.
  adb_s shell svc power stayon true || true
  adb_s shell input keyevent KEYCODE_WAKEUP || true
  sleep 0.25
  if is_keyguard_showing; then
    echo "Keyguard showing; unlocking with PIN"
    adb_s shell wm dismiss-keyguard || true
    sleep 0.35
    adb_s shell input swipe 540 1900 540 600 200 || true
    sleep 0.35
    adb_s shell input text "$UNLOCK_PIN" || true
    adb_s shell input keyevent KEYCODE_ENTER || true
    sleep 0.25
    if is_keyguard_showing; then
      tap_pin_keypad "$UNLOCK_PIN"
      sleep 0.4
    fi
  fi
}

pin_device() {
  ORIG_PEAK="$(adb_s shell settings get system peak_refresh_rate | strip_cr)"
  ORIG_MIN="$(adb_s shell settings get system min_refresh_rate | strip_cr)"
  ORIG_BRIGHTNESS="$(adb_s shell settings get system screen_brightness | strip_cr)"
  ORIG_BRIGHTNESS_MODE="$(adb_s shell settings get system screen_brightness_mode | strip_cr)"
  ORIG_STAY_ON="$(adb_s shell settings get global stay_on_while_plugged_in | strip_cr)"
  adb_s shell settings put system peak_refresh_rate 120
  adb_s shell settings put system min_refresh_rate 120
  adb_s shell settings put system screen_brightness_mode 0
  adb_s shell settings put system screen_brightness 128
  adb_s shell svc power stayon true
  unlock_if_needed
  DEVICE_PINNED=1
}

package_uid() {
  local package="$1"
  local from_pm
  from_pm="$(adb_s shell pm list packages -U "$package" | strip_cr | awk -F'uid:' 'NF>1{print $2; exit}' | tr -d ' ')"
  if [[ -n "$from_pm" ]]; then
    printf '%s\n' "$from_pm"
    return
  fi
  adb_s shell dumpsys package "$package" | strip_cr | awk '/appId=/{print $1; exit}' | grep -oE '[0-9]+' | head -1
}

snapshot_sysfs() {
  local dest="$1"
  local package="$2"
  mkdir -p "$dest"
  host_now >"$dest/host_unix.txt"
  adb_s shell date +%s | strip_cr >"$dest/device_unix.txt" || true
  local uid
  uid="$(package_uid "$package" || true)"
  printf '%s\n' "$uid" >"$dest/uid.txt"
  adb_s exec-out cat /sys/devices/platform/34f00000.gpu0/uid_time_in_state \
    >"$dest/uid_time_in_state.txt" 2>/dev/null || true
  adb_s exec-out cat /sys/class/devfreq/34f00000.gpu0/trans_stat \
    >"$dest/trans_stat.txt" 2>/dev/null || true
  adb_s exec-out cat /sys/class/devfreq/34f00000.gpu0/cur_freq \
    >"$dest/cur_freq.txt" 2>/dev/null || true
  adb_s exec-out cat /sys/devices/platform/34f00000.gpu0/power_state/time_in_state_ms \
    >"$dest/power_state_time_in_state_ms.txt" 2>/dev/null || true
  adb_s exec-out cat /sys/class/power_supply/battery/current_now \
    >"$dest/battery_current_now.txt" 2>/dev/null || true
  adb_s exec-out dumpsys thermalservice >"$dest/thermalservice.txt" 2>/dev/null || true
}

write_perfetto_config() {
  local dest="$1"
  local duration_ms="$2"
  local package="$3"
  cat >"$dest" <<EOF
buffers: {
    size_kb: 131072
    fill_policy: RING_BUFFER
}
data_sources: {
    config {
        name: "android.power"
        android_power_config {
            battery_poll_ms: 250
            battery_counters: BATTERY_COUNTER_CURRENT
            battery_counters: BATTERY_COUNTER_VOLTAGE
            battery_counters: BATTERY_COUNTER_CHARGE
            collect_power_rails: true
        }
    }
}
data_sources: {
    config {
        name: "linux.ftrace"
        ftrace_config {
            ftrace_events: "power/gpu_frequency"
            ftrace_events: "power/cpu_frequency"
            ftrace_events: "power/gpu_work_period"
            atrace_categories: "gfx"
            atrace_categories: "power"
            atrace_categories: "freq"
            atrace_categories: "idle"
            atrace_categories: "thermal"
            atrace_categories: "view"
            atrace_categories: "dart"
            atrace_apps: "$package"
        }
    }
}
data_sources: {
    config {
        name: "linux.process_stats"
        process_stats_config {
            scan_all_processes_on_start: true
        }
    }
}
data_sources: {
    config {
        name: "android.surfaceflinger.frametimeline"
    }
}
data_sources: {
    config {
        name: "linux.sys_stats"
        sys_stats_config {
            cpufreq_period_ms: 250
        }
    }
}
write_into_file: true
file_write_period_ms: 2000
duration_ms: $duration_ms
EOF
}

start_perfetto() {
  local cfg="$1"
  local remote="$2"
  adb_s push "$cfg" /data/misc/perfetto-configs/lg_gpu_bench.cfg >/dev/null
  adb_s shell rm -f "$remote" || true
  adb_s shell perfetto -c /data/misc/perfetto-configs/lg_gpu_bench.cfg --txt -o "$remote"
}

wait_for_marker() {
  local file="$1"
  local marker="$2"
  local timeout="$3"
  local start=$SECONDS
  while ((SECONDS - start < timeout)); do
    if grep -F -q -- "$marker" "$file" 2>/dev/null; then
      return 0
    fi
    sleep 0.15
  done
  return 1
}

detect_flutter_errors() {
  local file="$1"
  # Impeller logs pipeline-compile coalescing at ERROR; that is not a Dart crash.
  grep -E 'EXCEPTION CAUGHT|Unhandled exception|\[ERROR:flutter/' "$file" 2>/dev/null \
    | grep -v 'pipeline_compile_queue' >/dev/null
}

extract_summary_json() {
  local file="$1"
  local dest="$2"
  local line
  line="$(grep -F 'LIQUID_GLASS_BENCHMARK_SUMMARY:' "$file" | tail -1 || true)"
  if [[ -z "$line" ]]; then
    return 1
  fi
  printf '%s\n' "${line#*LIQUID_GLASS_BENCHMARK_SUMMARY:}" >"$dest"
}

ensure_device() {
  adb_s get-state >/dev/null
}

parse_common_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --serial)
        SERIAL="$2"
        shift 2
        ;;
      --out)
        OUT_DIR="$2"
        shift 2
        ;;
      --scenarios)
        SCENARIOS="$2"
        shift 2
        ;;
      --repetitions)
        REPETITIONS="$2"
        shift 2
        ;;
      --warmup)
        WARMUP="$2"
        shift 2
        ;;
      --measure)
        MEASURE="$2"
        shift 2
        ;;
      --skip-build)
        SKIP_BUILD=1
        shift
        ;;
      --package)
        MEASURE_PACKAGE="$2"
        shift 2
        ;;
      --seconds)
        MEASURE_SECONDS="$2"
        shift 2
        ;;
      --label)
        MEASURE_LABEL="$2"
        shift 2
        ;;
      --scroll)
        MEASURE_SCROLL=1
        shift
        ;;
      --pin)
        UNLOCK_PIN="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown argument: $1"
        ;;
    esac
  done
  ADB=(adb -s "$SERIAL")
}

cmd_scenarios() {
  parse_common_args "$@"
  ensure_device
  if [[ -z "$OUT_DIR" ]]; then
    OUT_DIR="$EXAMPLE_DIR/build/android_gpu_bench/$(timestamp)"
  fi
  mkdir -p "$OUT_DIR"
  OUT_DIR="$(cd "$OUT_DIR" && pwd)"
  local apk="$EXAMPLE_DIR/build/app/outputs/flutter-apk/app-profile.apk"
  local flutter_bin
  flutter_bin="$(find_flutter)"
  if [[ "$SKIP_BUILD" -eq 0 ]]; then
    echo "Building profile APK with $flutter_bin"
    (
      cd "$EXAMPLE_DIR"
      if [[ "$flutter_bin" == "fvm flutter" ]]; then
        fvm flutter build apk --profile -t integration_test/benchmark_test.dart
      else
        "$flutter_bin" build apk --profile -t integration_test/benchmark_test.dart
      fi
    )
  fi
  [[ -f "$apk" ]] || die "profile APK not found at $apk"
  echo "Installing $apk"
  adb_s install -r "$apk" >/dev/null
  unlock_if_needed
  pin_device
  trap restore_device EXIT
  local -a scenario_list
  # shellcheck disable=SC2206
  scenario_list=($SCENARIOS)
  local uid
  uid="$(package_uid "$PKG" || true)"
  python3 - "$OUT_DIR/meta.json" "$SERIAL" "$PKG" "$WARMUP" "$MEASURE" "$REPETITIONS" "$uid" <<'PY'
import json, sys
path, serial, package, warmup, measure, reps, uid = sys.argv[1:]
with open(path, "w", encoding="utf-8") as handle:
    json.dump({
        "mode": "scenarios",
        "serial": serial,
        "package": package,
        "warmupSeconds": int(warmup),
        "measureSeconds": int(measure),
        "repetitions": int(reps),
        "uid": uid,
    }, handle, indent=2)
    handle.write("\n")
PY

  local rep scenario
  for ((rep = 1; rep <= REPETITIONS; rep++)); do
    for scenario in "${scenario_list[@]}"; do
      run_scenario "$scenario" "$rep" "$uid"
    done
  done
  run_analyzer "$OUT_DIR"
}

run_scenario() {
  local scenario="$1"
  local rep="$2"
  local uid="$3"
  local run_dir="$OUT_DIR/${scenario}_r${rep}"
  mkdir -p "$run_dir"
  echo "==> $scenario repetition $rep"
  adb_s shell am force-stop "$PKG" || true
  sleep 0.4
  unlock_if_needed
  adb_s logcat -c || true
  : >"$run_dir/logcat.txt"
  adb_s logcat -v threadtime >"$run_dir/logcat.txt" &
  local logcat_pid=$!
  adb_s shell am start -W -n "$ACTIVITY" \
    --ez trace-systrace true \
    --es scenario "$scenario" \
    --ei warmupSeconds "$WARMUP" \
    --ei measureSeconds "$MEASURE" \
    --ei repetition "$rep" >/dev/null || true

  local status="ok"
  local reason=""
  local begin_marker="LIQUID_GLASS_BENCHMARK_MEASURE_BEGIN:${scenario}"
  local end_marker="LIQUID_GLASS_BENCHMARK_MEASURE_END:${scenario}"
  if ! wait_for_marker "$run_dir/logcat.txt" "$begin_marker" 90; then
    status="failed"
    reason="MEASURE_BEGIN timeout"
  fi
  if [[ "$status" == "ok" ]]; then
    adb_s exec-out screencap -p >"$run_dir/screenshot.png" 2>/dev/null || true
  fi

  local perfetto_pid=""
  local remote_trace="/data/misc/perfetto-traces/lg_${scenario}_r${rep}.pftrace"
  local duration_ms=$(( (MEASURE - 2) * 1000 ))
  if ((duration_ms < 1000)); then
    duration_ms=1000
  fi
  if [[ "$status" == "ok" ]]; then
    snapshot_sysfs "$run_dir/begin" "$PKG"
    write_perfetto_config "$run_dir/perfetto.cfg" "$duration_ms" "$PKG"
    start_perfetto "$run_dir/perfetto.cfg" "$remote_trace" >"$run_dir/perfetto.log" 2>&1 &
    perfetto_pid=$!
    if ! wait_for_marker "$run_dir/logcat.txt" "$end_marker" $((MEASURE + 90)); then
      status="failed"
      reason="MEASURE_END timeout"
    fi
    adb_s exec-out dumpsys gfxinfo "$PKG" framestats >"$run_dir/gfxinfo.txt" 2>/dev/null || true
    snapshot_sysfs "$run_dir/end" "$PKG"
    if ! wait_for_marker "$run_dir/logcat.txt" "LIQUID_GLASS_BENCHMARK_SUMMARY:" 60; then
      if [[ "$status" == "ok" ]]; then
        status="failed"
        reason="SUMMARY timeout"
      fi
    else
      extract_summary_json "$run_dir/logcat.txt" "$run_dir/flutter_summary.json" || true
      if [[ -f "$run_dir/flutter_summary.json" ]]; then
        local frame_count expected_half
        frame_count="$(python3 -c 'import json,sys; print(int(json.load(open(sys.argv[1])).get("frameCount") or 0))' "$run_dir/flutter_summary.json")"
        expected_half=$((MEASURE * 50))
        if ((frame_count < expected_half)); then
          status="failed"
          reason="no-frames"
        fi
      fi
    fi
  else
    snapshot_sysfs "$run_dir/begin" "$PKG" || true
    snapshot_sysfs "$run_dir/end" "$PKG" || true
  fi

  if [[ -n "$perfetto_pid" ]]; then
    wait "$perfetto_pid" || true
  fi
  adb_s pull "$remote_trace" "$run_dir/trace.pftrace" >/dev/null 2>&1 || true
  if detect_flutter_errors "$run_dir/logcat.txt"; then
    status="failed"
    reason="${reason:+$reason; }Flutter runtime error"
  fi
  adb_s shell am force-stop "$PKG" || true
  kill "$logcat_pid" >/dev/null 2>&1 || true
  wait "$logcat_pid" >/dev/null 2>&1 || true

  local wall=""
  if [[ -f "$run_dir/begin/host_unix.txt" && -f "$run_dir/end/host_unix.txt" ]]; then
    wall=$(( $(cat "$run_dir/end/host_unix.txt") - $(cat "$run_dir/begin/host_unix.txt") ))
  fi
  python3 -c '
import json, sys
payload = {
    "scenario": sys.argv[1],
    "baseScenario": sys.argv[2],
    "repetition": int(sys.argv[3]),
    "package": sys.argv[4],
    "uid": sys.argv[5] or None,
    "warmupSeconds": int(sys.argv[6]),
    "measureSeconds": int(sys.argv[7]),
    "wallSeconds": int(sys.argv[8]) if sys.argv[8] else None,
    "status": sys.argv[9],
    "failureReason": sys.argv[10] or None,
    "skipAnalysis": sys.argv[10] == "no-frames",
}
with open(sys.argv[11], "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2)
    handle.write("\n")
' "$scenario" "$scenario" "$rep" "$PKG" "$uid" "$WARMUP" "$MEASURE" "${wall:-}" "$status" "$reason" "$run_dir/run.json"
  echo "    $status${reason:+ ($reason)}"
}

cmd_measure() {
  parse_common_args "$@"
  [[ -n "$MEASURE_PACKAGE" ]] || die "--package is required"
  ensure_device
  if [[ -z "$OUT_DIR" ]]; then
    OUT_DIR="$EXAMPLE_DIR/build/android_gpu_bench/$(timestamp)"
  fi
  mkdir -p "$OUT_DIR"
  OUT_DIR="$(cd "$OUT_DIR" && pwd)"
  unlock_if_needed
  pin_device
  trap restore_device EXIT
  local run_dir="$OUT_DIR/${MEASURE_LABEL}"
  mkdir -p "$run_dir"
  local uid
  uid="$(package_uid "$MEASURE_PACKAGE" || true)"
  python3 - "$OUT_DIR/meta.json" "$SERIAL" "$MEASURE_PACKAGE" "$MEASURE_SECONDS" "$MEASURE_LABEL" "$uid" <<'PY'
import json, sys
path, serial, package, seconds, label, uid = sys.argv[1:]
with open(path, "w", encoding="utf-8") as handle:
    json.dump({
        "mode": "measure",
        "serial": serial,
        "package": package,
        "seconds": int(seconds),
        "label": label,
        "uid": uid,
    }, handle, indent=2)
    handle.write("\n")
PY
  adb_s shell dumpsys gfxinfo "$MEASURE_PACKAGE" reset >/dev/null || true
  adb_s exec-out dumpsys gfxinfo "$MEASURE_PACKAGE" framestats >"$run_dir/gfxinfo_before.txt" 2>/dev/null || true
  snapshot_sysfs "$run_dir/begin" "$MEASURE_PACKAGE"
  local duration_ms=$((MEASURE_SECONDS * 1000))
  write_perfetto_config "$run_dir/perfetto.cfg" "$duration_ms" "$MEASURE_PACKAGE"
  local remote_trace="/data/misc/perfetto-traces/lg_measure_${MEASURE_LABEL}.pftrace"
  start_perfetto "$run_dir/perfetto.cfg" "$remote_trace" >"$run_dir/perfetto.log" 2>&1 &
  local perfetto_pid=$!
  local scroll_pid=""
  if [[ "$MEASURE_SCROLL" -eq 1 ]]; then
    (
      while true; do
        adb_s shell input swipe 540 1700 540 700 300 || true
        sleep 0.2
        adb_s shell input swipe 540 700 540 1700 300 || true
        sleep 0.2
      done
    ) &
    scroll_pid=$!
  fi
  wait "$perfetto_pid" || true
  if [[ -n "$scroll_pid" ]]; then
    kill "$scroll_pid" >/dev/null 2>&1 || true
    wait "$scroll_pid" >/dev/null 2>&1 || true
  fi
  snapshot_sysfs "$run_dir/end" "$MEASURE_PACKAGE"
  adb_s exec-out dumpsys gfxinfo "$MEASURE_PACKAGE" framestats >"$run_dir/gfxinfo.txt" 2>/dev/null || true
  adb_s pull "$remote_trace" "$run_dir/trace.pftrace" >/dev/null 2>&1 || true
  local wall=""
  if [[ -f "$run_dir/begin/host_unix.txt" && -f "$run_dir/end/host_unix.txt" ]]; then
    wall=$(( $(cat "$run_dir/end/host_unix.txt") - $(cat "$run_dir/begin/host_unix.txt") ))
  fi
  python3 -c '
import json, sys
payload = {
    "scenario": sys.argv[1],
    "label": sys.argv[1],
    "repetition": 1,
    "package": sys.argv[2],
    "uid": sys.argv[3] or None,
    "measureSeconds": int(sys.argv[4]),
    "wallSeconds": int(sys.argv[5]) if sys.argv[5] else None,
    "status": "ok",
    "failureReason": None,
}
with open(sys.argv[6], "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2)
    handle.write("\n")
' "$MEASURE_LABEL" "$MEASURE_PACKAGE" "$uid" "$MEASURE_SECONDS" "${wall:-}" "$run_dir/run.json"
  run_analyzer "$OUT_DIR"
}

main() {
  local cmd="${1:-}"
  if [[ -z "$cmd" ]]; then
    usage
    exit 1
  fi
  shift
  case "$cmd" in
    scenarios) cmd_scenarios "$@" ;;
    measure) cmd_measure "$@" ;;
    -h|--help) usage ;;
    *) die "unknown subcommand: $cmd" ;;
  esac
}

main "$@"
