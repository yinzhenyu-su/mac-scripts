#!/bin/bash
# 发版一条龙：生成更新日志草稿 → 编辑 → 确认 → 提交 → 打 tag → 推送
#
#   ./scripts/release.sh v1.3.5            # 交互式（默认）
#   ./scripts/release.sh v1.3.5 --no-edit  # 不改草稿，直接确认
#   ./scripts/release.sh v1.3.5 --dry-run  # 只生成草稿并预览，不提交/不推送
#
# 推送 tag 前会被 .githooks/pre-push 检查：没有 release-notes/<tag>.md 就拒绝推送。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

TAG=""
NO_EDIT=0
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --no-edit) NO_EDIT=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    v*) TAG="$arg" ;;
    *) echo "未知参数：$arg" >&2; exit 1 ;;
  esac
done

die() { echo "✗ $*" >&2; exit 1; }

if [[ ! "$TAG" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  die "用法：$0 vX.Y.Z [--no-edit] [--dry-run]"
fi

command -v git >/dev/null || die "缺少 git"
[[ "$(git rev-parse --abbrev-ref HEAD)" == "master" ]] || die "请在 master 分支上发版（当前：$(git rev-parse --abbrev-ref HEAD)）"
[[ -z "$(git status --porcelain)" ]] || die "工作区不干净，先提交或 stash 再发版"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && die "tag $TAG 已存在"

PREV="$(git describe --tags --abbrev=0 HEAD 2>/dev/null || true)"
NOTES="release-notes/${TAG}.md"

echo "== 发版检查 =="
echo "  版本：$TAG"
echo "  上一个版本：${PREV:-（无）}"
if [[ -n "$PREV" ]]; then
  COMMITS="$(git log --no-merges --pretty="- %s" "${PREV}..HEAD" | grep -v "chore(appcast)" || true)"
  COUNT="$(printf '%s\n' "$COMMITS" | grep -c . || true)"
  echo "  待发布提交：${COUNT:-0} 个"
else
  COMMITS="$(git log --no-merges -10 --pretty="- %s" | grep -v "chore(appcast)" || true)"
  COUNT="$(printf '%s\n' "$COMMITS" | grep -c . || true)"
  echo "  待发布提交：${COUNT:-0} 个（无历史 tag，取最近 10 条）"
fi
[[ "${COUNT:-0}" -gt 0 ]] || die "自 ${PREV:-首个版本} 以来没有新提交，没东西可发"

if [[ -f "$NOTES" ]]; then
  echo "  更新日志：${NOTES}（已存在，保留你的内容）"
else
  mkdir -p release-notes
  {
    echo "## 更新内容"
    echo
    if [[ -n "$PREV" ]]; then
      echo "自 ${PREV} 以来的变更："
      echo
    fi
    printf '%s\n' "$COMMITS"
    echo
    echo "## 升级说明"
    echo
    echo "- 直接点「安装更新」即可，无需手动操作"
  } > "$NOTES"
  echo "  更新日志：${NOTES}（已根据 git log 生成草稿）"
fi

if [[ "$NO_EDIT" -eq 0 && "$DRY_RUN" -eq 0 && -t 0 ]]; then
  echo
  echo "── 编辑 ${NOTES}（保存退出后继续，留空则取消）──────────────────"
  "${EDITOR:-vim}" "$NOTES"
fi

echo
echo "── 即将随 $TAG 发布的更新日志 ─────────────────────────────"
cat "$NOTES"
echo "──────────────────────────────────────────────────────────"
echo

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "（--dry-run：草稿已生成，未提交、未打 tag）"
  exit 0
fi

read -r -p "确认提交并推送 ${TAG}？[y/N] " ANSWER
[[ "$ANSWER" =~ ^[Yy]$ ]] || { echo "已取消（草稿保留在 ${NOTES}）"; exit 1; }

git add "$NOTES"
if git diff --staged --quiet; then
  echo "更新日志无变化，跳过提交"
else
  git commit -m "docs(release): ${TAG} 更新日志"
fi

git tag "$TAG"
echo "推送 master 与 tag $TAG …"
git push origin master
git push origin "$TAG"

echo
echo "✔ 已推送 ${TAG}，CI 会自动构建、公证、部署到 app.bgm.fun"
echo "  进度：https://github.com/$(git remote get-url origin | sed -E 's#.*github\.com[:/]##; s#\.git$##')/actions"
