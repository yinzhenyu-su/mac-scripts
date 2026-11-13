## Context

参见 `proposal.md - Why`。当前实现与本次设计直接相关的约束：

- 只有一个触发源：`CloseMonitor` 接收红点与 `⌘W` 的鼠标/键盘事件，经 `CloseDecision.action(...)` 用 `RulePolicy` 判定，最后调用 `NSRunningApplication.terminate()`（`CloseMonitor.swift:208/251/376`）。
- `RuleStore` 是持久化范式：`UserDefaults` + `Codable` + `didSet` 写盘 + `onChange` 回调把 `RulePolicy` 推给 `CloseMonitor`（`RuleStore.swift:89-175`）。
- `NeatQuitAppDelegate.refreshMenu()` 在 `menuWillOpen` 时 `removeAllItems()` 后整表重建（`NeatQuitApp.swift:150-259`）。
- 已有一个 2 秒 `authorizationTimer`（`NeatQuitApp.swift:66-73`），v1.5.0 刚为降低空闲唤醒把轮询降到 2 秒。
- `enabled` 默认 `true`，只控制 `monitor.start()/stop()`（`NeatQuitApp.swift:34/263-266`），`toggleEnabled()` 在缺少辅助功能权限时只弹提示不切换（`NeatQuitApp.swift:262`）。
- `terminate()` 不需要辅助功能权限；`RestartAfterPermissionGrant` 会启动新实例并终止自己（`NeatQuitApp.swift:125-148`），因此任何待执行状态都不能只放内存。
- onboarding 既有用户判定依赖固定白名单（`RuleStore.swift:145-147`），新增偏好键不得进入该列表。
- 最低系统版本 macOS 13，`NSMenuItem.sectionHeader(title:)` 不可用（macOS 14+）；无沙盒（`ENABLE_APP_SANDBOX = NO`）。
- 测试是 `swiftc` + `precondition` 的单文件脚本（`neatquit/Tests/main.swift`），不能等待真实时间。

## Goals / Non-Goals

**Goals:**

- 引入与关窗退出并列的第二触发源，目标与时长为用户显式指定的独立状态。
- 复用既有退出动作与菜单组装路径，不新增常驻定时器、不新增权限、不新增第三方依赖。
- 把"何时该退""何时过期""菜单显示什么"收敛为可直接 `precondition` 的纯函数，使功能无需真实等待即可回归。
- 让「启用智能退出」成为语义自洽的全局总开关。

**Non-Goals:**

- 不做循环/每天重复的定时策略，不支持多个时间段。
- 不做强制退出、不做超时强杀、不做进程级信号。
- 不在菜单栏图标上显示倒计时，不引入常驻 1 秒定时器。
- 不做系统通知或横幅提示。
- 不改动应用规则的判定条件、引导状态与授权边界。
- 不为定时退出新建独立管理窗口；管理入口全部在菜单与其子菜单内。

## Decisions

### 1. 定时退出持有独立目标清单，不复用 `RulePolicy`

`RulePolicy` 回答"这个 App 归不归我管"，语义上绑定"关窗"这个时机。若给 `AppRule` 增加 `when` 字段，等于把两个触发源压进一个模型，会出现"例外列表里的 App 是否受定时器约束"这类无法自洽的问题。

选择：新增 `QuitTimer` 值类型（`id / bundleID / displayName / fireAt / state`），`QuitTimerStore` 独立持久化到 `schedule.timers`，与 `applicationRules`、`applicationQuitRules`、`ruleMode` 完全隔离。

代价：用户可能误以为例外列表能保护目标 App。缓解：spec 中「与应用规则策略独立」有两条反向 Scenario，添加面板底部给一行说明文案。

### 2. 绝对 `fireAt` + 墙钟比较，统一由一个 tick 驱动

三种候选：

| 方案 | 睡眠表现 | 重启表现 | 判定复杂度 |
|---|---|---|---|
| 累加计时器（每秒递减剩余） | 睡眠期间不递减，醒来后继续倒数 | 剩余量需持久化，重启后语义漂移 | 中 |
| 一次性 `Timer` 到点触发 | 睡眠期间不触发，醒来后立即触发 | 直接丢失 | 低但不可靠 |
| **绝对 `fireAt` + 墙钟比较（选用）** | 睡醒后按差值判定 | 读盘后同样按差值判定 | 低 |

因为判定只依赖 `now - fireAt`，"一直醒着""睡了一觉""授权触发自我重启""登录启动"四件事走同一条代码路径，不需要 `didWakeNotification`，也不需要记录"上次 tick 时刻"。App Nap 或定时器合并造成的几十秒延迟被 5 分钟窗口完全吸收。

### 3. 5 分钟补跑窗口，倒计时期间不持有防睡眠断言

