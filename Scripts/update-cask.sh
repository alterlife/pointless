#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
DMG_SHA="${2:-}"
CASK_PATH="Casks/pointless.rb"

if [ -z "$VERSION" ] || [ -z "$DMG_SHA" ]; then
  echo "Usage: $0 <version> <dmg_sha256>" >&2
  exit 1
fi

if [ ! -f "$CASK_PATH" ]; then
  echo "Error: $CASK_PATH not found" >&2
  exit 1
fi

ruby -e '
  version = ARGV[0]
  sha = ARGV[1]
  path = ARGV[2]
  content = File.read(path)
  content.sub!(/version\s+"[^"]+"/, %{version "#{version}"})
  content.sub!(/sha256\s+(?::no_check|"[^"]+")/, %{sha256 "#{sha}"})
  File.write(path, content)
' "$VERSION" "$DMG_SHA" "$CASK_PATH"

echo "Updated $CASK_PATH: version $VERSION, sha256 $DMG_SHA"
