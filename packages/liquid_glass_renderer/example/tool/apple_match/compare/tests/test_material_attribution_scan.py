"""Simulator-free contracts for the shared material attribution probe."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "material_attribution_scan", ROOT / "material_attribution_scan.py"
)
assert SPEC is not None and SPEC.loader is not None
scan = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(scan)


class MaterialAttributionScanTest(unittest.TestCase):
    def test_grids_include_authoritative_defaults(self) -> None:
        self.assertIn(7.0, scan.AXES["frost"])
        self.assertIn(0.9, scan.AXES["transmissionGamma"])
        self.assertIn(18.3, scan.AXES["edgeRefraction"])
        self.assertIn(0.15, scan.AXES["vibrancy"])
        self.assertIn(0.53, scan.AXES["tintAlpha"])
        self.assertIn(0.0, scan.AXES["chromaticAberration"])
        self.assertIn(0.005, scan.AXES["chromaticAberration"])
        self.assertIn(0.1, scan.AXES["chromaticAberration"])

    def test_candidate_preserves_geometry_and_spread(self) -> None:
        toolbar = {
            "shapeWidth": 224.5,
            "shapeHeight": 94.0,
            "shapeOffsetX": 0.0,
            "shapeOffsetY": -0.1667,
            "cornerRadius": 50.5,
            "shapeProfile": "superellipse",
            "thickness": 12.0,
            "refractionSpread": 0.0,
            "frost": 7.0,
        }
        geometry = dict(toolbar, shapeWidth=150.0, shapeHeight=70.0, cornerRadius=35.0)
        candidate = scan.candidate_settings(toolbar, geometry, "frost", 5.0)
        self.assertEqual(candidate["shapeWidth"], 150.0)
        self.assertEqual(candidate["shapeHeight"], 70.0)
        self.assertEqual(candidate["cornerRadius"], 35.0)
        self.assertEqual(candidate["refractionSpread"], 0.0)
        self.assertEqual(candidate["frost"], 5.0)


if __name__ == "__main__":
    unittest.main()
