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

# SwiftPM 链接 Sparkle.xcframework 时 rpath 指向构建目录（Vendor/ 或 .build/artifacts）——
# .app 里 dyld 找不到框架会启动即崩（Library not loaded: @rpath/Sparkle.framework）。
# 补一条 @executable_path/../Frameworks，指向 bundle 内嵌的框架。
RPATH="@executable_path/../Frameworks"
if ! otool -l "$APP_BUNDLE/Contents/MacOS/$APP_NAME" | grep -A1 LC_RPATH | grep -qF "$RPATH"; then
  install_name_tool -add_rpath "$RPATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
fi

# Copy Info.plist (with document type associations)
cp "$PROJECT_DIR/Sources/$APP_NAME/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Inject version from the single source of truth for the macOS app: <repo>/VERSION.
# (iOS takes its version from MARKETING_VERSION/CURRENT_PROJECT_VERSION in
# Mobile/MEditorMobile.xcodeproj instead.) To bump the version, edit VERSION —
# do NOT edit the version keys in Sources/MEditor/Info.plist.
# CI 发版时可用环境变量覆盖：MEDITOR_VERSION（= git tag 去 v）与
# MEDITOR_BUILD_NUMBER（= GITHUB_RUN_NUMBER，单调递增整型）——
# Sparkle 按 CFBundleVersion 比较新旧，老包（VERSION=1.1 时代）装的是
# "1.1"，若继续用点分版本比较会被判成「已是最新」，必须走整型 build 号。
VERSION_FILE="$PROJECT_DIR/VERSION"
if [ ! -s "$VERSION_FILE" ]; then
  echo "error: version file not found or empty: $VERSION_FILE" >&2
  exit 1
fi
APP_VERSION="${MEDITOR_VERSION:-$(tr -d '[:space:]' < "$VERSION_FILE")}"
BUILD_NUMBER="${MEDITOR_BUILD_NUMBER:-$APP_VERSION}"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist"

# Sparkle（自动更新）配置：feed 指向 workers.dev；公钥验更新包 EdDSA 签名。
# 公钥文件随仓库走（scripts/sparkle-ed-public-key.txt），私钥只在 CI secret。
/usr/libexec/PlistBuddy -c "Add :SUFeedURL string https://meditor-app.863129776.workers.dev/update/appcast.xml" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :SUFeedURL https://meditor-app.863129776.workers.dev/update/appcast.xml" "$APP_BUNDLE/Contents/Info.plist"
ED_PUBKEY_FILE="$PROJECT_DIR/scripts/sparkle-ed-public-key.txt"
if [ -s "$ED_PUBKEY_FILE" ]; then
  ED_PUBKEY="$(tr -d '[:space:]' < "$ED_PUBKEY_FILE")"
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $ED_PUBKEY" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $ED_PUBKEY" "$APP_BUNDLE/Contents/Info.plist"
else
  echo "warning: $ED_PUBKEY_FILE 缺失——本包无法校验更新签名，自动更新将不可用" >&2
fi

# Copy resources (icons, JS libraries, etc.)
if [ -n "$RESOURCE_DIR" ]; then
  cp -R "$RESOURCE_DIR/" "$APP_BUNDLE/Contents/Resources/"
fi

# Embed Sparkle.framework（自动更新）：SPM 只负责链接，不嵌包。
# 首选构建产物目录（.build/<triple>/<config>/Sparkle.framework）——Vendor 和
# 远程 binaryTarget 两种模式 SPM 都会把框架拷到可执行文件旁边，路径最稳定；
# Vendor/ 与 .build/artifacts 只作兜底（artifacts 的解包层级随 SPM 版本变，
# v0.6.6/0.6.7 的 CI 包就是因为 artifacts 路径没匹配上、只告警不报错，
# 打出缺框架的包，启动即崩）。
SPARKLE_FW=""
for ARCH in "${ARCHES[@]}"; do
  CAND="$PROJECT_DIR/.build/${ARCH}-apple-macosx/$CONFIG/Sparkle.framework"
  if [ -d "$CAND" ]; then
    SPARKLE_FW="$CAND"
    break
  fi
done
if [ -z "$SPARKLE_FW" ] && [ -d "$PROJECT_DIR/Vendor/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" ]; then
  SPARKLE_FW="$PROJECT_DIR/Vendor/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
fi
if [ -z "$SPARKLE_FW" ]; then
  SPARKLE_FW="$(find "$PROJECT_DIR/.build/artifacts" -type d -name "Sparkle.framework" \
    -path "*macos*" 2>/dev/null | head -1)"
fi
# 二进制无条件链接 Sparkle，缺框架的包必然启动即崩——直接失败，不许出货
if [ -z "$SPARKLE_FW" ]; then
  echo "error: 未找到 Sparkle.framework（构建产物 / Vendor / .build/artifacts 都没有）" >&2
  exit 1
fi
mkdir -p "$APP_BUNDLE/Contents/Frameworks"
cp -R "$SPARKLE_FW" "$APP_BUNDLE/Contents/Frameworks/"

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
