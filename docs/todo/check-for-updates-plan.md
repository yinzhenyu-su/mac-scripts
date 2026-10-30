# 关于页「检查更新」需求与方案

> 状态：**待批准**（批准后再动代码）
> 涉及文件：`smart-close/SmartClose/SmartCloseApp.swift`（AboutView）、新增 `smart-close/SmartClose/UpdateChecker.swift`、`smart-close/Tests/`

## 1. 背景与现状

| 项 | 现状 |
|---|---|
| 分发渠道 | GitHub Releases，tag `vX.Y.Z`，附件 `SmartClose-vX.Y.Z.dmg`（CI 已签名 + 公证） |
| 版本号来源 | `Info.plist` 的 `CFBundleShortVersionString` / `CFBundleVersion` ← `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`；发版时由 tag 与 `run_number` 注入 |
| 关于页 | `SmartCloseApp.swift` 里的 `AboutView`（SwiftUI，440×460，NSWindow 承载）：App 图标、名称、`版本 x.y.z（build）`、功能说明、致谢、仓库链接 |
| 仓库可见性 | public → 读 Releases API **不需要 token**，App 内不存任何密钥 |
| 沙盒 | `ENABLE_APP_SANDBOX = NO` → 发网络请求**不需要** entitlement |
| 最低系统 | macOS 13（可用 async/await、`URLSession.data(for:)`） |
| 现有测试方式 | `swiftc SmartClose/RuleStore.swift Tests/main.swift -o build/Tests/...`，纯 `precondition` 脚本，无 XCTest target |

## 2. 目标与非目标

**目标**

1. 用户能在关于页**一键**知道当前是否最新版，并一步拿到新版。
2. 有新版本时**不打扰**：不弹模态、不自动下载，只是把入口亮出来。
3. 一期**零第三方依赖**、可离线降级、失败不崩溃。

**一期不做（明确划出去）**

- 应用内自动下载 / 替换 / 重启（Sparkle 的能力）
- 增量更新、灰度发布、Beta 通道
- 使用统计、埋点
- 自动检查之外的后台常驻轮询

## 3. 路线选择

| | 方案 A：检查 + 提示 + 跳转（推荐一期） | 方案 B：Sparkle 2 全自动更新（二期可选） |
|---|---|---|
| 体验 | 提示有新版本 → 点「下载」到 Release 页/DMG；手动拖进「应用程序」 | 应用内下载、校验、替换、重启，全程一键 |
| 复杂度 | 低：一个 API 调用 + 状态机 + UI | 高：appcast.xml、EdDSA 私钥、CI 生成 appcast、Sparkle XPC 签名、版本渠道 |
| 维护 | 无额外依赖 | 跟随 Sparkle 版本升级；密钥管理 |
| 与现有流程 | 完全兼容（CI 产物不变） | 需要在发版流程里多生成/上传 appcast，并保证 appcast 与 DMG 同源 |
| 失败面 | 只读操作，失败影响小 | 涉及替换自身，需处理 translocated、权限、回滚 |

**建议**：一期做 A（先把「能发现新版」跑通，成本低、可逆）；如果之后觉得手动装太烦，再引入 B，一期 UI 的「下载」按钮可直接换成 Sparkle 的更新入口，不需要返工。

## 4. 功能需求

### FR-1 手动检查（P0）
- 关于页版本行下方新增按钮「检查更新」。
- 点击 → 立即进入检查中状态（按钮禁用 + 小 spinner），同一时刻只允许一个请求。
- 检查中再次点击无效（不排队、不重复请求）。

### FR-2 结果展示（P0）
在按钮旁/下方用一行文字展示结果，三种终态：

| 结果 | 文案 | 附加操作 |
|---|---|---|
| 已是最新 | `已是最新版本` | 无 |
| 有新版本 | `发现新版本 1.3.0` | 主按钮「下载」+ 次按钮「更新说明」 |
| 失败 | `检查失败：<原因>` | 「重试」 |

失败原因细分（不显示技术栈信息）：
- 无网络 / 无法连接 → `无法连接更新服务器`
- 超时（>10s）→ `连接超时，请稍后重试`
- 403 → `请求过于频繁，请稍后再试`
- 404 / 仓库无 Release → `暂无发布版本`
- 解析失败 / tag 不是 `vX.Y.Z` → `暂时无法判断版本`

