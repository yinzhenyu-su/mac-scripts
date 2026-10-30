# 「检查更新」测试方案（v2 · Sparkle）

配套需求：`docs/todo/check-for-updates-plan.md`

Sparkle 承担了下载/校验/替换，能自测的部分集中在 **appcast 生成** 与 **发布链路**，UI 行为靠手动矩阵 + 一次真实升级验证。

## A. 自动化测试

### A1 `scripts/make-appcast.py` 单测（Python，可在 CI 跑）

用 `unittest`（不引第三方库）：

| 用例 | 输入 | 期望 |
|---|---|---|
| 生成单条 | release JSON + dmg 签名 + 版本号 | `item` 含 `sparkle:version`、`shortVersionString`、`enclosure url`、`edSignature`、`length` |
| 合并历史 | 已有 appcast（含 1.3.0/1.3.1）+ 新 1.3.2 | 三条都在，按 `sparkle:version` 降序 |
| 重复发布同版本 | 已有 1.3.2，再发布 1.3.2 | 替换旧条目而不是追加 |
| 截断 | 已有 12 条 | 只保留最新 10 条 |
| XML 转义 | body 含 `<b>`、`&`、`]]>` | 生成 XML 可被 `xml.etree` 解析，内容不丢 |
| 缺 dmg 资产 | release 里没有 `.dmg` | 该版本跳过并在日志里告警（不生成坏条目） |
| 非法版本号 | tag 不是 `vX.Y.Z` | 跳过并告警 |

运行：

```bash
python3 -m unittest discover -s scripts -p 'test_*.py' -v
```

### A2 签名校验（CI 内，macOS）

```bash
sign_update --verify <dmg> -s "<appcast 里的 edSignature>" -l <length>
```

失败 → workflow 失败，不发版。

### A3 appcast 结构自检（CI 内）

```bash
python3 scripts/check-appcast.py appcast.xml --expect-version 1.3.2
```

校验：XML 合法、最新条目版本正确、`enclosure url` 可 HEAD 200、`sparkle:version` 比上一版大。

## B. 手动测试矩阵（真机）

| # | 场景 | 步骤 | 期望 |
|---|---|---|---|
| B1 | 无更新 | 当前版本 = 最新 appcast | 点「检查更新」→ Sparkle 提示「已是最新版本」 |
| B2 | 发现更新 | 用低版本构建（临时改 `MARKETING_VERSION`） | Sparkle 窗口出现，显示版本号、更新日志、安装/稍后/跳过 |
| B3 | 更新日志 | 同上 | 日志内容与 GitHub Release body 一致，可滚动 |
| B4 | 安装 | 点「安装更新」 | 下载进度可见 → 自动替换 → App 重启 |
| B5 | 版本生效 | 重启后打开关于页 | 版本号为新版，build 号为新 build |
| B6 | 跳过此版本 | 点「跳过此版本」，再点检查 | 不再提示该版本 |
| B7 | 更高版本 | 发布更高版本后 | 重新提示 |
| B8 | 断网 | 关闭网络后检查 | 可关闭的错误提示，App 正常 |
| B9 | 从 DMG 直接运行 | 挂载 DMG 直接运行 App 再检查 | 提示先移到「应用程序」 |
| B10 | /Applications 无写权限 | 用只读用户测试 | Sparkle 触发系统授权，取消后 App 不受影响 |
| B11 | 关闭自动检查 | 取消勾选 → 重启 → 观察 60s | 无 appcast 请求（`nettop -p 智能退出`） |
| B12 | 自动检查开启 | 勾选 → 重启 → 等待 | 有 appcast 请求，且仅在 24h 间隔内一次 |
| B13 | 布局 | 440×520 窗口，勾选/未勾选各看一遍 | 不裁切、不跳动，底部一行左右对齐 |
| B14 | 更新失败回滚 | 用坏签名 appcast（测试环境） | Sparkle 报签名校验失败，App 保持原版本可正常用 |

## C. 回归检查

| 项 | 方法 |
|---|---|
| Sparkle 嵌入签名 | `codesign -dv --verbose=4 智能退出.app/Contents/Frameworks/Sparkle.framework` 显示 Developer ID + runtime |
| 公证 | CI 的 `spctl -a -vvv` / `stapler validate` 仍全绿 |
| 规则测试 | `swiftc SmartClose/RuleStore.swift Tests/main.swift …` |
| 启动 | 关自动检查时启动 60s 内无网络连接 |
| 关于页其他内容 | 图标、致谢、仓库链接、版本号正常 |

## D. 发布链路验收（最关键的一条）

模拟真实用户：**用上一个已发布版本（如 1.3.1）安装后**，发布 1.3.2：

1. CI 全绿，`appcast.xml` 已提交且包含 1.3.2
2. 打开 1.3.1 的关于页 → 检查更新 → 出现 1.3.2
3. 安装 → 重启后是 1.3.2
4. 检查 1.3.1 的旧安装包仍可正常下载

## E. 验收清单

- [ ] A1 单测全绿
- [ ] A2/A3 在 CI 通过（含一次真实 tag 发布）
- [ ] B1–B14 全通过
- [ ] C 回归无异常
- [ ] D 真实升级链路走通（旧版 → 新版）
- [ ] 文档：`docs/ci-signing.md` 已补 Sparkle 密钥与 appcast 说明
