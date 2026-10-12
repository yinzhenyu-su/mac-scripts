#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP_PATH="$BUILD_DIR/Build/Products/Release/智能退出.app"
DMG_PATH="$BUILD_DIR/智能退出.dmg"

xcodebuild \
  -project "$SCRIPT_DIR/SmartClose.xcodeproj" \
  -scheme SmartClose \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "构建完成后未找到应用：$APP_PATH" >&2
  exit 1
fi

STAGING_DIR="$(mktemp -d "$BUILD_DIR/dmg-staging.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT

ditto "$APP_PATH" "$STAGING_DIR/智能退出.app"
ln -s /Applications "$STAGING_DIR/Applications"

# 清理由下载或复制过程带入的隔离属性；只处理 DMG 暂存副本。
xattr -rd com.apple.quarantine "$STAGING_DIR/智能退出.app" 2>/dev/null || true

hdiutil create \
  -volname "智能退出" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "DMG 已生成：$DMG_PATH"
