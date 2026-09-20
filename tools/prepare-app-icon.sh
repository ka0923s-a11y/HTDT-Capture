#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SOURCE="$ROOT/Branding/HTDT-AppIcon-source.jpg"
ICONSET="$ROOT/App/Assets.xcassets/AppIcon.appiconset"
OUTPUT="$ICONSET/AppIcon-1024.png"

if [ ! -f "$SOURCE" ]; then
  echo "Missing canonical HTDT app icon source: $SOURCE" >&2
  exit 1
fi

mkdir -p "$ICONSET"
/usr/bin/sips -z 1024 1024 -s format png "$SOURCE" --out "$OUTPUT" >/dev/null

WIDTH=$(/usr/bin/sips -g pixelWidth "$OUTPUT" | awk '/pixelWidth:/ {print $2}')
HEIGHT=$(/usr/bin/sips -g pixelHeight "$OUTPUT" | awk '/pixelHeight:/ {print $2}')
if [ "$WIDTH" != "1024" ] || [ "$HEIGHT" != "1024" ]; then
  echo "Generated app icon has unexpected size: ${WIDTH}x${HEIGHT}" >&2
  exit 1
fi
