#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_BINARY="$ROOT/apple/build/SceneModelTests"
mkdir -p "$(dirname "$TEST_BINARY")"
xcrun swiftc -parse-as-library \
  "$ROOT/apple/Sources/SceneModel.swift" \
  "$ROOT/apple/Tests/SceneModelTests.swift" \
  -o "$TEST_BINARY"
"$TEST_BINARY" "$ROOT/scenes/toolbar_capsule.json"
