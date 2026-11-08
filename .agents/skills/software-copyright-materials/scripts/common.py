#!/usr/bin/env python3
"""Shared helpers for the software copyright materials skill."""

from __future__ import annotations

import json
import hashlib
import os
import re
from pathlib import Path
from typing import Any, Iterable


EXCLUDE_DIRS = {
    ".git",
    ".hg",
    ".svn",
    ".idea",
    ".vscode",
    "__pycache__",
    "node_modules",
    "dist",
    "build",
    ".next",
    ".nuxt",
    ".output",
    "coverage",
    "target",
    "vendor",
    "软件著作权申请资料",
    "software-copyright-materials",
}

KNOWN_CONFIG_FILES = {
    ".babelrc",
    ".eslintrc",
    ".eslintrc.json",
    ".eslintrc.yaml",
    ".eslintrc.yml",
    ".prettierrc",
    ".prettierrc.json",
    ".prettierrc.yaml",
    ".prettierrc.yml",
    ".swcrc",
    "angular.json",
    "app.json",
    "astro.config.mjs",
    "astro.config.ts",
    "babel.config.js",
    "babel.config.json",
    "Cargo.lock",
    "Cargo.toml",
    "composer.json",
    "docker-compose.yaml",
    "docker-compose.yml",
    "eslint.config.cjs",
    "eslint.config.js",
    "eslint.config.mjs",
    "go.mod",
    "go.sum",
    "jsconfig.json",
    "lerna.json",
    "manifest.json",
    "next.config.js",
    "next.config.mjs",
    "next.config.ts",
    "nuxt.config.js",
    "nuxt.config.ts",
    "nx.json",
    "package-lock.json",
    "package.json",
    "playwright.config.js",
    "playwright.config.ts",
    "postcss.config.cjs",
    "postcss.config.js",
    "prettier.config.cjs",
    "prettier.config.js",
    "prettier.config.mjs",
    "project.json",
    "pyproject.toml",
    "rollup.config.js",
    "rollup.config.mjs",
    "rollup.config.ts",
    "svelte.config.js",
    "stylelintrc.json",
    "tailwind.config.js",
    "tailwind.config.ts",
    "tsconfig.app.json",
    "tsconfig.json",
    "tsconfig.node.json",
    "tslint.json",
    "turbo.json",
    "vite.config.js",
    "vite.config.mjs",
    "vite.config.ts",
    "vitest.config.js",
    "vitest.config.ts",
    "webpack.config.js",
    "webpack.config.ts",
    "workspace.json",
    ".env.example",
}

FRONTEND_EXTS = {
    ".vue",
    ".ts",
    ".tsx",
    ".js",
    ".jsx",
    ".mjs",
    ".css",
    ".scss",
    ".sass",
    ".less",
    ".html",
    ".svelte",
    ".astro",
}

LOCK_FILES = {
    "package-lock.json",
    "pnpm-lock.yaml",
    "yarn.lock",
    "bun.lockb",
    "bun.lock",
}

# Source discovery intentionally uses a denylist plus content detection instead
# of an extension allowlist. New languages and engine-specific scripts should be
# inventoried automatically; the model/user selection gate decides relevance.
DOCUMENT_EXTS = {
    ".adoc",
    ".doc",
    ".docx",
    ".md",
    ".odt",
    ".pdf",
    ".rst",
    ".rtf",
    ".txt",
    ".wps",
}

BINARY_EXTS = {
    ".7z",
    ".a",
    ".avi",
    ".bin",
    ".bmp",
    ".class",
    ".db",
    ".dll",
    ".dmg",
    ".eot",
    ".exe",
    ".flac",
    ".gif",
    ".gz",
    ".ico",
    ".iso",
    ".jar",
    ".jpeg",
    ".jpg",
    ".lib",
    ".lockb",
    ".mov",
    ".mp3",
    ".mp4",
    ".o",
    ".obj",
    ".ogg",
    ".otf",
    ".pdb",
    ".png",
    ".pyc",
    ".rar",
    ".so",
    ".sqlite",
    ".sqlite3",
    ".tar",
    ".ttf",
    ".wav",
    ".webm",
    ".webp",
    ".woff",
    ".woff2",
    ".xls",
    ".xlsx",
    ".zip",
}

