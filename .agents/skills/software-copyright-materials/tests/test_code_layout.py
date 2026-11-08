from __future__ import annotations

import sys
import unittest
from pathlib import Path


SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))

from extract_code_material import MAX_CODE_COLUMNS, display_width, material_code_lines, paginate, wrap_display_line  # noqa: E402


class CodeLayoutTests(unittest.TestCase):
    def test_display_width_counts_cjk_as_two_columns(self) -> None:
        self.assertEqual(display_width("abc中文"), 7)

    def test_long_line_wrap_preserves_all_characters(self) -> None:
        source = "const value = '" + ("中" * 70) + ("x" * 80) + "';"
        wrapped = wrap_display_line(source, 100)
        self.assertGreater(len(wrapped), 1)
        self.assertEqual("".join(wrapped), source)
        self.assertTrue(all(display_width(line) <= 100 for line in wrapped))

    def test_tabs_are_expanded_before_wrapping(self) -> None:
        wrapped = wrap_display_line("a\tb", 100)
        self.assertEqual(wrapped, ["a   b"])

    def test_material_lines_drop_blanks_and_wrap(self) -> None:
        material = material_code_lines("\nshort\n" + ("x" * 101) + "\n")
        self.assertEqual(material, ["short", "x" * MAX_CODE_COLUMNS, "x" * (101 - MAX_CODE_COLUMNS)])

    def test_paginate_uses_physical_lines(self) -> None:
        pages = paginate([str(i) for i in range(101)], 50)
        self.assertEqual([len(page) for page in pages], [50, 50, 1])


if __name__ == "__main__":
    unittest.main()
