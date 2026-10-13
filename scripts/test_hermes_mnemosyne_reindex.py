"""Exercise a candidate Nix CLI using only disposable memory databases.

Run with the candidate CLI, its Python interpreter, external provider package
and an already populated FastEmbed cache as positional arguments. Never pass a
memory DB: the harness creates all database paths under TMPDIR itself.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def main():
    cli, python, provider, model_cache = map(Path, sys.argv[1:])
    assert cli.is_file() and python.is_file()
    provider = provider.resolve(strict=True)
    assert (provider / "cli.py").is_file()
    with tempfile.TemporaryDirectory(prefix="reindex-e2e-", dir=os.environ["TMPDIR"]) as tmp:
        root = Path(tmp)
        home = root / "default"
        (home / "plugins").mkdir(parents=True)
        (home / "plugins" / "mnemosyne").symlink_to(provider, target_is_directory=True)
        (home / "config.yaml").write_text("plugins:\n  enabled: [mnemosyne]\nmemory:\n  provider: mnemosyne\n  mnemosyne:\n    profile_isolation: true\n")
        data = home / "mnemosyne/data"
        data.mkdir(parents=True)
        shutil.copytree(model_cache, root / "cache")
        env = {k: v for k, v in os.environ.items()
               if not k.startswith(("HERMES", "MNEMOSYNE", "PYTHON"))}
        env.update(HOME=str(root), HERMES_HOME=str(home), MNEMOSYNE_DATA_DIR=str(data),
                   MNEMOSYNE_FASTEMBED_CACHE_DIR=str(root / "cache"), HF_HUB_OFFLINE="1",
                   MNEMOSYNE_EMBEDDING_THREADS="2", PYTHONDONTWRITEBYTECODE="1")
        def run(argv, *, input=None, extra=None, expected=0):
            result = subprocess.run(list(map(str, argv)), input=input, text=True,
                                    capture_output=True, cwd=root, env=env | (extra or {}), timeout=180)
            assert result.returncode == expected, (argv, result.returncode, result.stdout, result.stderr)
            return result
        def command(*args, **kwargs):
            return run([cli, "mnemosyne", *args], **kwargs)
        def digest(path):
            return hashlib.sha256(path.read_bytes()).hexdigest()
        def core(code, **kwargs):
            return run([python, "-c", "import sys; sys.path.append(" + repr(str(provider.parent)) + ");\n" + code], **kwargs)
        core("""from mnemosyne.core.beam import BeamMemory
b = BeamMemory(session_id='fixture')
b.remember('Working source text to preserve.', source='fixture')
b.conn.execute("INSERT INTO episodic_memory(id,content,source,session_id) VALUES ('episode-fixture','Episode source text to preserve.','fixture','fixture')")
b.conn.commit()
b.conn.close()
""", extra={"MNEMOSYNE_NO_EMBEDDINGS": "1"})
        db = data / "mnemosyne.db"
        before = digest(db)
        assert "NOT atomic" in " ".join(command("reindex", "--help").stdout.split())
        for name in ("stats", "sleep", "version", "inspect", "clear", "doctor", "export", "import"):
            command(name, "--help")
        for args in (("--batch-size", "0"), ("--batch-size", "-1"), ("--bogus",), ("--no-backup",)):
            command("reindex", *args, expected=2)
        plan = json.loads(command("reindex", "--dry-run").stdout)
        assert plan["database"] == str(db)
        assert (plan["model"], plan["dim"], plan["working_memory"], plan["episodic_memory"]) == ("BAAI/bge-small-en-v1.5", 384, 1, 1)
        model_plan = json.loads(command("reindex", "--dry-run", "--model", "BAAI/bge-base-en-v1.5").stdout)
        assert model_plan["model"] == "BAAI/bge-base-en-v1.5" and model_plan["dim"] == 768
        assert digest(db) == before
        for answer in ("n\n", ""):
            assert "Cancelled" in command("reindex", input=answer).stdout
            assert digest(db) == before
            assert not list(data.glob("*.backup"))
        command("reindex", "--yes", expected=1, extra={"MNEMOSYNE_NO_EMBEDDINGS": "1"})
        assert digest(db) == before
        failed_backups = list(data.glob("*.backup"))
        assert len(failed_backups) == 1
        command("reindex", "--yes", "--batch-size", "1")
        backups = sorted(data.glob("*.backup"))
        assert len(backups) == 2
        for backup in backups:
            assert backup.stat().st_mode & 0o777 == 0o600
        verification = core("""import json, math, sqlite3, os
