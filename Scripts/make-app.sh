#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"

echo "Building release binary for arm64..."
swift build -c release --arch arm64

BIN_DIR=$(swift build -c release --arch arm64 --show-bin-path)

APP="build/Pointless.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Pointless" "$APP/Contents/MacOS/Pointless"
cp Packaging/Info.plist "$APP/Contents/Info.plist"
cp Packaging/Pointless.icns "$APP/Contents/Resources/Pointless.icns"

if [ -n "$VERSION" ]; then
  CLEAN_VERSION="${VERSION#v}"
  echo "Setting CFBundleShortVersionString to $CLEAN_VERSION..."
  plutil -replace CFBundleShortVersionString -string "$CLEAN_VERSION" "$APP/Contents/Info.plist"
fi

echo "Signing application bundle with ad-hoc signature..."
codesign --force --deep --sign - "$APP"

echo "Verifying code signature..."
codesign --verify --deep --strict "$APP"
echo "Built and verified $APP"