NON_SOURCE_TEXT_EXTS = {
    ".csv",
    ".log",
    ".tsv",
}

DOCUMENT_FILE_PREFIXES = (
    "changelog",
    "code_of_conduct",
    "contributing",
    "license",
    "readme",
    "security",
)

DOCUMENT_DIR_NAMES = {
    "doc",
    "docs",
    "documentation",
    "spec",
    "specs",
    "设计文档",
    "需求文档",
}

DOCUMENT_NAME_HINTS = (
    "architecture",
    "design",
    "manual",
    "prd",
    "requirement",
    "设计",
    "需求",
    "手册",
    "文档",
    "架构",
    "说明",
)

# Used only to keep obvious source files out of document evidence when their
# names contain words such as "design" or "manual". It is not a discovery gate.
KNOWN_SOURCE_HINT_EXTS = FRONTEND_EXTS | {
    ".c",
    ".cc",
    ".cpp",
    ".cs",
    ".cxx",
    ".dart",
    ".gd",
    ".gml",
    ".go",
    ".h",
    ".hh",
    ".hpp",
    ".java",
    ".kt",
    ".lua",
    ".php",
    ".ps1",
    ".py",
    ".rb",
    ".rs",
    ".sh",
    ".sql",
    ".swift",
}

MAX_SOURCE_FILE_BYTES = 800_000

# Shared code-document layout. The extractor uses the physical-line estimate
# only to choose enough material; Word still performs the final pagination.
CODE_FONT_NAME = "Consolas"
CODE_FONT_SIZE = "8pt"
CODE_LINE_SPACING = "13pt"
CODE_LINES_PER_PAGE = 55
CODE_MAX_COLUMNS = 90

CONFIRMATION_METADATA_KEYS = {
    "user_confirmed",
    "confirmation_note",
    "confirmed_at",
    "confirmed_content_sha256",
}

KNOWN_CODE_DRAFTS = {
    "代码-前30页.md",
    "代码-后30页.md",
    "代码-全部.md",
}


def is_excluded(path: Path) -> bool:
    # iter_project_files checks every directory entry while descending. Looking
    # at all absolute path parts would wrongly exclude a project merely because
    # one of its parent folders happens to be named "build" or like this skill,
    # "software-copyright-materials".
    if path.name in EXCLUDE_DIRS:
        return True
    name = path.name
    if name.startswith(".") and name not in {".env.example"}:
        return True
    if name in LOCK_FILES:
        return True
    if name.endswith(".map") or name.endswith(".min.js") or name.endswith(".min.css"):
        return True
    return False


def iter_project_files(project: Path, exts: set[str] | None = None) -> Iterable[Path]:
    project = project.resolve()
    for root, dirs, files in os.walk(project):
        root_path = Path(root)
        dirs[:] = [d for d in dirs if not is_excluded(root_path / d)]
        for filename in files:
            path = root_path / filename
            if is_excluded(path):
                continue
            if exts is not None and path.suffix.lower() not in exts:
                continue
            yield path


def rel(path: Path, root: Path) -> str:
    return path.resolve().relative_to(root.resolve()).as_posix()


def read_text(path: Path, limit: int | None = None) -> str:
    data = path.read_bytes()
    if limit is not None:
        data = data[:limit]
    encodings = ["utf-8", "utf-8-sig", "gb18030", "latin-1"]
    if data.startswith((b"\xff\xfe", b"\xfe\xff")):
        encodings.insert(0, "utf-16")
    if data.startswith((b"\xff\xfe\x00\x00", b"\x00\x00\xfe\xff")):
        encodings.insert(0, "utf-32")
    for encoding in encodings:
        try:
            return data.decode(encoding)
        except UnicodeDecodeError:
            continue
    return data.decode("utf-8", errors="replace")


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(read_text(path))


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


