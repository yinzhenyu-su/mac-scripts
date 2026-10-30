#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP_NAME="智能退出"
APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"

# 可选签名 / 公证（由环境变量驱动；本地不设 = 保持原来的 ad-hoc 构建）
#   SIGN_IDENTITY  "Developer ID Application: 名字 (TEAMID)"
#   TEAM_ID        10 位团队 ID（仅用于写入构建设置，可留空）
#   NOTARIZE=1     公证并 staple（需要 ASC_KEY_PATH / ASC_KEY_ID / ASC_ISSUER_ID）
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
TEAM_ID="${TEAM_ID:-}"
NOTARIZE="${NOTARIZE:-0}"
# UNIVERSAL=1 → 同时编译 arm64 与 x86_64（分发用；本地开发不设，编译更快）
UNIVERSAL="${UNIVERSAL:-0}"

NOTARY_ARGS=()

BUILD_ARGS=(
  -project "$SCRIPT_DIR/SmartClose.xcodeproj"
  -scheme SmartClose
  -configuration Release
  -derivedDataPath "$BUILD_DIR"
)

if [[ "$UNIVERSAL" == "1" ]]; then
  BUILD_ARGS+=("ARCHS=arm64 x86_64" "ONLY_ACTIVE_ARCH=NO")
fi

if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "签名身份：$SIGN_IDENTITY"
  BUILD_ARGS+=(
    CODE_SIGN_STYLE=Manual
    "CODE_SIGN_IDENTITY=$SIGN_IDENTITY"
    ENABLE_HARDENED_RUNTIME=YES
    "OTHER_CODE_SIGN_FLAGS=--options runtime --timestamp"
  )
  if [[ -n "$TEAM_ID" ]]; then
    BUILD_ARGS+=("DEVELOPMENT_TEAM=$TEAM_ID")
  fi
fi

if [[ $# -ne 0 ]]; then
  if [[ $# -ne 2 || ! "$1" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ || ! "$2" =~ ^[1-9][0-9]*$ ]]; then
    echo "用法：$0 [v主版本.次版本.修订版本 正整数构建号]" >&2
    exit 1
  fi
  VERSION="${1#v}"
  BUILD_NUMBER="$2"
  BUILD_ARGS+=("MARKETING_VERSION=$VERSION" "CURRENT_PROJECT_VERSION=$BUILD_NUMBER")
fi

if [[ "$NOTARIZE" == "1" ]]; then
  for v in ASC_KEY_PATH ASC_KEY_ID ASC_ISSUER_ID; do
    if [[ -z "${!v:-}" ]]; then
      echo "公证需要环境变量 $v" >&2
      exit 1
    fi
  done
  NOTARY_ARGS=(--key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")
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

if [[ "$UNIVERSAL" == "1" ]]; then
  EXEC_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_PATH/Contents/Info.plist")"
  ARCHS_FOUND="$(lipo -archs "$APP_PATH/Contents/MacOS/$EXEC_NAME")"
  if [[ "$ARCHS_FOUND" != *arm64* || "$ARCHS_FOUND" != *x86_64* ]]; then
    echo "通用包构建失败：实际只有 $ARCHS_FOUND" >&2
    exit 1
  fi
  echo "架构：$ARCHS_FOUND"
fi

# ---- 签名与公证（.app）----
if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --verify --deep --strict --verbose=2 "$APP_PATH"
  echo "App 签名校验通过"

  if [[ "$NOTARIZE" == "1" ]]; then
    NOTARIZE_ZIP="$BUILD_DIR/notarize-app.zip"
    rm -f "$NOTARIZE_ZIP"
    ditto -c -k --keepParent "$APP_PATH" "$NOTARIZE_ZIP"
    echo "提交 App 公证（通常 1-5 分钟）…"
    xcrun notarytool submit "$NOTARIZE_ZIP" "${NOTARY_ARGS[@]}" --wait
    xcrun stapler staple "$APP_PATH"
    xcrun stapler validate "$APP_PATH"
    echo "App 已公证并 stapled"
  fi
fi

STAGING_DIR="$(mktemp -d "$BUILD_DIR/dmg-staging.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT

ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

# 清理由下载或复制过程带入的隔离属性；只处理 DMG 暂存副本。
xattr -rd com.apple.quarantine "$STAGING_DIR/$APP_NAME.app" 2>/dev/null || true

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

# ---- 签名与公证（DMG）----
if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH"
  echo "DMG 签名校验通过"

  if [[ "$NOTARIZE" == "1" ]]; then
    echo "提交 DMG 公证 …"
    xcrun notarytool submit "$DMG_PATH" "${NOTARY_ARGS[@]}" --wait
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
    echo "DMG 已公证并 stapled"
  fi
fi

echo "DMG 已生成：$DMG_PATH"
