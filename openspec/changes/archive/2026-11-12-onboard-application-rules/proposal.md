## Why

首次使用者不知道默认哪些应用不会自动退出，也不容易发现应用规则入口。采纳社区反馈，完善默认排除列表，并在首次使用展示规则，让用户理解并配置后台应用的行为。

## What Changes

- 保持默认排除模式及现有预置项，为新用户增加 Messages 和 Apple Terminal 的默认排除规则。
- 首次启动展示默认排除列表、行为说明和规则调整入口，允许确认或稍后处理。
- 保存引导状态，支持从菜单栏再次打开；升级不覆盖已有模式或应用列表。
- 中英文同步；沿用已有试用/Pro 权限，不借引导扩大免费功能范围。
- 不修改设置窗口、浮动窗口、红色按钮或快捷键的退出判定。

## Capabilities

### New Capabilities

- `application-rule-onboarding`: 默认排除规则及首次使用规则引导，包含持久化和升级保护。

### Modified Capabilities

无；仓库此前没有 OpenSpec 规格。

## Impact

涉及 neatquit/NeatQuit/RuleStore.swift、NeatQuitApp.swift、SettingsView.swift、LicenseManager.swift 的现有授权接口及本地化资源。新增引导状态和界面；无新增服务依赖，不变更授权产品边界。