def file_sha256(path: Path) -> str:
    """Return a stable digest used to invalidate stale user confirmations."""
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def confirmation_payload_sha256(data: dict[str, Any]) -> str:
    """Hash JSON content while excluding confirmation bookkeeping fields."""
    payload = {key: value for key, value in data.items() if key not in CONFIRMATION_METADATA_KEYS}
    encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def confirmation_is_current(data: dict[str, Any]) -> bool:
    expected = str(data.get("confirmed_content_sha256") or "")
    return bool(expected) and expected == confirmation_payload_sha256(data)


def draft_snapshot(workdir: Path) -> dict[str, str]:
    """Hash user-reviewable drafts plus the selected screenshot inputs."""
    draft_dir = workdir / "草稿"
    if not draft_dir.is_dir():
        return {}
    paths = [
        path
        for path in sorted(draft_dir.rglob("*"))
        if path.is_file()
        and path.name != "最终生成确认.json"
        and path.suffix.lower() in {".md", ".json"}
    ]
    screenshot_confirmation = workdir / "截图方式确认.json"
    if screenshot_confirmation.is_file():
        paths.append(screenshot_confirmation)
    screenshot_manifest = workdir / "截图/截图清单.json"
    if screenshot_manifest.is_file():
        paths.append(screenshot_manifest)
        try:
            entries = read_json(screenshot_manifest).get("screenshots") or []
            for entry in entries:
                if not isinstance(entry, dict) or not entry.get("path"):
                    continue
                image_path = Path(str(entry["path"]))
                if not image_path.is_absolute():
                    image_path = screenshot_manifest.parent / image_path
                if image_path.is_file():
                    paths.append(image_path.resolve())
        except Exception:
            pass
    snapshot: dict[str, str] = {}
    resolved_workdir = workdir.resolve()
    for index, path in enumerate(paths, start=1):
        resolved = path.resolve()
        try:
            key = resolved.relative_to(resolved_workdir).as_posix()
        except ValueError:
            key = f"external-screenshot/{index}-{resolved.name}"
        snapshot[key] = file_sha256(resolved)
    return snapshot


def draft_completeness_issues(workdir: Path) -> list[str]:
    """Validate that every draft needed by the final builder exists and is coherent."""
    draft_dir = workdir / "草稿"
    required = [
        "业务理解.md",
        "业务理解.json",
        "代码文件选择.json",
        "代码提取清单.md",
        "代码提取清单.json",
        "申请表信息.md",
        "操作手册.md",
        "操作手册自检记录.md",
        "操作手册自检记录.json",
    ]
    issues = [f"缺少 草稿/{name}" for name in required if not (draft_dir / name).is_file()]
    manifest_path = draft_dir / "代码提取清单.json"
    if not manifest_path.is_file():
        return issues
    try:
        manifest = read_json(manifest_path)
    except Exception as exc:
        issues.append(f"草稿/代码提取清单.json 无法读取：{exc}")
        return issues
    outputs = manifest.get("outputs") if isinstance(manifest, dict) else None
    if not isinstance(outputs, list) or not outputs:
        issues.append("草稿/代码提取清单.json 未声明代码 Markdown 输出")
        return issues
    declared = {str(name) for name in outputs}
    invalid = sorted(declared - KNOWN_CODE_DRAFTS)
    if invalid:
        issues.append("代码提取清单包含未知输出：" + "、".join(invalid))
    for name in sorted(declared & KNOWN_CODE_DRAFTS):
        if not (draft_dir / name).is_file():
            issues.append(f"缺少清单声明的 草稿/{name}")
    stale = sorted(name for name in KNOWN_CODE_DRAFTS - declared if (draft_dir / name).exists())
    if stale:
        issues.append("存在与当前代码提取模式冲突的旧草稿：" + "、".join(stale))
    review_path = draft_dir / "操作手册自检记录.json"
    if review_path.is_file():
        try:
            review = read_json(review_path)
            rounds = review.get("rounds") if isinstance(review, dict) else None
            last_issues = rounds[-1].get("issues") if isinstance(rounds, list) and rounds else None
            if isinstance(last_issues, list) and last_issues:
                issues.append("操作手册自检仍有未解决问题：" + "；".join(str(item) for item in last_issues[:5]))
        except Exception as exc:
            issues.append(f"草稿/操作手册自检记录.json 无法读取：{exc}")
    return issues


