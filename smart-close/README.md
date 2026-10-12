# 智能退出

一个 macOS 菜单栏 App：点击窗口左上角的红色关闭按钮时，如果这是该 App 最后一个标准窗口，就请求该 App 正常退出；否则保留原本的关闭窗口行为。即使被点击的窗口所属 App 当时不是前台 App，也按同样规则处理。例外列表中的 App 始终只关闭窗口。

## 构建与运行

需要 macOS 13+ 和 Xcode。在本目录执行；如果“智能退出”已在运行，请先从菜单栏退出旧实例：

构建并生成可拖入“应用程序”的 DMG：

```sh
./package-dmg.sh
```

产物为 `build/智能退出.dmg`。脚本会在 DMG 暂存副本上尝试移除 `com.apple.quarantine`，不会修改构建目录中的 `.app`。下载后的 DMG 仍可能被浏览器或 macOS 标记隔离；若首次打开被拦截，可将 App 拖到“应用程序”后执行：

```sh
xattr -rd com.apple.quarantine "/Applications/智能退出.app"
```

该操作只适用于确认来源可信的未签名 App，也不会代替开发者签名或公证。

## GitHub Release

推送以 `v` 开头的标签（例如 `v1.0.0`）会自动在 GitHub Actions 的 macOS runner 上构建 DMG，并创建对应的 GitHub Release，将 `智能退出.dmg` 作为下载附件。重新运行同一标签的工作流会替换该 Release 中的 DMG 附件。

```sh
git tag v1.0.0
git push origin v1.0.0
```

当前 Release 产物未签名和公证；分发给用户时，首次打开可能需要按上面的说明移除隔离属性。

```sh
xcodebuild -project SmartClose.xcodeproj -scheme SmartClose -configuration Release -derivedDataPath build build
open "build/Build/Products/Release/智能退出.app"
```

构建产物位于项目内的 `build/Build/Products/Release/智能退出.app`，`build/` 已被 Git 忽略。也可以在 Xcode 中打开 `SmartClose.xcodeproj`，选择 `SmartClose` scheme 运行。

如需安装到“应用程序”，先从菜单栏退出正在运行的旧版“智能退出”，再执行：

```sh
ditto "build/Build/Products/Release/智能退出.app" "/Applications/智能退出.app"
open "/Applications/智能退出.app"
```

首次运行后，在菜单栏点击“智能退出”，按提示到系统设置授予“辅助功能”权限。未授权时，“启用智能退出”和“⌘W 智能退出”会显示为灰色；点击会提示授权，不会更改开关状态。App 检测到授权后会自动重新启动并开启监听；如果系统未能启动新实例，当前实例会直接尝试开启监听。菜单中可以暂停、管理例外应用、将当前 App 加入例外、设置登录时启动，并通过“关于智能退出”查看版本、权限说明及项目仓库链接。

菜单栏中的“⌘W 智能退出”可单独开启，默认关闭。开启后快捷键仍先由目标 App 正常处理；只有原本聚焦的是最后一个标准窗口，且该 App 的窗口已关闭或从屏幕消失时，才请求它正常退出。这样也能处理 Discord 一类将窗口隐藏、但仍保留辅助功能窗口对象的 App。关闭浏览器普通标签页、保存对话框阻止关闭或窗口信息不可读取时不会额外退出。若系统要求输入监控权限，菜单会显示授权入口；键盘监听无法启动时，鼠标关闭按钮功能仍可继续工作。

应用包名称为 `智能退出.app`。应用程序图标和菜单栏图标为直接生成的 PNG 资源，位于 `SmartClose/Assets.xcassets`；图标尺寸由这些主图缩放适配。不要运行旧版 `Assets/GenerateIcons.swift`，它会覆盖当前图标。

此工程没有启用 App Sandbox，因为沙盒应用无法通过 `NSRunningApplication.terminate()` 请求其他 App 退出。向普通用户分发时，需在 Xcode 配置开发者签名并对 App 进行公证。

## 行为边界

- 支持红色关闭按钮和可选的 `⌘W`，不处理应用菜单里的“退出”。
- 无法确定点击目标、窗口类型、标准窗口数量或辅助功能信息时，点击由目标 App 原样处理。
- 退出使用正常退出请求，目标 App 的未保存文档提示由目标 App 自己处理。
- 部分 App 的辅助功能元素不完整，可能保持系统默认的关闭窗口行为。

跨 Space 和全屏窗口的判定依据、诊断命令及后续稳定性改进顺序，见 [窗口退出判定计划](window-detection-plan.md)。

## 规则测试

```sh
mkdir -p build/Tests
swiftc SmartClose/RuleStore.swift Tests/main.swift -o build/Tests/smart-close-rules-test
build/Tests/smart-close-rules-test
```
