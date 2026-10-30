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
| 公证报 `Invalid` / `signature is invalid` | 必须有 **Hardened Runtime**（`--options runtime`）和 **`--timestamp`**；脚本里用 `OTHER_CODE_SIGN_FLAGS` 传了 |
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
