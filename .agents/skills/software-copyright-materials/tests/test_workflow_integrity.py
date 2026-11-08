from __future__ import annotations

import json
import shutil
import sys
import unittest
from pathlib import Path
from unittest.mock import patch


SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))

from capture_screenshots import collect_screenshots  # noqa: E402
import check_playwright_cli as playwright_check  # noqa: E402
from check_environment import check_environment  # noqa: E402
from check_playwright_cli import npm_global_candidates  # noqa: E402
from common import confirmation_is_current, read_json  # noqa: E402
from confirm_stage import (
    REQUIRED_FIELDS,
    application_field_issues,
    confirm_business,
    parse_screenshot_method,
)  # noqa: E402
from generate_application_info import submitted_code_page_count, total_source_line_count  # noqa: E402


class WorkflowIntegrityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = Path(__file__).resolve().parent / ".tmp-workflow-integrity"
        self.temp_dir.mkdir(exist_ok=True)

    def tearDown(self) -> None:
        shutil.rmtree(self.temp_dir)

    def test_application_uses_whole_project_source_count(self) -> None:
        analysis = {"source": {"line_count": 120, "total_line_count": 980}}
        manifest = {"source_line_count": 400, "selected_source_line_count": 350}

        self.assertEqual(total_source_line_count(analysis, manifest), 980)

    def test_officecli_install_waits_for_codex_restart_when_path_is_stale(self) -> None:
        installed = self.temp_dir / "OfficeCLI" / "officecli.exe"
        with (
            patch("check_environment.resolve_officecli", return_value=None),
            patch("check_environment.pending_windows_officecli_install", return_value=installed),
        ):
            result = check_environment()

        self.assertEqual(result["officecli_install_state"], "restart_required")
        self.assertTrue(result["requires_user_input"])
        self.assertIn("重启 Codex", result["next_action"])
        self.assertNotIn("OFFICECLI_PATH", result["next_action"])

    def test_playwright_cli_global_candidates_are_platform_standard(self) -> None:
        prefix = Path("global-prefix")
        windows = npm_global_candidates(prefix, windows=True)
        posix = npm_global_candidates(prefix, windows=False)

        self.assertEqual(windows[0], prefix / "playwright-cli.cmd")
        self.assertEqual(posix[0], prefix / "bin" / "playwright-cli")

    def test_playwright_cli_uses_global_prefix_without_restart(self) -> None:
        prefix = self.temp_dir / "global-prefix"
        prefix.mkdir()
        executable = prefix / "playwright-cli.cmd"
        executable.write_text("@echo off", encoding="utf-8")
        with (
            patch.object(playwright_check.shutil, "which", return_value=None),
            patch.object(playwright_check, "_npm_global_prefix", return_value=(prefix, "")),
            patch.object(playwright_check, "_read_version", return_value=("0.1.20", "")),
        ):
            result = playwright_check.check_playwright_cli()

        self.assertTrue(result["ready"])
        self.assertEqual(result["source"], "npm-global-prefix")
        self.assertEqual(Path(result["executable"]), executable.resolve())
        self.assertNotIn("重启", result["next_action"])

    def test_submitted_pages_are_60_for_front_back_mode(self) -> None:
        manifest = {"mode": "front30_back30", "total_pages": 143}

        self.assertEqual(submitted_code_page_count(manifest), 60)

    def test_user_screenshots_follow_numeric_prefix_order(self) -> None:
        source = self.temp_dir / "用户截图"
        output = self.temp_dir / "截图"
        source.mkdir()
        for name in ("10-settings.png", "2-home.png", "1-login.png"):
            (source / name).write_bytes(b"image")

        manifest = collect_screenshots(source, output)
        sources = [Path(item["source"]).name for item in manifest["screenshots"]]

        self.assertEqual(sources, ["1-login.png", "2-home.png", "10-settings.png"])

    def test_screenshot_methods_are_playwright_or_user_supplied(self) -> None:
        self.assertEqual(parse_screenshot_method("playwright-cli", ""), "playwright-cli")
        self.assertEqual(parse_screenshot_method("", "1"), "playwright-cli")
        self.assertEqual(parse_screenshot_method("user-supplied", ""), "user-supplied")
        self.assertEqual(parse_screenshot_method("", "2"), "user-supplied")
        self.assertEqual(parse_screenshot_method("skip", ""), "skip")

    def test_playwright_screenshot_manifest_records_method(self) -> None:
        source = self.temp_dir / "截图原始"
        output = self.temp_dir / "截图"
        source.mkdir()
        (source / "01-home.png").write_bytes(b"image")

        manifest = collect_screenshots(source, output, method="playwright-cli")

        self.assertEqual(manifest["method"], "playwright-cli")
        self.assertEqual(manifest["status"], "ok")

    def test_business_edit_invalidates_confirmation(self) -> None:
        draft = self.temp_dir / "草稿"
        draft.mkdir()
        path = draft / "业务理解.json"
        path.write_text('{"industry":"软件服务","user_confirmed":false}', encoding="utf-8")

        confirm_business(self.temp_dir, "确认")
        confirmed = read_json(path)
        self.assertTrue(confirmation_is_current(confirmed))

        confirmed["industry"] = "教育"
        path.write_text(json.dumps(confirmed, ensure_ascii=False), encoding="utf-8")
        self.assertFalse(confirmation_is_current(read_json(path)))

    def test_application_gate_checks_dates_counts_and_limits(self) -> None:
        values = {field: "有效内容" for field in REQUIRED_FIELDS}
        values.update(
            {
                "软件分类": "应用软件",
                "开发方式": "单独开发",
                "软件说明": "原创",
                "发表状态": "未发表",
                "权利范围": "全部权利",
                "权利取得方式": "原始取得",
                "开发完成日期": "2026-99-99",
                "软件的主要功能": "功" * 500,
                "源程序量": "12行",
                "页数": "0",
            }
        )
        path = self.temp_dir / "申请表信息.md"
        path.write_text("\n".join(f"➤{name}：{value}" for name, value in values.items()), encoding="utf-8")

        issues = application_field_issues(path)

        self.assertTrue(any("有效的 YYYY-MM-DD" in issue for issue in issues))
        self.assertTrue(any("源程序量" in issue and "纯数字" in issue for issue in issues))
        self.assertTrue(any("页数" in issue and "大于 0" in issue for issue in issues))


if __name__ == "__main__":
    unittest.main()
