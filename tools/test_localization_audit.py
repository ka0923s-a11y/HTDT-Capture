import importlib.util
import tempfile
import unittest
from pathlib import Path

_SPEC = importlib.util.spec_from_file_location(
    "localization_audit",
    Path(__file__).with_name("localization_audit.py"),
)
la = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(la)


class CatalogParsingTests(unittest.TestCase):
    def _parse(self, text: str):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "Localizable.strings"
            path.write_text(text, encoding="utf-8")
            return la.parse_catalog(path)

    def test_parses_entries(self):
        entries, problems = self._parse(
            '/* header */\n"Ready" = "準備完了";\n"Saved %d items" = "%d 件保存";\n'
        )
        self.assertEqual(problems, [])
        self.assertEqual(entries["Ready"][0], "準備完了")

    def test_flags_duplicate_key(self):
        _, problems = self._parse(
            '"A" = "1";\n"A" = "2";\n'
        )
        self.assertTrue(any("duplicate key" in p for p in problems))

    def test_flags_malformed_line(self):
        _, problems = self._parse('"A" = "1"\n')
        self.assertTrue(any("malformed" in p for p in problems))

    def test_flags_specifier_mismatch(self):
        _, problems = self._parse(
            '"Saved %d items" = "保存しました";\n'
        )
        self.assertTrue(
            any("specifier count mismatch" in p for p in problems)
        )


class NormalizationTests(unittest.TestCase):
    def test_interp_and_specs_collapse(self):
        self.assertEqual(
            la.normalize_pattern("Plan \\(a) v\\(b)"),
            la.normalize_pattern("Plan %@ v%lld"),
        )

    def test_positional_specs_collapse(self):
        self.assertEqual(
            la.normalize_pattern("%1$@ — %2$@"), "\x00 — \x00"
        )


class ExtractionTests(unittest.TestCase):
    def test_finds_string_localized_and_swiftui_labels(self):
        with tempfile.TemporaryDirectory() as td:
            src = Path(td) / "View.swift"
            src.write_text(
                'Text("Hello")\n'
                'Button("Do it") { }\n'
                'let x = String(localized: "World")\n'
                '.navigationTitle("Screen")\n',
                encoding="utf-8",
            )
            keys = {k for k, _ in la.extract_keys(src)}
        self.assertEqual(keys, {"Hello", "Do it", "World", "Screen"})


if __name__ == "__main__":
    unittest.main()
