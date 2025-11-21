# macOS 常用 AppleScript 自动化脚本

这个项目用于存放 macOS 上一些常用的 AppleScript 自动化脚本，旨在提升日常操作效率。每个脚本都放在独立的文件夹中，方便管理和查找。

## 脚本列表

### `quit-on-close` (智能关闭/退出应用)

`quit-on-close` 脚本提供了一个智能化的窗口管理方案。当你在某个应用中按下关闭窗口的快捷键时：

- 如果该应用仅剩一个窗口，脚本将直接退出整个应用。
- 如果该应用仍有多个窗口，脚本将仅关闭当前窗口。
它巧妙地解决了 macOS `System Events` 服务与某些应用（如基于 Electron 的应用）在识别进程和窗口时的兼容性问题，特别是通过主动从 BetterTouchTool (BTT) 获取 Bundle ID，并修复了 `System Events` 内部数据混淆的难题，确保了精确操作。

[查看 `quit-on-close` 脚本详细排查记录](quit-on-close/debug-log.md)
