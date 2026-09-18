#!/usr/bin/env python3
"""Synchronize the curated color groups in an Obsidian graph configuration.

The helper deliberately uses the vault's existing top-level path contract. It
never edits notes, tags, frontmatter, or unrelated graph settings.
"""

from __future__ import annotations

import argparse
import ctypes
import errno
import hashlib
import json
import os
import secrets
import stat
import sys
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterator

try:
    import fcntl
except ImportError:  # pragma: no cover - only relevant on non-POSIX hosts
    fcntl = None  # type: ignore[assignment]


DEFAULT_BACKUP_DIR = Path.home() / ".local/state/obsidian-vault-manager/backups"
LOCK_NAME = ".graph.json.vault-maintainer.lock"


@dataclass(frozen=True)
class GroupDefinition:
    """A human description plus the native Obsidian query it represents."""

    label: str
    query: str
    paths: tuple[str, ...]
    color_hex: str

    def color_entry(self) -> dict[str, object]:
        return {"a": 1, "rgb": rgb_from_hex(self.color_hex)}


# Keep this list small and tied to the documented vault map. The order is the
# priority order written to Obsidian, so the more operationally salient groups
# appear first if a future query overlaps one of these paths.
#
# Priority note: a more specific path group is placed before a broader one that
# contains it, so the specific group wins for matching notes. The
# "Unreproducible Claims" group is more specific than "Inbox" and appears first,
# so notes under `00-inbox/needs-review/` are colored red in the graph while the
# rest of the inbox remains amber. All needs-review items are attention items, so
# the broader red coloring is intentional; unreproducible-claim notes are also
# identifiable by their `type: unreproducible-claim` frontmatter.
GROUP_DEFINITIONS: tuple[GroupDefinition, ...] = (
    GroupDefinition(
        "Unreproducible Claims",
        "path:00-inbox/needs-review",
        ("00-inbox/needs-review",),
        "#EF4444",
    ),
    GroupDefinition("Inbox", "path:00-inbox", ("00-inbox",), "#F59E0B"),
    GroupDefinition(
        "Conversations", "path:01-conversations", ("01-conversations",), "#60A5FA"
    ),
    GroupDefinition(
        "Knowledge & Research",
        "path:02-knowledge OR path:05-research",
        ("02-knowledge", "05-research"),
        "#22D3EE",
    ),
    GroupDefinition(
        "Projects & Tasks",
        "path:03-projects OR path:05-tasks",
        ("03-projects", "05-tasks"),
        "#34D399",
    ),
    GroupDefinition("Decisions", "path:04-decisions", ("04-decisions",), "#A78BFA"),
    GroupDefinition(
        "People & System",
        "path:06-agents-and-people OR path:_system",
        ("06-agents-and-people", "_system"),
        "#F472B6",
    ),
)


@dataclass(frozen=True)
class GroupMatch:
    definition: GroupDefinition
    note_count: int

    def as_plan_dict(self) -> dict[str, object]:
        return {
            "label": self.definition.label,
            "query": self.definition.query,
            "color": self.definition.color_hex,
            "note_count": self.note_count,
        }

    def as_graph_dict(self) -> dict[str, object]:
        return {"query": self.definition.query, "color": self.definition.color_entry()}


@dataclass(frozen=True)
class VaultSnapshot:
    groups: tuple[GroupMatch, ...]
    markdown_sha256: str


@dataclass(frozen=True)
class SyncResult:
    changed: bool
    groups: tuple[GroupMatch, ...]
    before_sha256: str
    after_sha256: str
    backup_path: Path | None = None

    def as_dict(self) -> dict[str, object]:
        return {
            "changed": self.changed,
            "groups": [group.as_plan_dict() for group in self.groups],
            "before_sha256": self.before_sha256,
            "after_sha256": self.after_sha256,
            "backup_path": str(self.backup_path) if self.backup_path else None,
        }


def rgb_from_hex(value: str) -> int:
    """Convert an RGB hex color to Obsidian's packed integer representation."""

    normalized = value.removeprefix("#")
    if len(normalized) != 6:
        raise ValueError(f"RGB color must contain six hex digits: {value!r}")
    try:
        red = int(normalized[0:2], 16)
        green = int(normalized[2:4], 16)
        blue = int(normalized[4:6], 16)
    except ValueError as exc:
        raise ValueError(f"RGB color contains non-hex digits: {value!r}") from exc
    return (red << 16) | (green << 8) | blue


