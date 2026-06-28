#!/bin/zsh
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <app-path> <output-dmg-path> [volume-name]" >&2
  exit 1
fi

APP_PATH="$1"
OUTPUT_DMG="$2"
VOLUME_NAME="${3:-Matcha}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

TMPDIR="$(mktemp -d /tmp/matcha-dmg.XXXXXX)"
cleanup() {
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

xattr -cr "$APP_PATH"
codesign --force --deep --sign - "$APP_PATH"

cp -R "$APP_PATH" "$TMPDIR/$(basename "$APP_PATH")"
ln -s /Applications "$TMPDIR/Applications"

mkdir -p "$(dirname "$OUTPUT_DMG")"
rm -f "$OUTPUT_DMG"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$TMPDIR" \
  -ov \
  -format UDZO \
  "$OUTPUT_DMG"

