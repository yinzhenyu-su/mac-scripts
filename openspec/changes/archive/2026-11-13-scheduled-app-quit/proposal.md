## Why

NeatQuit 目前只有一种出手时机：用户关闭某个 App 的最后一个标准窗口。当用户想在离开前主动收尾（例如「30 分钟后把微信关掉」）时没有对应能力，只能手动逐个退出 App，而这恰好是本产品想替用户省掉的动作。

窗口关闭是「被动」时机，用户无法表达「我现在要收尾了」。补上这个主动时机，产品的行为可以概括为一句话：关窗即退，到点全退。

## What Changes

- 新增「定时退出」：一次性倒计时，到达时间后对用户显式指定的单个 App 调用 `terminate()`，不强杀（被拒时保留行并提供手动重试）。
- 定时退出的目标是独立的「App + 时长」清单，不读取「应用规则」的排除列表、仅包含列表或规则模式，也不向两套规则列表写入任何内容。
- 菜单重组为按用途区分的带：状态区 / 全局配置 / 辅助退出 / 定时退出 / 应用命令，用分隔线区分，不新增段标题。
- 「启用智能退出」升级为全局总开关：关闭时辅助退出与定时退出都不再生效。存在待执行计时器时先弹确认，确认后才取消全部计时器。
- 定时退出属于 Pro 功能，沿用现有 `openLicenseWindow()` 授权入口与 `（Pro）` 文案后缀。
- 倒计时只在菜单打开期间刷新，不新增常驻定时器，保持 v1.5.0 的低唤醒取向。
- **BREAKING**（行为语义）：「启用智能退出」从「仅控制关窗监听」变为「控制全部退出手法」。此前关闭它不影响任何其他能力；此后关闭它会取消待执行的定时退出。

## Capabilities

### New Capabilities

- `scheduled-app-quit`: 定时退出的创建、执行、取消、过期判定，及其与全局总开关、应用规则策略、Pro 授权和中英文呈现的关系。

### Modified Capabilities

（无。现有 `application-rule-onboarding` 的引导状态、升级保护与授权一致性要求不变；本次只新增并列的触发源，不改变关窗退出的判定条件。）

## Impact

- 代码
  - `neatquit/NeatQuit/NeatQuitApp.swift`：菜单组装重排、总开关联动、确认弹窗、添加面板窗口管理。
  - 新增 `QuitTimerStore`（持久化）、`QuitTimerScheduler`（计时与判定）、`AppTerminator`（抽出退出动作，供定时退出复用）。
  - `neatquit/NeatQuit/RuleStore.swift`：不改变关窗判定行为；仅可能抽出可共享的 App 匹配逻辑，供定时退出做目标校验。
  - `neatquit/NeatQuit/Localization.swift` 与 `zh-Hans.lproj` / `en.lproj` 两份 `Localizable.strings`。
- 存储：`UserDefaults` 新增 `schedule.*` 键。这些键 MUST NOT 加入 `RuleStore` 中判断「既有用户」的白名单（`enabled` / `keyboardEnabled` / `ruleMode` / `applicationRules` / `applicationQuitRules` / `license.*`），否则会让碰过定时退出的新用户被误判为升级用户。
- 测试：`neatquit/Tests/main.swift` 增加纯函数用例（剩余时间格式化、到期判定、过期判定、菜单标题），不依赖真实等待。
- 文档：`neatquit/README.md` 与 release notes 需说明新入口和总开关语义变化；`neatquit/软件著作权申请资料/` 中提及「启用智能退出」的草稿如仍在提交周期内需同步。
- 依赖：无新增第三方依赖。`terminate()` 不需要辅助功能权限，因此定时退出本身不引入新的权限要求。
