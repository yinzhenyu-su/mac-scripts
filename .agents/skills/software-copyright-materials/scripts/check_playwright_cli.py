#!/usr/bin/env python3
"""Resolve and verify a globally installed Playwright CLI."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
from pathlib import Path
from typing import Any


TESTED_PLAYWRIGHT_CLI_VERSION = "0.1.20"
PLAYWRIGHT_CLI_PACKAGE = f"@playwright/cli@{TESTED_PLAYWRIGHT_CLI_VERSION}"
PLAYWRIGHT_CLI_INSTALL_COMMAND = f"npm install -g {PLAYWRIGHT_CLI_PACKAGE}"


def npm_global_candidates(prefix: Path, *, windows: bool | None = None) -> list[Path]:
    """Return standard global npm executable locations for the current platform."""
    is_windows = os.name == "nt" if windows is None else windows
    if is_windows:
        return [
            prefix / "playwright-cli.cmd",
            prefix / "playwright-cli.exe",
            prefix / "playwright-cli",
        ]
    return [prefix / "bin" / "playwright-cli", prefix / "playwright-cli"]


def _run_program(program: Path, args: list[str], *, timeout: int = 30) -> subprocess.CompletedProcess[str]:
    command: list[str] | str
    use_shell = False
    if os.name == "nt" and program.suffix.lower() in {".cmd", ".bat"}:
        command = subprocess.list2cmdline([str(program), *args])
        use_shell = True
    else:
        command = [str(program), *args]
    return subprocess.run(
        command,
        text=True,
        encoding="utf-8",
        errors="replace",
        capture_output=True,
        timeout=timeout,
        check=False,
        shell=use_shell,
    )


def _npm_global_prefix() -> tuple[Path | None, str]:
    npm = shutil.which("npm") or shutil.which("npm.cmd") or shutil.which("npm.exe")
    if not npm:
        return None, "npm command not found"
    try:
        completed = _run_program(Path(npm), ["prefix", "-g"])
    except (OSError, subprocess.SubprocessError) as exc:
        return None, str(exc)
    if completed.returncode != 0:
        detail = (completed.stderr or completed.stdout).strip()
        return None, detail or f"npm prefix -g exited with {completed.returncode}"
    lines = [line.strip() for line in completed.stdout.splitlines() if line.strip()]
    if not lines:
        return None, "npm prefix -g returned an empty path"
    return Path(lines[-1]).expanduser(), ""


def _read_version(executable: Path) -> tuple[str, str]:
    try:
        completed = _run_program(executable, ["--version"])
    except (OSError, subprocess.SubprocessError) as exc:
        return "", str(exc)
    combined = "\n".join(part for part in (completed.stdout, completed.stderr) if part).strip()
    if completed.returncode != 0:
        return "", combined or f"version command exited with {completed.returncode}"
    match = re.search(r"\d+\.\d+\.\d+", combined)
    return (match.group(0) if match else combined), ""


def check_playwright_cli() -> dict[str, Any]:
    candidates: list[tuple[str, Path]] = []
    path_match = shutil.which("playwright-cli") or shutil.which("playwright-cli.cmd")
    if path_match:
        candidates.append(("path", Path(path_match)))

    npm_prefix, npm_error = _npm_global_prefix()
    if npm_prefix:
        candidates.extend(("npm-global-prefix", path) for path in npm_global_candidates(npm_prefix))

    checked: list[dict[str, str]] = []
    seen: set[str] = set()
    for source, candidate in candidates:
        key = os.path.normcase(str(candidate.resolve(strict=False)))
        if key in seen or not candidate.is_file():
            continue
        seen.add(key)
        version, error = _read_version(candidate)
        checked.append({"source": source, "path": str(candidate.resolve()), "version": version, "error": error})
        if not error and version == TESTED_PLAYWRIGHT_CLI_VERSION:
            return {
                "status": "ready",
                "ready": True,
                "executable": str(candidate.resolve()),
                "source": source,
                "version": version,
                "required_version": TESTED_PLAYWRIGHT_CLI_VERSION,
                "npm_prefix": str(npm_prefix.resolve()) if npm_prefix else "",
                "requires_user_input": False,
                "next_action": "使用 executable 字段中的绝对路径执行全部 Playwright CLI 命令。",
                "checked": checked,
            }

    if checked:
        versions = ", ".join(item["version"] or "unknown" for item in checked)
        status = "version_mismatch"
        next_action = (
            f"检测到 Playwright CLI {versions}，要求 {TESTED_PLAYWRIGHT_CLI_VERSION}。"
            f"请用户确认后执行：{PLAYWRIGHT_CLI_INSTALL_COMMAND}；完成后立即重新检查，无需重启。"
        )
    else:
        status = "not_found"
        next_action = (
            f"未找到全局 Playwright CLI。请用户确认后执行：{PLAYWRIGHT_CLI_INSTALL_COMMAND}；"
            "完成后立即重新检查，无需重启。"
        )
    return {
        "status": status,
        "ready": False,
        "executable": "",
        "source": "",
        "version": "not found" if not checked else checked[0]["version"],
        "required_version": TESTED_PLAYWRIGHT_CLI_VERSION,
        "npm_prefix": str(npm_prefix.resolve()) if npm_prefix else "",
        "npm_error": npm_error,
        "install_command": PLAYWRIGHT_CLI_INSTALL_COMMAND,
        "requires_user_input": True,
        "next_action": next_action,
        "checked": checked,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", help="Optional JSON result path")
    args = parser.parse_args()
    result = check_playwright_cli()
    if args.out:
        output = Path(args.out)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if not result["ready"]:
        print("STOP_FOR_USER")
        print(f"NEXT_ACTION: {result['next_action']}")
        raise SystemExit(2)


if __name__ == "__main__":
    main()