import sqlite_vec
from pathlib import Path
path = Path(os.environ['MNEMOSYNE_DATA_DIR']) / 'mnemosyne.db'
def open_db(p):
    c = sqlite3.connect(str(p)); c.enable_load_extension(True); sqlite_vec.load(c); c.enable_load_extension(False)
    return c
c = open_db(path)
assert c.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
rows = {}
for table in ('working_memory','episodic_memory'):
    rows[table] = c.execute('SELECT id,content FROM ' + table).fetchall()
    for backup in path.parent.glob('*.backup'):
        old = open_db(backup)
        assert old.execute('SELECT id,content FROM ' + table).fetchall() == rows[table]
        assert old.execute('SELECT COUNT(*) FROM vec_episodes').fetchone()[0] == 0
        old.close()
for table in ('vec_working','vec_episodes','memory_embeddings'):
    assert c.execute('SELECT COUNT(*) FROM ' + table).fetchone()[0] == 1
vec = json.loads(c.execute('SELECT embedding_json FROM memory_embeddings').fetchone()[0])
assert len(vec) == 384 and all(math.isfinite(v) for v in vec) and any(v != 0 for v in vec)
assert len(c.execute('SELECT binary_vector FROM episodic_memory').fetchone()[0]) > 0
assert c.execute('SELECT COUNT(*) FROM vec_facts').fetchone()[0] == 0
print(json.dumps({'working_vectors':1,'episodic_vectors':1,'dimension':384,'source_ids_text_preserved':True,'backup_verified':True}))
c.close()
""")
        # Named profile uses its provider bank, not the default database.
        profile = root / "research"
        (profile / "plugins").mkdir(parents=True)
        (profile / "plugins" / "mnemosyne").symlink_to(provider, target_is_directory=True)
        shutil.copyfile(home / "config.yaml", profile / "config.yaml")
        bank = data / "banks/research/mnemosyne.db"
        bank.parent.mkdir(parents=True)
        shutil.copyfile(db, bank)
        named = json.loads(command("reindex", "--dry-run", extra={"HERMES_HOME":str(profile), "HERMES_PROFILE":"research"}).stdout)
        assert named["database"] == str(bank)
        nonisolated = json.loads(command("reindex", "--dry-run", extra={"HERMES_HOME":str(profile), "HERMES_PROFILE":"research", "MNEMOSYNE_PROFILE_ISOLATION":"false"}).stdout)
        # Explicit Hermes config wins over env; still the named bank.
        assert nonisolated["database"] == str(bank)
        (profile / "config.yaml").write_text("plugins:\n  enabled: [mnemosyne]\nmemory:\n  provider: mnemosyne\n  mnemosyne:\n    profile_isolation: false\n")
        shared = json.loads(command("reindex", "--dry-run", extra={"HERMES_HOME":str(profile), "HERMES_PROFILE":"research"}).stdout)
        assert shared["database"] == str(db)
        missing_data = root / "missing-data"
        command("reindex", "--dry-run", extra={"MNEMOSYNE_DATA_DIR":str(missing_data)}, expected=1)
        assert not (missing_data / "mnemosyne.db").exists()
        corrupt_data = root / "corrupt-data"
        corrupt_data.mkdir()
        (corrupt_data / "mnemosyne.db").write_bytes(b"not sqlite")
        command("reindex", "--dry-run", extra={"MNEMOSYNE_DATA_DIR":str(corrupt_data)}, expected=1)
        print(verification.stdout.strip())
        print("PASS: candidate help, 8 existing command helps, invalid args, read-only preview/model, decline/EOF, failure backup, real vectors, profile/config routing, missing/corrupt DB")


if __name__ == "__main__":
    main()
