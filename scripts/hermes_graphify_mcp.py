#!/usr/bin/env python3
"""Read-only MCP tools for the Markdown notes in the Hermes vault."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

from mcp.server.fastmcp import FastMCP


MAX_NOTE_BYTES = 262144
MAX_SEARCH_RESULTS = 50
WIKILINK = re.compile(r"\[\[([^]#|]+)(?:#[^|]*)?(?:\|[^]]*)?\]\]")
VAULT: Path | None = None
mcp = FastMCP(
    "graphify-notes",
    host="127.0.0.1",
    port=9293,
    streamable_http_path="/mcp",
    stateless_http=True,
)


def configure_vault(path: Path) -> None:
    global VAULT
    VAULT = path.resolve()


def vault_path() -> Path:
    if VAULT is None:
        raise RuntimeError("note vault is not configured")
    return VAULT


def markdown_files() -> list[Path]:
    return sorted(path for path in vault_path().rglob("*.md") if path.is_file())


def safe_note_path(note_path: str) -> Path:
    root = vault_path()
    candidate = (root / note_path).resolve()
    try:
        candidate.relative_to(root)
    except ValueError as exc:
        raise ValueError("note path escapes the configured vault") from exc
    if candidate.suffix.casefold() != ".md" or not candidate.is_file():
        raise ValueError("note path must identify an existing Markdown file")
    return candidate


def note_title(path: Path, text: str) -> str:
    if text.startswith("---\n"):
        end = text.find("\n---", 4)
        if end >= 0:
            for line in text[4:end].splitlines():
                if line.startswith("title:"):
                    return line.split(":", 1)[1].strip().strip("\"'")
    return path.stem


def bounded_text(text: str) -> tuple[str, bool]:
    encoded = text.encode("utf-8", errors="replace")
    if len(encoded) <= MAX_NOTE_BYTES:
        return text, False
    return encoded[:MAX_NOTE_BYTES].decode("utf-8", errors="ignore"), True


@mcp.tool()
def search_notes(query: str, limit: int = 20) -> str:
    """Search Markdown note paths, titles, and bodies without modifying notes."""

    query = query.strip().casefold()
    if not query:
        raise ValueError("query must not be empty")
    limit = max(1, min(limit, MAX_SEARCH_RESULTS))
    results = []
    for path in markdown_files():
        text = path.read_text(encoding="utf-8", errors="replace")
        haystack = f"{path.relative_to(vault_path())}\n{note_title(path, text)}\n{text}".casefold()
        position = haystack.find(query)
        if position < 0:
            continue
        start = max(0, position - 120)
        snippet = haystack[start : start + 280].replace("\n", " ").strip()
        results.append(
            {
                "path": path.relative_to(vault_path()).as_posix(),
                "title": note_title(path, text),
                "snippet": snippet,
            }
        )
        if len(results) >= limit:
            break
    return json.dumps({"query": query, "results": results}, ensure_ascii=False)


@mcp.tool()
def get_note(path: str) -> str:
    """Return bounded content and metadata for one Markdown note."""

    note = safe_note_path(path)
    text, truncated = bounded_text(note.read_text(encoding="utf-8", errors="replace"))
    return json.dumps(
        {
            "path": note.relative_to(vault_path()).as_posix(),
            "title": note_title(note, text),
            "content": text,
            "truncated": truncated,
        },
        ensure_ascii=False,
    )


@mcp.tool()
def get_note_links(path: str) -> str:
    """Return outgoing wikilinks and notes that link to the requested note."""

    note = safe_note_path(path)
    relative = note.relative_to(vault_path()).with_suffix("").as_posix().casefold()
    stem = note.stem.casefold()
    outgoing = [target.strip().removesuffix(".md") for target in WIKILINK.findall(note.read_text(encoding="utf-8", errors="replace"))]
    incoming = []
    for candidate in markdown_files():
        if candidate == note:
            continue
        targets = [target.strip().removesuffix(".md") for target in WIKILINK.findall(candidate.read_text(encoding="utf-8", errors="replace"))]
        if any(target.casefold() == relative or Path(target).name.casefold() == stem for target in targets):
            incoming.append(candidate.relative_to(vault_path()).as_posix())
    return json.dumps(
        {
            "path": note.relative_to(vault_path()).as_posix(),
            "outgoing": outgoing,
            "incoming": sorted(incoming),
        },
        ensure_ascii=False,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--vault", type=Path, required=True)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=9293)
    args = parser.parse_args()
    configure_vault(args.vault)
    mcp.settings.host = args.host
    mcp.settings.port = args.port
    mcp.run(transport="streamable-http")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