### FR-3 版本比较（P0）
- 只比较 `major.minor.patch` 三段数字，**数值比较**（`1.2.10 > 1.2.9`）。
- 容忍 tag 前缀 `v`；`v1.3.0` 与 `1.3.0` 等价。
- 本地版本 **高于** 远端（开发版）→ 视为「已是最新」，不提示降级。
- `prerelease` / `draft` 的 release **忽略**（pull `/releases/latest` 本身已排除这两类，但解析时仍显式过滤一次）。
- tag 不符合 `vX.Y.Z`（如 `v1.3.0-rc1`、`nightly`）→ 该 release 视为不可比较，走「暂时无法判断版本」。

### FR-4 下载入口（P0）
- 主按钮「下载」：打开该 release 里**文件名以 `.dmg` 结尾**的第一个资产的 `browser_download_url`；没有 dmg 资产时退回 release 的 `html_url`。
- 次按钮「更新说明」：打开 `html_url`。
- 都用 `NSWorkspace.shared.open(_:)`，不在 App 内渲染网页。

### FR-5 检查失败处理（P0）
- 任何失败都**不弹模态框**，只在关于页显示一行文字。
- 失败不写入「上次检查时间」，允许用户立即重试（手动重试间隔 ≥ 5s，防连点）。
- 自动检查失败**完全静默**（不提示、不写菜单标记）。

### FR-6 自动检查（P1，可关）
- 默认**开启**，用户可在关于页用复选框「自动检查更新」关闭。
- 触发时机：App 启动后 **15s** 检查一次；之后每次启动时若「距上次检查 ≥ 24h」再检查（不做常驻定时器，省电）。
- 自动检查发现新版本时：只在关于页展示状态 + （可选，见 FR-8）菜单提示；**不弹窗**。
- 自动检查频率上限：24h 一次（以 UserDefaults 里 `lastCheckAt` 为准）。

### FR-7 跳过此版本（P1）
- 发现新版本时提供「跳过此版本」。
- 记录 `lastSkippedVersion`：自动检查不再提示该版本；**手动检查仍然提示**（用户主动问就得答）。
- 发布了更新的版本（大于被跳过的版本）时，重新提示。

### FR-8 菜单提示（P2，可选）
- 有新版本时，状态栏菜单里「关于智能退出」右侧显示 `1.3.0` 小字（或标题改为「关于智能退出（有新版本）」）。
- 不做图标角标/动画（LSUIElement 无 Dock 图标，容易过度打扰）。

### FR-9 隐私（P0）
- 只向 `api.github.com` 发 `GET /repos/yinzhenyu-su/mac-scripts/releases/latest`，不带任何用户标识、设备信息、使用数据。
- User-Agent 只含 `SmartClose/<version>`（GitHub API 必需）。
- 用户关闭自动检查后，只有点按钮才会联网。

### FR-10 布局（P0）
- 关于窗口现为 440×460，空间紧张。方案：在版本行下方插入一行 `[检查更新按钮] [状态文字]`，不改变窗口尺寸，长文案自动换行/截断。
- 如加「自动检查更新」复选框，放在「项目仓库 ↗」上方，与现有内容同宽。

## 5. 交互状态机

```
idle ──点击/自动触发──> checking ──成功且远端更新──> updateAvailable(release)
                          │                     └── 远端同版/更低 ──> upToDate
                          └──失败──> failed(reason) ──重试──> checking
```

- `updateAvailable` 下点「下载」不改变状态（只打开浏览器）。
- `upToDate` / `failed` 下按钮文案回到「检查更新」。

## 6. 技术方案

**接口**

```
GET https://api.github.com/repos/yinzhenyu-su/mac-scripts/releases/latest
Accept: application/vnd.github+json
X-GitHub-Api-Version: 2022-11-28
User-Agent: SmartClose/<CFBundleShortVersionString>
```

超时 10s，不重试，`URLSession.shared`（或注入的 session，便于测试）。仅接受 `https`。

**解析模型（只取需要的字段）**

```swift
struct ReleaseInfo: Decodable, Equatable {
    let tagName: String
    let htmlURL: URL
    let body: String?
    let publishedAt: Date?
    let prerelease: Bool
    let draft: Bool
    let assets: [Asset]        // name, browserDownloadURL
}
```

**版本模型**

```swift
struct AppVersion: Comparable, Equatable {
    let major: Int, minor: Int, patch: Int
    init?(_ raw: String)       // 允许 "v1.2.3" / "1.2.3"；其余返回 nil
}
```

**结果类型**

