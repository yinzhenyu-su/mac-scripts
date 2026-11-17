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


def make_item(
    version: str,
    build: int,
    notes: str = "notes",
    sig: str = "SIG",
    notes_en: str | None = None,
) -> ET.Element:
    return appcast.build_item(
        short_version=version,
        build=build,
        min_os="13.0",
        notes_html=notes,
        notes_html_en=notes_en,
        dmg_url=f"https://example.com/NeatQuit-v{version}.dmg",
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

    def test_replace_same_version_with_new_build(self):
        """同一版本号重发（build 变大）应替换旧条目，而不是并排出现两条。"""
        existing = [make_item("1.6.1", 19, notes="old"), make_item("1.6.0", 18)]
        merged = appcast.merge_items(existing, make_item("1.6.1", 20, notes="new"), 10)
        self.assertEqual([appcast.item_short_version(i) for i in merged], ["1.6.1", "1.6.0"])
        self.assertEqual([appcast.item_version(i) for i in merged], [20, 18])
        self.assertEqual(len(merged), 2)
        self.assertEqual(merged[0].findtext("description"), "new")

    def test_dedup_by_short_version(self):
        """去重按版本号：同版本不同 build 只保留新条目，不同版本不受影响。"""
        existing = [make_item("1.6.1", 19, notes="old"), make_item("1.6.0", 18)]
        merged = appcast.merge_items(existing, make_item("1.6.1", 21, notes="new"), 10)
        self.assertEqual(sum(1 for i in merged if appcast.item_short_version(i) == "1.6.1"), 1)
        self.assertEqual(
            [appcast.item_version(i) for i in merged if appcast.item_short_version(i) == "1.6.1"],
            [21],
        )

    def test_reject_old_version_with_larger_build(self):
        """用更大的 build 重发旧版本会被打进 feed 顶端，必须拒绝。"""
        existing = [make_item("1.6.0", 18), make_item("1.6.1", 19)]
        with self.assertRaises(SystemExit) as ctx:
            appcast.merge_items(existing, make_item("1.6.0", 20), 10)
        self.assertIn("1.6.0", str(ctx.exception))
        self.assertIn("1.6.1", str(ctx.exception))

    def test_reject_old_version_absent_from_feed(self):
        """旧版本已经掉出 feed（10 条上限）时，同样不能用更大的 build 重发。"""
        existing = [make_item("1.6.1", 19)]
        with self.assertRaises(SystemExit) as ctx:
            appcast.merge_items(existing, make_item("1.6.0", 20), 10)
        self.assertIn("1.6.0", str(ctx.exception))

    def test_reject_newest_version_with_lower_build(self):
        """重发最新版本时 build 不能变小，否则 feed 里该版本的 build 会回退。"""
        existing = [make_item("1.6.0", 18), make_item("1.6.1", 19)]
        with self.assertRaises(SystemExit):
            appcast.merge_items(existing, make_item("1.6.1", 18), 10)

    def test_allow_rerelease_old_version_with_same_build(self):
        """重发旧版本但 build 不超过已有最大 build 时无害，允许替换（比如补日志）。"""
        existing = [make_item("1.6.0", 18, notes="old"), make_item("1.6.1", 19)]
        merged = appcast.merge_items(existing, make_item("1.6.0", 18, notes="new"), 10)
        self.assertEqual([appcast.item_version(i) for i in merged], [19, 18])
        self.assertEqual(merged[1].findtext("description"), "new")

    def test_reject_non_increasing_build(self):
        """新版本 build 没有严格递增时拒绝发布。"""
        existing = [make_item("1.6.1", 19)]
        for build in (19, 18, 0):
            with self.assertRaises(SystemExit, msg=f"build {build}"):
                appcast.merge_items(existing, make_item("1.7.0", build), 10)

    def test_accept_monotonic_build(self):
        """build 与版本号都单调递增时正常通过。"""
        existing = [make_item("1.6.0", 18), make_item("1.6.1", 19)]
        merged = appcast.merge_items(existing, make_item("1.7.0", 20), 10)
        self.assertEqual([appcast.item_version(i) for i in merged], [20, 19, 18])
        self.assertEqual(appcast.item_short_version(merged[0]), "1.7.0")

    def test_first_item_skips_monotonic_check(self):
        merged = appcast.merge_items([], make_item("1.6.1", 19), 10)
        self.assertEqual([appcast.item_version(i) for i in merged], [19])

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

    def test_localized_descriptions(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "appcast.xml"
            item = make_item("1.5.0", 17, notes="中文说明", notes_en="English notes")
            appcast.write_appcast(path, "t", [item])
            descriptions = ET.parse(path).getroot().findall("channel/item/description")
            self.assertEqual([d.get("{http://www.w3.org/XML/1998/namespace}lang") for d in descriptions],
                             ["zh-Hans", "en"])
            self.assertIn("中文说明", descriptions[0].text)
            self.assertIn("English notes", descriptions[1].text)
            xml = path.read_text(encoding="utf-8")
            self.assertIn('<description xml:lang="zh-Hans"><![CDATA[', xml)
            self.assertIn('<description xml:lang="en"><![CDATA[', xml)


class ReplaceNotesTests(unittest.TestCase):
    def test_replace_keeps_enclosure_and_date(self):
        item = make_item("1.5.0", 17, notes="old")
        pub_date = item.findtext("pubDate")
        enclosure = item.find("enclosure")
        assert enclosure is not None
        self.assertTrue(appcast.replace_item_notes(
            [item], "1.5.0", "新中文", "New English"))
        descriptions = item.findall("description")
        self.assertEqual(len(descriptions), 2)
        self.assertEqual(descriptions[0].get("xml:lang"), "zh-Hans")
        self.assertIn("新中文", descriptions[0].text)
        self.assertIn("New English", descriptions[1].text)
        self.assertEqual(item.findtext("pubDate"), pub_date)
        self.assertEqual(item.find("enclosure"), enclosure)

    def test_replace_missing_version_returns_false(self):
        self.assertFalse(appcast.replace_item_notes([make_item("1.5.0", 17)], "1.4.1", "x"))


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

            self.assertEqual(run("v1.3.2", 7, "https://example.com/NeatQuit-v1.3.2.dmg", "SIG7"), 0)
            self.assertEqual(run("v1.3.3", 8, "https://example.com/NeatQuit-v1.3.3.dmg", "SIG8"), 0)
            root = ET.parse(path).getroot()
            items = root.findall("channel/item")
            self.assertEqual([appcast.item_version(i) for i in items], [8, 7])

    def test_cli_rejects_bad_version(self):
        with self.assertRaises(SystemExit):
            appcast.main(["--tag", "1.3.2", "--build", "7", "--length", "1",
                          "--dmg-url", "https://example.com/a.dmg", "--signature", "S"])

    def test_cli_rejects_old_version_rerelease(self):
        """用更大的 build 重发旧版本：CLI 必须以非零退出码失败。"""
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "appcast.xml"
            notes = Path(d) / "notes.md"
            notes.write_text("说明", encoding="utf-8")

            def run(tag, build):
                return appcast.main([
                    "--appcast", str(path), "--tag", tag, "--build", str(build),
                    "--length", "999", "--dmg-url", f"https://example.com/NeatQuit-{tag}.dmg",
                    "--signature", "SIG", "--notes-file", str(notes),
                ])

            self.assertEqual(run("v1.6.1", 19), 0)
            with self.assertRaises(SystemExit) as ctx:
                run("v1.6.0", 20)
            self.assertIn("低于", str(ctx.exception))
            # 失败后 appcast 未被改写，仍只有一条
            self.assertEqual(len(ET.parse(path).getroot().findall("channel/item")), 1)

    def test_cli_replace_notes(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "appcast.xml"
            zh = Path(d) / "notes.md"
            en = Path(d) / "notes.en.md"
            zh.write_text("中文", encoding="utf-8")
            en.write_text("English", encoding="utf-8")
            appcast.main([
                "--appcast", str(path), "--tag", "v1.5.0", "--build", "17",
                "--length", "1", "--dmg-url", "https://example.com/a.dmg",
                "--signature", "S", "--notes-file", str(zh),
            ])
            self.assertEqual(appcast.main([
                "--appcast", str(path), "--tag", "v1.5.0", "--replace-notes",
                "--notes-file", str(zh), "--notes-file-en", str(en),
            ]), 0)
            item = ET.parse(path).getroot().find("channel/item")
            assert item is not None
            descriptions = item.findall("description")
            self.assertEqual(len(descriptions), 2)
            self.assertEqual(descriptions[1].get("{http://www.w3.org/XML/1998/namespace}lang"), "en")


if __name__ == "__main__":
    unittest.main(verbosity=2)
