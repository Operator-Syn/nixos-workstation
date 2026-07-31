#!/usr/bin/env python3
"""Audit and reconcile Hermes runtime skill documentation against the vault.

The default mode is read-only. Apply mode only performs deterministic writes for
skills whose vault note explicitly declares reconciliation_mode.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import sys
import tempfile
import uuid
from dataclasses import dataclass
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_RUNTIME = Path("/home/yashindo/.hermes/skills")
DEFAULT_VAULT = Path("/srv/obsidian/hermes-vault/50 Reference/Skills")
DEFAULT_REGISTRY = Path("/srv/obsidian/hermes-vault/50 Reference/Hermes Skills Registry.md")
DEFAULT_BACKUPS = Path.home() / ".cache" / "hermes-skill-reconcile" / "backups"
FRONTMATTER_START = "---\n"
CANONICAL_MARKER = "## Canonical Skill Content"
CANONICAL_BOUNDARY = re.compile(r"\n## (?:Independent Audit Summary|Audit Notes|Computer Use)\b")


@dataclass(frozen=True)
class RuntimeSkill:
    name: str
    path: Path
    relative_path: str
    category: str
    content: str
    metadata: dict[str, str]
    sha256: str


@dataclass(frozen=True)
class VaultNote:
    name: str
    path: Path
    content: str
    metadata: dict[str, str]


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def parse_frontmatter(text: str) -> dict[str, str]:
    if not text.startswith(FRONTMATTER_START):
        return {}
    end = text.find("\n---", len(FRONTMATTER_START))
    if end < 0:
        return {}
    metadata: dict[str, str] = {}
    for line in text[len(FRONTMATTER_START) : end].splitlines():
        if not line or line.startswith((" ", "\t")) or ":" not in line:
            continue
        key, value = line.split(":", 1)
        metadata[key.strip()] = value.strip().strip("\"'")
    return metadata


def _frontmatter_end(text: str) -> int:
    end = text.find("\n---", len(FRONTMATTER_START))
    if end < 0:
        raise ValueError("missing frontmatter closing marker")
    return end + len("\n---")


def update_frontmatter(text: str, updates: dict[str, str]) -> str:
    end = _frontmatter_end(text)
    lines = text[len(FRONTMATTER_START) : end - len("\n---")].splitlines()
    seen: set[str] = set()
    output: list[str] = []
    for line in lines:
        if ":" in line and not line.startswith((" ", "\t")):
            key = line.split(":", 1)[0].strip()
            if key in updates:
                output.append(f"{key}: {updates[key]}")
                seen.add(key)
                continue
        output.append(line)
    for key, value in updates.items():
        if key not in seen and not any(line.startswith(f"{key}:") for line in output):
            output.append(f"{key}: {value}")
    return FRONTMATTER_START + "\n".join(output) + "\n---" + text[end:]


def extract_canonical_content(note_text: str) -> str:
    marker = note_text.find(CANONICAL_MARKER)
    if marker < 0:
        raise ValueError("vault note has no canonical skill-content section")
    start = note_text.find("\n", marker)
    if start < 0:
        raise ValueError("canonical skill-content section is empty")
    start += 1
    while start < len(note_text) and note_text[start] == "\n":
        start += 1
    boundary = CANONICAL_BOUNDARY.search(note_text, start)
    end = boundary.start() if boundary else len(note_text)
    content = note_text[start:end].strip("\n") + "\n"
    if not content.startswith(FRONTMATTER_START):
        raise ValueError("canonical skill content must contain runtime frontmatter")
    return content


def replace_canonical_content(note_text: str, runtime_content: str) -> str:
    marker = note_text.find(CANONICAL_MARKER)
    if marker < 0:
        raise ValueError("vault note has no canonical skill-content section")
    start = note_text.find("\n", marker)
    if start < 0:
        raise ValueError("canonical skill-content section is empty")
    start += 1
    while start < len(note_text) and note_text[start] == "\n":
        start += 1
    boundary = CANONICAL_BOUNDARY.search(note_text, start)
    end = boundary.start() if boundary else len(note_text)
    prefix = note_text[:start]
    suffix = note_text[end:]
    return prefix + runtime_content.rstrip("\n") + "\n" + suffix


def _safe_child(root: Path, candidate: Path) -> Path:
    root = root.resolve()
    candidate = candidate.resolve()
    try:
        candidate.relative_to(root)
    except ValueError as exc:
        raise ValueError(f"path escapes root: {candidate}") from exc
    return candidate


def discover_runtime(root: Path) -> dict[str, RuntimeSkill]:
    root = root.resolve()
    if not root.is_dir():
        raise FileNotFoundError(f"runtime skill root is not a directory: {root}")
    skills: dict[str, RuntimeSkill] = {}
    for path in sorted(root.rglob("SKILL.md")):
        if ".archive" in path.parts or path.is_symlink():
            continue
        path = _safe_child(root, path)
        content = path.read_text(encoding="utf-8")
        metadata = parse_frontmatter(content)
        name = metadata.get("name", "").strip()
        if not name:
            continue
        relative = path.relative_to(root).as_posix()
        category = path.parent.relative_to(root).as_posix()
        if name in skills:
            raise ValueError(f"duplicate runtime skill name: {name}")
        skills[name] = RuntimeSkill(
            name=name,
            path=path,
            relative_path=relative,
            category=category,
            content=content,
            metadata=metadata,
            sha256=sha256_text(content),
        )
    return skills


def discover_vault_notes(root: Path) -> dict[str, VaultNote]:
    root = root.resolve()
    if not root.is_dir():
        raise FileNotFoundError(f"vault skill-note root is not a directory: {root}")
    notes: dict[str, VaultNote] = {}
    for path in sorted(root.glob("*.md")):
        if path.is_symlink():
            continue
        path = _safe_child(root, path)
        content = path.read_text(encoding="utf-8")
        metadata = parse_frontmatter(content)
        if metadata.get("skill_category", "").strip().casefold() == "archived":
            continue
        name = metadata.get("skill_name", "").strip()
        if not name:
            continue
        if name in notes:
            raise ValueError(f"duplicate vault skill note: {name}")
        notes[name] = VaultNote(name=name, path=path, content=content, metadata=metadata)
    return notes


def registry_contains(registry: Path, name: str) -> bool:
    return name in registry.read_text(encoding="utf-8")


def audit(runtime_root: Path, vault_root: Path, registry: Path) -> dict[str, Any]:
    runtime = discover_runtime(runtime_root)
    vault = discover_vault_notes(vault_root)
    issues: list[dict[str, Any]] = []
    for name, skill in runtime.items():
        note = vault.get(name)
        if note is None:
            issues.append({"kind": "runtime_only", "name": name, "runtime_path": skill.relative_path})
            continue
        expected_hash = note.metadata.get("source_sha256", "")
        if expected_hash != skill.sha256:
            issues.append(
                {
                    "kind": "hash_mismatch",
                    "name": name,
                    "runtime_path": skill.relative_path,
                    "vault_path": note.path.name,
                    "runtime_sha256": skill.sha256,
                    "vault_sha256": expected_hash,
                    "reconciliation_mode": note.metadata.get("reconciliation_mode", "manual_review"),
                }
            )
        if note.metadata.get("source_path", "") != str(skill.path):
            issues.append(
                {
                    "kind": "source_path_mismatch",
                    "name": name,
                    "runtime_path": skill.relative_path,
                    "vault_path": note.path.name,
                }
            )
        if not registry_contains(registry, name):
            issues.append({"kind": "registry_missing", "name": name, "runtime_path": skill.relative_path})
    for name, note in vault.items():
        if name not in runtime:
            issues.append({"kind": "vault_only", "name": name, "vault_path": note.path.name})
    return {
        "runtime_count": len(runtime),
        "vault_count": len(vault),
        "issues": issues,
    }


def _backup(path: Path, backup_root: Path) -> Path | None:
    if not path.exists():
        return None
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    destination = backup_root / stamp / f"{path.name}.{uuid.uuid4().hex}.bak"
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, destination)
    return destination


def atomic_write(path: Path, content: str, backup_root: Path) -> Path | None:
    if path.is_symlink():
        raise ValueError(f"refusing to write through symlink: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    backup = _backup(path, backup_root)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return backup


def append_pending_registry(registry: Path, name: str, backup_root: Path) -> Path | None:
    text = registry.read_text(encoding="utf-8")
    link = f"- [[Skills/{name}|{name}]]"
    if link in text:
        return None
    section = "### pending-review\n"
    if section not in text:
        updated = text.rstrip("\n") + "\n\n" + section + link + "\n"
    else:
        updated = text.rstrip("\n") + "\n" + link + "\n"
    return atomic_write(registry, updated, backup_root)


def _draft_note(skill: RuntimeSkill) -> str:
    title = "".join(part.capitalize() for part in skill.name.split("-"))
    today = date.today().isoformat()
    metadata = [
        "---",
        f"title: {title}",
        "type: hermes-skill-reference",
        f"skill_name: {skill.name}",
        f"skill_category: {skill.category}",
        f"source_path: {skill.path}",
        f"source_sha256: {skill.sha256}",
        "reconciliation_mode: manual_review",
        "reconciliation_status: pending-review",
        f"audited_at: {today}",
        "---",
        "",
        f"# {title}",
        "",
        f"> Generated documentation draft for `{skill.path}`. Review before promotion to an active canonical reference.",
        "",
        "## Canonical Skill Content",
        "",
        skill.content.rstrip("\n"),
        "",
        "## Reconciliation Notes",
        "",
        "This note was created by the deterministic reconciler and remains pending review.",
        "",
    ]
    return "\n".join(metadata)


def _find_runtime(name: str, runtime_root: Path) -> RuntimeSkill:
    return discover_runtime(runtime_root)[name]


def reconcile(
    runtime_root: Path,
    vault_root: Path,
    registry: Path,
    backup_root: Path,
    *,
    apply: bool,
) -> dict[str, Any]:
    initial = audit(runtime_root, vault_root, registry)
    report: dict[str, Any] = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "mode": "reconcile" if apply else "check",
        "detected": initial["issues"],
        "applied": [],
        "manual_review": [],
        "failed": [],
        "verification": {"zero_drift": not initial["issues"]},
        "runtime_count": initial["runtime_count"],
        "vault_count": initial["vault_count"],
    }
    if not apply:
        report["status"] = "clean" if not initial["issues"] else "drift"
        return report

    runtime = discover_runtime(runtime_root)
    vault = discover_vault_notes(vault_root)
    handled: set[str] = set()
    for issue in initial["issues"]:
        name = issue["name"]
        if name in handled:
            continue
        handled.add(name)
        try:
            skill = runtime.get(name)
            note = vault.get(name)
            if skill is None or note is None:
                if skill is not None and note is None:
                    note_path = vault_root / f"{name}.md"
                    backup = atomic_write(note_path, _draft_note(skill), backup_root)
                    report["applied"].append(
                        {"name": name, "action": "created_pending_review_draft", "path": str(note_path), "backup": str(backup) if backup else None}
                    )
                    registry_backup = append_pending_registry(registry, name, backup_root)
                    report["applied"].append(
                        {"name": name, "action": "registered_pending_review", "path": str(registry), "backup": str(registry_backup) if registry_backup else None}
                    )
                    report["manual_review"].append(
                        {"kind": "pending_review", "name": name, "reason": "new runtime skill requires canonical review"}
                    )
                else:
                    report["manual_review"].append(issue)
                continue
            if issue["kind"] == "registry_missing" and note.metadata.get("reconciliation_status") == "pending-review":
                registry_backup = append_pending_registry(registry, name, backup_root)
                report["applied"].append(
                    {"name": name, "action": "registered_pending_review", "path": str(registry), "backup": str(registry_backup) if registry_backup else None}
                )
                report["manual_review"].append(
                    {"kind": "pending_review", "name": name, "reason": "new runtime skill requires canonical review"}
                )
                continue
            mode = note.metadata.get("reconciliation_mode", "manual_review")
            if mode == "vault_to_runtime":
                canonical = extract_canonical_content(note.content)
                backup = atomic_write(skill.path, canonical, backup_root)
                report["applied"].append(
                    {"name": name, "action": "vault_to_runtime", "path": str(skill.path), "backup": str(backup) if backup else None, "post_sha256": sha256_text(canonical)}
                )
            elif mode == "runtime_to_vault":
                updated = replace_canonical_content(note.content, skill.content)
                updated = update_frontmatter(
                    updated,
                    {
                        "source_path": str(skill.path),
                        "source_sha256": skill.sha256,
                        "audited_at": date.today().isoformat(),
                    },
                )
                backup = atomic_write(note.path, updated, backup_root)
                report["applied"].append(
                    {"name": name, "action": "runtime_to_vault", "path": str(note.path), "backup": str(backup) if backup else None, "post_sha256": skill.sha256}
                )
            else:
                report["manual_review"].append({**issue, "reason": "reconciliation_mode is manual_review or missing"})
        except Exception as exc:  # noqa: BLE001 - report every failed target and continue safely
            report["failed"].append({**issue, "error": f"{type(exc).__name__}: {exc}"})

    final = audit(runtime_root, vault_root, registry)
    report["verification"] = {
        "zero_drift": not final["issues"],
        "remaining_issues": final["issues"],
    }
    if report["failed"] and not report["applied"]:
        report["status"] = "failed"
    elif final["issues"] or report["manual_review"] or report["failed"]:
        report["status"] = "partial"
    else:
        report["status"] = "reconciled"
    return report


def build_report(
    runtime_root: Path,
    vault_root: Path,
    registry: Path,
    *,
    apply: bool,
    backup_root: Path = DEFAULT_BACKUPS,
) -> dict[str, Any]:
    return reconcile(runtime_root, vault_root, registry, backup_root, apply=apply)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, default=DEFAULT_RUNTIME)
    parser.add_argument("--vault", type=Path, default=DEFAULT_VAULT)
    parser.add_argument("--registry", type=Path, default=DEFAULT_REGISTRY)
    parser.add_argument("--backup-root", type=Path, default=DEFAULT_BACKUPS)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--check", action="store_true", help="audit only (the default)")
    group.add_argument("--reconcile", action="store_true", help="enable reconciliation mode")
    parser.add_argument("--apply", action="store_true", help="apply allowlisted deterministic repairs")
    args = parser.parse_args(argv)
    if args.apply and not args.reconcile:
        parser.error("--apply requires --reconcile")
    try:
        report = build_report(
            args.runtime.resolve(),
            args.vault.resolve(),
            args.registry.resolve(),
            apply=bool(args.reconcile and args.apply),
            backup_root=args.backup_root.resolve(),
        )
    except Exception as exc:  # noqa: BLE001 - cron must emit a machine-readable failure
        print(json.dumps({"status": "failed", "error": f"{type(exc).__name__}: {exc}"}, sort_keys=True))
        return 3
    print(json.dumps(report, ensure_ascii=False, sort_keys=True))
    if report["status"] == "failed":
        return 3
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
