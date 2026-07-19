from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = ROOT / "scripts" / "graphify_vault.py"


def load_helper():
    spec = importlib.util.spec_from_file_location("graphify_vault", SCRIPT_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {SCRIPT_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class GraphifyVaultTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.helper = load_helper()

    def test_manifest_changes_for_content_creation_deletion_and_rename(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)
            baseline = self.helper.manifest(source)
            note = source / "note.md"
            note.write_text("one", encoding="utf-8")
            created = self.helper.manifest(source)
            self.assertNotEqual(baseline, created)

            note.write_text("two", encoding="utf-8")
            changed = self.helper.manifest(source)
            self.assertNotEqual(created, changed)

            renamed = source / "renamed.md"
            note.rename(renamed)
            self.assertNotEqual(changed, self.helper.manifest(source))
            renamed.unlink()
            self.assertEqual(baseline, self.helper.manifest(source))

    def test_manifest_matches_detects_noop(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)
            (source / "note.md").write_text("stable", encoding="utf-8")
            manifest_path = source / "manifest.sha256"
            manifest_path.write_text(self.helper.manifest(source), encoding="utf-8")
            self.assertTrue(self.helper.manifest_matches(source, manifest_path))
            (source / "note.md").write_text("changed", encoding="utf-8")
            self.assertFalse(self.helper.manifest_matches(source, manifest_path))

    def test_empty_and_malformed_markdown_are_safe(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)
            (source / "empty.md").write_text("", encoding="utf-8")
            (source / "malformed.md").write_text("---\ntitle: [\nbody", encoding="utf-8")
            graph_path = source / "graph.json"
            graph_path.write_text(
                json.dumps({"nodes": [], "edges": []}), encoding="utf-8"
            )
            self.assertEqual(2, self.helper.build_markdown_graph(source, graph_path))
            graph = json.loads(graph_path.read_text(encoding="utf-8"))
            self.assertEqual(2, len(graph["nodes"]))

    def test_watcher_filters_markdown_events_case_insensitively(self):
        self.assertTrue(self.helper.is_markdown_event_path("folder/Note.MD"))
        self.assertFalse(self.helper.is_markdown_event_path("folder/.obsidian/workspace"))
        self.assertFalse(self.helper.is_markdown_event_path("folder/Note.md.tmp"))


if __name__ == "__main__":
    unittest.main()
