#!/usr/bin/env bash
set -euo pipefail

# Legacy entry point kept for callers that still invoke capture_loupe.sh;
# the loupe driver now lives in capture.sh's --loupe mode.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec bash "$ROOT/apple/capture.sh" --loupe "$@"
