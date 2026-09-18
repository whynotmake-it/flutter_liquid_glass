#!/usr/bin/env bash
# Print the device thermal state (Nominal|Fair|Serious|Critical|Unknown) from a
# 2 s Metal System Trace. Takes ~15 s because xctrace saves the trace.
#   IOS_UDID=<xctrace udid> ios_thermal_probe.sh
set -uo pipefail
: "${IOS_UDID:?xctrace device UDID}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_ROOT="${OUT_ROOT:-$HERE/../../build/ios_power_bench}"
mkdir -p "$OUT_ROOT/tmp"
T="$OUT_ROOT/tmp/_probe.trace"; X="$OUT_ROOT/tmp/_probe_thermal.xml"
rm -rf "$T"
xcrun xctrace record --device "$IOS_UDID" --template 'Metal System Trace' --time-limit 2s \
  --all-processes --output "$T" --no-prompt >/dev/null 2>&1
# xctrace export segfaults intermittently (Xcode 26.0); retry.
for attempt in 1 2 3 4; do
  rm -f "$X"
  xcrun xctrace export --input "$T" --output "$X" \
    --xpath "//trace-toc/run[@number=1]/data/table[@schema='device-thermal-state-intervals']" >/dev/null 2>&1 \
    && [[ -s "$X" ]] && break
  sleep 1
done
python3 - "$X" <<'PY'
import re, sys, pathlib
p = pathlib.Path(sys.argv[1])
x = p.read_text(errors="replace") if p.exists() else ""
states = re.findall(r'<thermal-state[^>]*fmt="([^"]+)"', x) or re.findall(r"<thermal-state[^>]*>([^<]+)<", x)
order = {"Nominal": 0, "Fair": 1, "Serious": 2, "Critical": 3}
print(max(states, key=lambda s: order.get(s, 9)) if states else "Unknown")
PY
rm -rf "$T" "$X"
