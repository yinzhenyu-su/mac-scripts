## Why

定时退出解决了「到点把 App 收掉」，但离开工位前的最后一件事往往是**拔移动硬盘**。用户现在要么等 App 退完再手动去 Finder 弹出，要么干脆不拔。把「按时间弹出指定磁盘」做成与定时退出应用并列的能力，`到点收尾` 才算完整。

## What Changes

- 新增「定时弹出硬盘」：为一块**物理磁盘**设定倒计时，到点逐卷卸载后整盘弹出。
- 磁盘段与定时退出应用段**并列**，中间用分隔线隔开；没有可弹出的磁盘时整段连同分隔线一起消失。
- 每块盘在菜单里有一行快捷入口「将「<主卷名>」定时弹出」，子菜单提供 5 / 15 / 30 / 60 / 120 分钟与「自定义…」。
- 磁盘段保留一行聚合入口「定时弹出硬盘 <最近到期时间>」，子菜单承载待执行清单、添加入口与全部取消——结构与定时退出应用完全同构。
- 目标单位是物理磁盘而非卷：`Ventoy` 与 `VTOYEFI` 属于同一块 U 盘，菜单里只出现一行。
- 菜单标签取主卷名（容量最大的可浏览卷），回退到整盘媒体名；整盘媒体名与设备型号进 tooltip。
- 到点只做正常卸载 + 弹出，**不强制弹出**；卷被占用时标记「未弹出」并提供手动重试。
- 磁盘被拔出时计时器自动消失，等价于定时退出应用里「目标 App 已退出」。
- **BREAKING**（内部数据模型）：`QuitTimer` 泛化为 `ScheduledAction`，目标由 `bundleID` 变为 `application` / `disk` 两种；`schedule.timers` 升级为 `schedule.actions` 并做一次性迁移。

## Capabilities

### New Capabilities

- `scheduled-disk-eject`: 磁盘定时弹出硬盘的目标归组与命名、到点执行与失败重试、过期判定、菜单呈现、与总开关和定时退出应用的关系、Pro 门禁与中英文文案。

### Modified Capabilities

（无。`scheduled-app-quit` 的行为契约不变，本次只把它的内部数据模型泛化，并在菜单分组上新增一段。菜单分组那条 Requirement 属于新能力的一部分，在 `scheduled-disk-eject` 中以增量要求表达。）

## Impact

- 代码
  - 新增 `ScheduledAction` / `ScheduleTarget`，`QuitTimerStore` 改名或扩展为 `ScheduledActionStore`，调度器的 `isRunning` / `quit` 闭包替换为 `isPresent(target)` / `perform(target)`。
  - 新增磁盘相关组件：物理磁盘归组（`DADiskCopyWholeDisk`）、主卷选择、卸载与弹出。
  - 新增 `EjectPanelView`（与应用面板共用时长控件）。
  - `NeatQuitApp.swift`：菜单增加磁盘段及其分隔线，磁盘行的倒计时刷新复用现有 1 秒 tick。
  - `Localization.swift` 与两份 `Localizable.strings`：时长预设改为动作中性文案，新增磁盘相关 key。
- 存储：`schedule.timers` → `schedule.actions`；旧数据在启动时迁移一次，失败则丢弃并保留原有行为。`schedule.*` 仍不得进入 `RuleStore` 的既有用户白名单。
- 依赖：无新增第三方依赖，使用系统 DiskArbitration 框架。
- 文档：`README.md` 与 release notes 需说明磁盘弹出、目标单位与「不强制弹出」策略。
- 测试：`Tests/main.swift` 增加目标泛化、主卷选择、过期判定的纯函数用例；磁盘枚举与弹出需要手工验证。

## Out of Scope

- 定时睡眠、锁屏、关机等同属「收尾」的动作。
- 单个卷的独立弹出（目标单位固定为物理磁盘）。
- 网络卷与虚拟挂载（OrbStack、Qrypt、云盘挂载）。
- 强制弹出及其数据风险提示。
- 挂载磁盘镜像（DMG）的弹出入口——首版排除，见 design 的 Open Questions。
