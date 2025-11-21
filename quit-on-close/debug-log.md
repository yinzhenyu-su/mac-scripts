# BTT/AppleScript “智能关闭”脚本问题排查记录

## 1. 初始问题

用户希望通过 BetterTouchTool (BTT) 运行一个 AppleScript 脚本 (`close-window.applescript`)，以实现“智能关闭”功能：

- 如果当前应用只有一个窗口，则退出整个应用。
- 如果当前应用有多个窗口，则只关闭当前窗口。

但在实际使用中发现，当在目标应用（如 `Antigravity`）中触发脚本时，脚本实际操作的却并非当前应用，导致行为不符合预期。

## 2. 排查过程

我们围绕“如何让脚本正确识别目标应用”这一核心，进行了一系列由浅入深的排查和尝试。

### 第一阶段：怀疑“焦点竞态”问题

这是 macOS 自动化中常见的问题，即 BTT 触发脚本的瞬间，系统焦点可能在 BTT 自身上，导致脚本识别错误。

- **尝试 1：加入 `delay 0.2`**
  - **操作**：在脚本获取前台应用信息前，加入 0.2 秒的短暂延迟，期望焦点能返回原始应用。
  - **结果**：问题依旧。日志显示，脚本不再识别 BTT，但错误地识别为了 VSCode (`com.microsoft.VSCode`)。

- **尝试 2：增加延迟至 `delay 0.5`**
  - **操作**：将延迟增加至 0.5 秒，排除延迟时间不足的可能性。
  - **结果**：问题依旧。这证明“焦点竞态”不是问题的根本原因。

### 第二阶段：尝试让 BTT 直接“告知”脚本目标应用

既然脚本自己“猜”不对，我们尝试让 BTT 在触发时，把目标应用的身份信息直接传递给脚本。

- **尝试 3：BTT 传递启动参数 (`on run`)**
  - **操作**：修改脚本，将其核心逻辑包裹在 `on run argv` 处理程序中，并配置 BTT 的“启动参数”传递 `{bundleIdentifier}`。
  - **结果**：失败。用户截图显示，其 BTT 版本/配置界面没有“启动参数”输入框，而是“Async function to call (optional)”。

- **尝试 4：BTT 调用具名函数 (`on handleClose`)**
  - **操作**：再次修改脚本，将逻辑包裹在具名函数 `on handleClose(bundleID)` 中，并指导用户在 BTT 的“Async function to call”中填入 `handleClose('{bundleIdentifier}')`。
  - **结果**：失败。用户反馈此方法不工作，参数未能成功传递。

### 第三阶段：脚本主动从 BTT 查询信息

根据用户提议，我们采用了最可靠的方式：脚本运行时，主动向 BTT 查询所需变量。

- **尝试 5：脚本主动查询 `BTTActiveAppBundleIdentifier`**
  - **操作**：移除了所有函数包裹，将脚本改回顶层执行。在脚本开头，加入 `tell application "BetterTouchTool" to get_string_variable "BTTActiveAppBundleIdentifier"` 代码，主动获取 Bundle ID。同时，清空 BTT 中的“Async function to call”配置。
  - **结果**：**取得了决定性进展**。日志显示，脚本**成功**从 BTT 获取了正确的 Bundle ID `com.google.antigravity`。

## 3. 最终诊断与问题解决

尽管脚本已经拿到了完全正确的 Bundle ID，但在此前，后续行为依然错误。通过添加更详细的诊断日志，我们最终锁定并解决了问题根源。

### 关键日志证据（已解决）

以下是执行 `lsregister -kill -r -domain local -domain system -domain user` 并重启 Mac 后，脚本的运行日志：

```csv
2025-11-21 14:35:29 | 🚀 脚本开始执行...
2025-11-21 14:35:29 | 👉 BTT 变量 BTTActiveAppBundleIdentifier: com.google.antigravity
2025-11-21 14:35:29 | 🔍 正在用 ID 'com.google.antigravity' 查询 System Events...
2025-11-21 14:35:29 | 🔍 查找到 1 个匹配进程。
2025-11-21 14:35:29 | 🔍 直接读取 frontProcess 对象的名字: Electron
2025-11-21 14:35:29 | 🔍 直接读取 frontProcess 对象的 Bundle ID: com.google.antigravity
2025-11-21 14:35:29 | 📱 目标应用信息: Electron (ID: com.google.antigravity, Version: Not Available) Path: /Applications/Antigravity.app
2025-11-21 14:35:29 | 🪟 标准窗口数量: 2
2025-11-21 14:35:29 | ❌ 判定: 还有其他窗口 (2个)，仅关闭当前
2025-11-21 14:35:29 | 👋 执行动作: Close Window
2025-11-21 14:35:30 | ✅ 方法1: 点击关闭按钮成功
2025-11-21 14:35:30 | 🏁 脚本结束
```

这份日志的关键点在于：

- 脚本成功请求 `System Events` 服务查找 `bundle identifier` 为 `com.google.antigravity` 的应用进程。
- `System Events` 服务**正确地返回了 Bundle ID 为 `com.google.antigravity` 的进程信息**。
- 尽管该进程的名字仍显示为 `Electron`（这是 Electron 应用的常见特性），但这并不影响脚本的精确识别和操作，因为我们所有的关键逻辑都基于其独特的 Bundle ID。

### 根本原因及解决方案

问题的根源在于 **macOS 的 `System Events` 服务与 `Antigravity` 应用之间的元数据关联在系统中出现了混淆**。这很可能与 macOS 的 Launch Services 数据库有关。

通过执行以下命令重建 Launch Services 数据库并重启 Mac，成功清除了系统层面的错误缓存和关联，使 `System Events` 能够正确地识别和索引 `Antigravity` 应用：

```bash
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -kill -r -domain local -domain system -domain user
```

## 4. 结论与后续建议

- **最终结论**：问题已解决！`close-window.applescript` 脚本现在能够通过 BTT 正确识别 `Antigravity` 应用，并根据窗口数量进行“智能关闭”或“退出应用”的操作，行为符合预期。

- **后续建议**：
    1. **清理脚本**：既然问题已解决且脚本运行正常，建议移除脚本中为诊断目的添加的额外日志代码（以 `🔍` 开头的几行），以使脚本更简洁，日志输出更精炼。
    2. **持续监控**：如果未来再次出现类似应用识别问题，可以再次尝试重建 Launch Services 数据库。
