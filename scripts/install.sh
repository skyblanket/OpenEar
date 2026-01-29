#!/bin/bash
# OpenEar - Quick Install Script
# Usage: curl -fsSL https://raw.githubusercontent.com/YOURUSERNAME/OpenEar/main/scripts/install.sh | bash

set -e

echo "🎤 Installing OpenEar..."

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check macOS version
if [[ $(sw_vers -productVersion | cut -d. -f1) -lt 14 ]]; then
    echo "❌ OpenEar requires macOS 14 (Sonoma) or later"
    exit 1
fi

# Download latest release
echo -e "${BLUE}Downloading latest release...${NC}"
DOWNLOAD_URL="https://github.com/YOURUSERNAME/OpenEar/releases/latest/download/OpenEar.dmg"
curl -L -o /tmp/OpenEar.dmg "$DOWNLOAD_URL"

# Mount DMG
echo -e "${BLUE}Mounting disk image...${NC}"
hdiutil attach /tmp/OpenEar.dmg -quiet

# Copy to Applications
echo -e "${BLUE}Installing to /Applications...${NC}"
cp -R "/Volumes/OpenEar/OpenEar.app" /Applications/

# Unmount
hdiutil detach "/Volumes/OpenEar" -quiet

# Cleanup
rm /tmp/OpenEar.dmg

echo -e "${GREEN}✅ OpenEar installed successfully!${NC}"
echo ""
echo "To start OpenEar:"
echo "  open /Applications/OpenEar.app"
echo ""
echo "On first launch, you'll need to grant:"
echo "  • Microphone permission"
echo "  • Accessibility permission (System Settings → Privacy & Security → Accessibility)"
echo ""
echo "🎤 Hold Fn or press Ctrl+Space to start recording!"
