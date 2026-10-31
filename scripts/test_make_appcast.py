#!/usr/bin/env python3
"""make-appcast.py 的单元测试：python3 scripts/test_make_appcast.py"""

import importlib.util
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("make-appcast.py")
spec = importlib.util.spec_from_file_location("make_appcast", MODULE_PATH)
assert spec is not None and spec.loader is not None
appcast = importlib.util.module_from_spec(spec)
spec.loader.exec_module(appcast)

SP = appcast.sp


def make_item(version: str, build: int, notes: str = "notes", sig: str = "SIG") -> ET.Element:
    return appcast.build_item(
        short_version=version,
        build=build,
        min_os="13.0",
        notes_html=notes,
        dmg_url=f"https://example.com/SmartClose-v{version}.dmg",
        length=1234,
        signature=sig,
    )


class ParseTagTests(unittest.TestCase):
    def test_valid(self):
        self.assertEqual(appcast.parse_tag("v1.3.2"), "1.3.2")
        self.assertEqual(appcast.parse_tag("v0.0.1"), "0.0.1")

    def test_invalid(self):
        for bad in ["1.3.2", "v1.3", "v1.3.2-rc1", "v1.3.x", "nightly", "v01.2.3"]:
            with self.assertRaises(SystemExit, msg=bad):
                appcast.parse_tag(bad)


class MergeTests(unittest.TestCase):
    def test_merge_keeps_newest_first(self):
        existing = [make_item("1.3.0", 5), make_item("1.3.1", 6)]
        merged = appcast.merge_items(existing, make_item("1.3.2", 7), 10)
        self.assertEqual([appcast.item_version(i) for i in merged], [7, 6, 5])

    def test_replace_same_build(self):
        existing = [make_item("1.3.2", 7, notes="old")]
        merged = appcast.merge_items(existing, make_item("1.3.2", 7, notes="new"), 10)
        self.assertEqual(len(merged), 1)
        self.assertEqual(merged[0].findtext("description"), "new")

    def test_truncate(self):
        existing = [make_item(f"1.0.{i}", i) for i in range(1, 13)]
        merged = appcast.merge_items(existing, make_item("1.1.0", 13), 10)
        self.assertEqual(len(merged), 10)
        self.assertEqual(appcast.item_version(merged[0]), 13)


class WriteTests(unittest.TestCase):
    def test_roundtrip_and_escaping(self):
        notes = "修复 <b>A & B</b> 的问题 ]]> 结束"
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "appcast.xml"
            appcast.write_appcast(path, "测试", [make_item("1.3.2", 7, notes=notes)])
            root = ET.parse(path).getroot()
            item = root.find("channel/item")
            assert item is not None
            self.assertEqual(item.findtext("description"), notes)  # 转义后解析回来一致
            self.assertEqual(item.findtext(SP("version")), "7")
            self.assertEqual(item.findtext(SP("shortVersionString")), "1.3.2")
            enclosure = item.find("enclosure")
            assert enclosure is not None
            self.assertEqual(enclosure.get(SP("edSignature")), "SIG")
            self.assertTrue(enclosure.get("url").endswith(".dmg"))

    def test_skip_description_when_notes_empty(self):
        item = make_item("1.3.2", 7, notes="   ")
        self.assertIsNone(item.find("description"))


class MarkdownTests(unittest.TestCase):
    def test_headings_lists_bold(self):
        html = appcast.markdown_to_html(
            "## 更新内容\n\n- 修复 **启动崩溃**\n- 新增 `--flag`\n\n详见 [文档](https://example.com/a?b=1)\n"
        )
        self.assertIn("<h2>更新内容</h2>", html)
        self.assertIn("<ul>", html)
        self.assertIn("<li>修复 <strong>启动崩溃</strong></li>", html)
        self.assertIn("<li>新增 <code>--flag</code></li>", html)
        self.assertIn('<a href="https://example.com/a?b=1">文档</a>', html)
        self.assertIn("<p>", html)

    def test_escapes_html_and_survives_xml(self):
        html = appcast.markdown_to_html("用 <script> 而不是 & 符号")
        self.assertIn("&lt;script&gt;", html)
        self.assertIn("&amp;", html)

    def test_description_written_as_cdata_html(self):
        """Sparkle 用 NSXMLElement.stringValue 读 description，必须输出 CDATA，否则标签会丢。"""
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "appcast.xml"
            item = appcast.build_item(
                short_version="1.3.4", build=12, min_os="13.0",
                notes_html="## 标题\n\n- 一条 **重点**", dmg_url="https://e.com/a.dmg",
                length=1, signature="S", notes_format="markdown",
            )
            appcast.write_appcast(path, "t", [item])
            xml = path.read_text(encoding="utf-8")
            self.assertIn("<![CDATA[<h2>标题</h2>", xml)
            self.assertIn("<strong>重点</strong>", xml)
            # 解析回来，stringValue 等价物应仍是 HTML 源码
            desc = ET.parse(path).getroot().find("channel/item/description")
            self.assertIn("<h2>标题</h2>", desc.text)

    def test_plain_text_fallback(self):
        html = appcast.markdown_to_html("just text")
        self.assertEqual(html, "<p>just text</p>")


class CliTests(unittest.TestCase):
    def test_cli_creates_and_updates(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "appcast.xml"
            notes = Path(d) / "notes.md"
            notes.write_text("首个版本", encoding="utf-8")

            def run(tag, build, url, sig):
                return appcast.main([
                    "--appcast", str(path), "--tag", tag, "--build", str(build),
                    "--length", "999", "--dmg-url", url, "--signature", sig,
                    "--notes-file", str(notes),
                ])

            self.assertEqual(run("v1.3.2", 7, "https://example.com/SmartClose-v1.3.2.dmg", "SIG7"), 0)
            self.assertEqual(run("v1.3.3", 8, "https://example.com/SmartClose-v1.3.3.dmg", "SIG8"), 0)
            root = ET.parse(path).getroot()
            items = root.findall("channel/item")
            self.assertEqual([appcast.item_version(i) for i in items], [8, 7])

    def test_cli_rejects_bad_version(self):
        with self.assertRaises(SystemExit):
            appcast.main(["--tag", "1.3.2", "--build", "7", "--length", "1",
                          "--dmg-url", "https://example.com/a.dmg", "--signature", "S"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
