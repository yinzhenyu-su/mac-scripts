#!/bin/bash
# 在 Mac 上运行：把 Developer ID 证书与 ASC API Key 写入 GitHub Actions Secrets。
#
#   ./scripts/setup-signing-secrets.sh DeveloperID.p12 AuthKey_XXXXXXXXXX.p8 \
#       --issuer xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx [--repo owner/name]
#
# 特点：
#   - 私钥只在内存/临时钥匙串里出现，磁盘上不留 base64 文件
#   - 会先用临时钥匙串验证 p12 是不是 Developer ID Application（顺带校验密码）
#   - 从证书 CN 自动解析 SIGN_IDENTITY 与 TEAM_ID，避免手抄出错
set -euo pipefail

REPO="${GH_REPO:-}"
ISSUER="${ASC_ISSUER_ID:-}"
CERT_PATH=""
KEY_PATH=""

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
}

fail() { echo "✗ $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)   REPO="${2:-}"; shift 2 ;;
    --issuer) ISSUER="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --*) echo "未知参数：$1" >&2; usage; exit 1 ;;
    *)
      if [[ -z "$CERT_PATH" ]]; then CERT_PATH="$1"
      elif [[ -z "$KEY_PATH" ]]; then KEY_PATH="$1"
      else fail "多余参数：$1"
      fi
      shift ;;
  esac
done

echo "== 预检 =="
command -v gh >/dev/null 2>&1 || fail "需要 gh CLI：brew install gh"
gh auth status >/dev/null 2>&1 || fail "先执行 gh auth login"
command -v openssl >/dev/null 2>&1 || fail "缺少 openssl"
command -v security >/dev/null 2>&1 || fail "此脚本只能在 macOS 上运行"

[[ -n "$CERT_PATH" && -f "$CERT_PATH" ]] || fail "找不到证书文件：${CERT_PATH:-<未提供>}"
[[ -n "$KEY_PATH" && -f "$KEY_PATH" ]] || fail "找不到 API Key 文件：${KEY_PATH:-<未提供>}"

if [[ -z "$REPO" ]]; then
  REMOTE="$(git -C "$(dirname "$0")/.." remote get-url origin 2>/dev/null || true)"
  REPO="$(printf '%s' "$REMOTE" | sed -E 's#^(git@github\.com:|https://github\.com/)##; s#\.git$##')"
  [[ "$REPO" =~ ^[^/]+/[^/]+$ ]] || fail "无法识别仓库，请用 --repo owner/name 指定"
fi
echo "  仓库：$REPO"

if [[ -z "${MACOS_CERT_PASSWORD:-}" ]]; then
  read -r -s -p "  .p12 导出密码：" MACOS_CERT_PASSWORD
  echo
fi
[[ -n "$MACOS_CERT_PASSWORD" ]] || fail "p12 密码不能为空"

if [[ -z "$ISSUER" ]]; then
  read -r -p "  App Store Connect Issuer ID（UUID）：" ISSUER
