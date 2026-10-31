# CI 自动签名与公证（Developer ID）

打 `v*` tag 时，GitHub Actions 会：**构建 → Developer ID 签名 → 公证（notarize）→ staple → 校验 → 发布 Release**。
用户下载 DMG 双击即可打开，**不再需要 `xattr -rd com.apple.quarantine`**。

> macOS 站外分发不需要描述文件（provisioning profile），只需要 **Developer ID Application 证书 + 公证**。
> 前提：Apple Developer Program（$99/年）会员有效。

---

## 一、一次性准备（在 Mac 上做）

### 1. 生成 Developer ID Application 证书

- Xcode → Settings → Accounts → 选中你的 Team → **Manage Certificates…**
- 左下 **+** → **Developer ID Application** → 生成后会自动装进钥匙串
  （也可以在 developer.apple.com → Certificates → **+** → *Developer ID Application*，用 CSR 生成后下载双击安装）
- 校验：
  ```bash
  security find-identity -v -p codesigning | grep "Developer ID Application"
  # "Developer ID Application: Yin Zhenyu (ABCDE12345)"
  ```
  括号里的 10 位就是 **TEAM_ID**。

### 2. 导出 .p12（证书 + 私钥）

钥匙串访问 → 找到上面那张证书 → 展开 → 同时选中 **证书和私钥** → 右键 *导出 2 项…* → 格式 **Personal Information Exchange (.p12)** → 设一个密码（记下来）。

```bash
openssl base64 -A -in DeveloperID.p12 -out DeveloperID.p12.b64   # 单行 base64
```

### 3. 建 App Store Connect API Key（公证用）

App Store Connect → **Users and Access** → **Integrations** → *App Store Connect API* → **+**
- 名称任意，权限选 **Developer**（App Manager 也行，Developer 足够）
- 记下 **Key ID** 和 **Issuer ID**，下载 `.p8`（**只能下一次**）

```bash
openssl base64 -A -in AuthKey_XXXXXXXXXX.p8 -out AuthKey.p8.b64
```

---

## 二、配置 GitHub Secrets

### 方式 A：一条命令（推荐）