def _absolute_without_resolving(path: Path) -> Path:
    """Normalize `..` without following symlinks in any path component."""

    return Path(os.path.abspath(os.fspath(path.expanduser())))


def markdown_files(vault: Path) -> list[Path]:
    """Return regular Markdown notes, excluding application metadata."""

    ignored = {".git", ".obsidian"}
    result: list[Path] = []
    for path in vault.rglob("*.md"):
        relative_parts = path.relative_to(vault).parts
        if ignored.intersection(relative_parts):
            continue
        try:
            metadata = os.lstat(path)
            parent_parts = relative_parts[:-1]
            for index in range(1, len(parent_parts) + 1):
                parent = vault.joinpath(*parent_parts[:index])
                parent_metadata = os.lstat(parent)
                if stat.S_ISLNK(parent_metadata.st_mode) or not stat.S_ISDIR(parent_metadata.st_mode):
                    raise RuntimeError(f"Markdown note is under an unsafe directory: {path}")
        except FileNotFoundError:
            continue
        except RuntimeError:
            continue
        if stat.S_ISREG(metadata.st_mode):
            result.append(path)
    return sorted(result)


def _is_under(path: Path, folder: str, vault: Path) -> bool:
    relative = path.relative_to(vault).as_posix()
    return relative == folder or relative.startswith(f"{folder}/")


def _groups_for_notes(vault: Path, notes: list[Path]) -> tuple[GroupMatch, ...]:
    matches: list[GroupMatch] = []
    for definition in GROUP_DEFINITIONS:
        count = sum(
            any(_is_under(note, folder, vault) for folder in definition.paths)
            for note in notes
        )
        if count:
            matches.append(GroupMatch(definition, count))
    return tuple(matches)


def discover_groups(vault: Path) -> tuple[GroupMatch, ...]:
    """Return only groups with at least one existing Markdown note."""

    return _groups_for_notes(vault, markdown_files(vault))


def _stable_note_bytes(vault: Path, path: Path) -> bytes:
    relative_parts = path.relative_to(vault).parts
    parent_fd = _open_dir_no_symlink(
        vault.joinpath(*relative_parts[:-1]),
        create=False,
    )
    try:
        flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_CLOEXEC", 0)
        fd = os.open(relative_parts[-1], flags, dir_fd=parent_fd)
    finally:
        os.close(parent_fd)
    try:
        before = os.fstat(fd)
        if not stat.S_ISREG(before.st_mode):
            raise RuntimeError(f"Markdown note is no longer a regular file: {path}")
        chunks: list[bytes] = []
        while True:
            chunk = os.read(fd, 1024 * 1024)
            if not chunk:
                break
            chunks.append(chunk)
        after = os.fstat(fd)
        identity_before = (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns)
        identity_after = (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns)
        if identity_before != identity_after:
            raise RuntimeError(f"Markdown note changed during inspection: {path}")
        return b"".join(chunks)
    finally:
        os.close(fd)


def _vault_snapshot(vault: Path) -> VaultSnapshot:
    notes = markdown_files(vault)
    digest = hashlib.sha256()
    for path in notes:
        relative = path.relative_to(vault).as_posix().encode("utf-8")
        digest.update(relative)
        digest.update(b"\0")
        digest.update(_stable_note_bytes(vault, path))
        digest.update(b"\0")
    return VaultSnapshot(_groups_for_notes(vault, notes), digest.hexdigest())


def _validate_paths(vault: Path, graph_path: Path) -> tuple[Path, Path]:
    vault = _absolute_without_resolving(vault).resolve()
    graph_path = _absolute_without_resolving(graph_path)
    if not vault.is_dir():
        raise ValueError(f"Vault directory does not exist: {vault}")
    try:
        graph_path.relative_to(vault)
    except ValueError as exc:
        raise ValueError("Graph configuration must be inside the vault") from exc
    if graph_path.name != "graph.json" or graph_path.parent.name != ".obsidian":
        raise ValueError("Graph configuration must be the vault's .obsidian/graph.json")
    try:
        metadata = os.lstat(graph_path)
    except FileNotFoundError as exc:
        raise ValueError(f"Graph configuration does not exist: {graph_path}") from exc
    if stat.S_ISLNK(metadata.st_mode):
        raise ValueError(f"Refusing to edit symlinked graph configuration: {graph_path}")
    if not stat.S_ISREG(metadata.st_mode):
        raise ValueError(f"Graph configuration is not a regular file: {graph_path}")
    return vault, graph_path


