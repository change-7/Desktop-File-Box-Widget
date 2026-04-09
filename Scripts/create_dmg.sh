#!/bin/zsh
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: ./Scripts/create_dmg.sh <app-bundle> <output-dmg> [volume-name]" >&2
  exit 1
fi

APP_BUNDLE="$1"
OUTPUT_DMG="$2"
VOLUME_NAME="${3:-$(basename "$APP_BUNDLE" .app)}"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "App bundle not found: $APP_BUNDLE" >&2
  exit 1
fi

STAGING_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGING_DIR"' EXIT

mkdir -p "$(dirname "$OUTPUT_DMG")"
rm -f "$OUTPUT_DMG"

APP_NAME="$(basename "$APP_BUNDLE")"
ditto "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$OUTPUT_DMG" >/dev/null

echo "Created DMG:"
echo "$OUTPUT_DMG"
