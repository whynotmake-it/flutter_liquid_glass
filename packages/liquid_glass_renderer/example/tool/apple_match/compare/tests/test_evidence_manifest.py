"""Simulator-free tests for the settings evidence contract."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "validate_evidence_manifest", ROOT / "validate_evidence_manifest.py"
)
assert SPEC is not None and SPEC.loader is not None
validator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validator)


class EvidenceManifestTest(unittest.TestCase):
    def test_manifest_covers_every_public_settings_field(self) -> None:
        errors, _ = validator.validate(strict=False)
        self.assertEqual(errors, [])

    def test_strict_gate_reports_unproven_axes(self) -> None:
        errors, notes = validator.validate(strict=True)
        self.assertTrue(notes)
        self.assertTrue(any("strict evidence gate is not closed" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
