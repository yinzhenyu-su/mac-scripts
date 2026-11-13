---
name: macos-app-ui-capture
description: Capture real NeatQuit macOS app UI screenshots in Chinese and English for docs, README or website assets. Use when menu bar, About, settings or version screenshots need to be created or refreshed, including permission-safe local builds, window capture, cropping and WebP export.
---

# NeatQuit 界面截图采集

从真实运行的应用窗口采集截图，输出中文/英文菜单、关于窗口等素材。只负责「采集与导出」；网站路径、说明文字与缓存版本由 `bgm.fun` 的 `neatquit-site-release` skill 完成。

## 输出约定

| 场景 | 建议文件 | 尺寸 |
| --- | --- | --- |
| 中文菜单 | `neatquit-menu.webp` | 约 492 × 610（按内容裁剪） |
| 中文关于 | `neatquit-about.webp` | 880 × 1104 |
| 英文菜单 | `neatquit-menu-en.webp` | 约 574 × 610（按内容裁剪） |
| 英文关于 | `neatquit-about-en.webp` | 880 × 1104 |
| 安装窗口 | `neatquit-install*.webp` | 720 × 320 |

菜单保留透明阴影区域；关于窗口保留标准标题栏和窗口圆角。

菜单包含六段：状态、全局配置、辅助退出、定时退出应用、磁盘弹出、应用命令。高度会随待执行任务数量变化，上面的尺寸只是参考，必须按实际内容边界裁剪，不要沿用旧版固定参数。

## 1. 准备截图构建

优先使用与目标发布版本一致的代码：

```sh
cd ~/Code/github/mac-scripts/neatquit
xcodebuild -project NeatQuit.xcodeproj -scheme NeatQuit -configuration Release \
  -derivedDataPath build \
  MARKETING_VERSION=X.Y.Z CURRENT_PROJECT_VERSION=<build> build
```

### 需要辅助功能授权时

菜单截图若要显示「已启用」状态，应用必须已获得辅助功能权限。新 Bundle ID 默认没有授权，可以在**仅用于截图**的构建中临时沿用旧 Bundle ID（该 ID 已有授权）：

```sh
xcodebuild -project NeatQuit.xcodeproj -scheme NeatQuit -configuration Release \
  -derivedDataPath build \
  MARKETING_VERSION=X.Y.Z CURRENT_PROJECT_VERSION=<build> \
  PRODUCT_BUNDLE_IDENTIFIER=com.yinzhenyu.smartclose build
```

注意：这个构建只用于截图，不要发布；界面与正式版本一致，只是 Bundle ID 不同。

## 2. 重启为截图实例

先退出同 Bundle ID 的正在运行实例：

```sh
# 旧 Bundle ID 的截图构建
osascript -e 'tell application id "com.yinzhenyu.smartclose" to quit'
# 正式 Bundle ID
osascript -e 'tell application id "fun.bgm.neatquit" to quit'
```

启动截图构建：

```sh
APP="$HOME/Code/github/mac-scripts/neatquit/build/Build/Products/Release/智能退出.app"

# 中文（跟随系统，或显式指定）
nohup "$APP/Contents/MacOS/智能退出" -AppleLanguages "(zh-Hans)" -AppleLocale "zh_CN" >/tmp/nq-zh.log 2>&1 &

# 英文
nohup "$APP/Contents/MacOS/智能退出" -AppleLanguages "(en)" -AppleLocale "en_US" >/tmp/nq-en.log 2>&1 &
```

`-AppleLanguages` 只有在应用包内存在对应 `.lproj` 时才生效。确认：

```sh
ls -d "$APP/Contents/Resources/en.lproj" "$APP/Contents/Resources/zh-Hans.lproj"
```

## 3. 窗口列表辅助脚本

```swift
// /tmp/winlist.swift
import CoreGraphics
import Foundation

let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]
for w in list {
    let owner = w[kCGWindowOwnerName as String] as? String ?? "?"
    let name = w[kCGWindowName as String] as? String ?? ""
    let layer = w[kCGWindowLayer as String] as? Int ?? 0
    let id = w[kCGWindowNumber as String] as? Int ?? 0
    let b = w[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
    print("\(id) layer=\(layer) owner=\(owner) name=\(name) bounds=\(b["X"] ?? 0),\(b["Y"] ?? 0),\(b["Width"] ?? 0)x\(b["Height"] ?? 0)")
}
```

运行：`swift /tmp/winlist.swift`

## 4. 采集菜单

```sh
# System Events 中的进程名可能是「智能退出」，窗口 owner 在英文下显示 Neat Quit
# 若进程名不匹配，先用 `get name of every process` 确认
osascript -e 'tell application "System Events" to tell process "智能退出" to click menu bar item 1 of menu bar 1'

# 菜单是 layer=101 的独立窗口，立即取 id
ID=$(swift /tmp/winlist.swift | grep 'layer=101' | grep 'owner=Neat Quit' | awk '{print $1}' | head -1)
screencapture -x -o -l"$ID" /tmp/menu-en.png
```

