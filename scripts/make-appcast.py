#!/usr/bin/env python3
"""生成 / 合并 Sparkle appcast.xml。

只依赖标准库。典型用法（CI）：

    python3 scripts/make-appcast.py \
        --appcast appcast.xml \
        --tag v1.3.2 --build 7 \
        --dmg-url https://github.com/OWNER/REPO/releases/download/v1.3.2/SmartClose-v1.3.2.dmg \
        --length 8123456 \
        --signature "$SIGNATURE" \
        --notes-file /tmp/notes.html

同一 build 号重复发布会替换旧条目；结果按 build 号降序保留最近 N 条。
"""

from __future__ import annotations

import argparse
import re
import sys
import xml.etree.ElementTree as ET
from email.utils import format_datetime
from datetime import datetime, timezone
from pathlib import Path

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE_NS)

TAG_RE = re.compile(r"^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")


def sp(name: str) -> str:
    return f"{{{SPARKLE_NS}}}{name}"


def parse_tag(tag: str) -> str:
    """v1.2.3 → 1.2.3；不合法直接失败（避免发出版本号奇怪的 appcast）。"""
    m = TAG_RE.match(tag)
    if not m:
        raise SystemExit(f"tag 不合法：{tag}（应为 vX.Y.Z）")
    return tag[1:]


def read_items(path: Path) -> list[ET.Element]:
    if not path.exists():
        return []
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError as exc:
        raise SystemExit(f"已有 appcast 解析失败：{exc}") from exc
    channel = root.find("channel")
    if channel is None:
        return []
    return list(channel.findall("item"))


def item_version(item: ET.Element) -> int:
    raw = item.findtext(sp("version"))
    try:
        return int(raw or 0)
    except ValueError:
        return 0


def build_item(
    *,
    short_version: str,
    build: int,
    min_os: str,
    notes_html: str,
    dmg_url: str,
    length: int,
    signature: str,
    pub_date: datetime | None = None,
) -> ET.Element:
    item = ET.Element("item")
    ET.SubElement(item, "title").text = short_version
    ET.SubElement(item, "pubDate").text = format_datetime(
        pub_date or datetime.now(timezone.utc))
    ET.SubElement(item, sp("version")).text = str(build)
    ET.SubElement(item, sp("shortVersionString")).text = short_version
    ET.SubElement(item, sp("minimumSystemVersion")).text = min_os
    if notes_html.strip():
        ET.SubElement(item, "description").text = notes_html
    ET.SubElement(
        item,
        "enclosure",
        {
            "url": dmg_url,
            "length": str(length),
            "type": "application/octet-stream",
            sp("edSignature"): signature,
        },
    )
    return item


def merge_items(existing: list[ET.Element], new: ET.Element, max_items: int) -> list[ET.Element]:
    new_build = item_version(new)
    kept = [i for i in existing if item_version(i) != new_build]
    kept.append(new)
    kept.sort(key=item_version, reverse=True)
    return kept[:max_items]


def write_appcast(path: Path, title: str, items: list[ET.Element]) -> None:
    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = title
    for it in items:
        channel.append(it)
    ET.indent(rss, space="  ")
    body = '<?xml version="1.0" encoding="utf-8"?>\n' + ET.tostring(rss, encoding="unicode")
    path.write_text(body + "\n", encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="生成 / 合并 Sparkle appcast.xml")
    ap.add_argument("--appcast", default="appcast.xml", type=Path)
    ap.add_argument("--tag", required=True, help="vX.Y.Z")
    ap.add_argument("--build", required=True, type=int, help="CFBundleVersion，必须递增")
    ap.add_argument("--dmg-url", required=True)
    ap.add_argument("--length", required=True, type=int)
    ap.add_argument("--signature", required=True, help="sign_update 输出的 edSignature")
    ap.add_argument("--notes-file", type=Path, help="HTML/文本更新日志")
    ap.add_argument("--min-os", default="13.0")
    ap.add_argument("--max-items", type=int, default=10)
    ap.add_argument("--title", default="智能退出")
    args = ap.parse_args(argv)

    short_version = parse_tag(args.tag)
    if args.build <= 0:
        raise SystemExit("build 必须是正整数")
    if not args.dmg_url.endswith(".dmg"):
        raise SystemExit("--dmg-url 必须以 .dmg 结尾")
    if not args.signature.strip():
        raise SystemExit("--signature 不能为空")

    notes = args.notes_file.read_text(encoding="utf-8") if args.notes_file else ""
    new_item = build_item(
        short_version=short_version,
        build=args.build,
        min_os=args.min_os,
        notes_html=notes,
        dmg_url=args.dmg_url,
        length=args.length,
        signature=args.signature.strip(),
    )
    items = merge_items(read_items(args.appcast), new_item, args.max_items)
    write_appcast(args.appcast, args.title, items)
    print(f"appcast 已更新：{args.appcast} · {short_version} (build {args.build}) · 共 {len(items)} 条")
    return 0


if __name__ == "__main__":
    sys.exit(main())
