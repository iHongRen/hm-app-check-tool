#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------
# hm-app-check-tool DMG 打包脚本
# 输出：./build/hm-app-check-tool-<version>.dmg
# ---------------------------------------------------------------

readonly ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
readonly PROJECT_DIR="$ROOT_DIR/hm-app-check-tool"
readonly BUILD_DIR="$ROOT_DIR/build"
readonly APP_NAME="hm-app-check-tool"

cd "$ROOT_DIR"

# 读取版本号
VERSION=$(awk '/MARKETING_VERSION/ {gsub(/;/,""); print $NF; exit}' "$PROJECT_DIR/hm-app-check-tool.xcodeproj/project.pbxproj")
readonly VERSION="${VERSION:-1.0}"
readonly DMG_NAME="${APP_NAME}-${VERSION}.dmg"
readonly DMG_STAGING="$BUILD_DIR/dmg_staging"
readonly DERIVED_DATA="$BUILD_DIR/.derivedData"

echo "=== 清理并创建构建目录 ==="
rm -rf "$BUILD_DIR"
mkdir -p "$DMG_STAGING"

echo "=== 构建 .app (Release) ==="
xcodebuild \
    -project "$PROJECT_DIR/hm-app-check-tool.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    build

echo "=== 移除隔离属性 ==="
APP_PATH=$(echo "$DERIVED_DATA/Build/Products/Release/"*.app | head -1)
xattr -cr "$APP_PATH"

echo "=== 制作 DMG ==="
cp -R "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$BUILD_DIR/$DMG_NAME"

echo "=== 清理中间文件 ==="
rm -rf "$DMG_STAGING" "$DERIVED_DATA"

echo "=== 完成 ==="
echo "DMG: $BUILD_DIR/$DMG_NAME"
ls -lh "$BUILD_DIR/$DMG_NAME"