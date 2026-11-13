## Why

Ventoy 实际已经弹出成功，菜单却显示「1 个任务未完成：Ventoy 未弹出」。原因是 `diskutil eject` 返回成功时卷已经卸载，但 DiskArbitration 的设备节点还会残留几秒；旧的复查把「设备仍在」当成「未弹出」，产生误报。误报的条目还会一直留在状态行，直到重启或手动重试。

## What Changes

- 磁盘弹出是否成功，以「卷是否仍挂载」为准；设备节点短暂残留 MUST NOT 导致标记「未弹出」。
- 处于「未弹出」状态的任务，在目标不再存在时（磁盘已卸载 / 应用已退出）自动移除，避免状态行卡住。
- 删除不再使用的 `isDiskPresent` 辅助。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `scheduled-disk-eject`: 新增「弹出成功的判定与残留清理」要求，规定以卷卸载为成功标准，并自动清理目标已消失的未完成任务。

## Impact

- **代码**：`NeatQuitApp.isTargetStillPresent`、`ScheduledActionScheduler.tick`、`DiskCatalog`。
- **测试**：调度器增加「未弹出目标消失后自动移除」用例；另需用真实可移除磁盘复测一次成功弹出。
- **兼容性**：不改变数据结构与已有规则。
