# Playwright CLI 截图

本流程只负责 Web 项目的自动浏览器操作和截图落盘。截图必须成为本地图片文件，才能由 `capture_screenshots.py` 生成清单并交给 OfficeCLI 插入操作手册。

## 固定版本与安装门禁

- 固定验证版本：`@playwright/cli@0.1.20`。
- 要求 Node.js 18 或更高版本。
- 官方仓库：https://github.com/microsoft/playwright-cli
- 先运行本 skill 的 `scripts/check_playwright_cli.py`，同时检查系统 PATH 和当前 npm 的全局可执行目录，并实际执行 `--version`。不得仅凭 `package.json` 或安装清单推断可用。
- 命令缺失或版本不等于 `0.1.20` 时必须停止并询问用户是否安装或切换固定版本，不得静默安装或升级。
- 用户同意后可执行 `npm install -g @playwright/cli@0.1.20`。该 CLI 是外部工具，不复制到本 skill，也不写入被分析项目的 `package.json`。
- 优先使用本机已安装的 Chrome：`--browser=chrome`。只有 Chrome 不可用且用户同意时，才按 Playwright 提示安装浏览器运行时。

检查命令：

```bash
<PYTHON> "<SKILL_DIR>/scripts/check_playwright_cli.py" \
  --out 软件著作权申请资料/截图工具检查.json
```

检查成功后必须读取 JSON 的 `executable`，后续所有命令都调用这个绝对路径，不要重新假设裸命令 `playwright-cli` 一定在 PATH。解析顺序是：系统 PATH，然后是 `npm prefix -g` 对应平台的标准全局可执行目录。这个规则与具体 Node 安装器或版本管理器无关，不修改系统 PATH，也不把工具复制进项目。

安装后立即重新运行检查，无需重启 Codex。只要全局 npm 目录中的命令能实际返回固定版本，就继续截图；仍不可用时报告检查 JSON 中的实际错误，让用户选择修复环境或改为自行截图。

## 截图前准备

1. 从已确认的 `草稿/业务理解.json` 的 `manual_modules`、项目路由和操作手册草稿中确定截图页面、顺序与需要呈现的交互状态。不要猜测不存在的路由或功能。
2. 根据项目已有脚本启动开发或预览服务，读取实际监听地址。长时间运行的服务必须放入受管理的后台会话或隐藏后台进程，保存 stdout/stderr；不得用前台阻塞命令等待 Vite、Next.js 等开发服务器退出。最多等待 60 秒出现就绪地址，进程提前退出则读取错误日志并停止。不要固定假设端口，也不要为截图改写业务代码。
3. 创建 `软件著作权申请资料/截图原始/`。旧截图可能属于上一次运行；覆盖或清理前先确认它们是否仍被当前截图清单引用，不得误删用户文件。
4. 为当前项目使用稳定且唯一的会话名，例如 `softcopyright-<项目短名>`。同一次截图任务始终复用该会话。
5. 根据软件实际布局选择一个固定视口，并在整组截图中保持一致。普通 Web 后台可使用 `1440×900`；面向 1080p 大屏设计的项目使用 `1920×1080`。

## 基本命令

下面的 `<PLAYWRIGHT_CLI>` 必须替换为 `截图工具检查.json` 的 `executable` 绝对路径；其他尖括号也必须替换为真实值。路径包含空格时必须加引号。

```bash
<PLAYWRIGHT_CLI> -s=<会话名> open <页面URL> --browser=chrome
<PLAYWRIGHT_CLI> -s=<会话名> resize <宽度> <高度>
<PLAYWRIGHT_CLI> -s=<会话名> snapshot
<PLAYWRIGHT_CLI> -s=<会话名> goto <页面URL>
<PLAYWRIGHT_CLI> -s=<会话名> screenshot --filename="<绝对路径或工作区相对路径>/01-首页.png"
```

`open` 默认使用无头浏览器。只有用户需要观察或接管过程时才加 `--headed`；是否显示窗口不影响截图必须写入本地文件的要求。

需要呈现交互状态时，先用 `snapshot` 获取当前页面引用，再通过 `click`、`fill`、`select`、`hover`、`press` 等命令完成真实操作。每次页面或状态变化后重新取得快照，不复用过期引用。例如：

```bash
<PLAYWRIGHT_CLI> -s=<会话名> snapshot
<PLAYWRIGHT_CLI> -s=<会话名> click <元素引用>
<PLAYWRIGHT_CLI> -s=<会话名> screenshot --filename="<输出目录>/02-操作结果.png"
```

## 截图质量与命名

- 按操作手册模块顺序使用数字前缀：`01-首页.png`、`02-查询结果.png`、`03-设置页面.png`。
- 默认截取实际视口，不生成纵向过长、缩小后无法阅读的整页长图。确需展示页面下方内容时，滚动或操作到目标区域后单独截图。
- 截图前确认页面已完成加载，关键文字、图表和操作结果可见，不保留加载动画、调试面板、浏览器权限提示或与手册无关的通知。
- 对弹窗、下拉菜单、悬浮提示等瞬时状态，先触发状态并重新确认页面，再立即截图。
- 不通过修改 DOM、伪造接口响应或注入展示数据来制造项目不存在的功能。测试数据或项目自带演示数据可以正常展示，但不得把伪造状态写入手册。
- 每次截图命令后检查目标文件确实存在、扩展名受支持且文件大小大于 0。仅在对话中看到图片不算成功。

## 生成截图清单

所有自动截图完成后运行：

```bash
<PYTHON> "<SKILL_DIR>/scripts/capture_screenshots.py" \
  --input-dir 软件著作权申请资料/截图原始 \
  --out-dir 软件著作权申请资料/截图 \
  --method playwright-cli
```

检查 `截图/截图清单.json`：

- `status` 必须为 `ok`。
- `method` 必须为 `playwright-cli`。
- 顺序必须与操作手册截图预留位一致。
- 每个 `path` 必须指向存在且非空的本地图片。

完成后关闭当前会话：

```bash
<PLAYWRIGHT_CLI> -s=<会话名> close
```

如果自动截图过程中无法启动项目、无法打开页面、浏览器不可用或图片不能落盘，停止并报告具体错误。用户可以修复后重试、改为自行截图，或明确选择暂时跳过截图并保留预留位。
