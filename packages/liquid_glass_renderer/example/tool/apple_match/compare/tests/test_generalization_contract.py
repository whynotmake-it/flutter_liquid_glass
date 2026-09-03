"""Simulator-free checks for the frozen-parameter generalization contract."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]


class GeneralizationContractTest(unittest.TestCase):
    def test_thickness_fit_is_explicitly_opt_in(self) -> None:
        completed = subprocess.run(
            [sys.executable, str(ROOT / "generalization.py"), "--help"],
            check=True,
            capture_output=True,
            text=True,
        )
        self.assertIn("--fit-thickness", completed.stdout)
        source = (ROOT / "generalization.py").read_text()
        self.assertIn('"thickness": toolbar_settings["thickness"]', source)
        self.assertIn('"thicknessPolicy"', source)
        self.assertIn('"generalizationGate"', source)


if __name__ == "__main__":
    unittest.main()
