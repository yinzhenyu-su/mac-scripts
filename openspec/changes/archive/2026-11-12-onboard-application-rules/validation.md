# 本机验证记录

## 环境

- 隔离 Bundle ID：`fun.bgm.neatquit.onboarding-validation`。
- Debug 隔离构建通过，`CODE_SIGNING_ALLOWED=NO`；构建目录 `/tmp/neatquit-onboarding-isolated`。
- 验证用应用复制到 `~/Applications/NeatQuitOnboardingValidation.app` 并 ad-hoc 签名，仅使用独立偏好域。
- `fun.bgm.neatquit` 日常实例的偏好未被读写，未启动或重启日常实例。
- 测试 Bundle ID 未授予辅助功能权限，用于验证“无权限仍可阅读引导”。

## 3.2 构建与自动测试

- `swiftc NeatQuit/RuleStore.swift Tests/main.swift` 编译通过；运行输出 `46 decision cases passed`、`Onboarding migration cases passed`。
- `xcodebuild -scheme NeatQuit -configuration Debug ... CODE_SIGNING_ALLOWED=NO build` 输出 `BUILD SUCCEEDED`。
- 本次改动未触及 `CloseDecision` 中标准窗口、全屏、跨 Space、⌘W 的退出判定；`git diff` 仅新增规则存储、迁移、引导和文案。

## 3.1 隔离偏好场景

| 场景 | 前置状态 | 结果 |
| --- | --- | --- |
| 全新安装（中文） | 删除测试偏好域后启动 | 自动展示“应用规则说明”，说明排除模式，列表 25 项，包含 `com.apple.MobileSMS`、`com.apple.Terminal` 及原预置项；即使测试 Bundle ID 无辅助功能权限也可阅读 |
| 稍后处理 | 点击“稍后处理” | `rules.onboardingHandled=1`，窗口关闭；重新启动不再自动展示 |
| 全新安装（英文） | 删除测试偏好域，`-AppleLanguages (en)` | 标题 `Application Rules Guide`，说明、列表、三个按钮均为英文；点击“Adjust Rules…”进入 `App Rules` |
| 升级老用户（无保存列表） | 仅写入 `enabled=false` | 不自动展示引导；`applicationRules` 迁移为 23 项旧默认集合，未新增 Messages / Terminal；模式保持默认排除模式 |
| 升级自定义配置 | `applicationRules=[]`、`ruleMode=onlyListed` | 不自动展示引导；空排除列表与仅包含模式原样保留，未被新增默认项覆盖 |
| 展示期间异常退出 | 首次启动未处理引导后 `kill -9` | 重启后引导再次展示，`rules.onboardingHandled` 仍为 0 |
| 权限恢复重启（等效验证） | 处理引导后重新启动同一 Bundle ID | 不再次展示引导；`restartAfterPermissionGrant` 使用同一 Bundle ID 偏好，代码路径确认不会重置状态。未真实切换 TCC 权限，详见“限制” |
| 试用到期 | `license.trialStart=2020-01-01`、无密钥、`license.migrated=1` | 引导可阅读；点击“调整规则…”打开“许可证…”窗口而非规则编辑；`applicationRules` 仍为 25 项，未被删除或重置 |
| 有效试用 | 全新偏好域（7 天试用） | 点击“调整规则…”打开“应用规则”窗口，展示当前模式与列表，授权入口未被误触发 |

## 3.2 人工检查

- 中文首次引导：标题、模式说明、默认列表、权限说明、`稍后处理 / 调整规则… / 我知道了` 文案与布局正确。
- 英文首次引导：标题、模式说明、默认列表、权限说明、`Later / Adjust Rules… / Got It` 文案与布局正确。
- 中文规则管理：`应用规则`窗口显示两种模式、搜索、添加与逐项移除，底部说明“不在上方列表中的 App 在关闭最后一个标准窗口时会自动退出”。
- 英文规则管理：`App Rules`窗口对应内容完整。
- 菜单栏存在“应用规则说明”入口；该入口调用同一 `openRuleGuide`，界面读取 `store.activeRules`，不会重新套用默认值。
- 中英文 onboarding 本地化键各 7 项，键集合一致，无硬编码单语文字。

## 限制

- 未真实在系统设置中为测试 Bundle ID 开启/关闭辅助功能权限；权限恢复重启以“同一偏好域重新启动进程”验证状态持久化，并核对了重启实现。
- 截图保存在 `/private/tmp/nq-*.png`，为临时验证产物，未加入仓库。
- 验证结束后删除测试应用、测试偏好域，未改动日常实例配置。
