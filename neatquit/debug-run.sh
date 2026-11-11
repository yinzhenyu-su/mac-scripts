#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP_NAME="智能退出"
APP_PATH="$BUILD_DIR/Build/Products/Debug/$APP_NAME.app"
BUNDLE_ID="fun.bgm.neatquit"

FORCE_PRO=0
SHOW_LOGS=0
SIGN_WITH_RELEASE=0

usage() {
  cat <<EOF
用法：$0 [选项]

构建 Debug 版，退出正在运行的「${APP_NAME}」，然后启动刚构建的版本。

选项：
  --pro    启动前临时写入 license.legacyPro=1，绕过 Pro 门禁打开例外应用窗口
  --logs   启动后用 log stream 实时输出该 App 的 os_log（Ctrl-C 退出）
  --sign   用 Developer ID Application 证书签名 Debug 版，继承正式版的辅助权限授权
  -h, --help  显示本帮助

说明：
  - Debug 版与已安装版共用 Bundle ID 和偏好设置，脚本会先退出所有正在运行的实例。
  - 默认 Debug 版为 ad-hoc 签名，重新构建后需要重新授予辅助功能 / 输入监控权限。
  - --sign 使用与正式版相同的 Developer ID 证书；若正式版已授权，测试版通常可直接继承。
  - 调试完成后可执行：defaults delete $BUNDLE_ID license.legacyPro
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pro) FORCE_PRO=1 ;;
    --logs) SHOW_LOGS=1 ;;
    --sign) SIGN_WITH_RELEASE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知选项：$1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

BUILD_ARGS=(
  -project "$SCRIPT_DIR/NeatQuit.xcodeproj"
  -scheme NeatQuit
  -configuration Debug
  -derivedDataPath "$BUILD_DIR"
)

if [[ "$SIGN_WITH_RELEASE" == "1" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application/ { print $2; exit }')"
  if [[ -z "$IDENTITY" ]]; then
    echo "未找到 Developer ID Application 证书，请先在 Xcode 登录开发者账号" >&2
    exit 1
  fi
  TEAM_ID="$(printf '%s' "$IDENTITY" | sed -nE 's/.*\(([A-Z0-9]{10})\)$/\1/p')"
  if [[ -z "$TEAM_ID" ]]; then
    echo "无法从证书名称解析 Team ID：$IDENTITY" >&2
    exit 1
  fi
  echo "使用 Developer ID 签名：$IDENTITY"
  BUILD_ARGS+=(
    CODE_SIGN_STYLE=Manual
    "CODE_SIGN_IDENTITY=$IDENTITY"
    "DEVELOPMENT_TEAM=$TEAM_ID"
    ENABLE_HARDENED_RUNTIME=YES
  )
fi

echo "构建 Debug 版…"
xcodebuild "${BUILD_ARGS[@]}" build

if [[ ! -d "$APP_PATH" ]]; then
  echo "构建完成后未找到应用：$APP_PATH" >&2
  exit 1
fi

stop_running_instances() {
  local pids
  pids="$(pgrep -x "$APP_NAME" || true)"
  if [[ -z "$pids" ]]; then
    return
  fi

  echo "退出正在运行的 ${APP_NAME}（PID: $(echo "$pids" | tr '\n' ' ')）"
  # shellcheck disable=SC2086
  kill $pids 2>/dev/null || true

  for _ in {1..30}; do
    if ! pgrep -x "$APP_NAME" >/dev/null; then
      return 0
    fi
    sleep 0.1
  done

  echo "进程未响应，强制结束"
  pkill -9 -x "$APP_NAME" 2>/dev/null || true
}

stop_running_instances

if [[ "$FORCE_PRO" == "1" ]]; then
  echo "临时启用 Pro（license.legacyPro=1）"
  defaults write "$BUNDLE_ID" license.legacyPro -string 1
fi

LOG_PID=""
cleanup() {
  if [[ -n "$LOG_PID" ]]; then
    kill "$LOG_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if [[ "$SHOW_LOGS" == "1" ]]; then
  log stream --level debug --style compact \
    --predicate "subsystem == \"$BUNDLE_ID\"" &
  LOG_PID=$!
fi

echo "启动 $APP_PATH"
open "$APP_PATH"

if [[ -n "$LOG_PID" ]]; then
  echo "日志输出中，按 Ctrl-C 停止（App 会继续运行）"
  wait "$LOG_PID" || true
fi
