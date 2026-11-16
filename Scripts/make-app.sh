#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/Pointless.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Pointless "$APP/Contents/MacOS/Pointless"
cp Packaging/Info.plist "$APP/Contents/Info.plist"

codesign --force --deep --sign - "$APP"
echo "Built $APP"
