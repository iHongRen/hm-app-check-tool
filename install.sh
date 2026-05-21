#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------
# hm-app-check-tool 一键安装脚本
# curl -fsSL https://raw.githubusercontent.com/iHongRen/hm-app-check-tool/main/install.sh | bash
# ---------------------------------------------------------------

readonly APP_NAME="hm-app-check-tool"
readonly REPO="iHongRen/hm-app-check-tool"
readonly TEMP_DIR="$(mktemp -d)"

cleanup() {
    echo "清理临时文件..."
    rm -rf "$TEMP_DIR"
    if mount | grep -q "$TEMP_DIR/mount"; then
        hdiutil detach "$TEMP_DIR/mount" 2>/dev/null || true
    fi
}
trap cleanup EXIT

echo "=== ${APP_NAME} 安装脚本 ==="

# 检查是否安装了旧版本
if [ -d "/Applications/${APP_NAME}.app" ]; then
    echo "已安装版本将被覆盖。"
    rm -rf "/Applications/${APP_NAME}.app"
fi

# 获取最新版本号
echo "获取最新版本信息..."
RELEASE_INFO=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest")
VERSION=$(echo "$RELEASE_INFO" | grep '"tag_name":' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')
readonly VERSION="${VERSION:-v1.0}"
echo "最新版本: ${VERSION}"

# 下载 DMG
DMG_URL="https://github.com/${REPO}/releases/latest/download/${APP_NAME}-${VERSION#v}.dmg"
echo "下载 ${DMG_URL} ..."
curl -fsSLO --output-dir "$TEMP_DIR" "$DMG_URL"
DMG_FILE=$(ls "$TEMP_DIR"/*.dmg | head -1)

if [ ! -f "$DMG_FILE" ]; then
    echo "错误: 下载失败，未找到 DMG 文件"
    exit 1
fi

# 挂载 DMG
echo "挂载 DMG..."
mkdir -p "$TEMP_DIR/mount"
hdiutil attach "$DMG_FILE" -mountpoint "$TEMP_DIR/mount" -nobrowse -quiet

# 拷贝到 /Applications
echo "安装到 /Applications..."
cp -R "$TEMP_DIR/mount/${APP_NAME}.app" /Applications/

# 卸载 DMG
echo "卸载 DMG..."
hdiutil detach "$TEMP_DIR/mount" -quiet

# 移除隔离属性
echo "移除隔离属性..."
xattr -dr com.apple.quarantine "/Applications/${APP_NAME}.app" 2>/dev/null || true

echo "=== 安装完成 ==="
echo "已安装到: /Applications/${APP_NAME}.app"
echo "首次打开时，若提示无法验证开发者，请在「系统设置 → 隐私与安全性」中允许。"