```swift
enum UpdateCheckResult: Equatable {
    case upToDate(current: AppVersion, latest: AppVersion)
    case updateAvailable(ReleaseInfo, latest: AppVersion)
    case failed(UpdateCheckError)   // .offline/.timeout/.rateLimited/.noRelease/.invalidTag/.badResponse
}
```

**代码结构**

| 文件 | 内容 | 依赖 |
|---|---|---|
| `SmartClose/UpdateChecker.swift` | `AppVersion`、`ReleaseInfo`、`UpdateCheckResult`、`UpdateChecker`（注入 `URLSession`） | 仅 Foundation（可被 Tests 单独编译） |
| `SmartClose/SmartCloseApp.swift` | `AboutView` 接入状态、按钮、复选框；`UpdatePromptModel` 用 `@State` + `Task` | SwiftUI / AppKit |

不引入第三方依赖；不加 entitlement；不改 Info.plist（不需要 ATS 例外，GitHub 是 https）。

## 7. 本地存储（UserDefaults）

| Key | 类型 | 默认 | 用途 |
|---|---|---|---|
| `autoCheckUpdates` | Bool | `true` | 自动检查开关 |
| `lastCheckAt` | Date | 无 | 自动检查节流（24h） |
| `lastSkippedVersion` | String | 无 | 「跳过此版本」 |

## 8. 边界情况与风险

| 情况 | 处理 |
|---|---|
| GitHub 匿名限流（60 次/小时/IP） | 403 → 「请求过于频繁」；自动检查静默失败，下次启动再试 |
| 公司代理 / 中间人证书拦截 | 请求失败 → 显示「无法连接更新服务器」，不弹窗 |
| Release notes 很长或含 Markdown | 一期不在 App 内渲染，只提供「更新说明」跳浏览器 |
| 从 DMG 直接运行（translocated） | 一期只读，无影响；未来 Sparkle 需要先提示「拖入应用程序」 |
| 用户长期不更新 | 每次启动最多提示一次（24h 节流），不做弹窗轰炸 |
| 版本号回退（发错版本） | 本地更高视为最新，不提示降级 |
| 未来引入 Sparkle | 需 appcast + EdDSA 密钥 + CI 生成；一期 UI 可直接复用 |

## 9. 验收标准

1. 当前版本 = 最新版：点「检查更新」→ 显示「已是最新版本」，无报错。
2. 远端发布更高版本：显示「发现新版本 x.y.z」+「下载」+「更新说明」；「下载」在浏览器打开 `.dmg` 链接。
3. 断网：10s 内显示「无法连接更新服务器」，App 不崩溃、按钮可再次点击。
4. 连续快速点击：只发一次请求。
5. 「跳过此版本」后重启：自动检查不再提示该版本；手动检查仍提示。
6. 关闭「自动检查更新」：启动后完全不发请求（可用 Charles/`nettop` 或日志确认）。
7. 版本比较单测全绿（见 `docs/tests/check-for-updates-tests.md`）。
8. 关于窗口布局在 440×460 下不裁切、不跳动。
9. 签名/公证流程不受影响（不新增网络 entitlement、不加依赖）。

## 10. 待决策（需要拍板）

| 编号 | 问题 | 建议 |
|---|---|---|
| Q1 | 一期只做「检查 + 跳转下载」，还是一步到位上 Sparkle 自动更新？ | **A**：先做检查 + 跳转（可逆、成本低） |
| Q2 | 自动检查默认开还是关？频率？ | **默认开**，启动后 15s 一次 + 每 24h 一次 |
| Q3 | 有新版本时菜单里是否提示？ | **一期不做**（只改关于页），避免打扰 |
| Q4 | 是否支持 Beta / 预发布通道？ | **不支持**，只认 `/releases/latest` |
| Q5 | 关于窗口是否允许加高（如 460 → 520）以放更新说明？ | **不改高度**，更新说明跳浏览器 |

## 11. 批准后的实施步骤

1. 新增 `UpdateChecker.swift`（纯 Foundation）+ `Tests/update-checker-tests.swift`，先跑通单测。
2. 接入 `AboutView`（按钮、状态、复选框、跳过）。
3. 加自动检查节流逻辑（`lastCheckAt`）。
4. 更新 `smart-close/README.md`（说明检查更新行为与隐私）。
5. `swiftc` 单测 + `xcodebuild` 构建验证；打一个测试 tag 走一遍 CI（可选）。
6. 通过后把本文件移到 `docs/done/`。