- 菜单窗口坐标可能为负（位于屏幕上方），属于正常现象
- 若 `screencapture` 报 `could not create image from window`，重新点击菜单并立刻重新取 id
- 不要截整屏：会带入桌面、其他窗口和个人信息

## 5. 采集关于窗口

```sh
osascript -e 'tell application "System Events" to tell process "智能退出" to click menu item "About Neat Quit" of menu 1 of menu bar item 1 of menu bar 1'

ID=$(swift /tmp/winlist.swift | grep 'owner=Neat Quit' | grep 'name=About Neat Quit' | awk '{print $1}' | head -1)
screencapture -x -o -l"$ID" /tmp/about-en.png
```

中文对应菜单项为「关于智能退出」，窗口名为「关于智能退出」。

关闭窗口：`click button 1 of window "About Neat Quit"`。

## 6. 裁剪与导出

菜单截图包含透明边距，需要裁剪到内容。菜单高度会随任务数量变化，先量原图与内容边界再裁，不要沿用旧参数：

```sh
# 先看原图尺寸，再按实际内容边界填写 W:H:X:Y
sips -g pixelWidth -g pixelHeight /tmp/menu-zh.png
ffmpeg -y -loglevel error -i /tmp/menu-zh.png -vf "crop=W:H:X:Y" /tmp/menu-zh-crop.png

# 英文菜单宽度会随文案变化，同样按内容边界裁剪
sips -g pixelWidth -g pixelHeight /tmp/menu-en.png
ffmpeg -y -loglevel error -i /tmp/menu-en.png -vf "crop=W:H:X:Y" /tmp/menu-en-crop.png

# 关于窗口保留完整尺寸
cp /tmp/about-en.png /tmp/about-en-final.png
```

转 WebP：

```sh
cwebp -q 85 -alpha_q 90 -m 6 /tmp/menu-zh-crop.png -o neatquit-menu.webp
cwebp -q 85 -alpha_q 90 -m 6 /tmp/menu-en-crop.png -o neatquit-menu-en.webp
cwebp -q 85 -m 6 /tmp/about-zh.png -o neatquit-about.webp
cwebp -q 85 -m 6 /tmp/about-en.png -o neatquit-about-en.webp
```

检查尺寸与文件大小：

```sh
for f in *.webp; do printf "%s " "$f"; sips -g pixelWidth -g pixelHeight "$f" | tail -2 | tr '\n' ' '; ls -lh "$f" | awk '{print $5}'; done
```

## 7. 隐私审查

提交前逐张确认：

- 不包含用户名、主目录路径、桌面壁纸、Dock、通知、浏览器标签或其他窗口
- 菜单中的「加入例外 / Add to Exceptions」或「设为自动退出 / Set to Auto Quit」只出现通用应用名
- 菜单与磁盘面板中的磁盘名使用演示卷（例如 Demo / DemoDisk），不要展示真实 U 盘、备份盘或加密卷的名称
- 关于窗口的致谢名单是应用内公开显示的内容
- 不展示「应用规则」窗口：其中包含本机安装的第三方应用列表
- 不截整屏，只截目标窗口图层

## 8. 恢复现场

```sh
# 退出截图构建
osascript -e 'tell application id "com.yinzhenyu.smartclose" to quit'
# 重新启动日常安装版
open "/Applications/智能退出.app"
```

如果使用过临时语言偏好或临时 Bundle ID，确认没有写入持久设置：

```sh
defaults read com.yinzhenyu.smartclose AppleLanguages 2>/dev/null || true
```

## 9. 交付给网站

把导出的 WebP 交给 `bgm.fun` 的 `neatquit-site-release` skill：

- 复制到 `dist/assets/`
- 更新 HTML 的 `width`、`height`、`alt` 与版本说明
- 图片 URL 增加新的 `?v=YYYYMMDD-HHMM`，避免 30 天缓存
- 更新 `docs/screenshots.md` 的版本、尺寸、来源与隐私审查记录

## 常见问题

| 现象 | 处理 |
| --- | --- |
| 菜单是中文，切不到英文 | 应用包缺少 `en.lproj`；先构建包含本地化的版本 |
| 菜单显示「需要辅助功能权限」 | 截图构建的 Bundle ID 没有授权；改用已授权的旧 Bundle ID 构建 |
| 找不到菜单窗口 | 菜单未打开或进程名不对；确认 `layer=101`，重新点击并立即取 id |
| `screencapture -l` 失败 | 窗口 id 已变化；重新列窗口后立刻截图 |
| 截图全黑/空白 | 终端缺少屏幕录制权限；在系统设置中授权终端 |
| 关于窗口版本号是旧值 | 构建时 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` 未覆盖 |
