# 「检查更新」测试方案

配套需求：`docs/todo/check-for-updates-plan.md`

## A. 单元测试（与现有 `Tests/main.swift` 同一风格）

现有工程没有 XCTest target，测试是 `precondition` 脚本。延续这个方式：

```bash
cd smart-close
swiftc SmartClose/UpdateChecker.swift Tests/update-checker-tests.swift \
  -o build/Tests/update-checker-tests
./build/Tests/update-checker-tests   # 全部通过时无输出、退出码 0
```

> 前提：`UpdateChecker.swift` 只依赖 Foundation，且把「取数据」抽象成可注入的 `URLSession`（测试用 `URLProtocol` 桩或直接测纯解析函数）。

### A1 版本解析与比较（`AppVersion`）

| 用例 | 输入 | 期望 |
|---|---|---|
| 三段解析 | `1.2.3` | `== (1,2,3)` |
| 带 v 前缀 | `v1.2.3` | `== (1,2,3)` |
| 数值比较（不是字典序） | `1.2.10` vs `1.2.9` | 后者更小 |
| 主版本优先 | `2.0.0` vs `1.99.99` | 前者更大 |
| 相等 | `1.2.3` vs `v1.2.3` | 相等 |
| 非法：两段 | `1.2` | `nil` |
| 非法：预发布 | `1.3.0-rc1` | `nil`（一期忽略） |
| 非法：非数字 | `v1.2.x` | `nil` |
| 非法：空串 | `` | `nil` |
| 前导零 | `v01.02.003` | `(1,2,3)`（允许） |

### A2 Release JSON 解析

内联 fixture（不依赖网络/bundle）：

```json
{
  "tag_name": "v1.3.0",
  "html_url": "https://github.com/yinzhenyu-su/mac-scripts/releases/tag/v1.3.0",
  "body": "修复若干问题",
  "published_at": "2026-10-20T10:00:00Z",
  "prerelease": false,
  "draft": false,
  "assets": [
    {"name": "SmartClose-v1.3.0.dmg",
     "browser_download_url": "https://github.com/yinzhenyu-su/mac-scripts/releases/download/v1.3.0/SmartClose-v1.3.0.dmg",
     "size": 123456, "content_type": "application/octet-stream"}
  ]
}
```

| 用例 | 期望 |
|---|---|
| 正常解析 | `tagName == "v1.3.0"`，`assets.count == 1`，解析版本 == (1,3,0) |
| dmg 选择 | 下载 URL 命中 `.dmg` 资产（忽略 `.zip`、`.sig`） |
| 无 dmg 资产 | `downloadURL == htmlURL`（回退） |
| `prerelease: true` | 结果按「不可比较/忽略」处理，不提示更新 |
| `draft: true` | 同上 |
| 缺字段（无 body / published_at） | 解析成功，可选字段为 nil |
| 非法 JSON | 抛 `.badResponse` |
| tag 非法（`nightly`） | `.invalidTag`，不崩 |

### A3 决策逻辑（纯函数）

抽一个 `UpdateChecker.decide(current:latestTag:release:) -> UpdateCheckResult` 便于测：

| 当前版本 | 远端 tag | 期望 |
|---|---|---|
| 1.2.3 | v1.2.3 | `.upToDate` |
| 1.2.3 | v1.2.4 | `.updateAvailable` |
| 1.2.3 | v1.3.0 | `.updateAvailable` |
| 1.3.0（开发版） | v1.2.3 | `.upToDate`（不提示降级） |
| 1.2.3 | v2.0.0 | `.updateAvailable` |

### A4 跳过与节流（逻辑层，注入 `UserDefaults` suite 与「现在」时间）

| 场景 | 期望 |
|---|---|
| `lastSkippedVersion == 1.3.0`，远端 1.3.0，自动检查 | 不提示（`.upToDate` 或静默） |
| 同上，手动检查 | 仍然 `.updateAvailable` |
| 远端 1.4.0 大于被跳过版本 | 重新提示 |
| `lastCheckAt` 距今 1h，自动检查 | 不发请求 |
| `lastCheckAt` 距今 25h，自动检查 | 发请求 |
| `autoCheckUpdates == false` | 自动检查不发请求；手动检查照常 |

## B. 手动测试矩阵（真机）

| # | 场景 | 步骤 | 期望 |
|---|---|---|---|
| B1 | 已是最新 | 当前版本 = 最新 release，点「检查更新」 | `已是最新版本`，无报错 |
| B2 | 有新版本 | 用一个低于最新版的本地构建（临时改 `MARKETING_VERSION`） | 显示 `发现新版本 x.y.z` + 两个按钮 |
| B3 | 下载按钮 | 点「下载」 | 浏览器打开 DMG 直链（不是 HTML 页面） |
| B4 | 更新说明 | 点「更新说明」 | 浏览器打开该 release 页面 |
| B5 | 断网 | 关闭 Wi-Fi，点检查 | ≤10s 显示 `无法连接更新服务器`，按钮恢复可点 |
| B6 | 连点 | 快速点 5 次 | 只发一次请求（Charles/日志确认） |
| B7 | 限流/异常 | 用 Charles 把响应改为 403 | 显示 `请求过于频繁，请稍后再试` |
| B8 | 无 release | 把仓库 API 改指向无 release 的仓库（或用桩） | 显示 `暂无发布版本` |
| B9 | 跳过 | 点「跳过此版本」后重启 App，等待自动检查 | 不再提示该版本 |
| B10 | 跳过≠永久 | 跳过 1.3.0 后发布 1.4.0 | 重新提示 |
| B11 | 关闭自动检查 | 取消勾选，重启 App | 启动 15s 后**无任何网络请求**（`nettop -p 智能退出` 或代理日志） |
| B12 | 布局 | 440×460 窗口，结果文案较长（如 `检查失败：无法连接更新服务器`） | 不裁切、不撑破窗口、按钮不换行错位 |
| B13 | 系统代理 | 开启 HTTP 代理后检查 | 走系统代理（`URLSession.shared` 默认行为），失败时同上 |

## C. 回归检查

| 项 | 方法 |
|---|---|
| 现有规则测试 | `swiftc SmartClose/RuleStore.swift Tests/main.swift ... && ./build/Tests/smart-close-rules-test` |
| 构建 | `xcodebuild -project SmartClose.xcodeproj -scheme SmartClose -configuration Release build` |
| 签名/公证 | CI 打 tag 跑一遍（`spctl` / `stapler validate` 由 workflow 校验） |
| 启动无网络 | 关闭自动检查时用 `nettop` 观察 60s，无 `api.github.com` 连接 |
| 关于页其他内容 | 图标、致谢、仓库链接、版本号仍正常 |

## D. 验收清单

- [ ] A1–A4 全绿（`build/Tests/update-checker-tests` 退出码 0）
- [ ] B1–B13 全通过，截图留档（关于页「有更新」状态）
- [ ] C 项回归无异常
- [ ] 无新增第三方依赖、无新增 entitlement
- [ ] README 补充了「检查更新」的行为与隐私说明