def _directory_flags() -> int:
    if os.name != "posix":
        raise RuntimeError("Safe descriptor-relative graph maintenance requires POSIX")
    return os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_CLOEXEC", 0)


def _open_dir_no_symlink(path: Path, *, create: bool) -> int:
    """Open a directory while refusing symlinked path components."""

    absolute = _absolute_without_resolving(path)
    fd = os.open(os.sep, _directory_flags())
    try:
        for component in absolute.parts[1:]:
            if component in {"", "."}:
                continue
            try:
                next_fd = os.open(component, _directory_flags(), dir_fd=fd)
            except FileNotFoundError:
                if not create:
                    raise
                os.mkdir(component, 0o700, dir_fd=fd)
                next_fd = os.open(component, _directory_flags(), dir_fd=fd)
            os.close(fd)
            fd = next_fd
        return fd
    except BaseException:
        os.close(fd)
        raise


def _read_entry(parent_fd: int, name: str = "graph.json") -> tuple[bytes, os.stat_result]:
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_CLOEXEC", 0)
    fd = os.open(name, flags, dir_fd=parent_fd)
    try:
        metadata_before = os.fstat(fd)
        if not stat.S_ISREG(metadata_before.st_mode):
            raise ValueError(f"Graph configuration is not a regular file: {name}")
        chunks: list[bytes] = []
        while True:
            chunk = os.read(fd, 1024 * 1024)
            if not chunk:
                break
            chunks.append(chunk)
        metadata_after = os.fstat(fd)
        identity_before = (
            metadata_before.st_dev,
            metadata_before.st_ino,
            metadata_before.st_size,
            metadata_before.st_mtime_ns,
        )
        identity_after = (
            metadata_after.st_dev,
            metadata_after.st_ino,
            metadata_after.st_size,
            metadata_after.st_mtime_ns,
        )
        if identity_before != identity_after:
            raise RuntimeError(f"Graph configuration changed during inspection: {name}")
        return b"".join(chunks), metadata_after
    finally:
        os.close(fd)


def _load_graph(graph_path: Path, raw: bytes | None = None) -> dict[str, object]:
    if raw is None:
        raw = graph_path.read_bytes()
    try:
        graph = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"Graph configuration is not valid UTF-8 JSON: {graph_path}") from exc
    if not isinstance(graph, dict):
        raise ValueError("Graph configuration must contain a JSON object")
    color_groups = graph.get("colorGroups", [])
    if not isinstance(color_groups, list):
        raise ValueError("Graph configuration colorGroups must be a JSON array")
    return graph


def _updated_graph(graph: dict[str, object], groups: tuple[GroupMatch, ...]) -> dict[str, object]:
    updated = dict(graph)
    updated["colorGroups"] = [group.as_graph_dict() for group in groups]
    return updated


