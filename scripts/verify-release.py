#!/usr/bin/env python3
"""校验一次已发布版本的公开事实与 DMG 本体。

用法：./scripts/verify-release.py v1.6.1
      ./scripts/verify-release.py 1.6.1
"""

from __future__ import annotations

import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

REPO = "yinzhenyu-su/mac-scripts"
APPCAST_URL = "https://app.bgm.fun/appcast.xml"
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
BUNDLE_ID = "fun.bgm.neatquit"
MIN_MACOS = "13.0"

# GitHub API 对未认证请求按来源 IP 限流（shared runner 很容易 403）。
# CI 里传入 workflow 的 github.token，本地可传 `GH_TOKEN=$(gh auth token)`。
GITHUB_TOKEN = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")

# 本次 tag 的工程配置（相对于脚本所在仓库），用来核对 DMG 里的 Bundle ID。
# verify job 是浅克隆，但工作区就是本次 tag 的代码，直接读文件即可，不依赖 git 历史。
PROJECT_FILE = Path(__file__).resolve().parent.parent / "neatquit" / "NeatQuit.xcodeproj" / "project.pbxproj"
BUNDLE_ID_RE = re.compile(r"PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([^;]+);")


def project_bundle_id() -> str:
    """从本次 tag 的 project.pbxproj 读取 PRODUCT_BUNDLE_IDENTIFIER。

    Debug / Release 必须一致（且只能有一个值），否则无法判断“期望的” Bundle ID。
    """
    if not PROJECT_FILE.is_file():
        raise SystemExit(f"找不到工程文件：{PROJECT_FILE}")
    values = {
        match.group(1).strip().strip('"')
        for match in BUNDLE_ID_RE.finditer(PROJECT_FILE.read_text(encoding="utf-8"))
    }
    if len(values) != 1:
        raise SystemExit(
            f"工程 PRODUCT_BUNDLE_IDENTIFIER 不唯一：{sorted(values) or '（未找到）'}"
        )
    return values.pop()


def run(command: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, capture_output=True, text=True)


def fetch(url: str) -> bytes:
    headers = {"User-Agent": "NeatQuit-release-verify"}
    if GITHUB_TOKEN and url.startswith("https://api.github.com/"):
        headers["Authorization"] = f"Bearer {GITHUB_TOKEN}"
    request = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return response.read()
    except urllib.error.HTTPError as error:
        if error.code == 403 and "api.github.com" in url:
            raise SystemExit(
                "GitHub API 返回 403（未认证限流）。请在 CI 里把 GITHUB_TOKEN/GH_TOKEN "
                "传给本脚本，或本地执行 GH_TOKEN=$(gh auth token) ./scripts/verify-release.py <tag>"
            ) from error
        raise


