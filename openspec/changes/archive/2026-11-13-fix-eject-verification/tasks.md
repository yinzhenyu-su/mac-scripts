## 1. 判定与清理

- [x] 1.1 `isTargetStillPresent` 对磁盘改为只看卷是否仍挂载，设备节点残留不再算「仍存在」，验证：Ventoy 成功后不再出现「未弹出」
- [x] 1.2 `tick` 增加 `refused` 清理：磁盘卷已卸载或应用已退出时移除条目，验证：未弹出后拔盘/退出应用，状态行自动消失
- [x] 1.3 删除不再使用的 `DiskCatalog.isDiskPresent`，验证：全项目无残留引用

## 2. 验证

- [x] 2.1 调度器单测覆盖「refused 目标消失后自动移除」，验证：`./build/Tests/neatquit-rules-test` 通过
- [x] 2.2 真实 Ventoy 复测：创建倒计时规则，确认弹出成功后菜单不显示未弹出、状态行不残留（需要重新插拔 U 盘）

## 3. 文档与发布

- [x] 3.1 更新 v1.6.1 中英文更新日志，说明误报修复，验证：文案与行为一致
- [x] 3.2 运行 `xcodebuild ... build` 与 `openspec validate fix-eject-verification --strict`，验证：构建与规格校验通过