def _json_bytes(graph: dict[str, object]) -> bytes:
    return (json.dumps(graph, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


@contextmanager
def _graph_lock(graph_path: Path) -> Iterator[int]:
    """Serialize helper writers using a no-follow, descriptor-relative lock."""

    parent_fd = _open_dir_no_symlink(graph_path.parent, create=False)
    lock_fd: int | None = None
    try:
        lock_flags = (
            os.O_RDWR
            | os.O_CREAT
            | os.O_NOFOLLOW
            | getattr(os, "O_CLOEXEC", 0)
        )
        lock_fd = os.open(LOCK_NAME, lock_flags, 0o600, dir_fd=parent_fd)
        if fcntl is not None:
            try:
                fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as exc:
                raise RuntimeError("Another graph maintenance run holds the graph lock") from exc
        try:
            yield parent_fd
        finally:
            if fcntl is not None:
                fcntl.flock(lock_fd, fcntl.LOCK_UN)
    finally:
        if lock_fd is not None:
            os.close(lock_fd)
        os.close(parent_fd)


def _write_all(fd: int, data: bytes) -> None:
    view = memoryview(data)
    while view:
        written = os.write(fd, view)
        view = view[written:]


def _backup(backup_dir: Path, raw: bytes) -> Path:
    """Create an exact backup using exclusive, descriptor-relative creation."""

    backup_dir = _absolute_without_resolving(backup_dir)
    directory_fd = _open_dir_no_symlink(backup_dir, create=True)
    try:
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        for suffix in range(1000):
            filename = f"graph.json.{stamp}.bak" if suffix == 0 else f"graph.json.{stamp}.{suffix}.bak"
            flags = (
                os.O_WRONLY
                | os.O_CREAT
                | os.O_EXCL
                | os.O_NOFOLLOW
                | getattr(os, "O_CLOEXEC", 0)
            )
            try:
                backup_fd = os.open(filename, flags, 0o600, dir_fd=directory_fd)
            except FileExistsError:
                continue
            try:
                _write_all(backup_fd, raw)
                os.fsync(backup_fd)
            except BaseException:
                try:
                    os.unlink(filename, dir_fd=directory_fd)
                except FileNotFoundError:
                    pass
                raise
            finally:
                os.close(backup_fd)
            os.fsync(directory_fd)
            return backup_dir / filename
        raise RuntimeError("Unable to reserve a unique graph backup name")
    finally:
        os.close(directory_fd)


def _stat_entry(parent_fd: int, name: str) -> os.stat_result:
    metadata = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
    if not stat.S_ISREG(metadata.st_mode):
        raise ValueError(f"Graph configuration is not a regular file: {name}")
    return metadata


def _same_identity(left: os.stat_result, right: os.stat_result) -> bool:
    return (left.st_dev, left.st_ino) == (right.st_dev, right.st_ino)


def _unlink_if_identity(parent_fd: int, name: str, expected: os.stat_result) -> bool:
    try:
        current = _stat_entry(parent_fd, name)
    except FileNotFoundError:
        return True
    except (OSError, ValueError):
        return False
    if not _same_identity(current, expected):
        return False
    try:
        os.unlink(name, dir_fd=parent_fd)
    except FileNotFoundError:
        return True
    except OSError:
        return False
    return True


def _create_temp(parent_fd: int, raw: bytes, mode: int) -> tuple[str, int, os.stat_result]:
    flags = (
        os.O_WRONLY
        | os.O_CREAT
        | os.O_EXCL
        | os.O_NOFOLLOW
        | getattr(os, "O_CLOEXEC", 0)
    )
    temporary_name: str | None = None
    temporary_fd: int | None = None
    for _ in range(1000):
        candidate = f".graph.json.{secrets.token_hex(16)}.tmp"
        try:
            temporary_fd = os.open(candidate, flags, mode, dir_fd=parent_fd)
        except FileExistsError:
            continue
        temporary_name = candidate
        break
    if temporary_fd is None or temporary_name is None:
        raise RuntimeError("Unable to reserve a temporary graph configuration name")
    temporary_stat = os.fstat(temporary_fd)
    try:
        os.fchmod(temporary_fd, mode)
        _write_all(temporary_fd, raw)
        os.fsync(temporary_fd)
        return temporary_name, temporary_fd, os.fstat(temporary_fd)
    except BaseException:
        os.close(temporary_fd)
        _unlink_if_identity(parent_fd, temporary_name, temporary_stat)
        raise


def _rename_exchange(parent_fd: int, source: str, destination: str) -> bool:
    """Atomically exchange two names when Linux renameat2 is available."""

    if sys.platform != "linux":
        return False
    try:
        libc = ctypes.CDLL(None, use_errno=True)
        renameat2 = libc.renameat2
    except (AttributeError, OSError):
        return False
    renameat2.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    renameat2.restype = ctypes.c_int
    result = renameat2(
        parent_fd,
        source.encode("utf-8"),
        parent_fd,
        destination.encode("utf-8"),
        0x2,  # RENAME_EXCHANGE
    )
    if result == 0:
        return True
    error_number = ctypes.get_errno()
    if error_number in {errno.ENOSYS, errno.EINVAL, errno.ENOTSUP}:
        return False
    raise OSError(error_number, os.strerror(error_number))


def _atomic_write(
    parent_fd: int,
    raw: bytes,
    mode: int,
    expected_before: bytes,
    expected_before_stat: os.stat_result,
) -> None:
    """Publish without clobbering a graph changed by an external writer."""

    temporary_name, temporary_fd, temporary_stat = _create_temp(parent_fd, raw, mode)
    exchanged = False
    try:
        if not _same_identity(_stat_entry(parent_fd, temporary_name), temporary_stat):
            raise RuntimeError("Temporary graph configuration changed before publication")
        exchanged = _rename_exchange(parent_fd, temporary_name, "graph.json")
        if not exchanged:
            raise RuntimeError("Safe graph publication requires renameat2(RENAME_EXCHANGE)")

        os.fsync(parent_fd)
        # After exchange, graph.json must still be the exact prepared inode.
        try:
            published, published_stat = _read_entry(parent_fd, "graph.json")
        except (OSError, RuntimeError, ValueError) as exc:
            # A symlink or non-regular replacement is never a valid winner.
            # If the displaced entry is still the verified old graph, exchange
            # it back so an attacker-controlled source cannot remain at target.
            try:
                displaced_stat = _stat_entry(parent_fd, temporary_name)
                if _same_identity(displaced_stat, expected_before_stat):
                    _rename_exchange(parent_fd, temporary_name, "graph.json")
                    os.fsync(parent_fd)
                    exchanged = False
            except (OSError, RuntimeError, ValueError):
                pass
            raise RuntimeError("Graph configuration changed during atomic publication") from exc
        if not _same_identity(published_stat, temporary_stat):
            raise RuntimeError("Graph configuration changed during atomic publication")
        try:
            displaced, displaced_stat = _read_entry(parent_fd, temporary_name)
        except (OSError, RuntimeError, ValueError) as exc:
            # A symlink/non-regular graph that arrived before exchange must be
            # restored at graph.json, never silently replaced by our plan.
            try:
                displaced_lstat = os.stat(
                    temporary_name,
                    dir_fd=parent_fd,
                    follow_symlinks=False,
                )
                if not stat.S_ISREG(displaced_lstat.st_mode):
                    _rename_exchange(parent_fd, temporary_name, "graph.json")
                    os.fsync(parent_fd)
                    exchanged = False
            except (OSError, RuntimeError, ValueError):
                pass
            raise RuntimeError("Graph configuration changed before atomic publication") from exc
        if displaced != expected_before or not _same_identity(displaced_stat, expected_before_stat):
            _rename_exchange(parent_fd, temporary_name, "graph.json")
            os.fsync(parent_fd)
            exchanged = False
            raise RuntimeError("Graph configuration changed before atomic publication")
        if published != raw:
            raise RuntimeError("Graph configuration changed during atomic publication")

        # Recheck both names before removing the displaced file. If an external
        # writer wins after publication, leave its graph state in place.
        latest, latest_stat = _read_entry(parent_fd, "graph.json")
        latest_displaced, latest_displaced_stat = _read_entry(parent_fd, temporary_name)
        if not _same_identity(latest_stat, temporary_stat) or latest != raw:
            raise RuntimeError("Graph configuration changed after atomic publication")
        if not _same_identity(latest_displaced_stat, displaced_stat) or latest_displaced != expected_before:
            raise RuntimeError("Temporary graph entry changed before cleanup")
        if not _unlink_if_identity(parent_fd, temporary_name, displaced_stat):
            raise RuntimeError("Temporary graph entry changed before cleanup")
        os.fsync(parent_fd)
        exchanged = False
    except BaseException:
        if exchanged:
            # Roll back only when both entries still prove that our exchange is
            # present. Never exchange an unknown external object over graph.json.
            try:
                current_graph, current_graph_stat = _read_entry(parent_fd, "graph.json")
                current_displaced, current_displaced_stat = _read_entry(parent_fd, temporary_name)
                if (
                    current_graph == raw
                    and _same_identity(current_graph_stat, temporary_stat)
                    and current_displaced == expected_before
                    and _same_identity(current_displaced_stat, expected_before_stat)
                ):
                    _rename_exchange(parent_fd, temporary_name, "graph.json")
                    os.fsync(parent_fd)
                    exchanged = False
            except (OSError, RuntimeError, ValueError):
                pass
        raise
    finally:
        try:
            _unlink_if_identity(parent_fd, temporary_name, temporary_stat)
        finally:
            os.close(temporary_fd)


def _workspace_active_leaf_types(node: object, active_id: str) -> list[str | None]:
    matches: list[str | None] = []
    if isinstance(node, dict):
        if node.get("id") == active_id and node.get("type") == "leaf":
            state = node.get("state")
            matches.append(state.get("type") if isinstance(state, dict) else None)
        for value in node.values():
            matches.extend(_workspace_active_leaf_types(value, active_id))
    elif isinstance(node, list):
        for value in node:
            matches.extend(_workspace_active_leaf_types(value, active_id))
    return matches


def _active_graph_view(vault: Path) -> bool:
    """Return whether the active Obsidian workspace leaf is a graph view."""

    parent_fd = _open_dir_no_symlink(vault / ".obsidian", create=False)
    try:
        raw, _ = _read_entry(parent_fd, "workspace.json")
    finally:
        os.close(parent_fd)
    try:
        workspace = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise RuntimeError("Obsidian workspace is not valid UTF-8 JSON") from exc
    if not isinstance(workspace, dict):
        raise RuntimeError("Obsidian workspace must contain a JSON object")
    active_id = workspace.get("active")
    if not isinstance(active_id, str):
        raise RuntimeError("Obsidian workspace active leaf is missing")
    active_types = _workspace_active_leaf_types(workspace, active_id)
    if len(active_types) != 1 or not isinstance(active_types[0], str):
        raise RuntimeError("Obsidian workspace active leaf is missing or ambiguous")
    return active_types[0] == "graph"


def plan(vault: Path) -> tuple[GroupMatch, ...]:
    vault = _absolute_without_resolving(vault).resolve()
    if not vault.is_dir():
        raise ValueError(f"Vault directory does not exist: {vault}")
    return _vault_snapshot(vault).groups


def sync(
    vault: Path,
    graph_path: Path,
    backup_dir: Path = DEFAULT_BACKUP_DIR,
    *,
    dry_run: bool = False,
) -> SyncResult:
    """Synchronize managed groups and preserve every unrelated graph setting."""

    vault, graph_path = _validate_paths(vault, graph_path)
    if not dry_run and _active_graph_view(vault):
        raise RuntimeError("Obsidian graph view is active; deferring graph configuration sync")
    with _graph_lock(graph_path) as parent_fd:
        before, before_stat = _read_entry(parent_fd)
        current_graph = _load_graph(graph_path, before)
        snapshot = _vault_snapshot(vault)
        desired_graph = _updated_graph(current_graph, snapshot.groups)

        # Check both the graph and all Markdown inputs again after discovery so
        # a concurrent editor cannot cause a stale grouping plan to be written.
        observed, _ = _read_entry(parent_fd)
        observed_snapshot = _vault_snapshot(vault)
        if observed != before or observed_snapshot.markdown_sha256 != snapshot.markdown_sha256:
            raise RuntimeError("Vault or graph configuration changed during inspection; refusing to overwrite it")
        if current_graph == desired_graph:
            digest = sha256_bytes(before)
            return SyncResult(False, snapshot.groups, digest, digest)

        desired = _json_bytes(desired_graph)
        if dry_run:
            return SyncResult(True, snapshot.groups, sha256_bytes(before), sha256_bytes(desired))

        backup_path = _backup(backup_dir, before)

        # The backup can take time. Perform the final optimistic checks directly
        # before replacement; the advisory lock does not coordinate with an
        # Obsidian process that ignores this helper's lock file.
        final_before, final_stat = _read_entry(parent_fd)
        final_snapshot = _vault_snapshot(vault)
        if final_before != before or final_snapshot.markdown_sha256 != snapshot.markdown_sha256:
            raise RuntimeError("Vault or graph configuration changed before replacement; refusing to overwrite it")
        if (final_stat.st_dev, final_stat.st_ino) != (before_stat.st_dev, before_stat.st_ino):
            raise RuntimeError("Graph configuration identity changed before replacement; refusing to overwrite it")
        if _active_graph_view(vault):
            raise RuntimeError("Obsidian graph view became active before replacement; refusing to overwrite it")

        _atomic_write(
            parent_fd,
            desired,
            stat.S_IMODE(final_stat.st_mode),
            before,
            before_stat,
        )
        written, _ = _read_entry(parent_fd)
        if written != desired:
            raise RuntimeError("Graph configuration did not match the verified atomic write")
        return SyncResult(
            True,
            snapshot.groups,
            sha256_bytes(before),
            sha256_bytes(written),
            backup_path,
        )


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("plan", "sync", "check"))
    parser.add_argument("--vault", type=Path, required=True)
    parser.add_argument("--graph", type=Path, default=None)
    parser.add_argument("--backup-dir", type=Path, default=DEFAULT_BACKUP_DIR)
    parser.add_argument("--dry-run", action="store_true", help="Show a sync without writing")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    vault = args.vault.expanduser().resolve()
    graph = args.graph or vault / ".obsidian/graph.json"
    try:
        if args.command == "plan":
            groups = plan(vault)
            result: dict[str, object] = {
                "vault": str(vault),
                "groups": [group.as_plan_dict() for group in groups],
            }
        elif args.command == "check":
            synced = sync(vault, graph, args.backup_dir, dry_run=True)
            result = synced.as_dict()
            if synced.changed:
                print(json.dumps(result, indent=2, ensure_ascii=False))
                return 1
        else:
            synced = sync(vault, graph, args.backup_dir, dry_run=args.dry_run)
            result = synced.as_dict()
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"obsidian_graph_groups: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
