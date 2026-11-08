from __future__ import annotations

import sys
import shutil
import unittest
import zipfile
from pathlib import Path


SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))

from common import is_document_candidate, is_source_candidate, iter_source_files  # noqa: E402
from generate_business_context import collect_documents  # noqa: E402


class SourceDiscoveryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.project = Path(__file__).resolve().parent / ".tmp-source-discovery"
        self.project.mkdir(exist_ok=True)

    def tearDown(self) -> None:
        shutil.rmtree(self.project)

    def write_text(self, relative: str, text: str) -> Path:
        path = self.project / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def test_unknown_text_extensions_are_source_candidates(self) -> None:
        gdscript = self.write_text("game/player.gd", "extends CharacterBody2D\nfunc move():\n    pass\n")
        future_language = self.write_text("src/feature.futurelang", "module feature {\n  run();\n}\n")

        self.assertTrue(is_source_candidate(gdscript))
        self.assertTrue(is_source_candidate(future_language))

    def test_documents_configs_and_binary_files_are_not_source_candidates(self) -> None:
        readme = self.write_text("README.md", "# Project\n")
        config = self.write_text("package.json", '{"name": "demo"}\n')
        binary = self.project / "assets" / "unknown.asset"
        binary.parent.mkdir(parents=True)
        binary.write_bytes(b"binary\x00payload")

        self.assertFalse(is_source_candidate(readme))
        self.assertFalse(is_source_candidate(config))
        self.assertFalse(is_source_candidate(binary))

    def test_project_scan_does_not_depend_on_a_language_allowlist(self) -> None:
        self.write_text("scripts/main.gml", "function create_player() { return 1; }\n")
        self.write_text("native/core.cpp", "int main() { return 0; }\n")
        self.write_text("src/logic.no_registry_entry", "let answer = 42\n")
        self.write_text("docs/设计说明.md", "# 设计说明\n")

        found = {path.relative_to(self.project).as_posix() for path in iter_source_files(self.project)}

        self.assertEqual(found, {"native/core.cpp", "scripts/main.gml", "src/logic.no_registry_entry"})

    def test_design_documents_include_docx_and_unregistered_text_formats(self) -> None:
        docx = self.project / "设计文档" / "总体设计.docx"
        docx.parent.mkdir(parents=True)
        with zipfile.ZipFile(docx, "w") as archive:
            archive.writestr(
                "word/document.xml",
                '<?xml version="1.0" encoding="UTF-8"?>'
                '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
                "<w:body><w:p><w:r><w:t>系统总体设计</w:t></w:r></w:p></w:body></w:document>",
            )
        self.write_text("docs/业务架构.notes", "业务架构覆盖用户、订单和审批流程。\n")

        documents = {item["path"]: item for item in collect_documents(self.project)}

        self.assertIn("设计文档/总体设计.docx", documents)
        self.assertIn("docs/业务架构.notes", documents)
        self.assertIn("系统总体设计", documents["设计文档/总体设计.docx"]["opening"])
        self.assertTrue(documents["设计文档/总体设计.docx"]["text_extracted"])

    def test_source_named_design_is_not_misclassified_as_documentation(self) -> None:
        source = self.write_text("src/design.py", "def build_layout():\n    return {}\n")

        self.assertTrue(is_source_candidate(source))
        self.assertFalse(is_document_candidate(source, self.project))


if __name__ == "__main__":
    unittest.main()
