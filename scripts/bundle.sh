#!/bin/bash
# bundle.sh — Create MEditor.app bundle after swift build
# Usage: ./scripts/bundle.sh
# Then: open .build/debug/MEditor.app

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build/debug"
APP_NAME="MEditor"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "🔨 Creating $APP_NAME.app bundle..."

# Create bundle structure
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy Info.plist (with document type associations)
cp "$PROJECT_DIR/Sources/$APP_NAME/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Copy resources (icons, JS libraries, etc.)
cp -R "$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle/Resources/" "$APP_BUNDLE/Contents/Resources/"

# Validate Info.plist
plutil -lint "$APP_BUNDLE/Contents/Info.plist" > /dev/null

# Ad-hoc sign the bundle (required for macOS to launch from .app)
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null

echo "✅ $APP_NAME.app created at:"
echo "   $APP_BUNDLE"
echo ""
echo "🚀 Run: open \"$APP_BUNDLE\""
