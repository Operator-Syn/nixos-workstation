#!/usr/bin/env python3
"""Build the deterministic Markdown portion of the Hermes Graphify vault."""

from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path


WIKILINK = re.compile(r"\[\[([^]#|]+)(?:#[^|]*)?(?:\|[^]]*)?\]\]")


def markdown_files(source: Path) -> list[Path]:
    return sorted(path for path in source.rglob("*.md") if path.is_file())


def manifest(source: Path) -> str:
    """Return a stable digest of Markdown paths and contents under *source*."""

    digest = hashlib.sha256()
    for path in markdown_files(source):
        relative = path.relative_to(source).as_posix().encode("utf-8")
        digest.update(relative)
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def manifest_matches(source: Path, manifest_path: Path) -> bool:
    try:
        expected = manifest_path.read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        return False
    return bool(expected) and expected == manifest(source)


def parse_frontmatter(text: str) -> dict[str, str]:
    if not text.startswith("---\n"):
        return {}
    end = text.find("\n---", 4)
    if end < 0:
        return {}
    result: dict[str, str] = {}
    for line in text[4:end].splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        result[key.strip()] = value.strip().strip("\"'")
    return result


def build_markdown_graph(source: Path, graph_path: Path) -> int:
    graph = json.loads(graph_path.read_text(encoding="utf-8"))
    nodes = graph.setdefault("nodes", [])
    edges = graph.setdefault("edges", [])

    files = markdown_files(source)
    by_key: dict[str, str] = {}
    by_stem: dict[str, list[str]] = {}

    def key_for(path: Path) -> str:
        return path.relative_to(source).with_suffix("").as_posix()

    for path in files:
        key = key_for(path)
        frontmatter = parse_frontmatter(path.read_text(encoding="utf-8"))
        node_id = f"markdown:{key}"
        by_key[key.casefold()] = node_id
        by_stem.setdefault(path.stem.casefold(), []).append(node_id)
        nodes.append(
            {
                "id": node_id,
                "label": frontmatter.get("title", path.stem),
                "file_type": "document",
                "source_file": f"{key}.md",
                "source_location": None,
                "source_url": None,
                "captured_at": None,
                "author": None,
                "contributor": None,
            }
        )

    seen_edges = {
        (edge.get("source"), edge.get("target"), edge.get("relation"))
        for edge in edges
    }
    for path in files:
        source_key = key_for(path)
        source_id = by_key[source_key.casefold()]
        for raw_target in WIKILINK.findall(path.read_text(encoding="utf-8")):
            target = raw_target.strip().removesuffix(".md")
            target_id = by_key.get(target.casefold())
            if target_id is None:
                target_id = by_stem.get(Path(target).name.casefold(), [None])[0]
            if target_id is None:
                continue
            edge_key = (source_id, target_id, "references")
            if edge_key in seen_edges:
                continue
            seen_edges.add(edge_key)
            edges.append(
                {
                    "source": source_id,
                    "target": target_id,
                    "relation": "references",
                    "confidence": "EXTRACTED",
                    "confidence_score": 1.0,
                    "source_file": f"{source_key}.md",
                    "source_location": None,
                    "weight": 1.0,
                }
            )

    graph_path.write_text(
        json.dumps(graph, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    return len(files)


def is_markdown_event_path(path: str) -> bool:
    return path.casefold().endswith(".md")


def main() -> int:
    command = sys.argv[1]
    source = Path(sys.argv[2]).resolve()
    if command == "manifest":
        print(manifest(source))
        return 0
    if command == "matches":
        return 0 if manifest_matches(source, Path(sys.argv[3])) else 1
    if command == "build":
        build_markdown_graph(source, Path(sys.argv[3]))
        return 0
    raise SystemExit(f"unknown command: {command}")


if __name__ == "__main__":
    raise SystemExit(main())
