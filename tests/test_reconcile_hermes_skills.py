from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = ROOT / "scripts" / "reconcile_hermes_skills.py"


def load_helper():
    spec = importlib.util.spec_from_file_location("reconcile_hermes_skills", SCRIPT_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {SCRIPT_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class ReconcileHermesSkillsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.helper = load_helper()

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        root = Path(self.directory.name)
        self.runtime = root / "runtime"
        self.vault = root / "vault"
        self.notes = self.vault / "Skills"
        self.registry = self.vault / "Hermes Skills Registry.md"
        self.backups = root / "backups"
        self.runtime.mkdir(parents=True)
        self.notes.mkdir(parents=True)
        self.skill = self.runtime / "character" / "example" / "SKILL.md"
        self.skill.parent.mkdir(parents=True)
        self.runtime_content = "---\nname: example\nversion: 1.0.0\n---\n\n# Example\n\nUse the example.\n"
        self.skill.write_text(self.runtime_content, encoding="utf-8")
        self.note = self.notes / "example.md"
        self.write_note(self.runtime_content, mode="manual_review")
        self.registry.write_text(
            "---\nskill_count: 1\n---\n\n[[Skills/example|example]]\n",
            encoding="utf-8",
        )

    def tearDown(self):
        self.directory.cleanup()

    def write_note(self, canonical: str, *, mode: str) -> None:
        source_hash = self.helper.sha256_text(canonical)
        content = (
            "---\n"
            "title: Example\n"
            "type: hermes-skill-reference\n"
            "skill_name: example\n"
            "skill_category: character/example\n"
            f"source_path: {self.skill}\n"
            f"source_sha256: {source_hash}\n"
            f"reconciliation_mode: {mode}\n"
            "audited_at: 2026-07-29\n"
            "---\n\n"
            "# Example\n\n"
            "> Mirror.\n\n"
            "## Canonical Skill Content\n\n"
            f"{canonical}\n\n"
            "## Audit Notes\n\nKeep this note.\n"
        )
        self.note.write_text(content, encoding="utf-8")

    def test_audit_is_clean_for_matching_skill(self):
        report = self.helper.audit(self.runtime, self.notes, self.registry)
        self.assertEqual([], report["issues"])
        self.assertEqual(1, report["runtime_count"])
        self.assertEqual(1, report["vault_count"])

    def test_audit_detects_missing_note_and_hash_drift(self):
        self.skill.write_text(self.runtime_content.replace("Use the example.", "Use the changed example."), encoding="utf-8")
        report = self.helper.audit(self.runtime, self.notes, self.registry)
        kinds = {issue["kind"] for issue in report["issues"]}
        self.assertIn("hash_mismatch", kinds)

        self.note.unlink()
        report = self.helper.audit(self.runtime, self.notes, self.registry)
        self.assertIn("runtime_only", {issue["kind"] for issue in report["issues"]})

    def test_vault_to_runtime_rewrite_is_atomic_and_verified(self):
        newer = self.runtime_content.replace("Use the example.", "Use the canonical example.")
        self.write_note(newer, mode="vault_to_runtime")
        self.skill.write_text(self.runtime_content, encoding="utf-8")

        report = self.helper.reconcile(
            self.runtime,
            self.notes,
            self.registry,
            self.backups,
            apply=True,
        )
        self.assertEqual("reconciled", report["status"])
        self.assertEqual(newer, self.skill.read_text(encoding="utf-8"))
        self.assertTrue(report["applied"])
        self.assertTrue(report["verification"]["zero_drift"])
        self.assertTrue(list(self.backups.rglob("*")))

    def test_runtime_to_vault_rewrite_preserves_audit_notes(self):
        newer = self.runtime_content.replace("Use the example.", "Use the deployed example.")
        self.skill.write_text(newer, encoding="utf-8")
        self.write_note(self.runtime_content, mode="runtime_to_vault")

        report = self.helper.reconcile(
            self.runtime,
            self.notes,
            self.registry,
            self.backups,
            apply=True,
        )
        self.assertEqual("reconciled", report["status"])
        note_text = self.note.read_text(encoding="utf-8")
        self.assertIn("Use the deployed example.", note_text)
        self.assertIn("## Audit Notes", note_text)
        self.assertEqual([], self.helper.audit(self.runtime, self.notes, self.registry)["issues"])

    def test_manual_review_reports_partial_without_writing(self):
        changed = self.runtime_content.replace("Use the example.", "Use the reviewed example.")
        self.skill.write_text(changed, encoding="utf-8")
        before = self.note.read_text(encoding="utf-8")
        report = self.helper.reconcile(
            self.runtime,
            self.notes,
            self.registry,
            self.backups,
            apply=True,
        )
        self.assertEqual("partial", report["status"])
        self.assertEqual(before, self.note.read_text(encoding="utf-8"))
        self.assertTrue(report["manual_review"])

    def test_runtime_only_creates_pending_draft_and_registry_entry(self):
        self.note.unlink()
        report = self.helper.reconcile(
            self.runtime,
            self.notes,
            self.registry,
            self.backups,
            apply=True,
        )
        self.assertEqual("partial", report["status"])
        self.assertTrue((self.notes / "example.md").exists())
        self.assertIn("pending-review", (self.notes / "example.md").read_text(encoding="utf-8"))
        self.assertIn("[[Skills/example|example]]", self.registry.read_text(encoding="utf-8"))
        self.assertTrue(report["verification"]["zero_drift"])

    def test_cli_emits_json_and_check_does_not_write(self):
        result = self.helper.build_report(self.runtime, self.notes, self.registry, apply=False, backup_root=self.backups)
        encoded = json.dumps(result)
        self.assertIn('"status": "clean"', encoded)
        self.assertFalse(self.backups.exists())


if __name__ == "__main__":
    unittest.main()
