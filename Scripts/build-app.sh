#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname "$0")"/.. && pwd)"
PRODUCT_NAME="FileWidgetsApp"
HELPER_NAME="VisibilityGuardian"
APP_NAME="Desktop File Box Widget"
BUILD_CONFIGURATION="${1:-debug}"
BUILD_ROOT="$ROOT_DIR/.build/arm64-apple-macosx/$BUILD_CONFIGURATION"
EXECUTABLE_PATH="$BUILD_ROOT/$PRODUCT_NAME"
HELPER_PATH="$BUILD_ROOT/$HELPER_NAME"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
HELPERS_DIR="$CONTENTS_DIR/Helpers"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PLIST_SOURCE="$ROOT_DIR/AppResources/Info.plist"
ICON_SOURCE="$ROOT_DIR/AppResources/AppIcon.icns"

if [[ "$BUILD_CONFIGURATION" != "debug" && "$BUILD_CONFIGURATION" != "release" ]]; then
  echo "Unsupported build configuration: $BUILD_CONFIGURATION" >&2
  echo "Usage: ./Scripts/build-app.sh [debug|release]" >&2
  exit 1
fi

pushd "$ROOT_DIR" >/dev/null
swift build -c "$BUILD_CONFIGURATION"
popd >/dev/null

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$HELPERS_DIR" "$RESOURCES_DIR"

cp "$PLIST_SOURCE" "$CONTENTS_DIR/Info.plist"
cp "$EXECUTABLE_PATH" "$MACOS_DIR/$APP_NAME"
cp "$HELPER_PATH" "$HELPERS_DIR/$HELPER_NAME"
if [[ -f "$ICON_SOURCE" ]]; then
  cp "$ICON_SOURCE" "$RESOURCES_DIR/AppIcon.icns"
fi
chmod +x "$MACOS_DIR/$APP_NAME"
chmod +x "$HELPERS_DIR/$HELPER_NAME"
printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null

echo "Created app bundle:"
echo "$APP_BUNDLE"
