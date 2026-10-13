"""Regression tests for the packaged Mnemosyne CLI extension (stdlib only)."""
import argparse
import importlib.util
from pathlib import Path
import unittest
import sqlite3
import tempfile
from types import SimpleNamespace
from unittest.mock import patch
import contextlib
import io

ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / "home/yashindo/apps/hermes/mnemosyne_reindex.py"

class ModuleMixin:
    def load(self):
        self.assertTrue(MODULE.is_file(), "packaged reindex extension is missing")
        spec = importlib.util.spec_from_file_location("reindex_extension", MODULE)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

class ReindexTests(ModuleMixin, unittest.TestCase):
    def test_parser_registers_reindex_without_replacing_existing_commands(self):
        module = self.load()
        parser = argparse.ArgumentParser()
        commands = parser.add_subparsers(dest="mnemosyne_cmd")
        commands.add_parser("stats")
        module.register_reindex(parser)
        args = parser.parse_args(["reindex", "--dry-run"])
        self.assertTrue(args.dry_run)
        self.assertEqual(args.func, module.reindex_command)
        self.assertEqual(parser.parse_args(["stats"]).mnemosyne_cmd, "stats")

class ReindexExecutionTests(ModuleMixin, unittest.TestCase):
    def test_preview_reads_existing_db_without_writes(self):
        module = self.load()
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "memory.db"
            with contextlib.closing(sqlite3.connect(path)) as conn, conn:
                conn.execute("CREATE TABLE working_memory(id TEXT, content TEXT)")
                conn.execute("CREATE TABLE episodic_memory(id TEXT, content TEXT)")
                conn.execute("INSERT INTO episodic_memory VALUES ('ep-1', 'source text')")
            before = path.read_bytes()
            backend = SimpleNamespace(reindex_vectors=lambda conn, **kw: {
                "dry_run": kw["dry_run"], "model": "test", "dim": 384,
                "working_memory": 0, "episodic_memory": 1})
            args = SimpleNamespace(dry_run=True, yes=False, model=None, batch_size=64)
            with patch.object(module, "resolve_target", return_value=path), \
                 patch.object(module, "load_backend", return_value=backend), \
                 contextlib.redirect_stdout(io.StringIO()) as output:
                self.assertEqual(module.reindex_command(args), 0)
            self.assertIn('"episodic_memory": 1', output.getvalue())
            self.assertEqual(path.read_bytes(), before)
            self.assertEqual(list(Path(directory).iterdir()), [path])

    def test_invalid_batch_sizes_are_rejected(self):
        module = self.load()
        for value in ("0", "-1"):
            with self.assertRaises(argparse.ArgumentTypeError):
                module.positive_int(value)
        self.assertEqual(module.positive_int("1"), 1)

    def test_native_reindex_is_not_overridden(self):
        module = self.load()
        parser = argparse.ArgumentParser()
        commands = parser.add_subparsers(dest="mnemosyne_cmd")
        original = commands.add_parser("reindex")
        original.set_defaults(func="native")
        module.register_reindex(parser)
        self.assertEqual(parser.parse_args(["reindex"]).func, "native")

    def test_missing_database_returns_nonzero_without_creating_it(self):
        module = self.load()
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "missing.db"
            with patch.object(module, "resolve_target", return_value=path), \
                 contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(module.reindex_command(SimpleNamespace()), 1)
            self.assertFalse(path.exists())

    def test_corrupt_database_returns_nonzero(self):
        module = self.load()
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "corrupt.db"
            path.write_bytes(b"not SQLite")
            with patch.object(module, "resolve_target", return_value=path), \
                 patch.object(module, "load_backend", return_value=SimpleNamespace()), \
                 contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(module.reindex_command(SimpleNamespace(model=None)), 1)
            self.assertEqual(path.read_bytes(), b"not SQLite")

    def test_incomplete_backend_result_is_failure_with_backup_retained(self):
        module = self.load()
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "memory.db"
            with contextlib.closing(sqlite3.connect(path)) as conn, conn:
                conn.execute("CREATE TABLE working_memory(id TEXT, content TEXT)")
                conn.execute("CREATE TABLE episodic_memory(id TEXT, content TEXT)")
            def rebuild(conn, **kwargs):
                if kwargs.get("dry_run"):
                    return {"working_memory": 1, "episodic_memory": 1}
                return {"working_memory_reindexed": 0, "episodic_memory_reindexed": 0}
            args = SimpleNamespace(dry_run=False, yes=True, model=None, batch_size=64)
            with patch.object(module, "resolve_target", return_value=path), \
                 patch.object(module, "load_backend", return_value=SimpleNamespace(reindex_vectors=rebuild)), \
                 contextlib.redirect_stdout(io.StringIO()), \
                 contextlib.redirect_stderr(io.StringIO()) as errors:
                self.assertEqual(module.reindex_command(args), 1)
            self.assertIn("Backup retained", errors.getvalue())
            backups = list(Path(directory).glob("*.backup"))
            self.assertEqual(len(backups), 1)
            self.assertEqual(backups[0].stat().st_mode & 0o777, 0o600)
            with contextlib.closing(sqlite3.connect(backups[0])) as backup:
                self.assertEqual(backup.execute("PRAGMA integrity_check").fetchone()[0], "ok")

if __name__ == "__main__":
    unittest.main()
