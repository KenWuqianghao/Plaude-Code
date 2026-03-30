#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-1.0.0}"
APP_NAME="Plaude Code"
BINARY_NAME="PlaudeCode"
RELEASE_BIN="$ROOT/.build/arm64-apple-macosx/release/$BINARY_NAME"
STAGE="$ROOT/dist/staging"
APP_DIR="$STAGE/$APP_NAME.app"
DMG_NAME="PlaudeCode-${VERSION}.dmg"
DMG_PATH="$ROOT/dist/$DMG_NAME"

cd "$ROOT"
swift build -c release

if [[ ! -x "$RELEASE_BIN" ]]; then
	echo "Missing release binary: $RELEASE_BIN" >&2
	exit 1
fi

rm -rf "$ROOT/dist"
mkdir -p "$APP_DIR/Contents/MacOS"
cp "$RELEASE_BIN" "$APP_DIR/Contents/MacOS/$BINARY_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$BINARY_NAME"
cp "$ROOT/Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP_DIR/Contents/Info.plist"

ln -sf /Applications "$STAGE/Applications"

hdiutil create \
	-volname "$APP_NAME $VERSION" \
	-srcfolder "$STAGE" \
	-ov \
	-format UDZO \
	"$DMG_PATH"

echo "Built $DMG_PATH"