def count_text_lines(path: Path, skip_blank: bool = True) -> int:
    try:
        text = read_text(path)
    except Exception:
        return 0
    if not text:
        return 0
    if skip_blank:
        return sum(1 for line in text.splitlines() if line.strip())
    return len(text.splitlines())


def is_known_config_file(path: Path) -> bool:
    """Return True for well-known config files that shouldn't count as source code."""
    return path.name in KNOWN_CONFIG_FILES


def looks_binary(path: Path) -> bool:
    try:
        chunk = path.read_bytes()[:8192]
    except Exception:
        return True
    if not chunk:
        return False
    if path.suffix.lower() in BINARY_EXTS:
        return True
    if chunk.startswith((b"PK\x03\x04", b"%PDF-", b"\x1f\x8b", b"\x89PNG", b"GIF8")):
        return True
    if chunk.startswith((b"\xff\xfe", b"\xfe\xff", b"\xff\xfe\x00\x00", b"\x00\x00\xfe\xff")):
        return False
    if b"\x00" in chunk:
        return True
    control_count = sum(1 for byte in chunk if byte < 32 and byte not in {9, 10, 12, 13})
    return control_count / len(chunk) > 0.02


def is_document_candidate(path: Path, project: Path | None = None) -> bool:
    """Return True for explicit or strongly signalled project documentation."""
    suffix = path.suffix.lower()
    name = path.name.lower()
    if suffix in DOCUMENT_EXTS or name.startswith(DOCUMENT_FILE_PREFIXES):
        return True
    try:
        display_path = Path(rel(path, project)) if project is not None else path
    except ValueError:
        display_path = path
    directory_names = {part.lower() for part in display_path.parent.parts}
    in_document_directory = bool(directory_names & DOCUMENT_DIR_NAMES)
    hinted_name = any(hint in path.stem.lower() for hint in DOCUMENT_NAME_HINTS)
    return (in_document_directory or (hinted_name and suffix not in KNOWN_SOURCE_HINT_EXTS)) and not looks_binary(path)


def is_source_candidate(path: Path) -> bool:
    """Detect readable source without requiring its language extension to be known."""
    if not path.is_file() or is_known_config_file(path):
        return False
    suffix = path.suffix.lower()
    name = path.name.lower()
    if suffix in DOCUMENT_EXTS | BINARY_EXTS | NON_SOURCE_TEXT_EXTS:
        return False
    if any(
        name == prefix or name.startswith(prefix + ".") or name.startswith(prefix + "-") or name.startswith(prefix + "_")
        for prefix in DOCUMENT_FILE_PREFIXES
    ):
        return False
    try:
        size = path.stat().st_size
    except OSError:
        return False
    if size <= 0 or size > MAX_SOURCE_FILE_BYTES or looks_binary(path):
        return False
    try:
        sample = read_text(path, limit=20_000)
    except Exception:
        return False
    if not sample.strip():
        return False
    if any(len(line) > 3000 for line in sample.splitlines()[:80]):
        return False
    return any(char.isalnum() for char in sample)


def iter_source_files(project: Path) -> Iterable[Path]:
    """Yield source candidates using content detection, not an extension allowlist."""
    for path in iter_project_files(project):
        if is_source_candidate(path):
            yield path


def normalize_title(value: str) -> str:
    value = re.sub(r"[-_]+", " ", value).strip()
    value = re.sub(r"\s+", " ", value)
    return value or "待命名软件"


def safe_filename(value: str) -> str:
    value = re.sub(r'[\\/:*?"<>|]+', "_", value).strip()
    return value or "软件"


def ensure_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path
