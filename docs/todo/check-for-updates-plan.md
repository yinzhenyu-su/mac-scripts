# 关于页「检查更新」需求与方案（v2：Sparkle 自动下载安装）

> 状态：**待批准**（批准后再动代码）
> v2 变更：用户确认需要「下载并**更新**」——应用内完成下载、安装、重启，因此不再采用 v1 的「提示 + 跳转浏览器」，改用 **Sparkle 2**。

## 1. 背景与现状

| 项 | 现状 |
|---|---|
| 分发渠道 | GitHub Releases，tag `vX.Y.Z`，附件 `SmartClose-vX.Y.Z.dmg`（CI 已 Developer ID 签名 + 公证） |
| 版本号 | `Info.plist` ← `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`（CI 用 tag + run_number 注入） |
| 关于页 | `AboutView`（SwiftUI，440×460 NSWindow）：图标 / 名称 / `版本 x.y.z（build）` / 说明 / 致谢 / 仓库链接 |
| 设置窗口 | 只有「例外应用」列表，没有通用设置分区 |
| 沙盒 | `ENABLE_APP_SANDBOX = NO`（Sparkle 在非沙盒下工作最省事） |
| 测试方式 | `swiftc` + `precondition` 脚本，无 XCTest target |
| 仓库 | public → appcast 与 DMG 都可匿名下载 |

## 2. 目标与非目标

**目标**

1. 关于页能发现新版本，并在**应用内完成下载、安装、自动重启**。
2. 安装前能看到**更新日志**（版本、日期、变更条目）。
3. 「自动检查更新」可控（默认开），后台检查不打扰。

**不做**

- 增量（delta）更新：Sparkle 支持，但需要额外的 delta 打包与托管，一期不做
- Beta / 预发布通道
- 自研下载/替换逻辑（这正是 Sparkle 存在的理由）

## 3. 方案对比：为什么是 Sparkle 2

| 方案 | 结论 |
|---|---|
| 自研「下载 DMG → 挂载 → 替换 /Applications → 重启」 | ✗ 要自己处理签名+公证校验、translocated 启动、写权限、原子替换与回滚、下载中断、重启时机——每个都是线上事故源 |
| **Sparkle 2（SPM 依赖）** | ✓ 业界标准，内置 EdDSA 签名校验、下载、解压、替换、重启、「跳过此版本」、自动检查调度、更新日志窗口 |
| 只提示 + 打开浏览器（v1） | ✗ 用户明确要「下载并更新」 |

**必须接受的代价**

- 新增一个 SPM 依赖（Sparkle 2.x），体积 +1–2 MB
- 需要一对 **EdDSA 密钥**：公钥进 `Info.plist`，私钥只放 CI secret
- 每次发版 CI 要多产出并发布 `appcast.xml`；**appcast 没更新 = 用户收不到更新**

## 4. 功能需求

### FR-1 手动检查（P0）
- 版本号下方新增「检查更新」按钮（方案 A 布局）。
- 点击 → `SPUStandardUpdaterController.checkForUpdates(nil)`。
- 进行中的反馈由 Sparkle 自己提供；不重复触发（Sparkle 内部串行）。

### FR-2 下载与安装（P0）
- 发现新版：Sparkle 标准窗口展示版本号、更新日志、`安装更新` / `稍后` / `跳过此版本`。
- 点安装：下载 DMG → EdDSA 校验 → 解包 → 替换当前 App → 重启。
- 失败（网络/签名/权限）由 Sparkle 提示，我们不自研兜底。

### FR-3 更新日志（P0）
- 来源：`appcast.xml` 中该版本的 `<description>`（HTML，CI 从 Release body 生成）。
- 展示：Sparkle 更新窗口内的滚动区域（自带）。
- 附「在浏览器查看完整说明」→ Release 页面。

### FR-4 自动检查（P0，可关）
- 关于页底部一行 `[✓] 自动检查更新`，绑定 `updater.automaticallyChecksForUpdates`。
- 调度交给 Sparkle：`SUEnableAutomaticChecks=YES`、`SUScheduledCheckInterval=86400`。
- **不再自研 24h 节流逻辑**。

### FR-5 跳过此版本（P0，Sparkle 自带）
- 点了之后不再提示该版本；发更高版本仍提示。

### FR-6 错误与边界（P0）
- 无网络 / 下载失败 / 签名校验失败 / 替换失败 → Sparkle 标准 UI。
- appcast 404 或格式错误 → Sparkle 静默失败，不影响 App 使用。

### FR-7 布局（P0，方案 A）
- 窗口 440×460 → **440×520**。
- 版本号下方放「检查更新」；「已是最新」类状态文案交给 Sparkle，不在关于页重复。

```
[图标]
智能退出
版本 1.3.1（6）
[ 检查更新 ]
（说明三行）
──────
致谢名单
@hahahhqyou
──────
[✓] 自动检查更新            项目仓库 ↗
```

### FR-8 隐私（P0）
- 只请求 appcast URL，不带用户标识。
- 关闭自动检查后，只有点按钮才联网。

## 5. 技术方案

### 5.1 集成

- SPM：`https://github.com/sparkle-project/Sparkle`，major `2`
- Target `SmartClose` 增加 `Sparkle`
- `SmartCloseApp.swift` 持有控制器：

```swift
private let updaterController = SPUStandardUpdaterController(
    startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
```

### 5.2 Info.plist 新增

