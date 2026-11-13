## Context

参见 `proposal.md - Why`。当前实现与本次设计直接相关的约束：

- 定时退出刚落地：`QuitTimer`（`bundleID` / `displayName` / `fireAt` / `state`）、`QuitTimerStore`（`schedule.timers`）、`QuitTimerScheduler`（注入 `now` / `isRunning` / `quit` 闭包）、`ScheduleDecision`（纯函数：5 分钟窗口、剩余时间格式化、排序）。
- 调度由现有 2 秒 `authorizationTimer` 驱动，菜单打开期间才启动 1 秒倒计时刷新（挂 `.common` mode）。
- 菜单已按用途分段：状态（条件出现）/ 全局配置 / 辅助退出 / 定时退出应用 / 应用命令，段间用分隔线，无段标题。
- 「启用智能退出」是全局总开关，关闭前确认、确认后取消全部 App 计时器。
- 时长预设当前写作「5 分钟后退出」，是动作绑定文案。
- 应用未沙盒化（`ENABLE_APP_SANDBOX = NO`），可直接使用 DiskArbitration。
- 测试是 `swiftc` + `precondition`，不能等待真实时间，也不能触碰真实磁盘。

本机实测（用于校准命名与归组，不作为规格）：

```
  Volume /Volumes/Ventoy   bsd=disk4s1   VolumeName=Ventoy
    DADiskCopyWholeDisk -> disk4
      MediaName   = SanDisk Ultra USB 3.0 Media
      DeviceVendor= SanDisk, DeviceModel = Ultra USB 3.0
  Volume /Volumes/VTOYEFI  bsd=disk4s2   VolumeName=VTOYEFI   (33 MB)
  Root   /                 bsd=disk3s1s1 -> whole=disk3  MediaName=AppleAPFSMedia
  虚拟挂载 OrbStack / Qrypt：不是本地卷，也不可弹出
```

## Goals / Non-Goals

**Goals:**

- 在现有调度器上增加第二种目标类型，5 分钟窗口、过期丢弃、剩余时间、排序等逻辑零改动。
- 磁盘目标按物理磁盘归组，菜单行数与"插了几块盘"一致，而不是"挂载了几个卷"。
- 菜单结构与定时退出应用完全同构，用户只需学一次。
- 所有磁盘操作保持"绝不强制"，失败可重试、可解释。

**Non-Goals:**

- 不做定时睡眠/锁屏/关机。
- 不做单卷弹出，不做网络卷、虚拟挂载、DMG 的弹出入口。
- 不做磁盘健康检查、SMART 读取或弹出前的"是否在备份"检测。
- 不改动关窗退出的判定与应用规则。

## Decisions

### 1. 目标单位是物理磁盘，归组用 `DADiskCopyWholeDisk`

要判断"两个卷是不是同一块盘"，最稳的是让系统回答，而不是切 BSD 名字：

```
  /Volumes/Ventoy  (disk4s1)   --DADiskCopyWholeDisk-->  disk4
  /Volumes/VTOYEFI (disk4s2)   --DADiskCopyWholeDisk-->  disk4    同一块
  /                (disk3s1s1) --DADiskCopyWholeDisk-->  disk3    APFS 也不会切错
```

BSD 字符串剥 `sN` 在 APFS（`disk3s1s1`）和多层分区上都容易出错，弃用。

### 2. 持久化标识用主卷路径，运行时解析整盘

`disk4` 这类整盘 BSD 名在重启、重插后可能变化，不能作为跨启动的身份。计时器存**主卷路径**（`/Volumes/Ventoy`）：

- 路径存在 → 解析出整盘，执行弹出。
- 路径消失 → 视为目标已移除，移除计时器（等价于"目标 App 已退出"）。

整盘 BSD 名可以在创建时作为提示一并存下，但只用于同一次运行内的失败复查，不作为身份。

### 3. 显示名取主卷名，回退到整盘媒体名

实测三类名字的差别很大：

| 来源 | Ventoy 实测值 | 问题 |
|---|---|---|
| 主卷 `volumeLocalizedName` | `Ventoy` | 用户认得，可被改名，一块盘可能有多个 |
| 整盘 `MediaName` | `SanDisk Ultra USB 3.0 Media` | 同型号完全相同，带 " Media" 后缀；系统盘是 `AppleAPFSMedia` |
| 厂商 + 型号 | `SanDisk` / `Ultra USB 3.0` | 太泛 |

选择：主卷 = 可浏览、非只读、有名称的卷中容量最大者（15.34 GB 的 Ventoy 胜过 33 MB 的 VTOYEFI）。标签用主卷名，回退整盘 `MediaName` 去掉 ` Media`，再回退厂商+型号，最后「未命名磁盘」。tooltip 放厂商 / 型号 / 容量。

身份用路径、显示名每次刷新重取，因此用户重命名卷后菜单会跟着变，而计时器不会失效。