def sha256(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    if len(sys.argv) != 2:
        print("用法：verify-release.py vX.Y.Z", file=sys.stderr)
        return 2
    version = sys.argv[1].lstrip("v")
    tag = f"v{version}"
    failures: list[str] = []

    def check(name: str, actual: object, expected: object) -> None:
        if str(actual) == str(expected):
            print(f"✓ {name}: {actual}")
        else:
            failures.append(f"{name}: 实际 {actual!r} ≠ 期望 {expected!r}")
            print(f"✗ {name}: 实际 {actual!r} ≠ 期望 {expected!r}")

    print(f"发布校验 {tag}")

    # 公开来源
    github = json.loads(fetch(f"https://api.github.com/repos/{REPO}/releases/tags/{tag}"))
    appcast_xml = fetch(APPCAST_URL)
    root = ET.fromstring(appcast_xml)
    items = root.findall("./channel/item")
    item = next(
        (
            candidate
            for candidate in items
            if candidate.findtext(f"{SPARKLE}shortVersionString") == version
        ),
        None,
    )
    if item is None:
        print(f"✗ appcast 中找不到版本 {version}", file=sys.stderr)
        return 1

    build = item.findtext(f"{SPARKLE}version") or ""
    enclosure = item.find("enclosure")
    if enclosure is None:
        print("✗ appcast 缺少 enclosure", file=sys.stderr)
        return 1
    dmg_url = enclosure.get("url", "")
    dmg_length = enclosure.get("length", "")
    signature = enclosure.get(f"{SPARKLE}edSignature", "")

    check("GitHub tag", github.get("tag_name"), tag)
    check("发布记录非草稿", github.get("draft"), False)
    check("发布记录非预发布", github.get("prerelease"), False)

    assets = github.get("assets", [])
    asset_name = f"NeatQuit-{tag}.dmg"
    asset = next((candidate for candidate in assets if candidate.get("name") == asset_name), None)
    if asset is None:
        print(f"✗ GitHub Release 缺少资产 {asset_name}", file=sys.stderr)
        return 1
    check("GitHub 资产名", asset.get("name"), asset_name)
    check("appcast 版本", item.findtext("title"), version)
    print(f"✓ appcast build: {build}")
    check("appcast 最低系统", item.findtext(f"{SPARKLE}minimumSystemVersion"), MIN_MACOS)
    check("appcast 附件 URL", dmg_url, f"https://app.bgm.fun/{asset_name}")
    check("appcast 附件大小", dmg_length, asset.get("size"))
    if not signature:
        failures.append("appcast 缺少 sparkle:edSignature")
        print("✗ appcast 缺少 sparkle:edSignature")
    else:
        print("✓ appcast 签名存在")

    # 本次 tag 的工程配置：DMG 的 Bundle ID 必须与它一致。
    # Bundle ID 是 UserDefaults 的域，换掉它等于清空老用户的规则和许可证，
    # 所以这里以工程文件为准，再和硬编码常量 BUNDLE_ID 对齐（常量兜底，防工程被改错）。
    expected_bundle_id = project_bundle_id()
    check("工程 PRODUCT_BUNDLE_IDENTIFIER", expected_bundle_id, BUNDLE_ID)

    # 下载并核对 DMG
    workdir = tempfile.mkdtemp(prefix="neatquit-verify-")
    dmg_path = os.path.join(workdir, asset_name)
    mountpoint = os.path.join(workdir, "mnt")
    os.makedirs(mountpoint, exist_ok=True)
    attached = False
    try:
        with open(dmg_path, "wb") as handle:
            handle.write(fetch(dmg_url))
        actual_size = os.path.getsize(dmg_path)
        check("DMG 大小（下载）", actual_size, asset.get("size"))
        actual_sha = sha256(dmg_path)
        digest = asset.get("digest") or ""
        if digest.startswith("sha256:"):
            check("DMG SHA-256", actual_sha, digest.removeprefix("sha256:"))
        else:
            print("! GitHub 未提供 digest，跳过 SHA-256 对比")

        attach = run(["hdiutil", "attach", "-nobrowse", "-readonly", "-mountpoint", mountpoint, dmg_path])
        if attach.returncode != 0:
            failures.append(f"DMG 挂载失败：{attach.stderr.strip()}")
            print(f"✗ DMG 挂载失败：{attach.stderr.strip()}")
            return 1
        attached = True

        app_name = next((name for name in os.listdir(mountpoint) if name.endswith(".app")), None)
        if app_name is None:
            failures.append("DMG 中找不到 .app")
            print("✗ DMG 中找不到 .app")
            return 1
        app_path = os.path.join(mountpoint, app_name)
        info_path = os.path.join(app_path, "Contents", "Info.plist")
        with open(info_path, "rb") as handle:
            info = plistlib.load(handle)

        check("CFBundleShortVersionString", info.get("CFBundleShortVersionString"), version)
        check("CFBundleVersion", info.get("CFBundleVersion"), build)
        check("CFBundleIdentifier", info.get("CFBundleIdentifier"), expected_bundle_id)
        check("LSMinimumSystemVersion", info.get("LSMinimumSystemVersion"), MIN_MACOS)

        resources = os.path.join(app_path, "Contents", "Resources")
        for language in ("en.lproj", "zh-Hans.lproj"):
            check(f"本地化 {language}", os.path.isdir(os.path.join(resources, language)), True)

        codesign = run(["codesign", "-dv", "--verbose=2", app_path])
        codesign_output = codesign.stdout + codesign.stderr
        check(
            "Developer ID 签名",
            "Authority=Developer ID Application" in codesign_output,
            True,
        )
        check("公证票据", "Notarization Ticket=stapled" in codesign_output, True)

        spctl = run(["spctl", "-a", "-vvv", "-t", "install", app_path])
        spctl_output = spctl.stdout + spctl.stderr
        check("spctl 通过", spctl.returncode == 0 and "accepted" in spctl_output, True)
    finally:
        if attached:
            run(["hdiutil", "detach", mountpoint])
        shutil.rmtree(workdir, ignore_errors=True)

    if failures:
        print("\n校验失败：")
        for failure in failures:
            print(f"  - {failure}")
        return 1
    print("\n发布校验通过。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
