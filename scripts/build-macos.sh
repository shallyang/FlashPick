#!/bin/bash
# 闪拾 FlashPick · macOS 一键构建并安装到 /Applications
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> flutter pub get"
flutter pub get

echo "==> flutter analyze"
flutter analyze

echo "==> flutter build macos --release"
flutter build macos --release

APP="build/macos/Build/Products/Release/flashpick.app"

echo "==> 安装到 /Applications/FlashPick.app"
# 若旧版在运行先退出
pkill -x flashpick 2>/dev/null || true
sleep 1
rm -rf "/Applications/FlashPick.app"
cp -R "$APP" "/Applications/FlashPick.app"

echo "==> 完成：open /Applications/FlashPick.app"
echo "    注意：新编译的 ad-hoc 签名会被视为新应用，首次热键抓取需重新授予辅助功能权限。"
