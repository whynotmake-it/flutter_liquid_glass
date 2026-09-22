#!/usr/bin/env bash
# Record xctrace Power Profiler or Metal System Trace sessions of an installed
# iOS app, one launch per label, with a thermal gate before every run.
#
# Usage:
#   IOS_UDID=<xctrace udid> DEVICECTL_ID=<devicectl id> BUNDLE=<bundle id> \
#     ios_power_bench.sh <power|metal> <label>[:<mode>] [...]
#
# Optional environment:
#   OUT_ROOT     output root (default build/ios_power_bench in the example)
#   TRACE_S      recording length after settle (default 20)
#   SETTLE_S     seconds between launch and attach (default 12)
#   COOL_TO      thermal state to wait for: Nominal|Fair (default Fair)
#   LAUNCH_ENV   JSON object of environment variables for the launch; the
#                literal MODE inside it is replaced by the label's mode. Your
#                app must read it and drive itself (navigate, scroll) so the
#                recorded window is deterministic; xctrace cannot drive UI.
#   TRIGGER_DEST relative path inside the app's Documents container; when set,
#                {"mode":"<mode>","scroll":true} is copied there before launch
#                and {"mode":"none"} after the run.
#
# Requirements: Xcode 26 command line tools, the phone on USB (xctrace cannot
# attach over Wi-Fi), a profile or release build already installed.
set -uo pipefail

KIND="${1:?power|metal}"; shift
: "${IOS_UDID:?xctrace device UDID}"
: "${DEVICECTL_ID:?devicectl device identifier}"
: "${BUNDLE:?app bundle identifier}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_ROOT="${OUT_ROOT:-$HERE/../../build/ios_power_bench}"
TRACE_S="${TRACE_S:-20}"
SETTLE_S="${SETTLE_S:-12}"
OUT="$OUT_ROOT/traces"; LOGS="$OUT_ROOT/logs"; SHOTS="$OUT_ROOT/shots"; TMP="$OUT_ROOT/tmp"
mkdir -p "$OUT" "$LOGS" "$SHOTS" "$TMP"
case "$KIND" in
  metal) TEMPLATE="Metal System Trace" ;;
  power) TEMPLATE="Power Profiler" ;;
  *) echo "kind must be power or metal" >&2; exit 1 ;;
esac

app_pid() {
  xcrun devicectl device info processes --device "$DEVICECTL_ID" \
    --json-output "$TMP/procs.json" >/dev/null 2>&1
  python3 - "$TMP/procs.json" "$TMP/apps.json" "$BUNDLE" <<'PY'
import json, sys
procs, apps, bundle = sys.argv[1:]
d = json.load(open(procs)); a = json.load(open(apps))
urls = [x['url'] for x in a['result']['apps'] if x.get('bundleIdentifier') == bundle]
if urls:
    url = urls[0].replace('file://', '')
    for p in d['result']['runningProcesses']:
        exe = str(p.get('executable', '')).replace('file://', '')
        if exe.startswith(url):
            print(p['processIdentifier']); break
PY
}

on_usb() {
  xcrun devicectl list devices --json-output "$TMP/devs.json" >/dev/null 2>&1
  python3 - "$TMP/devs.json" "$IOS_UDID" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
ok = any(x['connectionProperties'].get('transportType') == 'wired'
         for x in d['result']['devices'] if x['hardwareProperties'].get('udid') == sys.argv[2])
sys.exit(0 if ok else 1)
PY
}

rank() { case "$1" in Nominal) echo 0;; Fair) echo 1;; Serious) echo 2;; Critical) echo 3;; *) echo 9;; esac; }

xcrun devicectl device info apps --device "$DEVICECTL_ID" --json-output "$TMP/apps.json" >/dev/null 2>&1
for spec in "$@"; do
  LABEL="${spec%%:*}"; MODE="${spec##*:}"
  n=1; while [[ -e "$OUT/${LABEL}_r${n}_${KIND}.trace" ]]; do n=$((n+1)); done
  RUN="${LABEL}_r${n}"
  echo "=== $RUN mode=$MODE $(date +%T)"
  if ! on_usb; then echo "device not on USB; xctrace cannot attach. Aborting." >&2; exit 2; fi
  pid=$(app_pid); [[ -n "$pid" ]] && xcrun devicectl device process terminate --device "$DEVICECTL_ID" --pid "$pid" >/dev/null 2>&1
  waited=0
  while :; do
    state=$(IOS_UDID="$IOS_UDID" OUT_ROOT="$OUT_ROOT" bash "$HERE/ios_thermal_probe.sh")
    [[ $(rank "$state") -le $(rank "${COOL_TO:-Fair}") ]] && break
    echo "    thermal=$state, cooling (${waited}s)"; sleep 60; waited=$((waited+60))
  done
  echo "    start thermal=$state after ${waited}s"
  if [[ -n "${TRIGGER_DEST:-}" ]]; then
    printf '{"mode":"%s","scroll":true}\n' "$MODE" > "$TMP/trigger.json"
    xcrun devicectl device copy to --device "$DEVICECTL_ID" --domain-type appDataContainer \
      --domain-identifier "$BUNDLE" --source "$TMP/trigger.json" --destination "$TRIGGER_DEST" \
      > "$LOGS/${RUN}_copy.log" 2>&1 || { echo "trigger copy failed"; continue; }
  fi
  launch=(xcrun devicectl device process launch --terminate-existing --device "$DEVICECTL_ID")
  if [[ -n "${LAUNCH_ENV:-}" ]]; then launch+=(--environment-variables "${LAUNCH_ENV//MODE/$MODE}"); fi
  "${launch[@]}" "$BUNDLE" > "$LOGS/${RUN}_launch.log" 2>&1 || { echo "launch failed"; tail -3 "$LOGS/${RUN}_launch.log"; continue; }
  sleep "$SETTLE_S"
  xcrun devicectl device capture screenshot --device "$DEVICECTL_ID" --destination "$SHOTS/${RUN}_${KIND}.png" >/dev/null 2>&1 || true
  rm -rf "$OUT/${RUN}_${KIND}.trace"
  xcrun xctrace record --device "$IOS_UDID" --template "$TEMPLATE" --time-limit "${TRACE_S}s" \
    --attach "$(app_pid)" --output "$OUT/${RUN}_${KIND}.trace" --no-prompt \
    > "$LOGS/${RUN}_${KIND}_xctrace.log" 2>&1
  echo "    trace status=$? $(ls -d "$OUT/${RUN}_${KIND}.trace" 2>/dev/null)"
  xcrun devicectl device capture screenshot --device "$DEVICECTL_ID" --destination "$SHOTS/${RUN}_${KIND}_end.png" >/dev/null 2>&1 || true
  if [[ -n "${TRIGGER_DEST:-}" ]]; then
    printf '{"mode":"none"}\n' > "$TMP/trigger.json"
    xcrun devicectl device copy to --device "$DEVICECTL_ID" --domain-type appDataContainer \
      --domain-identifier "$BUNDLE" --source "$TMP/trigger.json" --destination "$TRIGGER_DEST" >/dev/null 2>&1 || true
  fi
  pid=$(app_pid); [[ -n "$pid" ]] && xcrun devicectl device process terminate --device "$DEVICECTL_ID" --pid "$pid" >/dev/null 2>&1
  sleep 2
done
echo "ALL_DONE $(date +%T)"
