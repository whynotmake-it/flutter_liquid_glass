#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK_VERSION="$(xcrun --sdk iphonesimulator --show-sdk-version)"
if [[ "${SDK_VERSION%%.*}" -lt 27 ]]; then
  echo "iOS 27 SDK required; installed simulator SDK is ${SDK_VERSION}." >&2
  exit 2
fi

APP="$ROOT/apple/build/AppleMatch.app"
rm -rf "$APP"
mkdir -p "$APP"
cp "$ROOT/apple/Info.plist" "$APP/Info.plist"
cp "$ROOT"/scenes/*.json "$APP/"

xcrun --sdk iphonesimulator swiftc \
  -parse-as-library \
  -target "arm64-apple-ios27.0-simulator" \
  -framework SwiftUI \
  -framework UIKit \
  "$ROOT/apple/Sources/SceneModel.swift" \
  "$ROOT/apple/Sources/AppleMatchApp.swift" \
  -o "$APP/AppleMatch"
codesign --force --sign - "$APP"
echo "$APP"