关闭 App 是几秒钟的动作，但 `PreventUserIdleSystemSleep` 的代价要按整个倒计时的长度支付。它对合盖、用户主动睡眠、低电量保护都无效，却会让整机在倒计时期间不进入空闲睡眠，与 v1.5.0 的降唤醒取向相反，也会在 `pmset -g assertions` 里留下显眼的记录。

选择：

- 倒计时期间不持有任何阻止系统睡眠的断言。
- 触发瞬间持有一个短命断言（10~30 秒），覆盖 `terminate()` 与结果复查，成功、被拒、取消三条路径都必须释放。
- 跨过触发点的睡眠由 5 分钟窗口处理：≤5 分钟补跑，>5 分钟丢弃并写一条 `os_log`。

代价：睡眠跨过触发点基本等于作废（空闲睡眠通常发生在离开 10 分钟之后）。这一点写进 Risks，不出现在 UI 文案中。

### 4. 复用现有 2 秒轮询，不新增常驻定时器

`authorizationTimer` 已经在跑，`tick()` 挂在同一回调上即可，零新增唤醒。倒计时的"秒级"刷新只在菜单打开期间有意义：`menuWillOpen` 启动 1 秒 `Timer`，`menuDidClose` 立刻 `invalidate`，成本被"菜单开着"的时间严格封顶。

替代方案"菜单栏图标显示倒计时"需要 1 分钟粒度的常驻定时器，且新增一整套状态栏绘制逻辑，本期不做。

### 5. 「启用智能退出」成为全局总开关，关闭前确认

选择：`enabled` 同时控制关窗退出与定时退出。关闭时若存在待执行计时器，先弹 `NSAlert` 列出数量与剩余时间（超过 3 条折叠为「等 N 个」），确认后才取消全部计时器并 `monitor.stop()`；用户撤销时 `enabled` 与计时器都不变。

替代方案"改名 `关窗时退出` + 两个触发源正交"被否决，因为用户要求保留现文案并让总开关名副其实。代价是「只用定时退出、不用关窗退出」这一配置不再成立，记录在 Risks。

`status.paused` 文案保持「已暂停」：总开关关闭后确实一切暂停，措辞反而比改动前更准确。

### 6. 菜单五段、无段标题

```
状态 / 全局配置 / 辅助退出 / 定时退出应用 / 应用命令
```

只用 `NSMenuItem.separator()` 分段，段标题一律不用。状态段本身也是条件性的：一切正常时不显示任何灰字，菜单首项直接是「启用智能退出」，避免用一行「已启用」复述旁边的勾选状态；只有缺少权限、已暂停、监听失败或试用剩余天数才占用这一行。不用段标题的原因：`sectionHeader` 需要 macOS 14，自造 disabled 标题项会让 `refreshMenu()` 多一层"这段要不要标题"的条件判断（段内容本身是动态的：权限提示、计时器数量），且「定时退出应用」段标题会与同名子菜单重复。

「将「Safari」定时退出」是「定时退出应用」正下方的一级快捷键行，子菜单给出 5 / 15 / 30 / 60 / 120 分钟与「自定义…」。选预设直接建表，不再经过面板——面板只在「自定义…」和「其它 App」时出现，从主路径降级为兜底路径。它属于定时退出应用段（与辅助退出段之间隔着分隔线），不会与上一段的「将 Safari 加入例外」并排，因此用一级入口换少一次点击。目标已有计时器时这一行仍然显示：选一个新时长天然就是改时长，比"取消后重设"少两步。总开关关闭时它被置灰——这一行是执行动作而不是配置，和暂停期间仍可编辑的应用规则不是一类。清单、添加入口与全部取消仍留在「定时退出应用」的子菜单内。

### 7. 目标只能从"当前运行中的普通应用"里选

`NSWorkspace.shared.runningApplications` 过滤 `activationPolicy == .regular` 并排除自身，既排除了 Finder、Dock、XPC 服务与菜单栏工具，也顺手消灭了一整类边界：选了未启动的 App、倒计时结束发现无事可做、App 中途退出导致条目悬空。

替代方案沿用规则界面的 `NSOpenPanel` 选 `/Applications`，在倒计时语义下会允许无意义输入，否决。

### 8. `terminate()` 的返回值不代表退出成功

`terminate()` 返回的是"请求是否已发出"，不是"应用是否已退出"。被存盘对话框挡住时它仍可能返回 `true`。因此退出流程是：发起请求 → 延迟 2~3 秒复查 `isTerminated` → 未退出则把条目标记为 `refused`。

`refused` 只存在内存，不持久化：重启后一条"未退出"的陈旧记录没有意义。

### 9. 组件切分

