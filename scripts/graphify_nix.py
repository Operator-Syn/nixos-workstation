#!/usr/bin/env python3
"""Add static Nix source relationships to Graphify's JSON graph.

This intentionally does not evaluate Nix. It only records relationships that
can be resolved from source text, so graph generation remains read-only and
does not execute repository configuration.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path


ORIGIN = "nix-static"
IGNORED_PARTS = {".git", ".codex", ".agents", ".venv", "node_modules", "secrets"}
RELATIVE_PATH = re.compile(r"(?<![A-Za-z0-9_])((?:\.\.?/)+[A-Za-z0-9_./-]+)")
INPUT_REFERENCE = re.compile(r"\binputs\.([A-Za-z][A-Za-z0-9_-]*)\b")
INPUT_DECLARATION = re.compile(
    r"\b([A-Za-z][A-Za-z0-9_-]*)\s*(?:\.url\s*=\s*\"([^\"]+)\"|=\s*\{\s*url\s*=\s*\"([^\"]+)\")",
    re.DOTALL,
)


def strip_comments(text: str) -> str:
    """Remove Nix comments while preserving line breaks for locations."""

    text = re.sub(r"/\*.*?\*/", lambda match: "\n" * match.group(0).count("\n"), text, flags=re.DOTALL)
    return re.sub(r"#[^\n]*", "", text)


def relative_path(path: Path, root: Path) -> str:
    return path.relative_to(root).as_posix()


def node_id(path: str) -> str:
    path_without_suffix = str(Path(path).with_suffix(""))
    return re.sub(r"[^A-Za-z0-9]+", "_", path_without_suffix).strip("_").lower()


def line_number(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def resolve_reference(source: Path, reference: str, root: Path) -> Path | None:
    candidate = (source.parent / reference).resolve()
    try:
        candidate.relative_to(root.resolve())
    except ValueError:
        return None

    if candidate.is_dir():
        candidate = candidate / "default.nix"
    if candidate.suffix != ".nix":
        candidate = candidate.with_suffix(".nix")
    return candidate if candidate.is_file() else None


def make_file_node(path: Path, root: Path) -> dict[str, object]:
    rel = relative_path(path, root)
    return {
        "id": node_id(rel),
        "label": rel,
        "file_type": "code",
        "source_file": rel,
        "source_location": "L1",
        "_origin": ORIGIN,
    }


def add_link(links: list[dict[str, object]], source: str, target: str, relation: str, file: str, line: int) -> None:
    stable_key = f"{source}|{relation}|{target}|{file}|{line}".encode("utf-8")
    links.append(
        {
            "id": "nix_link_" + hashlib.sha1(stable_key).hexdigest()[:16],
            "source": source,
            "target": target,
            "relation": relation,
            "context": "nix",
            "confidence": "EXTRACTED",
            "source_file": file,
            "source_location": f"L{line}",
            "weight": 1.0,
            "_origin": ORIGIN,
        }
    )


def build_nix_graph(root: Path) -> tuple[list[dict[str, object]], list[dict[str, object]]]:
    files = sorted(
        path
        for path in root.rglob("*.nix")
        if not any(part in IGNORED_PARTS for part in path.relative_to(root).parts)
    )
    nodes = [make_file_node(path, root) for path in files]
    known_ids = {node["id"] for node in nodes}
    links: list[dict[str, object]] = []

    for path in files:
        rel = relative_path(path, root)
        source_id = node_id(rel)
        original = path.read_text(encoding="utf-8")
        text = strip_comments(original)

        seen_paths: set[str] = set()
        for match in RELATIVE_PATH.finditer(text):
            target = resolve_reference(path, match.group(1), root)
            if target is None:
                continue
            target_rel = relative_path(target, root)
            if target_rel in seen_paths:
                continue
            seen_paths.add(target_rel)
            add_link(links, source_id, node_id(target_rel), "references", rel, line_number(original, match.start()))

        for match in INPUT_REFERENCE.finditer(text):
            input_id = f"nix_input_{match.group(1).lower()}"
            if input_id not in known_ids:
                nodes.append(
                    {
                        "id": input_id,
                        "label": match.group(1),
                        "file_type": "concept",
                        "source_file": rel,
                        "source_location": f"L{line_number(original, match.start())}",
                        "_origin": ORIGIN,
                    }
                )
                known_ids.add(input_id)
            add_link(links, source_id, input_id, "uses_input", rel, line_number(original, match.start()))

        if path == root / "flake.nix":
            for match in INPUT_DECLARATION.finditer(text):
                input_id = f"nix_input_{match.group(1).lower()}"
                if input_id not in known_ids:
                    nodes.append(
                        {
                            "id": input_id,
                            "label": match.group(1),
                            "file_type": "concept",
                            "source_file": rel,
                            "source_location": f"L{line_number(original, match.start())}",
                            "_origin": ORIGIN,
                        }
                    )
                    known_ids.add(input_id)
                add_link(links, source_id, input_id, "declares_input", rel, line_number(original, match.start()))

    return nodes, links


def merge_graph(root: Path, graph_path: Path) -> tuple[int, int]:
    graph = json.loads(graph_path.read_text(encoding="utf-8"))
    existing_nodes = graph.get("nodes", [])
    generated_ids = {node["id"] for node in existing_nodes if node.get("_origin") == ORIGIN}
    graph["nodes"] = [node for node in existing_nodes if node.get("_origin") != ORIGIN]
    graph["links"] = [
        link
        for link in graph.get("links", [])
        if link.get("_origin") != ORIGIN
        and link.get("source") not in generated_ids
        and link.get("target") not in generated_ids
    ]

    nodes, links = build_nix_graph(root)
    graph["nodes"].extend(nodes)
    graph["links"].extend(links)

    # Graphify's structural extractors may emit references to external modules
    # without materializing nodes for them. Add lightweight concept nodes so
    # the merged graph remains schema-valid without pretending those modules
    # belong to this repository.
    known_ids = {node["id"] for node in graph["nodes"]}
    for relation_list in (graph.get("edges", []), graph.get("links", [])):
        for relation in relation_list:
            for endpoint in ("source", "target"):
                endpoint_id = relation.get(endpoint)
                if endpoint_id and endpoint_id not in known_ids:
                    graph["nodes"].append(
                        {
                            "id": endpoint_id,
                            "label": endpoint_id,
                            "file_type": "concept",
                            "source_file": "",
                            "source_location": "",
                            "_origin": "external-reference",
                        }
                    )
                    known_ids.add(endpoint_id)

    graph_path.write_text(json.dumps(graph, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return len(nodes), len(links)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd(), help="repository root (default: current directory)")
    parser.add_argument("--graph", type=Path, default=None, help="Graphify JSON path (default: ROOT/graphify-out/graph.json)")
    args = parser.parse_args()
    root = args.root.resolve()
    graph_path = (args.graph or root / "graphify-out/graph.json").resolve()
    if not graph_path.is_file():
        parser.error(f"Graphify graph not found: {graph_path}")
    nodes, links = merge_graph(root, graph_path)
    print(f"Added {nodes} Nix nodes and {links} Nix relationships to {graph_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