```bash
# 先确保 gh 已登录，且当前目录在仓库里
./scripts/setup-signing-secrets.sh DeveloperID.p12 AuthKey_XXXXXXXXXX.p8 \
  --issuer xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

脚本会：验证 p12 里确实是 **Developer ID Application**（临时钥匙串，顺带校验密码）→ 从证书 CN 解析 `SIGN_IDENTITY` / `TEAM_ID` → 写入 8 个 secret（base64 通过管道直传，**磁盘不留临时文件**）→ 逐个校验。
Key ID 从 `AuthKey_<KeyID>.p8` 文件名自动取。

### 方式 B：手动（没有 gh 时用网页也行）

```bash
gh secret set MACOS_CERT_P12      < DeveloperID.p12.b64      # 证书（base64）
gh secret set MACOS_CERT_PASSWORD --body '导出 p12 时设的密码'
gh secret set KEYCHAIN_PASSWORD   --body "$(openssl rand -hex 16)"   # 任意随机串，CI 内部用
gh secret set ASC_KEY_P8          < AuthKey.p8.b64            # 公证密钥（base64）
gh secret set ASC_KEY_ID          --body 'XXXXXXXXXX'
gh secret set ASC_ISSUER_ID       --body 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
gh secret set SIGN_IDENTITY       --body 'Developer ID Application: Yin Zhenyu (ABCDE12345)'
gh secret set TEAM_ID             --body 'ABCDE12345'
```

一次性核查：

```bash
gh secret list
```

> ⚠️ `.p12` 含私钥，**不要发到聊天工具/邮箱**让任何人代配；只通过 `gh secret set` 或 GitHub 网页直传。

---

## 三、发版

```bash
git tag v1.3.0 && git push origin v1.3.0
```

CI 会跑大约 **3-8 分钟**（两次公证：先 .app 再 DMG）。

本地想复现同样流程（需钥匙串里已有证书）：

```bash
cd smart-close
export SIGN_IDENTITY="Developer ID Application: Yin Zhenyu (ABCDE12345)"
export TEAM_ID=ABCDE12345
export NOTARIZE=1
export ASC_KEY_PATH="$HOME/.keys/AuthKey_XXXXXXXXXX.p8"
export ASC_KEY_ID=XXXXXXXXXX
export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
./package-dmg.sh v1.3.0 42
```

不设 `SIGN_IDENTITY` 时行为与以前一致（ad-hoc 签名）。

---

## 四、坑与注意事项

| 坑 | 说明 |
|---|---|
| `User interaction is not allowed` | 漏了 `security set-key-partition-list`（workflow 里已有） |
| `security import` 报 `SecKeychainItemImport: One or more parameters passed to a function were not valid.` | 解码后的 `.p12` 是 **0 字节**。secret 里是 `openssl base64 -A` 生成的**单行** base64，而 `openssl base64 -d` 按 1024 字符行缓冲，遇到超长单行会**静默输出 0 字节且 exit 0**。workflow 已改成 `openssl base64 -d -A`（等价可选 `base64 --decode`）；手动复现时别漏 `-A` |
| 公证报 `Invalid` / `signature is invalid` | 必须有 **Hardened Runtime**（`--options runtime`）和 **`--timestamp`**；脚本里用 `OTHER_CODE_SIGN_FLAGS` 传了 |
| 公证日志：`Sparkle.framework/.../Autoupdate` 或 `Updater.app` 不是 Developer ID 签名 / 缺时间戳 | SPM 里 Sparkle 的这些嵌套组件是官方 **ad-hoc** 签名，Xcode 只重签 `Sparkle` 本体。`package-dmg.sh` 现在会在构建后由内到外显式重签（Autoupdate → Updater.app → XPC → framework → App） |
| 公证日志：`The executable requests the com.apple.security.get-task-allow entitlement` | Xcode 默认注入调试用 entitlement。构建参数加了 `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO`，并去掉主 App 的 entitlements 重签 |
| **装完双击打不开**，崩溃日志里是 `dyld: Library not loaded: @rpath/Sparkle.framework/Versions/B/Sparkle` | 主程序缺少 `@executable_path/../Frameworks` 这条 rpath。`build.yml` 与 `package-dmg.sh` 现在都会断言它，编译/签名/公证都过但跑不起来的情况会被提前挡住 |
| 只签名不 staple | 离线用户首次打开仍会被拦；脚本对 `.app` 和 `.dmg` 都 `stapler staple` 并 `validate` |
| `.p8` 泄露 | 只能下载一次；只放 GitHub Secrets，不要进仓库 |
| 证书被 revoke | 所有用它签过的版本**新装/首次校验**都会失败，用户已装的可继续跑，但升级要换新证书 |
| 一年到期 | 证书 1 年，到期前重新生成/续费，否则 release 构建会失败 |
| **TCC 权限会失效** | 从 ad-hoc 换成 Developer ID 后签名变了，**辅助功能/输入监控等授权需要用户重新授予**（一次性）。Release notes 里要写清楚 |
| 构建号 | CI 用 `github.run_number`，天然递增；不要手动改回小的值 |
| Intel / Apple Silicon | **CI 已默认编译通用包**（`UNIVERSAL=1` → `ARCHS="arm64 x86_64"`），并在构建后 `lipo -archs` 断言两个架构都在；本地不设 `UNIVERSAL` 时只编当前架构 |
| 发布包校验 | workflow 用 `spctl -a -vvv -t exec` + `stapler validate` 双重校验，任一失败即中止（不会发出坏包） |

---

## 五、回滚

CI 只是构建产物，回滚 = 删掉/覆盖 Release 里的 DMG，或把 tag 指回旧提交重新发版。
本地 `package-dmg.sh` 不设签名相关环境变量时与旧行为完全一致。

---

## 六、Sparkle 自动更新（appcast）

自动更新走 Sparkle 2，需要在 CI 里多做两件事：给 DMG 生成 EdDSA 签名、更新并提交 `appcast.xml`。

### 6.1 生成密钥（一次性，在你 Mac 上）

```bash
curl -L -o /tmp/sparkle.tar.xz https://github.com/sparkle-project/Sparkle/releases/download/2.6.4/Sparkle-2.6.4.tar.xz
tar -xf /tmp/sparkle.tar.xz -C /tmp
/tmp/bin/generate_keys                     # 输出公钥 → 填进 Info.plist 的 SUPublicEDKey
/tmp/bin/generate_keys -x ~/sparkle-private.key   # 导出私钥文本 → 只放进 GitHub secret
gh secret set SPARKLE_ED_PRIVATE_KEY --repo yinzhenyu-su/mac-scripts < ~/sparkle-private.key
```

- 公钥可以公开；**私钥丢了就再也发不出能被老版本接受的新版本**，务必备份（密码管理器）
- `.key` 是文本文件，`gh secret set < 文件` 直接把内容存成 secret

### 6.2 CI 里发生什么

1. 下载 Sparkle 工具（版本写死在 workflow 里）
2. `sign_update --ed-key-file -` 从 `SPARKLE_ED_PRIVATE_KEY` 读私钥，对 DMG 签名
3. 从刚创建的 Release 取 body 当更新日志
4. `scripts/make-appcast.py` 合并生成 `appcast.xml`（保留最近 10 条）
5. 提交回 `master`（bot commit）

> **顺序很重要**：先上传 DMG 到 Release，再提交 appcast；反过来用户会拿到 404 的下载链接。

### 6.3 客户端配置（Info.plist）

| Key | 值 |
|---|---|
| `SUFeedURL` | `https://raw.githubusercontent.com/yinzhenyu-su/mac-scripts/master/appcast.xml` |
| `SUPublicEDKey` | `generate_keys` 输出的公钥 |
| `SUEnableAutomaticChecks` | `YES` |
| `SUScheduledCheckInterval` | `86400` |
| `SUAllowsAutomaticUpdates` | `NO`（先让用户点安装） |

