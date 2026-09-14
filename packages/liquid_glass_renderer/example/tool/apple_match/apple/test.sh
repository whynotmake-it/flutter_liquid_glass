#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_BINARY="$ROOT/apple/build/SceneModelTests"
mkdir -p "$(dirname "$TEST_BINARY")"
xcrun swiftc -parse-as-library \
  "$ROOT/apple/Sources/SceneModel.swift" \
  "$ROOT/apple/Tests/SceneModelTests.swift" \
  -o "$TEST_BINARY"
for scene in toolbar_capsule material_capsule material_capsule_tall material_circle material_card; do
  "$TEST_BINARY" "$ROOT/scenes/$scene.json"
done