fi
[[ "$ISSUER" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] \
  || fail "Issuer ID 格式不对（应为 8-4-4-4-12 的 UUID）"

KEY_BASENAME="$(basename "$KEY_PATH")"
[[ "$KEY_BASENAME" =~ ^AuthKey_([A-Z0-9]{10})\.p8$ ]] \
  || fail "API Key 文件名应为 AuthKey_<10位KeyID>.p8，实际：$KEY_BASENAME"
KEY_ID="${BASH_REMATCH[1]}"

grep -q "BEGIN PRIVATE KEY" "$KEY_PATH" || fail "$KEY_PATH 不像 .p8 私钥文件"

echo "== 验证证书 =="
TMP_DIR="$(mktemp -d)"
KC_PASS="$(openssl rand -hex 16)"
KC="$TMP_DIR/setup.keychain-db"
cleanup() {
  security delete-keychain "$KC" 2>/dev/null || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

security create-keychain -p "$KC_PASS" "$KC"
security set-keychain-settings -lut 600 "$KC"
security unlock-keychain -p "$KC_PASS" "$KC"
if ! security import "$CERT_PATH" -k "$KC" -P "$MACOS_CERT_PASSWORD" -T /usr/bin/codesign >/dev/null 2>&1; then
  fail "导入 .p12 失败：密码错误、文件损坏，或者里面只有证书没有私钥"
fi
security set-key-partition-list -S apple-tool:,apple: -s -k "$KC_PASS" "$KC" >/dev/null

IDENTITIES="$(security find-identity -v -p codesigning "$KC" | sed -n 's/^.*"\(.*\)"[[:space:]]*$/\1/p')"
SIGN_IDENTITY="$(printf '%s\n' "$IDENTITIES" | grep -m1 '^Developer ID Application: ' || true)"
if [[ -z "$SIGN_IDENTITY" ]]; then
  echo "  这个 p12 里的身份：" >&2
  printf '%s\n' "$IDENTITIES" | sed 's/^/    /' >&2
  fail "没有 Developer ID Application 证书（Developer ID Installer / Apple Distribution 不能签 .app）"
fi
TEAM_ID="$(printf '%s' "$SIGN_IDENTITY" | sed -nE 's/.*\(([A-Z0-9]{10})\)$/\1/p')"
[[ -n "$TEAM_ID" ]] || fail "无法从证书名解析 TEAM_ID：$SIGN_IDENTITY"

echo "  身份：$SIGN_IDENTITY"
echo "  Team：$TEAM_ID"
if printf '%s\n' "$IDENTITIES" | grep -q '^Developer ID Installer: '; then
  echo "  （另含 Developer ID Installer，本流程不使用）"
fi

echo "== 写入 GitHub Secrets =="
set_secret_value() {
  local name="$1" value="$2"
  printf '%s' "$value" | gh secret set "$name" --repo "$REPO" >/dev/null
  echo "  ✔ $name"
}
set_secret_stream() {
  local name="$1"
  gh secret set "$name" --repo "$REPO" >/dev/null
  echo "  ✔ $name"
}

openssl base64 -A -in "$CERT_PATH" | set_secret_stream MACOS_CERT_P12
set_secret_value MACOS_CERT_PASSWORD "$MACOS_CERT_PASSWORD"
set_secret_value KEYCHAIN_PASSWORD "$(openssl rand -hex 16)"
set_secret_value SIGN_IDENTITY "$SIGN_IDENTITY"
set_secret_value TEAM_ID "$TEAM_ID"
openssl base64 -A -in "$KEY_PATH" | set_secret_stream ASC_KEY_P8
set_secret_value ASC_KEY_ID "$KEY_ID"
set_secret_value ASC_ISSUER_ID "$ISSUER"

echo "== 校验 =="
LISTED="$(gh secret list --repo "$REPO" 2>/dev/null | awk '{print $1}')"
MISSING=()
for name in MACOS_CERT_P12 MACOS_CERT_PASSWORD KEYCHAIN_PASSWORD SIGN_IDENTITY \
            TEAM_ID ASC_KEY_P8 ASC_KEY_ID ASC_ISSUER_ID; do
  printf '%s\n' "$LISTED" | grep -qx "$name" || MISSING+=("$name")
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
  fail "以下 secret 未写入：${MISSING[*]}"
fi
echo "  8 个 secret 全部就位"

cat <<'EOF'

下一步：
  1) 打个测试 tag（必须是 vX.Y.Z 形式）：
       git tag v1.2.3 && git push origin v1.2.3
  2) 到 Actions 看 "Release DMG" 是否全绿
  3) 下载 Release 里的 DMG，不做任何 xattr 操作，直接双击

证书文件与 .p8 请自己留着（续期/换机器还要用）；本脚本不会在磁盘上留 base64。
EOF
