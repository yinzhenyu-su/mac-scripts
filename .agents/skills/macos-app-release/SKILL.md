---
name: macos-app-release
description: Release a new version of the NeatQuit macOS app in mac-scripts end to end. Use when the user asks to release/发布 NeatQuit X.Y.Z, cut a tag, publish a DMG, update appcast, or recover a failed release workflow.
---

# NeatQuit macOS 发版

在 `~/Code/github/mac-scripts` 中完成：更新日志 → tag → CI 构建/签名/公证 → GitHub Release → app.bgm.fun DMG 与 appcast。

## 关键事实

| 项 | 值 |
| --- | --- |
| 应用目录 | `neatquit/` |
| 工程 / scheme | `neatquit/NeatQuit.xcodeproj` / `NeatQuit` |
| 产物 | `neatquit/build/智能退出.app`、`neatquit/build/智能退出.dmg` |
| CI 分发名 | `NeatQuit-<tag>.dmg` |
| Bundle ID | `fun.bgm.neatquit` |
| 最低系统 | macOS 13 |
| 版本号 | 取自 tag（去掉 `v`） |
| 构建号 | GitHub Actions `run_number` |
| 更新源 | `https://app.bgm.fun/appcast.xml` |
| 主下载 | `https://app.bgm.fun/NeatQuit-vX.Y.Z.dmg` |
| 备用下载 | GitHub Release 同名资产 |

## 1. 发版前检查

```sh
cd ~/Code/github/mac-scripts
git branch --show-current          # 必须是 master
git status --short                 # 必须干净（release-notes 文件除外）
git tag --sort=-v:refname | head -3
```

确认：

- tag `vX.Y.Z` 不存在
- 工作区没有未提交改动
- 最近一次 CI `Build` 成功

```sh
gh run list --limit 3
```

## 2. 写更新日志

创建 `release-notes/vX.Y.Z.md`，用用户能理解的语言写：

```md
## 更新内容

- 面向用户的变化
- 不要罗列内部重构

## 升级说明

- 是否需要重新授权、重启或手动安装
- 是否有兼容性/数据迁移影响
```

Bundle ID 变更、最低系统提升、签名方式变化必须写进「升级说明」。Bundle ID 变更时明确：旧版本无法自动跨 ID 更新，需要手动覆盖安装一次。

不要用 release.sh 自动生成的 git log 草稿直接发版，除非变更很少且确认可读。

## 3. 打 tag 并发版

```sh
printf 'y\n' | ./scripts/release.sh vX.Y.Z --no-edit
```

该脚本会：

1. 校验分支、脏工作区、tag 是否已存在
2. 保留已存在的 `release-notes/vX.Y.Z.md`
3. 提交更新日志
4. 创建并推送 tag
5. 推送 master

推送 tag 后 GitHub Actions `Release DMG` 自动执行：构建 → Developer ID 签名 → 公证 → staple → 上传 GitHub Release → 生成 appcast → 部署到 `app.bgm.fun` → 把 appcast 提交回 master。

## 4. 监控 CI

```sh
gh run list --limit 3
gh run watch <run-id> --exit-status
```

关注步骤：`构建并签名公证`、`校验签名与公证`、`发布到 GitHub Release`、`生成 appcast`、`部署到 app.bgm.fun`、`提交 appcast 回 master`。

### FTP 超时（exit code 28）

`部署到 app.bgm.fun` 偶发 curl 超时。**不要重新打 tag**，直接重跑失败任务：

```sh
gh run rerun <run-id> --failed
```

重跑会重新构建并上传，appcast 与下载地址不会重复。

### 其他失败

- 签名失败：检查仓库 Secrets 中的 `SIGN_IDENTITY`、`TEAM_ID`、证书与钥匙串导入
- 公证失败：检查 `ASC_KEY_PATH` / `ASC_KEY_ID` / `ASC_ISSUER_ID`，以及 Sparkle 嵌套组件签名
- appcast 生成失败：检查 `SPARKLE_ED_PRIVATE_KEY`
- tag 已存在：不能覆盖发版，提升版本号重新走流程

## 5. 校验发布物

### GitHub Release

```sh
curl -fsSL https://api.github.com/repos/yinzhenyu-su/mac-scripts/releases/tags/vX.Y.Z \
  | python3 -c "import json,sys;d=json.load(sys.stdin);print(d['published_at']);[print(a['name'],a['size'],a.get('digest'),a['browser_download_url']) for a in d['assets']]"
```

应包含 `NeatQuit-vX.Y.Z.dmg`，大小与 digest 与官网一致。

### appcast

```sh
curl -s https://app.bgm.fun/appcast.xml | sed -n '1,25p'
```

确认最新条目：

- `<title>X.Y.Z</title>`
- `<sparkle:version>` 为本次构建号
- `<sparkle:minimumSystemVersion>13.0`
- `<enclosure url="https://app.bgm.fun/NeatQuit-vX.Y.Z.dmg">`
- `length` 与文件一致
- `sparkle:edSignature` 存在

### DMG 本体

```sh
curl -fsSL -o /tmp/NeatQuit-vX.Y.Z.dmg https://app.bgm.fun/NeatQuit-vX.Y.Z.dmg
shasum -a 256 /tmp/NeatQuit-vX.Y.Z.dmg
hdiutil attach -nobrowse -readonly -mountpoint /tmp/nq /tmp/NeatQuit-vX.Y.Z.dmg
APP="/tmp/nq/智能退出.app"
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$APP/Contents/Info.plist"
ls -d "$APP/Contents/Resources/en.lproj" "$APP/Contents/Resources/zh-Hans.lproj"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E "Authority|Notarization"
spctl -a -vvv -t install "$APP"
hdiutil detach /tmp/nq
```

应满足：版本/构建号正确、Bundle ID 为 `fun.bgm.neatquit`、最低 13.0、包含中英文资源、Developer ID 签名、公证已 staple、`spctl` accepted。

### 同步仓库

CI 会把新 appcast 提交回 master：

```sh
git pull --ff-only origin master
git log --oneline -3
```

## 6. 发布后

官网版本同步不在本仓库完成。使用 `bgm.fun` 仓库的 `neatquit-site-release` skill：更新 `data/release.json`、产品页、版本记录、截图、分享图并部署。

## 验收清单

- [ ] `release-notes/vX.Y.Z.md` 已写清用户变化与升级说明
- [ ] tag 已推送，CI `Release DMG` 全绿
- [ ] GitHub Release 有 `NeatQuit-vX.Y.Z.dmg`
- [ ] app.bgm.fun DMG 可下载，大小与 SHA-256 正确
- [ ] appcast 最新条目指向新版本，签名/长度正确
- [ ] DMG 内版本、构建号、Bundle ID、最低系统、签名、公证正确
- [ ] 中英文资源存在（若本版本包含本地化）
- [ ] 本地 master 已同步 CI 提交的 appcast
- [ ] 官网已通过 `neatquit-site-release` 更新
