#!/bin/bash
# bundle.sh — Create MEditor.app bundle (Universal: arm64 + x86_64)
# Usage: ./scripts/bundle.sh [debug|release]
#   default: debug
# Then: open .build/<config>/MEditor.app
#
# 双架构说明：swift build 默认只编 host 架构，打出来的包在另一种
# 架构的 Mac 上只能靠 Rosetta。这里显式编译 arm64 + x86_64 两份，
# 用 lipo 合成 Universal binary；资源包两份一致，取 x86_64 侧的即可。

set -euo pipefail

CONFIG="${1:-debug}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build/$CONFIG"
APP_NAME="MEditor"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
ARCHES=(arm64 x86_64)

echo "🔨 Building $APP_NAME ($CONFIG) for: ${ARCHES[*]}..."

BINARIES=()
RESOURCE_DIR=""
for ARCH in "${ARCHES[@]}"; do
  swift build -c "$CONFIG" --arch "$ARCH" --package-path "$PROJECT_DIR"
  TRIPLE_DIR="$PROJECT_DIR/.build/${ARCH}-apple-macosx/$CONFIG"
  BINARIES+=("$TRIPLE_DIR/$APP_NAME")
  # 资源 bundle 各架构内容一致，记录第一份即可
  if [ -z "$RESOURCE_DIR" ] && [ -d "$TRIPLE_DIR/${APP_NAME}_${APP_NAME}.bundle/Resources" ]; then
    RESOURCE_DIR="$TRIPLE_DIR/${APP_NAME}_${APP_NAME}.bundle/Resources"
  fi
done

echo "📦 Creating $APP_NAME.app bundle ($CONFIG, universal)..."

# Create bundle structure
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Lipo both architectures into a universal binary
lipo -create "${BINARIES[@]}" -output "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy Info.plist (with document type associations)
cp "$PROJECT_DIR/Sources/$APP_NAME/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Inject version from the single source of truth for the macOS app: <repo>/VERSION.
# (iOS takes its version from MARKETING_VERSION/CURRENT_PROJECT_VERSION in
# Mobile/MEditorMobile.xcodeproj instead.) To bump the version, edit VERSION —
# do NOT edit the version keys in Sources/MEditor/Info.plist.
VERSION_FILE="$PROJECT_DIR/VERSION"
if [ ! -s "$VERSION_FILE" ]; then
  echo "error: version file not found or empty: $VERSION_FILE" >&2
  exit 1
fi
APP_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_VERSION" "$APP_BUNDLE/Contents/Info.plist"

# Copy resources (icons, JS libraries, etc.)
if [ -n "$RESOURCE_DIR" ]; then
  cp -R "$RESOURCE_DIR/" "$APP_BUNDLE/Contents/Resources/"
fi

# Validate Info.plist
plutil -lint "$APP_BUNDLE/Contents/Info.plist" > /dev/null

# Ad-hoc sign the bundle (required for macOS to launch from .app)
if command -v codesign &>/dev/null; then
  codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null
fi

echo "✅ $APP_NAME.app created at:"
echo "   $APP_BUNDLE"
lipo -info "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
echo ""
echo "🚀 Run: open \"$APP_BUNDLE\""
