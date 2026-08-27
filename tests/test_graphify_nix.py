from __future__ import annotations

import importlib.util
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = ROOT / "scripts" / "graphify_nix.py"


def load_adapter():
    spec = importlib.util.spec_from_file_location("graphify_nix", SCRIPT_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {SCRIPT_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class GraphifyNixAdapterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.adapter = load_adapter()
        cls.nodes, cls.links = cls.adapter.build_nix_graph(ROOT)
        cls.node_by_id = {node["id"]: node for node in cls.nodes}

    def test_file_labels_and_ids_are_path_qualified_and_unique(self):
        file_nodes = [node for node in self.nodes if node["file_type"] == "code"]
        self.assertEqual(len(file_nodes), len({node["id"] for node in file_nodes}))
        self.assertEqual(len(file_nodes), len({node["label"] for node in file_nodes}))
        self.assertIn("hosts/hiraeth/default.nix", {node["label"] for node in file_nodes})
        self.assertNotIn("default.nix", {node["label"] for node in file_nodes})
        self.assertEqual(
            self.node_by_id[self.adapter.node_id("hosts/hiraeth/default.nix")]["id"],
            "hosts_hiraeth_default",
        )

    def test_node_types_are_graphify_compatible(self):
        self.assertTrue(
            {node["file_type"] for node in self.nodes}
            <= {"code", "concept", "document", "image", "paper", "rationale"}
        )

    def test_all_links_have_existing_endpoints(self):
        for link in self.links:
            self.assertIn(link["source"], self.node_by_id)
            self.assertIn(link["target"], self.node_by_id)

    def test_active_relative_references_are_represented_once(self):
        expected = set()
        for path in sorted(ROOT.rglob("*.nix")):
            if any(part in self.adapter.IGNORED_PARTS for part in path.relative_to(ROOT).parts):
                continue
            rel = path.relative_to(ROOT).as_posix()
            original = path.read_text(encoding="utf-8")
            stripped = self.adapter.strip_comments(original)
            for match in self.adapter.RELATIVE_PATH.finditer(stripped):
                target = self.adapter.resolve_reference(path, match.group(1), ROOT)
                if target is not None:
                    expected.add((rel, target.relative_to(ROOT).as_posix()))

        actual = {
            (
                link["source_file"],
                self.node_by_id[link["target"]]["source_file"],
            )
            for link in self.links
            if link["relation"] == "references"
        }
        self.assertEqual(expected, actual)
        self.assertEqual(len(expected), len(actual))

    def test_commented_imports_are_excluded_and_directories_resolve(self):
        host_links = {
            self.node_by_id[link["target"]]["source_file"]
            for link in self.links
            if link["source_file"] == "hosts/hiraeth/default.nix"
            and link["relation"] == "references"
        }
        self.assertIn("modules/nixos/core/default.nix", host_links)
        self.assertNotIn("modules/nixos/development/debian-container.nix", host_links)

    def test_all_flake_inputs_have_declaration_links(self):
        expected = {
            "nixpkgs",
            "nur",
            "nixpkgs-unstable",
            "home-manager",
            "plasma-manager",
            "sops-nix",
            "aagl",
            "bedrock-on-linux",
        }
        actual = {
            link["target"].removeprefix("nix_input_")
            for link in self.links
            if link["relation"] == "declares_input"
        }
        self.assertEqual(expected, actual)

    @unittest.skipUnless((ROOT / "graphify-out" / "graph.json").exists(), "generated graph is unavailable")
    def test_graphify_cli_distinguishes_duplicate_basenames(self):
        graph = ROOT / "graphify-out" / "graph.json"
        explain = subprocess.run(
            ["pipenv", "run", "graphify", "explain", "hosts/hiraeth/default.nix", "--graph", str(graph)],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        ).stdout
        self.assertIn("hosts/hiraeth/default.nix", explain)

        path = subprocess.run(
            [
                "pipenv",
                "run",
                "graphify",
                "path",
                "flake.nix",
                "hosts/hiraeth/default.nix",
                "--graph",
                str(graph),
            ],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        ).stdout
        self.assertIn("hosts/hiraeth/default.nix", path)


if __name__ == "__main__":
    unittest.main()
