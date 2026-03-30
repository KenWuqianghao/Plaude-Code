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
ICON_SRC="$ROOT/Packaging/Logo/AppIcon-1024.png"
ICONSET="$ROOT/dist/AppIcon.iconset"
# RW image then convert — more reliable than -srcfolder; avoids odd symlink/layout issues.
RW_DMG="$ROOT/dist/.build-temp-raster.dmg"
MOUNT_PT="$ROOT/dist/.mnt"

cd "$ROOT"
swift build -c release

if [[ ! -x "$RELEASE_BIN" ]]; then
	echo "Missing release binary: $RELEASE_BIN" >&2
	exit 1
fi

if [[ ! -f "$ICON_SRC" ]]; then
	echo "Missing icon source: $ICON_SRC" >&2
	exit 1
fi

rm -rf "$ROOT/dist"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$RELEASE_BIN" "$APP_DIR/Contents/MacOS/$BINARY_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$BINARY_NAME"
cp "$ROOT/Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP_DIR/Contents/Info.plist"

printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

# ---- AppIcon.icns (required filenames for iconutil) ----
mkdir -p "$ICONSET"
sips -z 16 16 "$ICON_SRC" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SRC" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SRC" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SRC" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SRC" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SRC" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SRC" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SRC" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SRC" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_SRC" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

# Strip extended attributes (avoids Gatekeeper “damaged” after copy from DMG).
xattr -cr "$APP_DIR"

# Signing:
# • Release DMGs from GitHub use ad-hoc signing (`-`). macOS still shows a malware warning until the app is
#   signed with Developer ID and the DMG is notarized; see README.
# • Set CODESIGN_IDENTITY to "Developer ID Application: Your Name (TEAMID)" for a notarizable build.
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
	codesign --force --sign "$CODESIGN_IDENTITY" --timestamp --options runtime --deep "$APP_DIR"
else
	codesign --force --sign - --timestamp=none --deep "$APP_DIR"
fi

# ---- DMG: blank read-write image → copy → detach → compress ----
mkdir -p "$MOUNT_PT"
# HFS+ is the most compatible DMG filesystem across Macs.
hdiutil create -ov -size 320m -fs HFS+ -volname "Plaude Code" "$RW_DMG"
hdiutil attach -readwrite -mountpoint "$MOUNT_PT" -noverify -noautoopen "$RW_DMG"
cp -R "$APP_DIR" "$MOUNT_PT/"
# Finder alias to Applications (symlink to /Applications is standard for drag installs).
ln -sf /Applications "$MOUNT_PT/Applications"
chmod -R a+rX "$MOUNT_PT"
sync
hdiutil detach "$MOUNT_PT"
rmdir "$MOUNT_PT" 2>/dev/null || true

hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH"
rm -f "$RW_DMG"

echo "Built $DMG_PATH"
