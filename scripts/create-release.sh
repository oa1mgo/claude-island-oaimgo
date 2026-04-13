#!/bin/bash
# Create a local-share DMG for Claude Island (no Team ID / notarization)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
EXPORT_PATH="$BUILD_DIR/export"
RELEASE_DIR="$PROJECT_DIR/releases"
APP_PATH="$EXPORT_PATH/Claude Island.app"
APP_NAME="ClaudeIsland"

echo "=== Creating Local Share DMG ==="
echo ""

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: App not found at $APP_PATH"
    echo "Run ./scripts/build.sh first"
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_PATH/Contents/Info.plist")
DMG_PATH="$RELEASE_DIR/$APP_NAME-$VERSION-local.dmg"

echo "Version: $VERSION (build $BUILD)"
echo ""

mkdir -p "$RELEASE_DIR"
rm -f "$DMG_PATH"

if command -v create-dmg >/dev/null 2>&1; then
    echo "Using create-dmg..."
    create-dmg \
        --volname "Claude Island" \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "Claude Island.app" 150 200 \
        --app-drop-link 450 200 \
        --hide-extension "Claude Island.app" \
        "$DMG_PATH" \
        "$APP_PATH"
else
    echo "Using hdiutil..."
    hdiutil create -volname "Claude Island" \
        -srcfolder "$APP_PATH" \
        -ov -format UDZO \
        "$DMG_PATH"
fi

echo ""
echo "=== Local Share Package Ready ==="
echo "DMG: $DMG_PATH"
echo ""
echo "Note: This build is for friend-to-friend testing."
echo "macOS may still show a security warning on other machines."
echo "Your friend can right-click the app and choose Open if needed."