```
NeatQuitAppDelegate
  ├── 2 秒 authorizationTimer ──> QuitTimerScheduler.tick()
  ├── 菜单组装（五段）
  ├── 添加面板（NSWindow + NSHostingView）
  └── 确认弹窗（NSAlert）

QuitTimerScheduler        @MainActor，持有 now: () -> Date（可注入）
  ├── add(bundleID:displayName:duration:)
  ├── cancel(id:) / cancelAll()
  ├── tick()
  └── onChange: ([QuitTimer]) -> Void

QuitTimerStore            持久化 schedule.timers，对齐 RuleStore 范式

ScheduleDecision          纯函数，无 UI 无 AppKit 状态
  ├── remainingText(fireAt:now:)  -> "29:41" / "1:12:00"
  ├── isDue(fireAt:now:)          -> Bool
  ├── isStale(fireAt:now:window:) -> Bool
  └── topLevelSuffix(timers:now:) -> String?

AppTerminator             正常退出动作，CloseMonitor 与 Scheduler 共用
```

把退出动作抽出来的理由：定时退出与关窗退出在"如何退"上必须完全一致（都是正常退出、都不强杀），任一处将来改动都不应出现两套行为。

### 10. 持久化键与 onboarding 边界

| 键 | 内容 |
|---|---|
| `schedule.timers` | `[QuitTimer]` 的 JSON，仅含 `armed` 条目 |

硬约束：`schedule.*` MUST NOT 加入 `RuleStore.swift:145-147` 的既有用户白名单。该判断只在 `onboardingKey == nil` 时执行，而任何创建过计时器的用户必然已有该键，因此不加即安全，加了会误判新用户。

### 11. Pro 门禁沿用现有路径

入口文案由 `L10n.scheduleTitle(pro:)` 生成，未授权时点击直接 `openLicenseWindow()`，与 `menu.rules.pro` / `menu.keyboard.pro` 一致。试用到期不删除计时器（与 onboarding 规格里"试用到期不删除规则"的原则一致）。

## Risks / Trade-offs

- **[睡眠跨过触发点基本等于作废]** → 5 分钟窗口是刻意的取舍；丢弃时写 `os_log` 便于排查，不进 UI，避免为低频场景增加菜单状态。
- **[`terminate()` 被存盘对话框长期挡住，条目停留在「未退出」]** → 不做自动重试、不强杀；用户回来后手动重试或手动处理。这是"绝不丢数据"的代价，已由 5 分钟窗口与"不强杀"决策确认。
- **[主开关语义变化影响老用户]** → 升级瞬间不存在任何计时器，因此关闭开关的实际行为与旧版一致；风险集中在文档与 release notes，需明确写出"关闭总开关会取消定时退出"。
- **[「只用定时退出」的配置不再成立]** → 已由用户确认接受；`design.md` 与 README 需说明这是总开关的代价，避免后续被当作缺陷。
- **[菜单打开期间增删 item 可能出现抖动]** → 归零时只把标题改为「正在退出…」，不增删条目；条目的增删留到菜单关闭后下次打开时重排。此行为需在实机上验证（见 Open Questions）。
- **[状态断言泄漏导致整机不睡]** → 断言只在触发窗口内持有，成功/被拒/取消三条路径都释放；进程退出时系统会回收作为兜底；排查手段记录为 `pmset -g assertions`。
- **[1 秒刷新定时器忘记释放]** → 只在 `menuWillOpen` 创建、`menuDidClose` 与 `applicationWillTerminate` 双保险释放；无计时器时不创建。
- **[中英文文案遗漏]** → 新增 key 在两个 `Localizable.strings` 同时落地，并在任务清单中列为独立验收项。
- **[倒计时条目与关窗退出竞争同一 App]** → 两边都以"App 是否仍在运行"为唯一事实来源，天然幂等，不需要互斥或通知。

## Migration Plan

1. 新增 `schedule.timers` 键，无历史数据需要迁移；`RuleStore` 的既有判定逻辑不动。
2. 升级后 `enabled` 仍为既有值，计时器列表为空，行为与升级前完全一致；总开关的新语义只在用户第一次创建计时器后才具备可观察差异。
3. 回滚：旧版本不读取 `schedule.timers`，残留数据无害；新菜单项消失后无其他副作用。
4. 验证顺序：先跑纯函数用例，再手工验证菜单五段、面板创建、归零退出、拒绝退出、过期丢弃、主开关确认弹窗、中英文切换。

## Open Questions

- 菜单处于打开状态时计时器归零，就地修改 `NSMenuItem.title` 是否会在 menu tracking 期间产生视觉抖动，需在 macOS 13/14/15 实机验证；若抖动明显，改为关闭菜单后再重排，标题维持「正在退出…」。
