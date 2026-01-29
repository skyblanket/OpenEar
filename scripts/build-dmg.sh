#!/bin/bash
# Build OpenEar DMG
# Usage: ./scripts/build-dmg.sh [version]

set -e

VERSION=${1:-"0.1.0"}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "🔨 Building OpenEar v${VERSION}..."

# Build release
echo "Building release..."
xcodebuild -project "$PROJECT_DIR/OpenEar.xcodeproj" \
    -scheme OpenEar \
    -configuration Release \
    -derivedDataPath "$PROJECT_DIR/.build-temp" \
    build

APP_PATH="$PROJECT_DIR/.build-temp/Build/Products/Release/OpenEar.app"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ Build failed - app not found"
    exit 1
fi

# Create releases directory
mkdir -p "$PROJECT_DIR/releases"

# Create temp folder for DMG
DMG_TEMP="/tmp/OpenEar-DMG-$$"
mkdir -p "$DMG_TEMP"
cp -R "$APP_PATH" "$DMG_TEMP/"
ln -sf /Applications "$DMG_TEMP/Applications"

# Create DMG
DMG_PATH="$PROJECT_DIR/releases/OpenEar-v${VERSION}.dmg"
echo "Creating DMG..."
hdiutil create -volname "OpenEar" -srcfolder "$DMG_TEMP" -ov -format UDZO "$DMG_PATH"

# Cleanup
rm -rf "$DMG_TEMP"
rm -rf "$PROJECT_DIR/.build-temp"

echo ""
echo "✅ DMG created: $DMG_PATH"
echo "   Size: $(du -h "$DMG_PATH" | cut -f1)"
echo ""
echo "To test: open \"$DMG_PATH\""
