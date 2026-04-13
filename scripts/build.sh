#!/bin/bash
# Build Claude Island for local sharing (no Team ID / notarization required)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
DERIVED_DATA_PATH="$BUILD_DIR/local-share"
EXPORT_PATH="$BUILD_DIR/export"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/Claude Island.app"

echo "=== Building Claude Island (Local Share) ==="
echo ""

rm -rf "$DERIVED_DATA_PATH" "$EXPORT_PATH"
mkdir -p "$BUILD_DIR" "$EXPORT_PATH"

cd "$PROJECT_DIR"

BUILD_CMD=(
    xcodebuild
    build
    -scheme ClaudeIsland
    -configuration Release
    -derivedDataPath "$DERIVED_DATA_PATH"
    CODE_SIGN_STYLE=Automatic
    "OTHER_SWIFT_FLAGS=\$(inherited) -DLOCAL_SHARE_BUILD"
)

echo "Building app..."
if command -v xcpretty >/dev/null 2>&1; then
    set +e
    "${BUILD_CMD[@]}" 2>&1 | xcpretty
    BUILD_EXIT=${PIPESTATUS[0]}
    set -e
else
    set +e
    "${BUILD_CMD[@]}"
    BUILD_EXIT=$?
    set -e
fi

if [ "$BUILD_EXIT" -ne 0 ]; then
    echo "ERROR: Build failed."
    exit 1
fi

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: Expected app not found at $APP_PATH"
    exit 1
fi

cp -R "$APP_PATH" "$EXPORT_PATH/"

echo ""
echo "=== Build Complete ==="
echo "App built at: $APP_PATH"
echo "Copied to: $EXPORT_PATH/Claude Island.app"
echo ""
echo "Next: Run ./scripts/create-release.sh to create a local-share DMG"
