#!/usr/bin/env python3
"""Collect local screenshot files into an ordered OfficeCLI manifest."""

from __future__ import annotations

import argparse
import json
import shutil
import re
from pathlib import Path

from common import ensure_dir, write_json


def safe_name(path: str) -> str:
    value = path.strip("/") or "home"
    value = re.sub(r"[^A-Za-z0-9._-]+", "_", value)
    return value[:80] or "page"


def manual_sort_key(path: Path) -> tuple[int, int, str]:
    """Honor numeric filename prefixes such as 2-home before 10-settings."""
    match = re.match(r"^(\d+)", path.stem)
    if match:
        return (0, int(match.group(1)), path.name.casefold())
    return (1, 0, path.name.casefold())


def collect_screenshots(
    input_dir: Path,
    out_dir: Path,
    method: str = "user-supplied",
) -> dict[str, object]:
    if input_dir.resolve() == out_dir.resolve():
        raise SystemExit("Screenshot input and output directories must be different")
    out_dir = ensure_dir(out_dir)
    screenshots = []
    errors = []
    allowed = {".png", ".jpg", ".jpeg", ".webp"}
    if not input_dir.is_dir():
        raise SystemExit(f"Screenshot directory not found: {input_dir}")
    for index, path in enumerate(sorted(input_dir.iterdir(), key=manual_sort_key), start=1):
        if path.suffix.lower() not in allowed or not path.is_file():
            continue
        target = out_dir / f"{index:02d}-{safe_name(path.stem)}{path.suffix.lower()}"
        if path.resolve() != target.resolve():
            shutil.copy2(path, target)
        screenshots.append({
            "route": "",
            "url": "",
            "path": str(target.resolve()),
            "source": str(path.resolve()),
        })
    if not screenshots:
        errors.append({"error": f"no screenshot images found in {input_dir}"})
    manifest = {
        "status": "ok" if screenshots else "empty",
        "method": method,
        "screenshots": screenshots,
        "errors": errors,
    }
    write_json(out_dir / "截图清单.json", manifest)
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", default="软件著作权申请资料/截图")
    parser.add_argument("--input-dir", required=True, help="Directory containing screenshots to organize")
    parser.add_argument(
        "--method",
        choices=["playwright-cli", "user-supplied"],
        default="user-supplied",
        help="Capture method recorded in the screenshot manifest",
    )
    args = parser.parse_args()

    manifest = collect_screenshots(Path(args.input_dir), Path(args.out_dir), args.method)
    print(json.dumps(manifest, ensure_ascii=False, indent=2))
    if not manifest["screenshots"]:
        raise SystemExit(3)


if __name__ == "__main__":
    main()
