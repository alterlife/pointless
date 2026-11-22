#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Pointless.app"
DMG="build/Pointless.dmg"
ZIP="build/Pointless.zip"
STAGING="build/dmg-staging"
CHECKSUMS="build/checksums.txt"

if [ ! -d "$APP" ]; then
  echo "Error: $APP not found. Running Scripts/make-app.sh first..."
  bash Scripts/make-app.sh
fi

echo "Creating zip archive: $ZIP"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "Creating staging directory for DMG: $STAGING"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "Building disk image: $DMG"
rm -f "$DMG"
hdiutil create \
  -volname "Pointless" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG"

rm -rf "$STAGING"

echo "Verifying DMG mount..."
MOUNT_POINT=$(hdiutil attach "$DMG" -nobrowse -readonly | grep -o '/Volumes/.*' | head -n 1)
if [ -n "$MOUNT_POINT" ]; then
  if [ -d "$MOUNT_POINT/Pointless.app" ] && [ -L "$MOUNT_POINT/Applications" ]; then
    echo "DMG structure verified: Pointless.app and /Applications symlink present."
  else
    echo "Warning: DMG mounted at $MOUNT_POINT but expected contents missing."
  fi
  hdiutil detach "$MOUNT_POINT" -quiet
fi

echo "Generating SHA-256 checksums..."
(cd build && shasum -a 256 Pointless.dmg Pointless.zip > checksums.txt)

echo "Packaging complete:"
echo "  - $DMG ($(du -h "$DMG" | cut -f1))"
echo "  - $ZIP ($(du -h "$ZIP" | cut -f1))"
echo "  - $CHECKSUMS"
cat "$CHECKSUMS"
