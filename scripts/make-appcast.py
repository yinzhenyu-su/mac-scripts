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
from xml.sax.saxutils import unescape
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


def _esc(text: str) -> str:
    """HTML 转义，防止更新日志里混入标签。"""
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def _inline(text: str) -> str:
    """行内 Markdown → HTML（输入已做 HTML 转义）。"""
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", r'<a href="\2">\1</a>', text)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<![\*\w])\*(?!\s)(.+?)(?<!\s)\*(?![\*\w])", r"<em>\1</em>", text)
    return text


def markdown_to_html(md: str) -> str:
    """把常见的 Markdown 子集转成 Sparkle 弹窗能渲染的 HTML。

    只覆盖发布说明用得到的语法：标题、列表、引用、代码块、加粗、行内代码、链接。
    """
    out: list[str] = []
    lines = md.replace("\r\n", "\n").split("\n")
    i = 0
    list_tag: str | None = None
    para: list[str] = []

    def flush_para() -> None:
        if para:
            out.append("<p>" + _inline(" ".join(para)) + "</p>")
            para.clear()

    def close_list() -> None:
        nonlocal list_tag
        if list_tag:
            out.append(f"</{list_tag}>")
            list_tag = None

    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        if stripped.startswith("```"):
            flush_para()
            close_list()
            i += 1
            block: list[str] = []
            while i < len(lines) and not lines[i].strip().startswith("```"):
                block.append(lines[i])
                i += 1
            i += 1
            out.append("<pre><code>" + _esc("\n".join(block)) + "</code></pre>")
            continue

        if not stripped:
            flush_para()
            close_list()
            i += 1
            continue

        heading = re.match(r"^(#{1,6})\s+(.*)$", stripped)
        if heading:
            flush_para()
            close_list()
            level = len(heading.group(1))
            out.append(f"<h{level}>" + _inline(_esc(heading.group(2))) + f"</h{level}>")
            i += 1
            continue

        if re.match(r"^(-{3,}|\*{3,}|_{3,})$", stripped):
            flush_para()
            close_list()
            out.append("<hr>")
            i += 1
            continue

        bullet = re.match(r"^[-*+]\s+(.*)$", stripped)
        ordered = re.match(r"^\d+[.)]\s+(.*)$", stripped)
        if bullet or ordered:
            flush_para()
            want = "ul" if bullet else "ol"
            if list_tag != want:
                close_list()
                out.append(f"<{want}>")
                list_tag = want
            body = (bullet or ordered).group(1)
            out.append("<li>" + _inline(_esc(body)) + "</li>")
            i += 1
            continue

        quote = re.match(r"^>\s?(.*)$", stripped)
        if quote:
            flush_para()
            close_list()
            out.append("<blockquote>" + _inline(_esc(quote.group(1))) + "</blockquote>")
            i += 1
            continue

        para.append(_esc(line.strip()))
        i += 1

    flush_para()
    close_list()
    return "\n".join(out)


def notes_to_html(notes: str, notes_format: str = "markdown") -> str:
    return markdown_to_html(notes) if notes_format == "markdown" else notes


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
    notes_format: str = "html",
) -> ET.Element:
    item = ET.Element("item")
    ET.SubElement(item, "title").text = short_version
    ET.SubElement(item, "pubDate").text = format_datetime(
        pub_date or datetime.now(timezone.utc))
    ET.SubElement(item, sp("version")).text = str(build)
    ET.SubElement(item, sp("shortVersionString")).text = short_version
    ET.SubElement(item, sp("minimumSystemVersion")).text = min_os
    if notes_html.strip():
        # Sparkle 用 NSXMLElement.stringValue 取这个节点的文本，再当 HTML 渲染。
        # 所以必须把 HTML 存成「文本」（最终输出为 CDATA），不能拆成 XML 子节点，
        # 否则标签会被吃掉，弹窗里只剩纯文字。
        html = notes_to_html(notes_html, notes_format)
        ET.SubElement(item, "description").text = html
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


CDATA_RE = re.compile(r"<description>(.*?)</description>", re.DOTALL)


def _to_cdata(match: re.Match[str]) -> str:
    """把 <description> 的转义文本还原成 CDATA，Sparkle 才能拿到原始 HTML。"""
    html = unescape(match.group(1))
    return "<description><![CDATA[" + html.replace("]]>", "]]]]><![CDATA[>") + "]]></description>"


def write_appcast(path: Path, title: str, items: list[ET.Element]) -> None:
    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = title
    for it in items:
        channel.append(it)
    ET.indent(rss, space="  ")
    body = '<?xml version="1.0" encoding="utf-8"?>\n' + ET.tostring(rss, encoding="unicode")
    body = CDATA_RE.sub(_to_cdata, body)
    path.write_text(body + "\n", encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="生成 / 合并 Sparkle appcast.xml")
    ap.add_argument("--appcast", default="appcast.xml", type=Path)
    ap.add_argument("--tag", required=True, help="vX.Y.Z")
    ap.add_argument("--build", required=True, type=int, help="CFBundleVersion，必须递增")
    ap.add_argument("--dmg-url", required=True)
    ap.add_argument("--length", required=True, type=int)
    ap.add_argument("--signature", required=True, help="sign_update 输出的 edSignature")
    ap.add_argument("--notes-file", type=Path, help="更新日志：Markdown（默认）或 HTML，见 --notes-format")
    ap.add_argument("--notes-format", choices=["markdown", "html"], default="markdown",
                    help="--notes-file 的格式；markdown 会被转成 HTML 供 Sparkle 渲染")
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
        notes_format=args.notes_format,
    )
    items = merge_items(read_items(args.appcast), new_item, args.max_items)
    write_appcast(args.appcast, args.title, items)
    print(f"appcast 已更新：{args.appcast} · {short_version} (build {args.build}) · 共 {len(items)} 条")
    return 0


if __name__ == "__main__":
    sys.exit(main())