| Key | 值 |
|---|---|
| `SUFeedURL` | `https://raw.githubusercontent.com/yinzhenyu-su/mac-scripts/main/appcast.xml` |
| `SUPublicEDKey` | `generate_keys` 输出的公钥（base64，32 字节） |
| `SUEnableAutomaticChecks` | `YES` |
| `SUScheduledCheckInterval` | `86400` |
| `SUAllowsAutomaticUpdates` | `NO`（先让用户点安装，观察一阵再考虑放开） |

### 5.3 appcast.xml（CI 生成，提交回 main）

```xml
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>智能退出</title>
    <item>
      <title>1.3.2</title>
      <pubDate>…</pubDate>
      <sparkle:version>7</sparkle:version>
      <sparkle:shortVersionString>1.3.2</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <description><![CDATA[ <html>…Release body…</html> ]]></description>
      <enclosure url="https://github.com/yinzhenyu-su/mac-scripts/releases/download/v1.3.2/SmartClose-v1.3.2.dmg"
                 sparkle:edSignature="…" length="…" type="application/octet-stream"/>
    </item>
  </channel>
</rss>
```

- 保留最近 10 个版本即可，避免无限增长。
- `edSignature` 由 Sparkle 的 `sign_update` 用私钥对 DMG 生成。
- **`sparkle:version` 必须递增**（Sparkle 以它判断新旧，不是 `shortVersionString`）。

### 5.4 CI 改动（release.yml）

现有「签名 + 公证 + 校验」之后追加：

1. 把 `SPARKLE_ED_PRIVATE_KEY`（secret）写入临时文件
2. `sign_update <dmg>` → 得到签名
3. 运行 `scripts/make-appcast.py` → 合并生成 `appcast.xml`（保留历史条目）
4. **先**上传 DMG 到 Release
5. **再**提交 `appcast.xml` 回 `main`（bot commit）

顺序很重要：appcast 先于 DMG 发布会让用户拿到 404。

### 5.5 代码结构

| 文件 | 内容 |
|---|---|
| `SmartClose/SmartCloseApp.swift` | 创建 `SPUStandardUpdaterController`；AboutView 按钮/复选框；窗口 460 → 520 |
| `SmartClose/Info.plist` | 4 个 `SU*` key |
| `SmartClose.xcodeproj/project.pbxproj` | Sparkle SPM 依赖 |
| `scripts/make-appcast.py` | 生成/合并 appcast（纯 Python，可测） |
| `.github/workflows/release.yml` | 签名 + 生成 + 提交 appcast |
| `docs/ci-signing.md` | 补 Sparkle 密钥与 appcast 流程 |

## 6. 边界与风险

| 风险 | 处理 |
|---|---|
| EdDSA 私钥丢失 | 新版本无法签名 → 所有用户收不到更新。私钥备份到密码管理器，CI 只放 secret |
| appcast 未更新/提交失败 | 用户看不到新版 → 把「appcast 已包含当前版本」纳入发布步骤，失败即报警 |
| raw.githubusercontent 缓存约 5 分钟 | 可接受；介意就换 GitHub Pages |
| 从 DMG 直接运行（translocated） | Sparkle 会提示先拖进「应用程序」 |
| /Applications 无写权限 | Sparkle 走系统授权（弹管理员密码） |
| 自动安装过于激进 | `SUAllowsAutomaticUpdates=NO`，先观察 |
| 更新包未签名/未公证 | Sparkle 的 EdDSA 校验会失败 → CI 已保证签名+公证 |

## 7. 验收标准

1. 关于页出现「检查更新」按钮 + 「自动检查更新」复选框（默认勾选）。
2. 有新版时点按钮 → Sparkle 窗口出现，含版本号、更新日志、安装/稍后/跳过。
3. 点「安装更新」→ 下载 → 校验 → 替换 → 自动重启，重启后关于页版本号为新版。
4. 更新日志与 GitHub Release body 一致。
5. 取消勾选后重启 → 启动阶段无 appcast 请求。
6. 断网检查 → 可关闭的错误提示，App 正常使用。
7. 「跳过此版本」生效；更高版本重新提示。
8. `spctl` / 公证校验 + Sparkle XPC services 签名全绿。
9. `sign_update --verify` 能验证 appcast 里的签名。

## 8. 待决策

| 编号 | 问题 | 建议 |
|---|---|---|
| Q1 | appcast 托管：main + raw.githubusercontent / GitHub Pages / gh-pages 分支 | **main + raw**（最简单，5 分钟缓存可接受） |
| Q2 | 允许后台静默安装？ | **先 NO**，让用户点安装 |
| Q3 | 更新日志：Sparkle 自带窗口 / 自研 sheet | **Sparkle 自带**（少写代码、行为标准） |
| Q4 | 保留「跳过此版本」？ | **保留**（自带，零成本） |

## 9. 批准后的实施步骤

1. 加 Sparkle SPM 依赖（Xcode 里点，或我改 `project.pbxproj`）
2. 你在 Mac 上跑 Sparkle 的 `generate_keys` → 公钥发我（公开信息）；私钥导出后写进 GitHub secret `SPARKLE_ED_PRIVATE_KEY`
3. 我实现：About 页 UI（方案 A）、窗口加高、Info.plist、`make-appcast.py`、CI 步骤、文档
4. 打测试 tag 走一遍：Sparkle 窗口出现 → 安装 → 重启后版本正确
5. 通过后本文件移到 `docs/done/`
