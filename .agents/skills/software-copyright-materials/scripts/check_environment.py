#!/usr/bin/env python3
"""Check Python and pinned OfficeCLI capabilities before the workflow starts."""

from __future__ import annotations

import argparse
import platform
import sys
from pathlib import Path
from typing import Any

from common import ensure_dir, write_json
from officecli_backend import (
    OFFICECLI_DOWNLOAD_URL,
    OFFICECLI_INSTALL_COMMAND,
    TESTED_OFFICECLI_VERSION,
    OfficeCli,
    OfficeCliError,
    pending_windows_officecli_install,
    resolve_officecli,
)


def check_environment() -> dict[str, Any]:
    resolved = resolve_officecli()
    pending_install = pending_windows_officecli_install() if resolved is None else None
    version = "not found"
    error = ""
    if resolved:
        try:
            version = OfficeCli(require_tested_version=False).version
        except OfficeCliError as exc:
            error = str(exc)

    officecli_available = resolved is not None and not error
    tested_version = officecli_available and version == TESTED_OFFICECLI_VERSION
    requires_user_input = not tested_version
    if pending_install:
        next_action = (
            "OfficeCLI 已安装到官方全局目录，但当前 Codex 进程尚未获取更新后的 PATH。"
            "请重启 Codex，回到此项目后重新运行环境检查；不要在项目目录内复制 OfficeCLI。"
        )
    elif not officecli_available:
        next_action = (
            f"请在 PowerShell 中执行官方全局安装命令：{OFFICECLI_INSTALL_COMMAND}。"
            "安装完成后重启 Codex，回到此项目再重新运行环境检查。"
        )
    else:
        next_action = (
            f"当前 OfficeCLI 为 {version}，请切换到已验证版本 {TESTED_OFFICECLI_VERSION}；"
            "如确认自行承担兼容性风险，可在正式生成时显式使用 --allow-untested-officecli。"
        )
    if tested_version:
        next_action = "OfficeCLI 固定版本已就绪，可以进入项目分析。"

    return {
        "output_directory": "当前目录/软件著作权申请资料",
        "capabilities": {
            "markdown_drafts": True,
            "application_txt": True,
            "officecli": officecli_available,
            "officecli_tested_version": tested_version,
            "docx_create": tested_version,
            "docx_openxml_validate": tested_version,
            "docx_preview": tested_version,
            "native_word_page_count_possible": platform.system() == "Windows",
        },
        "versions": {
            "python": platform.python_version(),
            "officecli": version,
            "officecli_required": TESTED_OFFICECLI_VERSION,
        },
        "paths": {"officecli": str(resolved) if resolved else ""},
        "officecli_install_state": "restart_required" if pending_install else ("ready" if resolved else "not_installed"),
        "final_docx_mode": "officecli" if tested_version else "unavailable",
        "recommendation": (
            f"OfficeCLI {version} 已就绪；生成时禁用自动更新并使用原子 batch 写入。"
            if tested_version
            else f"正式 DOCX 统一依赖 OfficeCLI v{TESTED_OFFICECLI_VERSION}，不再使用 python-docx、Pandoc 或内置 .NET 工具包兜底。"
        ),
        "install_prompt": (
            "无需安装，固定版本可用。"
            if tested_version
            else (
                "OfficeCLI 已全局安装；请重启 Codex 后继续。"
                if pending_install
                else f"是否全局安装 OfficeCLI？命令：`{OFFICECLI_INSTALL_COMMAND}`；已验证版本发布页：{OFFICECLI_DOWNLOAD_URL}"
            )
        ),
        "requires_user_input": requires_user_input,
        "confirmation_stage": "environment" if requires_user_input else None,
        "next_action": next_action,
        "officecli_error": error,
    }


def write_markdown(path: Path, data: dict[str, Any]) -> None:
    caps = data["capabilities"]
    lines = [
        "# 软著申请资料生成环境检查",
        "",
        f"- 输出目录：`{data['output_directory']}`",
        f"- 最终 Word 模式：`{data['final_docx_mode']}`",
        f"- Python：`{data['versions']['python']}`",
        f"- OfficeCLI：`{data['versions']['officecli']}`（要求 `{data['versions']['officecli_required']}`）",
        f"- OfficeCLI 路径：`{data['paths']['officecli'] or '未找到'}`",
        f"- OfficeCLI 安装状态：`{data['officecli_install_state']}`",
        "",
        "## 能力状态",
        "",
        f"- Markdown 草稿：{'可用' if caps['markdown_drafts'] else '不可用'}",
        f"- 申请表 TXT：{'可用' if caps['application_txt'] else '不可用'}",
        f"- OfficeCLI DOCX 生成：{'可用' if caps['docx_create'] else '不可用'}",
        f"- OpenXML 结构校验：{'可用' if caps['docx_openxml_validate'] else '不可用'}",
        f"- DOCX 预览：{'可用' if caps['docx_preview'] else '不可用'}",
        f"- Word 原生页数校验：{'可能可用' if caps['native_word_page_count_possible'] else '需在 Word/WPS 中人工复核'}",
        "",
        "## 建议",
        "",
        data["recommendation"],
        "",
        "## 用户选择",
        "",
        data["install_prompt"],
        "",
    ]
    if data.get("requires_user_input"):
        lines.extend([
            "OfficeCLI 缺失、需要重启 Codex 或版本不匹配时必须停止，不得静默安装或退回其他 DOCX 后端。",
            "",
            "```text",
            "STOP_FOR_USER",
            f"NEXT_ACTION: {data['next_action']}",
            "```",
            "",
        ])
    if data.get("officecli_error"):
        lines.extend(["## OfficeCLI 错误", "", "```text", data["officecli_error"], "```", ""])
    path.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", default="软件著作权申请资料")
    args = parser.parse_args()
    if sys.version_info < (3, 10):
        raise SystemExit("Python 3.10+ is required")
    out_dir = ensure_dir(Path(args.out_dir))
    data = check_environment()
    write_json(out_dir / "环境检查.json", data)
    write_markdown(out_dir / "环境检查.md", data)
    print(f"OK environment check: {out_dir}")
    print(f"Final DOCX mode: {data['final_docx_mode']}")
    print(data["recommendation"])
    if data.get("requires_user_input"):
        print("STOP_FOR_USER")
        print(f"NEXT_ACTION: {data['next_action']}")


if __name__ == "__main__":
    main()
