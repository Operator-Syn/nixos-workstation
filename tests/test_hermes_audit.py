from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = ROOT / "scripts" / "hermes_audit.py"


def load_helper():
    spec = importlib.util.spec_from_file_location("hermes_audit", SCRIPT_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {SCRIPT_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class HermesAuditTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.helper = load_helper()

    def test_redacts_assignment_json_and_private_key_secrets(self):
        source = (
            "token=abc123 password: hunter2 \"api_key\": \"secret\"\n"
            "-----BEGIN PRIVATE KEY-----\nsecret\n-----END PRIVATE KEY-----"
        )
        result = self.helper.redact_text(source)
        self.assertNotIn("abc123", result)
        self.assertNotIn("hunter2", result)
        self.assertNotIn("secret", result)
        self.assertIn("[REDACTED]", result)
        self.assertIn("[REDACTED PRIVATE KEY BLOCK]", result)

    def test_bounds_utf8_output(self):
        result = self.helper.bound_text("x" * 100, limit=32)
        self.assertLessEqual(len(result.encode("utf-8")), 32)

    def test_empty_section_fixture_is_not_a_collector_error(self):
        self.assertEqual("", self.helper.bound_text(""))


if __name__ == "__main__":
    unittest.main()
