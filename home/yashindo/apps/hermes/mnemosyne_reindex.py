"""Nix-local extension of the external Mnemosyne argparse command tree.

No provider initialization here: BeamMemory construction migrates databases,
which is inappropriate for a preview or a declined maintenance operation.
"""
import argparse
import contextlib
import importlib
import json
import os
from pathlib import Path
import sqlite3
import sys
import tempfile


def register_reindex(parser):
    """Extend the existing provider parser; leave upstream commands untouched."""
    commands = next(action for action in parser._actions
                    if isinstance(action, argparse._SubParsersAction))
    if "reindex" in commands.choices:
        return  # An upgraded provider owns its native implementation.
    command = commands.add_parser(
        "reindex", help="Offline rebuild of memory vectors (backup required)",
        description="Stop all writers to this database first. Reindex commits "
                    "in batches and is NOT atomic. A verified SQLite backup is "
                    "always created before writing. --yes acknowledges this warning.")
    command.add_argument("--dry-run", action="store_true",
                         help="Read-only plan: database, model, dimension and counts")
    command.add_argument("--yes", action="store_true",
                         help="Confirm writers are stopped and approve the rebuild")
    command.add_argument("--model", help="Embedding model for this process only")
    command.add_argument("--batch-size", type=positive_int, default=64)
    command.set_defaults(func=reindex_command)


def positive_int(value):
    value = int(value)
    if value <= 0:
        raise argparse.ArgumentTypeError("batch size must be positive")
    return value


def resolve_target():
    """Mirror provider bank routing without opening/creating a bank or database.

    The provider config reader owns precedence and the profile-bank sanitizer.
    Keep the version-sensitive adapter explicit rather than initializing it.
    """
    from hermes_constants import get_hermes_home
    from hermes_memory_provider import MnemosyneMemoryProvider
    from mnemosyne.core import beam
    provider = MnemosyneMemoryProvider()
    provider._hermes_home = str(get_hermes_home())
    provider._agent_identity = os.environ.get("HERMES_PROFILE", "")
    provider._apply_provider_config({})
    bank = provider._resolve_profile_bank() if provider._profile_isolation_enabled else "default"
    data = beam._default_data_dir()
    return data / "mnemosyne.db" if bank == "default" else data / "banks" / bank / "mnemosyne.db"


def load_backend(model):
    from mnemosyne.core import beam, embeddings
    if model:
        # Plugin discovery may already have imported embeddings. Reload only
        # this process's model settings; never persist provider configuration.
        os.environ["MNEMOSYNE_EMBEDDING_MODEL"] = model
        importlib.reload(embeddings)
    return beam


def connect(path, *, readonly):
    conn = sqlite3.connect(path.as_uri() + ("?mode=ro" if readonly else "?mode=rw"),
                           uri=True, timeout=5)
    conn.row_factory = sqlite3.Row
    try:
        tables = conn.execute("SELECT sql FROM sqlite_master WHERE sql LIKE '%USING vec0%'").fetchall()
        if tables:
            import sqlite_vec
            conn.enable_load_extension(True)
            try:
                sqlite_vec.load(conn)
            finally:
                conn.enable_load_extension(False)
        # Fail rather than treating a malformed/unrelated database as empty.
        for table in ("working_memory", "episodic_memory"):
            conn.execute(f"SELECT id, content FROM {table} LIMIT 0")
        return conn
    except BaseException:
        conn.close()
        raise


def reindex_command(args):
    backup = None
    try:
        path = resolve_target().expanduser().resolve(strict=True)
        backend = load_backend(args.model)
        with contextlib.closing(connect(path, readonly=True)) as source:
            plan = backend.reindex_vectors(source, dry_run=True)
            plan["database"] = str(path)
            print(json.dumps(plan, indent=2))
            if args.dry_run:
                return 0
            print("WARNING: stop ALL writers to this database first. Reindex is "
                  "NOT atomic (batch commits); restore the backup on failure.", file=sys.stderr)
            if not args.yes:
                try:
                    answer = input("Writers stopped; back up and rebuild this database? [y/N]: ")
                except EOFError:
                    answer = ""
                if answer.strip().lower() not in ("y", "yes"):
                    print("Cancelled; database unchanged.")
                    return 0
            fd, name = tempfile.mkstemp(prefix=path.name + ".reindex-", suffix=".backup", dir=path.parent)
            os.close(fd)  # mkstemp's owner-only permissions protect memory text.
            backup = Path(name)
            with contextlib.closing(sqlite3.connect(backup)) as destination:
                source.backup(destination)
                if destination.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
                    raise RuntimeError("Backup integrity check failed; database not modified")
            print(f"Backup: {backup}", file=sys.stderr)
        with contextlib.closing(connect(path, readonly=False)) as conn:
            result = backend.reindex_vectors(conn, batch_size=args.batch_size)
            for store in ("working_memory", "episodic_memory"):
                if result.get(store + "_reindexed") != plan[store]:
                    raise RuntimeError(f"Incomplete {store} rebuild; restore backup before restarting writers")
            if plan.get("sqlite_vec"):
                for store, table in (("working_memory", "vec_working"), ("episodic_memory", "vec_episodes")):
                    count = conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
                    if count != plan[store]:
                        raise RuntimeError(f"Incomplete {table} coverage; restore backup before restarting writers")
            result.update(database=str(path), backup=str(backup))
            print(json.dumps(result, indent=2))
        return 0
    except (Exception, KeyboardInterrupt) as exc:
        print(f"Reindex failed: {exc}", file=sys.stderr)
        if backup:
            print(f"Backup retained: {backup}; do not restart writers until recovery is verified.", file=sys.stderr)
        return 1