> `SUFeedURL` 会被**固化进已发布的 App**：以后若改默认分支名，老版本就会 404。想彻底避免，改用 GitHub Pages 的 `https://<user>.github.io/mac-scripts/appcast.xml`（URL 不含分支名）。

### 6.4 手动验证

```bash
# 校验 appcast 里的签名与 DMG 是否匹配
echo "$SPARKLE_ED_PRIVATE_KEY" | /tmp/bin/sign_update --ed-key-file - SmartClose-v1.3.2.dmg
# 对比输出的 edSignature 与 appcast.xml 中的值
```

---

# 五、应用内更新分发（app.bgm.fun）

App 里写死的更新地址：

```
SUFeedURL = https://app.bgm.fun/appcast.xml
```

站点根目录（FTPS 的 chroot 根，也是 nginx 的 root）：

```
/opt/1panel/www/sites/app.bgm.fun/index
```

## 发版时的执行顺序

CI 里是**先传包、再改 feed**，任何一步失败都不会让用户拿到死链：

1. 构建 → 签名 → 公证 → staple
2. 发布 GitHub Release（作为备份归档）
3. 生成 appcast（`enclosure` 指向 `https://app.bgm.fun/SmartClose-<tag>.dmg`）
4. 上传 DMG 到 `.upload-<name>` → `RNFR/RNTO` 原子改名为正式名 → 用 HTTPS `Content-Length` 校验大小
5. 上传 `appcast.xml` 到临时名 → 原子改名 → 用 HTTPS 回读确认含本次版本
6. 把 appcast 提交回仓库，让仍读旧 feed（GitHub raw）的老用户也能收到

只保留最近 5 个 DMG（`KEEP_DMGS`），更旧的自动删除。

## 需要的 Secrets

| Secret | 值 |
|---|---|
| `APP_BGM_FTP_HOST` | `app.bgm.fun` |
| `APP_BGM_FTP_USER` | `app` |
| `APP_BGM_FTP_PASS` | FTP 密码 |
| `APP_BGM_URL` | `https://app.bgm.fun` |

签名相关的 `SPARKLE_ED_PRIVATE_KEY` 等见上文。

## 服务器一次性配置

### 1. 给 pure-ftpd 开 TLS

1Panel 的 FTP 默认**没有** TLS，密码会明文过公网。用站点证书生成合并 PEM：

```bash
cat /opt/1panel/www/sites/app.bgm.fun/ssl/privkey.pem \
    /opt/1panel/www/sites/app.bgm.fun/ssl/fullchain.pem \
  > /etc/ssl/private/pure-ftpd.pem
chmod 600 /etc/ssl/private/pure-ftpd.pem
echo 1 > /etc/pure-ftpd/conf/TLS

systemctl restart pure-ftpd.service

# 验证
echo | openssl s_client -starttls ftp -connect 127.0.0.1:21 2>&1 | grep -E "subject=|Protocol"
```

> 若以后在 1Panel 页面里改过 FTP 设置，可能覆盖 `/etc/pure-ftpd/conf/TLS`，重跑上面的命令即可。

### 2. appcast.xml 禁止长缓存

否则用户可能几小时都收不到更新。nginx 站点配置（1Panel → 网站 → 配置文件，或 `/opt/1panel/www/conf.d/app.bgm.fun.conf`）：

```nginx
location = /appcast.xml {
    add_header Cache-Control "no-cache" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
}
```

改完在容器里校验并重载：

```bash
docker exec 1Panel-openresty-XXXX openresty -t && \
docker exec 1Panel-openresty-XXXX openresty -s reload
```

## 坑

