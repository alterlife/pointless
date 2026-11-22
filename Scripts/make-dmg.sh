#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
APP="build/Pointless.app"
DMG="build/Pointless.dmg"
ZIP="build/Pointless.zip"
STAGING="build/dmg-staging"
CHECKSUMS="build/checksums.txt"
MOUNT_DIR=$(mktemp -d /tmp/pointless-mount.XXXXXX)

cleanup() {
  if [ -d "$MOUNT_DIR" ]; then
    hdiutil detach "$MOUNT_DIR" -force -quiet 2>/dev/null || true
    rmdir "$MOUNT_DIR" 2>/dev/null || true
  fi
  rm -rf "$STAGING"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [ ! -d "$APP" ]; then
  echo "Application bundle not found. Building with Scripts/make-app.sh..."
  bash Scripts/make-app.sh "$VERSION"
fi

echo "Verifying code signature of $APP..."
codesign --verify --deep --strict "$APP"

echo "Creating zip archive: $ZIP"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "Creating staging directory for DMG: $STAGING"
rm -rf "$STAGING"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/Pointless.app"
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
hdiutil attach "$DMG" -mountpoint "$MOUNT_DIR" -nobrowse -readonly -quiet

if [ -d "$MOUNT_DIR/Pointless.app" ] && [ -L "$MOUNT_DIR/Applications" ]; then
  echo "DMG structure verified: Pointless.app and /Applications symlink present."
else
  echo "Error: DMG verification failed. Required files missing inside disk image." >&2
  hdiutil detach "$MOUNT_DIR" -force -quiet 2>/dev/null || true
  exit 1
fi

hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null || { sleep 1; hdiutil detach "$MOUNT_DIR" -force -quiet; }

echo "Generating SHA-256 checksums..."
(cd build && shasum -a 256 Pointless.dmg Pointless.zip > checksums.txt)

echo "Packaging complete:"
echo "  - $DMG ($(du -h "$DMG" | cut -f1))"
echo "  - $ZIP ($(du -h "$ZIP" | cut -f1))"
echo "  - $CHECKSUMS"
cat "$CHECKSUMS"
