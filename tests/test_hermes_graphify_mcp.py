from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = ROOT / "scripts" / "hermes_graphify_mcp.py"


def load_helper():
    spec = importlib.util.spec_from_file_location("hermes_graphify_mcp", SCRIPT_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {SCRIPT_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class HermesGraphifyMcpTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.helper = load_helper()

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.vault = Path(self.directory.name)
        self.helper.configure_vault(self.vault)
        (self.vault / "a.md").write_text(
            "---\ntitle: Alpha\n---\nSee [[b]].", encoding="utf-8"
        )
        (self.vault / "b.md").write_text("Beta note", encoding="utf-8")

    def tearDown(self):
        self.directory.cleanup()

    def test_search_and_read_are_read_only(self):
        search = json.loads(self.helper.search_notes("alpha"))
        self.assertEqual("a.md", search["results"][0]["path"])
        note = json.loads(self.helper.get_note("a.md"))
        self.assertIn("See [[b]]", note["content"])
        self.assertEqual("Alpha", note["title"])
        self.assertEqual("See [[b]].", (self.vault / "a.md").read_text().split("---\n", 2)[-1])

    def test_links_include_outgoing_and_incoming(self):
        links = json.loads(self.helper.get_note_links("b.md"))
        self.assertEqual([], links["outgoing"])
        self.assertEqual(["a.md"], links["incoming"])

    def test_path_escape_and_non_markdown_are_rejected(self):
        with self.assertRaises(ValueError):
            self.helper.get_note("../outside.md")
        (self.vault / "image.txt").write_text("not a note", encoding="utf-8")
        with self.assertRaises(ValueError):
            self.helper.get_note("image.txt")


if __name__ == "__main__":
    unittest.main()
