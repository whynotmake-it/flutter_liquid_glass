"""Simulator-free contracts for the coupled spread/thickness probe."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "coupled_spread_scan", ROOT / "coupled_spread_scan.py"
)
assert SPEC is not None and SPEC.loader is not None
scan = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(scan)


def row(scene: str, spread: float, thickness: float, loss: float) -> dict:
    return {
        "scene": scene,
        "spread": spread,
        "thickness": thickness,
        "repetition": 1,
        "score": 100.0 - loss,
        "fitLoss": loss,
        "directMae8Bit": loss,
        "errors": {"shape": loss, "combined": loss, "flow": loss},
        "capture": "/tmp/capture",
    }


class CoupledSpreadScanTest(unittest.TestCase):
    def test_selects_thickness_per_scene_for_each_shared_spread(self) -> None:
        rows = []
        for scene in scan.SCENES:
            rows.extend(
                [
                    row(scene, 0.0, 4.0, 0.4),
                    row(scene, 0.0, 8.0, 0.2),
                    row(scene, 0.25, 4.0, 0.3),
                    row(scene, 0.25, 8.0, 0.1),
                ]
            )
        summary = scan.summarize(rows, [0.0, 0.25], [4.0, 8.0])
        for spread in ("0.0", "0.25"):
            for scene in scan.SCENES:
                key = "toolbar" if scene == "toolbar_capsule" else scene
                selected = summary["selectedBySpread"][spread][key]
                self.assertEqual(selected["thickness"], 8.0)

    def test_optics_loss_weights_flow_and_combined(self) -> None:
        self.assertAlmostEqual(scan.optics_loss({"flow": 0.5, "combined": 0.25}), 0.7)


if __name__ == "__main__":
    unittest.main()