### 4. 数据模型：`QuitTimer` 泛化为 `ScheduledAction`

```
  ScheduledAction
    id
    target: ScheduleTarget
      .application(bundleID: String)
      .disk(mainVolumePath: String, bsdName: String?)
    displayName
    fireAt
    state: armed / firing / refused
```

调度器把两个闭包换成两个按目标分派的方法：

```
  isPresent(.application) -> NSRunningApplication 是否存在
  isPresent(.disk)        -> 主卷路径是否仍挂载
  perform(.application)   -> terminate + 2.5 秒后复查 isRunning
  perform(.disk)          -> 逐卷 unmount -> 整盘 eject -> 复查整盘是否还在
```

替代方案是平行再造一套 `EjectTimerStore` / `EjectScheduler`，被否决：5 分钟窗口、过期丢弃、剩余时间格式化、排序、菜单刷新全都要复制一遍，任何一处规则改动都会变成两处。

`ScheduleDecision` 一行不改，它只认 `fireAt`。

### 5. 弹出实现：调用系统 `diskutil eject`，绝不强制

最初打算直接走 DiskArbitration。用一个 20 MB 的 APFS 测试镜像实测后推翻：

```
  卷 /Volumes/NeatQuitTestDisk  bsd=disk6s1
    DADiskCopyWholeDisk -> disk6（APFS 合成容器，不是物理盘）
    disk6 的 DeviceProtocol = "Virtual Interface"

  DA: 逐卷 unmount 成功 -> DADiskEject(disk6) -> 退出码之外无从判断
  结果：卷消失，但镜像仍然 attach（disk5 还在）
```

结论：`DADiskCopyWholeDisk` 对 APFS 卷返回的是合成容器，对容器 eject 不会断开底层设备；外置 APFS 盘会遇到同样的问题。

选择：用一个短命进程调用

```
  /usr/sbin/diskutil eject <mainVolumePath>
  成功判定：退出码 == 0
```

- `diskutil eject` 接受挂载点，会自行处理卷 → 容器 → 物理盘，也处理磁盘映像的整条链路。实测同一个测试镜像：退出码 0、卷消失、镜像彻底 detach。
- **绝不使用 `-force`**。被占用时 `diskutil` 返回非零，磁盘保持挂载，不会丢数据——与「不强杀 App」是同一条原则。
- 输出与退出码写入 `os_log`，排查时能直接看到拒绝原因。
- 代价：spawn 一个系统进程（低频、几秒）。换来的是不必自己解析 APFS/DMG 的父子关系。
- 异步执行，结果 hop 回主线程再更新 store。

失败复查：完成回调为 false 时，调度器用「主卷路径是否仍挂载」或「整盘 BSD 名是否仍存在」判断是否标记「未弹出」。若 `diskutil` 返回 0，视为已弹出。

### 6. 菜单：独立段 + 分隔线 + 聚合行 + 每块盘一行

```
  定时退出应用  14:48                >
  将「微信」定时退出                  >
  --------------------------------------------------
  定时弹出硬盘  42:00                >
  将「Ventoy」定时弹出                >
```

- 两段之间恒有分隔线；没有可弹出磁盘时整段连同分隔线消失（`refreshMenu()` 用返回值决定是否加分隔线，和状态段的做法一致）。
- 聚合行展示最早到期磁盘计时器的剩余时间，子菜单承载清单 / 添加入口 / 全部取消，与定时退出应用同构；0 个计时器时退化为直接开面板的单行。
- 每块可弹出磁盘一行快捷入口；已有计时器时行尾显示剩余时间（与 App 的快捷行不同，这里允许，因为聚合行与快捷行回答的是不同问题）。
- 段内排序按磁盘显示名。

替代方案"一块盘两行去掉聚合行"（行即状态）被否决：App 的目标集合不可枚举，磁盘可枚举，若两边都用"行即状态"，App 那边永远无法做到，统一只是表象。

### 7. 复用现有 tick 与刷新预算

- 到点判定继续挂在 2 秒 `authorizationTimer` 上，零新增唤醒。
- 菜单打开期间的 1 秒刷新同时更新聚合行与各磁盘行；关闭即释放。
- 磁盘枚举只在 `refreshMenu()` 与打开面板时做，不做常驻监听。插拔磁盘后下一次打开菜单即可看到变化。

### 8. 总开关与授权

- 总开关关闭时磁盘段整体置灰、不展开；关闭动作沿用现有的确认流程，确认后连同磁盘计时器一起取消（不需要第二个确认）。
- 定时弹出硬盘属于 Pro 功能，沿用 `license.isEntitled` 与 `（Pro）` 后缀；试用到期不删除计时器。
- 不需要新增系统权限：DiskArbitration 在非沙盒应用中可用，卸载/弹出不触发 TCC。

### 9. 时长预设改为动作中性文案

