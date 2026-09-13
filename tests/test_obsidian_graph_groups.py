from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import os
import sys
import tempfile
import unittest
from datetime import datetime as datetime_type
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = ROOT / "scripts" / "obsidian_graph_groups.py"


def load_helper():
    spec = importlib.util.spec_from_file_location("obsidian_graph_groups", SCRIPT_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {SCRIPT_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class ObsidianGraphGroupsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.helper = load_helper()

    def make_vault(self, directory: str) -> tuple[Path, Path, Path]:
        vault = Path(directory)
        graph_path = vault / ".obsidian" / "graph.json"
        backup_dir = vault / "backups"
        graph_path.parent.mkdir(parents=True)
        graph_path.write_text(
            json.dumps(
                {
                    "collapse-filter": True,
                    "search": "path:02-knowledge",
                    "showTags": False,
                    "colorGroups": [{"query": "tag:#old", "color": {"a": 1, "rgb": 1}}],
                    "nodeSizeMultiplier": 1.75,
                },
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )
        (vault / ".obsidian" / "workspace.json").write_text(
            json.dumps(
                {
                    "main": {
                        "type": "tabs",
                        "children": [
                            {
                                "type": "leaf",
                                "id": "active-empty",
                                "state": {"type": "empty"},
                            }
                        ],
                    },
                    "active": "active-empty",
                }
            )
            + "\n",
            encoding="utf-8",
        )
        return vault, graph_path, backup_dir

    def add_note(self, vault: Path, relative_path: str) -> None:
        note = vault / relative_path
        note.parent.mkdir(parents=True, exist_ok=True)
        note.write_text("# note\n", encoding="utf-8")

    def test_rgb_packing_matches_obsidian_integer_format(self):
        self.assertEqual(self.helper.rgb_from_hex("#F59E0B"), int("F59E0B", 16))
        self.assertEqual(self.helper.rgb_from_hex("22D3EE"), int("22D3EE", 16))
        with self.assertRaises(ValueError):
            self.helper.rgb_from_hex("#12")

    def test_discover_groups_uses_stable_order_and_nonempty_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            vault = Path(directory)
            paths = (
                "00-inbox/one.md",
                "01-conversations/thread/overview.md",
                "02-knowledge/topic/one.md",
                "05-research/audit.md",
                "03-projects/project/current-state.md",
                "05-tasks/active/task.md",
                "04-decisions/decision.md",
                "06-agents-and-people/user/profile.md",
                "_system/changelog.md",
                "90-archive/source.md",
            )
            for path in paths:
                self.add_note(vault, path)
            self.add_note(vault, ".obsidian/ignored.md")

            groups = self.helper.discover_groups(vault)

            self.assertEqual(
                [group.definition.label for group in groups],
                [
                    "Inbox",
                    "Conversations",
                    "Knowledge & Research",
                    "Projects & Tasks",
                    "Decisions",
                    "People & System",
                ],
            )
            self.assertEqual([group.note_count for group in groups], [1, 1, 2, 2, 1, 2])

    def test_discovery_ignores_symlinked_notes_and_directories(self):
        with tempfile.TemporaryDirectory() as directory:
            vault = Path(directory)
            (vault / "00-inbox").mkdir(parents=True)
            (vault / "01-conversations").mkdir()
            outside_note = vault.parent / f"outside-note-{vault.name}.md"
            outside_dir = vault.parent / f"outside-dir-{vault.name}"
            outside_dir.mkdir()
            outside_note.write_text("# external\n", encoding="utf-8")
            (outside_dir / "external.md").write_text("# external\n", encoding="utf-8")
            try:
                (vault / "00-inbox" / "linked.md").symlink_to(outside_note)
                (vault / "01-conversations" / "linked-dir").symlink_to(
                    outside_dir,
                    target_is_directory=True,
                )

                self.assertEqual(self.helper.discover_groups(vault), ())
            finally:
                outside_note.unlink(missing_ok=True)
                (outside_dir / "external.md").unlink(missing_ok=True)
                outside_dir.rmdir()

    def test_sync_preserves_unrelated_settings_and_backs_up_exact_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            vault, graph_path, backup_dir = self.make_vault(directory)
            for path in (
                "00-inbox/item.md",
                "01-conversations/thread.md",
                "02-knowledge/item.md",
                "03-projects/item.md",
                "04-decisions/item.md",
                "05-research/item.md",
                "05-tasks/item.md",
                "06-agents-and-people/item.md",
                "_system/rules.md",
            ):
                self.add_note(vault, path)
            before = graph_path.read_bytes()
            original = json.loads(before)

            result = self.helper.sync(vault, graph_path, backup_dir)

            self.assertTrue(result.changed)
            self.assertIsNotNone(result.backup_path)
            self.assertEqual(result.backup_path.read_bytes(), before)
            updated = json.loads(graph_path.read_bytes())
            self.assertEqual(updated["collapse-filter"], original["collapse-filter"])
            self.assertEqual(updated["search"], original["search"])
            self.assertEqual(updated["showTags"], original["showTags"])
            self.assertEqual(updated["nodeSizeMultiplier"], original["nodeSizeMultiplier"])
            self.assertEqual(len(updated["colorGroups"]), 6)
            self.assertEqual(
                [group["query"] for group in updated["colorGroups"]],
                [group.definition.query for group in self.helper.discover_groups(vault)],
            )

    def test_sync_is_idempotent_and_does_not_create_second_backup(self):
        with tempfile.TemporaryDirectory() as directory:
            vault, graph_path, backup_dir = self.make_vault(directory)
            self.add_note(vault, "01-conversations/thread.md")

            first = self.helper.sync(vault, graph_path, backup_dir)
            second = self.helper.sync(vault, graph_path, backup_dir)

            self.assertTrue(first.changed)
            self.assertFalse(second.changed)
            self.assertIsNone(second.backup_path)
            self.assertEqual(len(list(backup_dir.glob("graph.json.*.bak"))), 1)

    def test_dry_run_and_check_do_not_write(self):
        with tempfile.TemporaryDirectory() as directory:
            vault, graph_path, backup_dir = self.make_vault(directory)
            self.add_note(vault, "00-inbox/item.md")
            before = graph_path.read_bytes()

            result = self.helper.sync(vault, graph_path, backup_dir, dry_run=True)

            self.assertTrue(result.changed)
            self.assertEqual(graph_path.read_bytes(), before)
            self.assertFalse(backup_dir.exists())
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(
                    self.helper.main(
                        [
                            "check",
                            "--vault",
                            str(vault),
                            "--graph",
                            str(graph_path),
                            "--backup-dir",
                            str(backup_dir),
                        ]
                    ),
                    1,
                )
            self.assertEqual(graph_path.read_bytes(), before)

    def test_sync_refuses_active_or_unresolvable_workspace_without_backup(self):
        with tempfile.TemporaryDirectory() as directory:
            vault, graph_path, backup_dir = self.make_vault(directory)
            self.add_note(vault, "00-inbox/item.md")
            before = graph_path.read_bytes()
            workspace_path = vault / ".obsidian" / "workspace.json"

            workspace_path.write_text(
                json.dumps(
                    {
                        "main": {
                            "type": "tabs",
                            "children": [
                                {
                                    "type": "leaf",
                                    "id": "active-graph",
                                    "state": {"type": "graph"},
                                }
                            ],
                        },
                        "active": "active-graph",
                    }
                )
                + "\n",
                encoding="utf-8",
            )
            with self.assertRaises(RuntimeError):
                self.helper.sync(vault, graph_path, backup_dir)

            workspace_path.write_text(
                json.dumps(
                    {
                        "main": {
                            "type": "tabs",
                            "children": [
                                {
                                    "type": "leaf",
                                    "id": "duplicate-active",
                                    "state": {"type": "empty"},
                                },
                                {
                                    "type": "leaf",
                                    "id": "duplicate-active",
                                    "state": {"type": "graph"},
                                },
                            ],
                        },
                        "active": "duplicate-active",
                    }
                )
                + "\n",
                encoding="utf-8",
            )
            with self.assertRaises(RuntimeError):
                self.helper.sync(vault, graph_path, backup_dir)

            workspace_path.write_text("not json\n", encoding="utf-8")
            with self.assertRaises(RuntimeError):
                self.helper.sync(vault, graph_path, backup_dir)

            self.assertEqual(graph_path.read_bytes(), before)
            self.assertFalse(backup_dir.exists())

    def test_empty_categories_remain_neutral(self):
        with tempfile.TemporaryDirectory() as directory:
            vault, graph_path, backup_dir = self.make_vault(directory)
            graph_path.write_text(
                json.dumps({"search": "", "colorGroups": []}) + "\n", encoding="utf-8"
            )

            result = self.helper.sync(vault, graph_path, backup_dir)

            self.assertFalse(result.changed)
            self.assertEqual(json.loads(graph_path.read_text(encoding="utf-8"))["colorGroups"], [])

    def test_graph_path_outside_vault_and_symlinked_parent_are_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            vault, graph_path, backup_dir = self.make_vault(directory)
            outside = Path(directory).parent / f"outside-graph-{Path(directory).name}.json"
            outside.write_text(json.dumps({"colorGroups": []}), encoding="utf-8")
            try:
                with self.assertRaises(ValueError):
                    self.helper.sync(vault, outside, backup_dir)

                real_obsidian = vault / "real-obsidian"
                real_obsidian.mkdir()
                real_graph = real_obsidian / "graph.json"
                real_graph.write_bytes(graph_path.read_bytes())
                graph_path.unlink()
                (graph_path.parent / "workspace.json").unlink()
                graph_path.parent.rmdir()
                graph_path.parent.symlink_to(real_obsidian, target_is_directory=True)
                with self.assertRaises(OSError):
                    self.helper.sync(vault, vault / ".obsidian" / "graph.json", backup_dir)
            finally:
                outside.unlink(missing_ok=True)

    def test_symlinked_backup_directory_is_refused_without_changing_graph(self):
        with tempfile.TemporaryDirectory() as directory:
            vault, graph_path, _ = self.make_vault(directory)
            self.add_note(vault, "00-inbox/item.md")
            target = vault / "real-backups"
            target.mkdir()
            backup_link = vault / "backup-link"
            backup_link.symlink_to(target, target_is_directory=True)
            before = graph_path.read_bytes()

            with self.assertRaises(OSError):
                self.helper.sync(vault, graph_path, backup_link)

            self.assertEqual(graph_path.read_bytes(), before)
            self.assertEqual(list(target.iterdir()), [])

    def test_lock_symlink_is_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            vault, graph_path, backup_dir = self.make_vault(directory)
            self.add_note(vault, "00-inbox/item.md")
            lock_target = vault / "lock-target"
            lock_target.write_text("sentinel", encoding="utf-8")
            lock_path = graph_path.parent / self.helper.LOCK_NAME
            lock_path.symlink_to(lock_target)

            with self.assertRaises(OSError):
                self.helper.sync(vault, graph_path, backup_dir)

            self.assertEqual(lock_target.read_text(encoding="utf-8"), "sentinel")

    def test_existing_backup_symlink_is_skipped_without_following_it(self):
        with tempfile.TemporaryDirectory() as directory:
            backup_dir = Path(directory) / "backups"
            backup_dir.mkdir()
            target = Path(directory) / "backup-target"
            target.write_bytes(b"sentinel")
            fixed_datetime = mock.Mock()
            fixed_datetime.now.return_value = datetime_type(2026, 1, 2, 3, 4, 5)
            symlink_name = backup_dir / "graph.json.20260102T030405Z.bak"
            symlink_name.symlink_to(target)

            with mock.patch.object(self.helper, "datetime", fixed_datetime):
                result = self.helper._backup(backup_dir, b"safe backup")

            self.assertEqual(target.read_bytes(), b"sentinel")
            self.assertEqual(result.name, "graph.json.20260102T030405Z.1.bak")
            self.assertEqual(result.read_bytes(), b"safe backup")

    @unittest.skipUnless(sys.platform == "linux", "requires Linux renameat2 publication")
    def test_atomic_exchange_rolls_back_when_graph_changes_before_exchange(self):
        with tempfile.TemporaryDirectory() as directory:
            vault, graph_path, backup_dir = self.make_vault(directory)
            self.add_note(vault, "00-inbox/item.md")
            real_exchange = self.helper._rename_exchange

            def exchange_after_graph_mutation(parent_fd, source, destination):
                graph_path.write_text(json.dumps({"colorGroups": []}) + "\n", encoding="utf-8")
                return real_exchange(parent_fd, source, destination)

            with mock.patch.object(self.helper, "_rename_exchange", side_effect=exchange_after_graph_mutation):
                with self.assertRaises(RuntimeError):
                    self.helper.sync(vault, graph_path, backup_dir)

            self.assertEqual(json.loads(graph_path.read_text(encoding="utf-8"))["colorGroups"], [])
            self.assertEqual(len(list(backup_dir.glob("graph.json.*.bak"))), 1)
            self.assertEqual(list((graph_path.parent).glob(".graph.json.*.tmp")), [])

    @unittest.skipUnless(sys.platform == "linux", "requires Linux renameat2 publication")
    def test_atomic_exchange_does_not_clobber_graph_changed_after_exchange(self):
        with tempfile.TemporaryDirectory() as directory:
            vault, graph_path, backup_dir = self.make_vault(directory)
            self.add_note(vault, "00-inbox/item.md")
            real_exchange = self.helper._rename_exchange
            calls = 0

            def exchange_then_graph_mutation(parent_fd, source, destination):
                nonlocal calls
                result = real_exchange(parent_fd, source, destination)
                calls += 1
                if calls == 1:
                    graph_path.write_text(
                        json.dumps({"colorGroups": [{"query": "external-writer"}]}) + "\n",
                        encoding="utf-8",
                    )
                return result

            with mock.patch.object(self.helper, "_rename_exchange", side_effect=exchange_then_graph_mutation):
                with self.assertRaises(RuntimeError):
                    self.helper.sync(vault, graph_path, backup_dir)

            self.assertEqual(
                json.loads(graph_path.read_text(encoding="utf-8"))["colorGroups"],
                [{"query": "external-writer"}],
            )
            self.assertEqual(len(list(backup_dir.glob("graph.json.*.bak"))), 1)

    @unittest.skipUnless(sys.platform == "linux", "requires Linux renameat2 publication")
    def test_atomic_exchange_rejects_temporary_symlink_swap(self):
        with tempfile.TemporaryDirectory() as directory:
            vault, graph_path, backup_dir = self.make_vault(directory)
            self.add_note(vault, "00-inbox/item.md")
            target = vault / "outside-target"
            target.write_text("sentinel", encoding="utf-8")
            before = graph_path.read_bytes()
            real_exchange = self.helper._rename_exchange
            calls = 0

            def exchange_after_temp_swap(parent_fd, source, destination):
                nonlocal calls
                calls += 1
                if calls == 1:
                    temporary_path = graph_path.parent / source
                    temporary_path.unlink()
                    temporary_path.symlink_to(target)
                return real_exchange(parent_fd, source, destination)

            with mock.patch.object(self.helper, "_rename_exchange", side_effect=exchange_after_temp_swap):
                with self.assertRaises(RuntimeError):
                    self.helper.sync(vault, graph_path, backup_dir)

            self.assertEqual(graph_path.read_bytes(), before)
            self.assertEqual(target.read_text(encoding="utf-8"), "sentinel")
            self.assertTrue(graph_path.is_file())
            self.assertEqual(len(list(backup_dir.glob("graph.json.*.bak"))), 1)

    def test_sync_refuses_without_safe_atomic_publication(self):
        with tempfile.TemporaryDirectory() as directory:
            vault, graph_path, backup_dir = self.make_vault(directory)
            self.add_note(vault, "00-inbox/item.md")
            before = graph_path.read_bytes()

            with mock.patch.object(self.helper, "_rename_exchange", return_value=False):
                with self.assertRaisesRegex(RuntimeError, "requires renameat2"):
                    self.helper.sync(vault, graph_path, backup_dir)

            self.assertEqual(graph_path.read_bytes(), before)
            self.assertEqual(len(list(backup_dir.glob("graph.json.*.bak"))), 1)

    def test_final_graph_check_refuses_a_change_after_backup(self):
        with tempfile.TemporaryDirectory() as directory:
            vault, graph_path, backup_dir = self.make_vault(directory)
            self.add_note(vault, "00-inbox/item.md")
            real_backup = self.helper._backup

            def backup_then_mutate(backup_path, raw):
                result = real_backup(backup_path, raw)
                graph_path.write_text(json.dumps({"colorGroups": []}) + "\n", encoding="utf-8")
                return result

            with mock.patch.object(self.helper, "_backup", side_effect=backup_then_mutate):
                with self.assertRaises(RuntimeError):
                    self.helper.sync(vault, graph_path, backup_dir)

            self.assertEqual(json.loads(graph_path.read_text(encoding="utf-8"))["colorGroups"], [])
            self.assertEqual(len(list(backup_dir.glob("graph.json.*.bak"))), 1)

    def test_note_change_during_discovery_refuses_stale_grouping(self):
        with tempfile.TemporaryDirectory() as directory:
            vault, graph_path, backup_dir = self.make_vault(directory)
            self.add_note(vault, "00-inbox/item.md")
            real_snapshot = self.helper._vault_snapshot
            calls = 0

            def snapshot_then_add_note(snapshot_vault):
                nonlocal calls
                result = real_snapshot(snapshot_vault)
                calls += 1
                if calls == 1:
                    self.add_note(vault, "01-conversations/new.md")
                return result

            with mock.patch.object(self.helper, "_vault_snapshot", side_effect=snapshot_then_add_note):
                with self.assertRaises(RuntimeError):
                    self.helper.sync(vault, graph_path, backup_dir)

            self.assertFalse(backup_dir.exists())

    def test_malformed_and_symlinked_graphs_are_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            vault = Path(directory)
            graph_path = vault / ".obsidian" / "graph.json"
            graph_path.parent.mkdir(parents=True)
            graph_path.write_text("not json", encoding="utf-8")
            (graph_path.parent / "workspace.json").write_text(
                json.dumps(
                    {
                        "main": {
                            "type": "tabs",
                            "children": [
                                {
                                    "type": "leaf",
                                    "id": "active-empty",
                                    "state": {"type": "empty"},
                                }
                            ],
                        },
                        "active": "active-empty",
                    }
                )
                + "\n",
                encoding="utf-8",
            )
            with self.assertRaises(ValueError):
                self.helper.sync(vault, graph_path, vault / "backups")

            target = vault / "real.json"
            target.write_text(json.dumps({"colorGroups": []}), encoding="utf-8")
            graph_path.unlink()
            graph_path.symlink_to(target)
            with self.assertRaises(ValueError):
                self.helper.sync(vault, graph_path, vault / "backups")


if __name__ == "__main__":
    unittest.main()
