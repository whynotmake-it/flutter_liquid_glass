"""Simulator-free contracts for the loupe seed scanner."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("seed_scan", ROOT / "seed_scan.py")
assert SPEC is not None and SPEC.loader is not None
seed_scan = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(seed_scan)


class SeedScanTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.scene = json.loads((ROOT / "scenes/loupe.json").read_text())
        cls.base = json.loads((ROOT / "settings/baseline.json").read_text())

    def test_loupe_grid_contains_only_effective_axes(self) -> None:
        seeds, axes, forced = seed_scan.build_seed_candidates(
            scene_id="loupe",
            scene=self.scene,
            base=self.base,
        )

        self.assertEqual(len(seeds), 12)
        self.assertEqual(axes, ("thickness", "edgeRefraction"))
        self.assertEqual(forced, seed_scan.LOUPE_FORCED_SETTINGS)
        self.assertEqual(
            len({json.dumps(seed, sort_keys=True) for seed in seeds}), len(seeds)
        )
        for seed in seeds:
            for key, value in forced.items():
                self.assertEqual(seed[key], value)

    def test_loupe_rejects_ineffective_profile_controls(self) -> None:
        with self.assertRaisesRegex(ValueError, "not effective controls"):
            seed_scan.build_seed_candidates(
                scene_id="loupe",
                scene=self.scene,
                base=self.base,
                spread=0.5,
            )
        with self.assertRaisesRegex(ValueError, "not effective controls"):
            seed_scan.build_seed_candidates(
                scene_id="loupe",
                scene=self.scene,
                base=self.base,
                profile_gate=True,
            )

    def test_generic_seed_grid_remains_available(self) -> None:
        scene = json.loads((ROOT / "scenes/toolbar_capsule.json").read_text())
        seeds, axes, forced = seed_scan.build_seed_candidates(
            scene_id="toolbar_capsule",
            scene=scene,
            base=self.base,
        )

        self.assertEqual(len(seeds), 144)
        self.assertEqual(
            axes,
            (
                "tintAlpha",
                "frost",
                "thickness",
                "edgeRefraction",
                "refractionSpread",
            ),
        )
        self.assertEqual(forced, {})


if __name__ == "__main__":
    unittest.main()
