#!/usr/bin/env python3
"""Record explicit user confirmations for gated workflow stages."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
from pathlib import Path
import re
from typing import Any

from common import (
    confirmation_is_current,
    confirmation_payload_sha256,
    draft_completeness_issues,
    draft_snapshot,
    file_sha256,
    read_json,
    write_json,
)


MAIN_FUNCTION_MIN_CHARS = 500
MAIN_FUNCTION_MAX_CHARS = 1300
SCREENSHOT_METHODS = {"playwright-cli", "user-supplied", "skip"}
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
FIELD_LIMITS = {
    "开发的硬件环境": 50,
    "运行的硬件环境": 50,
    "开发该软件的操作系统": 50,
    "软件开发环境 / 开发工具": 50,
    "该软件的运行平台 / 操作系统": 50,
    "软件运行支撑环境 / 支持软件": 50,
    "开发目的": 50,
    "面向领域 / 行业": 50,
    "软件的技术特点": 100,
    "编程语言": 120,
}
ENUM_FIELDS = {
    "软件分类": {"应用软件", "嵌入式软件", "中间件", "系统软件", "其他"},
    "开发方式": {"单独开发", "合作开发", "委托开发", "下达任务开发"},
    "软件说明": {"原创", "修改（含翻译软件、合成软件）"},
    "发表状态": {"已发表", "未发表"},
    "权利范围": {"全部权利", "部分权利"},
    "权利取得方式": {"原始取得", "继受取得"},
}
REQUIRED_FIELDS = (
    "软件全称",
    "版本号",
    "软件分类",
    "开发完成日期",
    "开发方式",
    "软件说明",
    "发表状态",
    "著作权人",
    "权利范围",
    "权利取得方式",
    "开发的硬件环境",
    "运行的硬件环境",
    "开发该软件的操作系统",
    "软件开发环境 / 开发工具",
    "该软件的运行平台 / 操作系统",
    "软件运行支撑环境 / 支持软件",
    "编程语言",
    "源程序量",
    "开发目的",
    "面向领域 / 行业",
    "软件的主要功能",
    "软件的技术特点",
    "页数",
)


def timestamp() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def load_json_or_empty(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    return read_json(path)


def write_confirmation(path: Path, data: dict[str, Any], key: str, note: str) -> None:
    data[key] = True
    data["confirmation_note"] = note
    data["confirmed_at"] = timestamp()
    data["confirmed_content_sha256"] = confirmation_payload_sha256(data)
    write_json(path, data)


def pending_application_fields(md_path: Path) -> list[str]:
    if not md_path.exists():
        return [f"缺少 {md_path}"]
    return [line.strip() for line in md_path.read_text(encoding="utf-8").splitlines() if "待用户确认" in line]


def effective_len(value: str) -> int:
    return len(str(value or "").replace(" ", "").replace("\n", ""))


def application_field_value(md_path: Path, field_name: str) -> str:
    prefix = f"➤{field_name}："
    for line in md_path.read_text(encoding="utf-8").splitlines():
        if line.startswith(prefix):
            return line[len(prefix) :].strip()
    return ""


def application_field_issues(md_path: Path) -> list[str]:
    issues = pending_application_fields(md_path)
    if not md_path.exists():
        return issues

    for field_name in REQUIRED_FIELDS:
        if not application_field_value(md_path, field_name):
            issues.append(f"➤{field_name}：不能为空。")

    main_function = application_field_value(md_path, "软件的主要功能")
    if not main_function:
        issues.append("➤软件的主要功能：缺少填写内容，请填写 500~1300 字。")
    elif "待用户确认" not in main_function:
        count = effective_len(main_function)
        if count < MAIN_FUNCTION_MIN_CHARS:
            issues.append(
                f"➤软件的主要功能：当前 {count} 字，少于 {MAIN_FUNCTION_MIN_CHARS} 字，请扩写至 500~1300 字。"
            )
        elif count > MAIN_FUNCTION_MAX_CHARS:
            issues.append(
                f"➤软件的主要功能：当前 {count} 字，超过 {MAIN_FUNCTION_MAX_CHARS} 字，请精简至 500~1300 字。"
            )
    for field_name, allowed in ENUM_FIELDS.items():
        value = application_field_value(md_path, field_name)
        if value and "待用户确认" not in value and value not in allowed:
            issues.append(f"➤{field_name}：值“{value}”不在允许范围内（{'/'.join(sorted(allowed))}）。")
    for field_name in ("开发完成日期", "首次发表日期"):
        value = application_field_value(md_path, field_name)
        if value and "待用户确认" not in value:
            try:
                if not DATE_RE.fullmatch(value):
                    raise ValueError
                datetime.strptime(value, "%Y-%m-%d")
            except ValueError:
                issues.append(f"➤{field_name}：必须是有效的 YYYY-MM-DD 日期。")
    if application_field_value(md_path, "发表状态") == "已发表" and not application_field_value(md_path, "首次发表日期"):
        issues.append("➤首次发表日期：发表状态为“已发表”时必须填写。")
    for field_name, limit in FIELD_LIMITS.items():
        value = application_field_value(md_path, field_name)
        if value and "待用户确认" not in value and len(value) > limit:
            issues.append(f"➤{field_name}：当前 {len(value)} 字符，超过 {limit} 字符限制。")
    for field_name in ("源程序量", "页数"):
        value = application_field_value(md_path, field_name)
        if value and "待用户确认" not in value and (not value.isdigit() or int(value) <= 0):
            issues.append(f"➤{field_name}：必须填写大于 0 的纯数字。")
    return issues


def current_confirmation_issue(path: Path, label: str) -> str | None:
    if not path.exists():
        return f"{label}尚未确认"
    data = read_json(path)
    if not data.get("user_confirmed"):
        return f"{label}尚未确认"
    if not confirmation_is_current(data):
        return f"{label}在确认后已被修改，请重新确认"
    return None


def confirm_environment(workdir: Path, note: str) -> Path:
    out_path = workdir / "环境确认.json"
    data = load_json_or_empty(out_path)
    write_confirmation(out_path, data, "environment_confirmed", note)
    return out_path


def confirm_project(workdir: Path, note: str) -> Path:
    out_path = workdir / "项目确认.json"
    data = load_json_or_empty(out_path)
    write_confirmation(out_path, data, "project_confirmed", note)
    return out_path


def confirm_business(workdir: Path, note: str) -> Path:
    path = workdir / "草稿/业务理解.json"
    if not path.exists():
        raise SystemExit("Missing 草稿/业务理解.json")
    data = read_json(path)
    write_confirmation(path, data, "user_confirmed", note)
    return path


def confirm_code_selection(workdir: Path, note: str) -> Path:
    path = workdir / "草稿/代码文件选择.json"
    if not path.exists():
        raise SystemExit("Missing 草稿/代码文件选择.json")
    data = read_json(path)
    files = data.get("files") if isinstance(data, dict) else []
    selected = [item for item in files if isinstance(item, dict) and item.get("selected")]
    if not selected:
        raise SystemExit(
            "STOP_FOR_USER\n"
            "NEXT_ACTION: 代码文件选择尚未由模型填写。请先选择至少一个源码文件并填写选择理由，再让用户确认。"
        )
    missing_reason = [item.get("path") for item in selected if not str(item.get("model_reason") or "").strip()]
    if data.get("model_selection_required") and missing_reason:
        raise SystemExit(
            "STOP_FOR_USER\n"
            "NEXT_ACTION: 已选源码缺少模型选择理由，请补全 `model_reason` 后再确认。\n"
            + "\n".join(f"- {item}" for item in missing_reason[:20])
        )
    write_confirmation(path, data, "user_confirmed", note)
    return path


def parse_screenshot_method(method: str, note: str) -> str:
    value = (method or note or "").lower()
    if any(key in value for key in ("skip", "no-screenshot", "none", "不截图", "跳过", "暂不", "先不", "不要截图", "无需截图")):
        return "skip"
    if value.strip() == "1" or any(key in value for key in ("playwright", "playwright-cli", "自动截图", "自动")):
        return "playwright-cli"
    if value.strip() == "2" or any(key in value for key in ("user", "manual", "self", "手动", "自己", "用户")):
        return "user-supplied"
    raise SystemExit(
        "STOP_FOR_USER\n"
        "NEXT_ACTION: 请明确截图方式：playwright-cli、user-supplied 或 skip。"
    )


def confirm_screenshot_method(workdir: Path, note: str, method: str) -> Path:
    selected = parse_screenshot_method(method, note)
    out_path = workdir / "截图方式确认.json"
    data = load_json_or_empty(out_path)
    data["screenshot_method"] = selected
    write_confirmation(out_path, data, "screenshot_method_confirmed", note)
    return out_path


def confirm_application_fields(workdir: Path, note: str) -> Path:
    md_path = workdir / "草稿/申请表信息.md"
    issues = application_field_issues(md_path)
    if issues:
        raise SystemExit(
            "STOP_FOR_USER\n"
            "NEXT_ACTION: 申请表信息仍有字段未满足要求。请先补全或修正字段，再重新确认。\n"
            + "\n".join(f"- {item}" for item in issues[:20])
        )
    out_path = workdir / "草稿/申请表字段确认.json"
    data = load_json_or_empty(out_path)
    data["application_md_sha256"] = file_sha256(md_path)
    write_confirmation(out_path, data, "application_fields_confirmed", note)
    return out_path


def confirm_markdown(workdir: Path, note: str) -> Path:
    issues = []
    business = workdir / "草稿/业务理解.json"
    selection = workdir / "草稿/代码文件选择.json"
    screenshot = workdir / "截图方式确认.json"
    fields = workdir / "草稿/申请表字段确认.json"

    business_issue = current_confirmation_issue(business, "业务理解")
    if business_issue:
        issues.append(business_issue)
    selection_issue = current_confirmation_issue(selection, "代码文件选择")
    if selection_issue:
        issues.append(selection_issue)
    if not screenshot.exists() or not read_json(screenshot).get("screenshot_method_confirmed"):
        issues.append("截图方式尚未确认")
    elif read_json(screenshot).get("screenshot_method") not in SCREENSHOT_METHODS:
        issues.append("截图方式已失效，请重新选择 Playwright CLI 自动截图、用户自行截图或跳过截图")
    if not fields.exists() or not read_json(fields).get("application_fields_confirmed"):
        issues.append("申请表字段尚未确认")
    else:
        app_md = workdir / "草稿/申请表信息.md"
        if not app_md.exists() or read_json(fields).get("application_md_sha256") != file_sha256(app_md):
            issues.append("申请表信息在确认后已被修改，请重新确认")
    field_issues = application_field_issues(workdir / "草稿/申请表信息.md")
    if field_issues:
        issues.append("申请表信息仍有字段未满足要求")
    issues.extend(draft_completeness_issues(workdir))

    if issues:
        raise SystemExit(
            "STOP_FOR_USER\n"
            "NEXT_ACTION: Markdown 草稿确认前需要先处理以下事项：\n"
            + "\n".join(f"- {item}" for item in issues)
        )

    out_path = workdir / "草稿/最终生成确认.json"
    data = load_json_or_empty(out_path)
    data["draft_file_sha256"] = draft_snapshot(workdir)
    write_confirmation(out_path, data, "markdown_confirmed", note)
    return out_path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workdir", default="软件著作权申请资料")
    parser.add_argument(
        "--stage",
        required=True,
        choices=[
            "environment",
            "project",
            "business",
            "code-selection",
            "screenshot-method",
            "application-fields",
            "markdown",
        ],
    )
    parser.add_argument("--note", default="用户已确认")
    parser.add_argument(
        "--method",
        choices=sorted(SCREENSHOT_METHODS),
        help="Screenshot capture method when --stage screenshot-method",
    )
    args = parser.parse_args()

    workdir = Path(args.workdir)
    if args.stage == "environment":
        path = confirm_environment(workdir, args.note)
    elif args.stage == "project":
        path = confirm_project(workdir, args.note)
    elif args.stage == "business":
        path = confirm_business(workdir, args.note)
    elif args.stage == "code-selection":
        path = confirm_code_selection(workdir, args.note)
    elif args.stage == "screenshot-method":
        path = confirm_screenshot_method(workdir, args.note, args.method or "")
    elif args.stage == "application-fields":
        path = confirm_application_fields(workdir, args.note)
    else:
        path = confirm_markdown(workdir, args.note)

    print(f"OK confirmation recorded: {args.stage}")
    print(path)


if __name__ == "__main__":
    main()