现在写的是「5 分钟后退出」，弹盘需要「5 分钟后弹出」。两套文案会翻倍且容易漏。改为「5 分钟」「15 分钟」「30 分钟」「1 小时」「2 小时」，两个子菜单共用；父级行已经说明点下去会发生什么。

### 10. 排除范围与 DMG

- 只处理 `volumeIsEjectable == true` 的本地卷。
- 排除启动盘、App 自身所在卷、家目录所在卷：用一个"受保护路径前缀"集合判断。
- 虚拟挂载（OrbStack、Qrypt 等）因 `volumeIsLocal == false` 或不可弹出被自然排除。
- DMG 的整盘媒体名会变成产品名，可能冒出一行无意义的入口。计划用 `DeviceProtocol == "Disk Image"` 排除，**但这条未在实机验证**（当前没有挂载的镜像），列入 Open Questions。

### 11. 立即弹出

每块磁盘的快捷子菜单顶部放一条「立即弹出」，直接调用同一个 `DiskEjector`，不经过调度器、不写任何计时器记录。失败时弹一个单按钮提示（`NSAlert`），说明磁盘仍被占用——这是唯一会主动打断用户的地方，因为立即弹出发生在用户刚点完的几秒内，必须给出结果。

顺序：立即弹出 → 分隔线 → 5/15/30/60/120 → 自定义… →（有计时器时）分隔线 + 取消定时弹出。取消放在最后，避免和"立即弹出"挨得太近而误点。

### 12. 未完成任务的可见性

失败发生在用户可能已经离开的时候，所以不能只靠"打开菜单才能看到的那一行"。

- **菜单栏角标**：只要存在 `refused` 条目，就在模板图标右下角画一个 6pt 圆点。模板图只用 alpha，深浅色自动适配；不引入彩色或额外图标资源。
- **菜单状态段**：复用现有的条件状态段，最前面加一行「N 个任务未完成：微信未退出、Ventoy 未弹出」，超过两个折叠成「等 N 个」。
- **不做系统通知**：失败后果是"任务没完成"，不是数据损坏；为它引入通知权限，对一个菜单栏工具来说信任成本过高。若后续确有需求，再加可开关的选项。
- 标记与提示同时覆盖应用与磁盘两类 `refused`，因为它们来自同一个状态机。

## Risks / Trade-offs

- **[卸载成功但弹出失败会被误判为"目标消失"]** → 复查改用整盘 BSD 名是否仍存在，而不是主卷路径；重试只补弹出。
- **[多卷盘中任一卷被占用，整盘都弹不出去]** → 明确报「未弹出」并给出重试；不做部分成功。用户释放占用后可重试。
- **[同名磁盘无法区分]**（两块同型号、卷都无名） → 接受；tooltip 带 BSD 名便于识别，不做额外 UI。
- **[每次打开菜单都枚举磁盘]** → 枚举是几个系统调用，成本可忽略；换来零常驻监听与零插拔通知。
- **[菜单随硬件变化]** → 插拔后行出现/消失是预期行为；若拔盘时菜单正好打开，行会保留到下次打开（与计时器条目消失的处理一致，均不在 menu tracking 期间增删）。
- **[数据模型迁移写坏导致 App 计时器丢失]** → 新版首次启动时读旧键并写入新键；解码失败则丢弃旧数据、保持空列表，绝不阻塞关窗退出；迁移逻辑放进测试。
- **[DMG 入口噪音]** → 待验证的 `DeviceProtocol` 过滤；若不可靠，退化为"允许出现但不会自动选中"，并在 release notes 说明。
- **[弹出时某些 App 报错]**（如编辑器打开着盘内文件） → 这是 macOS 的正常拒绝，按失败处理，不重试、不弹窗。

## Migration Plan

1. 启动时读取 `schedule.timers`（`[QuitTimer]`），转换为 `[ScheduledAction]`（`target = .application(bundleID:)`），写入 `schedule.actions`，成功后删除旧键。
2. 新键不存在且旧键也不存在 → 正常空状态。
3. 解码失败 → 丢弃，写一条日志；不删除旧键，便于回滚排查。
4. 回滚：旧版本不读 `schedule.actions`，App 计时器可能"消失"，但不影响关窗退出与规则。
5. 验证顺序：纯函数用例 → 迁移用例 → 手工验证磁盘枚举、命名、弹出成功、占用失败、拔盘消失、总开关联动、中英文。

## Open Questions

- ~~DMG 能否用 `DeviceProtocol == "Disk Image"` 排除~~ —— 已实测否定：整盘报的是 `Virtual Interface`，与 APFS 合成容器无法区分。既然 `diskutil eject` 对磁盘映像工作正常，首版决定**不排除 DMG**：它作为可弹出目标出现，用户可以正常定时弹出；代价是挂载的安装镜像会多占一行菜单。
- 多卷盘在"部分卷卸载成功、剩余卷失败"时，是否需要在「未弹出」行里说明是哪个卷占用；首版只给统一失败态，若实际反馈足够痛再加。
