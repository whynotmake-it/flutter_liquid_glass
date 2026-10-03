#!/usr/bin/env bash
# Re-analyzes a benchmark result directory from either runner and writes
# summary.md and summary.json next to the raw data.
#
#   tool/bench_analyze.sh build/benchmark            # Metal (benchmark.sh)
#   tool/bench_analyze.sh build/android-gpu-bench/X  # Pixel, with mW columns
#   tool/bench_analyze.sh build/android-ab/X         # Pixel A/B (android_ab_bench.py)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLE_DIR="$(dirname "$SCRIPT_DIR")"
dir="${1:?usage: bench_analyze.sh RESULT_DIR [--minimum-repetitions N]}"
shift

if [[ -f "$dir/meta.json" ]] && grep -q '"arms"' "$dir/meta.json"; then
  py="$SCRIPT_DIR/.venv-android-bench/bin/python"
  [[ -x "$py" ]] || py=python3
  "$py" "$SCRIPT_DIR/android_ab_analyze.py" "$dir" >/dev/null
elif [[ -f "$dir/meta.json" ]] && grep -q '"serial"' "$dir/meta.json"; then
  py="$SCRIPT_DIR/.venv-android-bench/bin/python"
  [[ -x "$py" ]] || py=python3
  "$py" "$SCRIPT_DIR/android_gpu_bench_analyze.py" --out "$dir"
else
  (cd "$EXAMPLE_DIR" && "${LIQUID_GLASS_DART_BIN:-dart}" run \
    tool/parse_benchmark_results.dart \
    --input "$dir" \
    --markdown "$dir/summary.md" \
    --json "$dir/summary.json" \
    "$@")
fi
cat "$dir/summary.md"
