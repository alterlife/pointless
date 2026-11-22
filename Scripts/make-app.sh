#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "Building release binary for arm64..."
swift build -c release --arch arm64

APP="build/Pointless.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Pointless "$APP/Contents/MacOS/Pointless"
cp Packaging/Info.plist "$APP/Contents/Info.plist"
cp Packaging/Pointless.icns "$APP/Contents/Resources/Pointless.icns"

echo "Signing application bundle with ad-hoc signature..."
codesign --force --deep --sign - "$APP"

echo "Verifying code signature..."
codesign --verify --deep --strict "$APP"
echo "Built and verified $APP"
