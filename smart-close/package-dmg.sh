#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP_PATH="$BUILD_DIR/Build/Products/Release/智能退出.app"
DMG_PATH="$BUILD_DIR/智能退出.dmg"

BUILD_ARGS=(
  -project "$SCRIPT_DIR/SmartClose.xcodeproj"
  -scheme SmartClose
  -configuration Release
  -derivedDataPath "$BUILD_DIR"
)

if [[ $# -ne 0 ]]; then
  if [[ $# -ne 2 || ! "$1" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ || ! "$2" =~ ^[1-9][0-9]*$ ]]; then
    echo "用法：$0 [v主版本.次版本.修订版本 正整数构建号]" >&2
    exit 1
  fi
  VERSION="${1#v}"
  BUILD_NUMBER="$2"
  BUILD_ARGS+=("MARKETING_VERSION=$VERSION" "CURRENT_PROJECT_VERSION=$BUILD_NUMBER")
fi

xcodebuild "${BUILD_ARGS[@]}" build

if [[ ! -d "$APP_PATH" ]]; then
  echo "构建完成后未找到应用：$APP_PATH" >&2
  exit 1
fi

if [[ $# -ne 0 ]]; then
  APP_PLIST="$APP_PATH/Contents/Info.plist"
  ACTUAL_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PLIST")"
  ACTUAL_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PLIST")"
  if [[ "$ACTUAL_VERSION" != "$VERSION" || "$ACTUAL_BUILD" != "$BUILD_NUMBER" ]]; then
    echo "应用版本校验失败：期望 $VERSION ($BUILD_NUMBER)，实际 $ACTUAL_VERSION ($ACTUAL_BUILD)" >&2
    exit 1
  fi
  echo "应用版本已校验：$ACTUAL_VERSION ($ACTUAL_BUILD)"
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
