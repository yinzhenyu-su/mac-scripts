---
name: neatquit-app-licensing
description: Modify or debug Neat Quit's client-side licensing in mac-scripts — trial state, grandfathered Pro, feature gating, the License window, and testing with real or test keys. Use when changing the trial length or Pro boundary, fixing activation/validation behavior, or simulating expired trials and legacy users.
---

# Neat Quit 客户端授权

客户端只访问 `https://bgm.fun/license-api/`，Creem API key 永远在服务端。本 skill 覆盖状态机、功能门控与本地测试方法。

## 文件

| 文件 | 作用 |
| --- | --- |
| `neatquit/NeatQuit/LicenseManager.swift` | 状态、试用、老用户判定、激活/校验/解绑 |
| `neatquit/NeatQuit/LicenseView.swift` | 许可证窗口 |
| `neatquit/NeatQuit/NeatQuitApp.swift` | 菜单项与功能门控 |
| `neatquit/NeatQuit/Localization.swift` + `*.lproj` | 中英文文案 |
| `neatquit/README.md` | 对外的授权说明 |

## 状态机

```text
loadTier()
  ├─ legacyPro = 1        → .pro
  ├─ 有 license key       → .pro（先显示，联网失败再降级）
  ├─ 试用未过期           → .trial(daysLeft)
  └─ 其他                 → .free
```

- `.pro`：已购买或老用户。
- `.trial`：7 天全功能，`isEntitled == true`。
- `.free`：红按钮智能退出、登录启动、菜单开关；⌘W 与例外列表锁定。

`hasPro` 只表示「已购买」，用于许可证窗口展示；功能门控一律用 `isEntitled`（pro + trial）。

## 功能门控点

`NeatQuitApp.swift` 中：

- `monitor.setKeyboardEnabled(license.isEntitled && keyboardEnabled)`
- `toggleKeyboard()`：非 entitled → 打开许可证窗口
- `openExceptionsWindow()`：非 entitled → 打开许可证窗口
- `addCurrentApplication()`：非 entitled → 打开许可证窗口
- 菜单标题：非 entitled 时加 `（Pro）` / `(Pro)`
- `applyLicenseState()`：状态变化后重算键盘监听并刷新菜单

改 Pro 边界时必须同时改：门控点、菜单标题、许可证窗口说明、`Localizable.strings`、官网定价区与 FAQ。

## 存储决策

许可证 key、instanceId、试用开始时间、老用户标记都存在 **UserDefaults**，不用 Keychain。

原因：临时签名/重签会让 Keychain 反复弹系统密码框；许可证 key 不是登录凭据，激活次数由服务端限制。删除偏好可重置试用，这是可接受的取舍。

键名：

| key | 含义 |
| --- | --- |
| `license.key` | 许可证密钥 |
| `license.instance` | Creem instance id |
| `license.trialStart` | 试用开始（ISO8601） |
| `license.legacyPro` | 老用户 `1` |
| `license.migrated` | 迁移已执行 |
| `license.lastValidatedAt` | 上次校验时间戳 |
| `license.apiBase` | 调试用 API 覆盖 |

## 远程配置

启动时 `LicenseManager.refreshConfiguration()` 会请求 `GET /license-api/config`，读取：

- `trialDays`：写入 `license.trialDays`，失败时沿用缓存或默认 7
- `activationLimit`：用于展示，实际限制仍由 Creem 许可证执行

改试用天数只需要改服务器 `.env` 的 `TRIAL_DAYS`，不需要发新版。

## 老用户判定

1.4.0 首次启动时，只要存在以下任一偏好，就写入 `license.legacyPro=1`：

- `keyboardEnabled`（用过 ⌘W）
- `applicationRules`（改过例外列表）
- `enabled`（动过主开关）

迁移只执行一次（`license.migrated`）。激活新许可证不会清除 `legacyPro`，老用户解绑后仍保留 Pro。

## API 契约

```http
POST /license-api/activate   { key, instanceName } → { status, instanceId, activation, activationLimit, expiresAt }
POST /license-api/validate   { key, instanceId }   → 同上
POST /license-api/deactivate { key, instanceId }   → { ok: true }
```

- 启动时校验，最多 24 小时一次。
- 网络错误不降级；只有 Creem 明确返回 `expired` / `disabled` / `invalid_license` 才收回。
- 错误码：`invalid_key_format`、`invalid_license`、`activation_limit`、`license_expired`、`rate_limited`。

## 本地构建

```sh
cd ~/Code/github/mac-scripts/neatquit
xcodebuild -project NeatQuit.xcodeproj -scheme NeatQuit -configuration Release \
  -derivedDataPath build MARKETING_VERSION=1.4.0 CURRENT_PROJECT_VERSION=15 build
```

截图或测试时若需沿用辅助功能授权，可临时用旧 Bundle ID 构建；**不要发布这个构建**。

## 测试方法

### 指向本地 license-api

```sh
defaults write fun.bgm.neatquit license.apiBase http://127.0.0.1:3100
```

### 模拟试用到期

```sh
osascript -e 'tell application id "fun.bgm.neatquit" to quit'
defaults delete fun.bgm.neatquit
defaults write fun.bgm.neatquit license.trialStart -string "2026-10-25T00:00:00Z"  # 8 天前
```

预期：菜单显示「免费版」，⌘W 与例外列表带 `（Pro）`，点击打开许可证窗口。

### 模拟老用户

```sh
defaults delete fun.bgm.neatquit
defaults write fun.bgm.neatquit keyboardEnabled -bool true
```

预期：菜单显示 `Neat Quit Pro`，⌘W 已勾选，不进入试用。

### 自动输入密钥

SwiftUI 窗口的层级是 `window → group 1 → [image, staticText×3, textField, button, …]`：

```applescript
tell application "System Events" to tell process "智能退出"
  set value of UI element 5 of UI element 1 of window "许可证…" to "ABC12-…"
  click UI element 6 of UI element 1 of window "许可证…"
end tell
```

### 验证激活上限

第 4 台设备激活应返回 `activation_limit`，界面提示「激活设备数已达上限」。

## 修改检查清单

- [ ] 试用天数：`LicenseManager.trialDays`、文案、官网 FAQ
- [ ] Pro 边界：门控点、菜单标题、许可证窗口、定价区
- [ ] 新错误码：`message(for:)` 与 `Localizable.strings`
- [ ] 中英文文案都更新
- [ ] 老用户迁移逻辑不受影响
- [ ] 本地构建通过，并用测试密钥激活一次
- [ ] 发布后用正式 DMG 重新采集「关于」截图