| 现象 | 原因 |
|---|---|
| `curl --quote "-DELE x"` 把刚改名的文件删了 | 带前导减号的 quote 命令会被 curl 放到传输**之后**执行。RNTO 本身支持覆盖同名文件，不需要先 DELE |
| `curl: (67) Access denied: 530` | 密码错了（注意从 md 里抄时别把反引号带上） |
| `AUTH TLS` 返回 `500` | pure-ftpd 没开 TLS，按上面第 1 步配置 |
| 上传成功但 HTTPS 404 | 检查 FTP 的 chroot 根是否就是 nginx 的 `root`，两者必须是同一个目录 |

---

# 六、更新日志（Sparkle 更新弹窗显示的内容）

## 写在哪

新建 `release-notes/<tag>.md`，比如 `release-notes/v1.3.5.md`，用 Markdown 写就行：

```md
## 更新内容

- 修复 xxx
- 新增 **yyy**

## 升级说明

- 直接点「安装更新」即可
```

发版时 CI 会：

1. 找到 `release-notes/<tag>.md` 就用它；找不到就用 `git log <上一个tag>..<tag>` 自动生成
2. 同一份内容写入 **GitHub Release** 和 **appcast.xml 的 description**
3. Markdown 自动转成 HTML（标题/列表/粗体/行内代码/链接/引用/代码块）

## 为什么必须是 HTML + CDATA

Sparkle 解析 appcast 时用的是 `NSXMLElement.stringValue`：

```objc
NSString *description = node.stringValue;   // 只取「文本」，不含子节点标签
...
_itemDescriptionFormat = @"html";
```

所以 `<description>` 里必须是一段**文本形式的 HTML**（CDATA 或转义文本），写成 XML 子节点会被吃掉标签，弹窗里只剩纯文字——这就是之前「更新日志不完整」的原因。`make-appcast.py` 现在统一输出：

```xml
<description><![CDATA[<h2>更新内容</h2><ul><li>…</li></ul>]]></description>
```

## 历史版本补日志

appcast 已发布的条目可以单独回填，不用重新打包：

```bash
python3 scripts/make-appcast.py --appcast appcast.xml \
  --tag v1.3.4 --build 12 \
  --dmg-url https://app.bgm.fun/SmartClose-v1.3.4.dmg \
  --length <appcast 里的 length> \
  --signature <appcast 里的 edSignature> \
  --notes-file release-notes/v1.3.4.md

# 再上传 appcast.xml 到 app.bgm.fun（FTPS 原子替换），并提交回仓库
```

签名和 length 必须与已发布 DMG 保持一致，否则 Sparkle 会拒绝安装。

---

# 七、发版流程（强制带更新日志）

## 为什么需要约束

更新日志会直接出现在用户的 Sparkle 更新弹窗里。如果忘了写，CI 只能拿提交标题凑数（`fix(appcast): …` 这种），用户看不懂。

所以做了两层约束：

| 层 | 机制 |
|---|---|
| 本地 | `.githooks/pre-push`：推送 `v*` tag 时，如果该提交里没有 `release-notes/<tag>.md`，**直接拒绝推送** |
| CI | 缺文件时用 git log 兜底，并在 Actions 界面打一条 warning annotation |

## 一次性启用钩子

```bash
git config core.hooksPath .githooks
```

> 每台克隆仓库的机器都要执行一次（hook 靠这个配置生效，不在 `.git/hooks` 里）。

## 日常发版：一条命令

```bash
./scripts/release.sh v1.3.5
```

它会依次：

1. 检查：在 master、工作区干净、tag 不存在、有新提交
2. 用 `git log <上一个tag>..HEAD` 生成 `release-notes/v1.3.5.md` 草稿
3. 打开 `$EDITOR`（默认 vim）让你改
4. 打印最终内容，等你输入 `y` 确认
5. 提交更新日志 → 打 tag → 推送 master 和 tag
6. CI 接手：构建、签名、公证、部署到 app.bgm.fun

其他参数：

```bash
./scripts/release.sh v1.3.5 --no-edit   # 不改草稿，直接确认
./scripts/release.sh v1.3.5 --dry-run   # 只生成草稿并预览，不提交
```

草稿长这样，改完保存退出即可：

```md
## 更新内容

自 v1.3.4 以来的变更：

- fix(ui): 修复设置页崩溃
- feat: 支持按进程名排除

## 升级说明

- 直接点「安装更新」即可，无需手动操作
```

## 想手动发版时

钩子会拦住没有 notes 的 tag。确实要跳过（比如补发）：

```bash
git push --no-verify origin v1.3.5
```
