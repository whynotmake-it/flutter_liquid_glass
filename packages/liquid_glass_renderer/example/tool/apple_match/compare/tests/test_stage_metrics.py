import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

import cv2
import numpy as np


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("stage_metrics", ROOT / "stage_metrics.py")
assert SPEC and SPEC.loader
stage_metrics = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = stage_metrics
SPEC.loader.exec_module(stage_metrics)


class StageMetricsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.scene = json.loads((ROOT / "scenes/material_capsule.json").read_text())

    def test_shape_regions_are_nonempty_and_partition_useful_bands(self) -> None:
        regions = stage_metrics.region_masks(self.scene)
        self.assertGreater(np.count_nonzero(regions["outerContour0To3px"]), 0)
        self.assertGreater(np.count_nonzero(regions["innerBevel3To12px"]), 0)
        self.assertGreater(np.count_nonzero(regions["faceOver12px"]), 0)
        self.assertGreater(np.count_nonzero(regions["outside0To3px"]), 0)
        self.assertGreater(np.count_nonzero(regions["outside3To12px"]), 0)
        self.assertGreater(np.count_nonzero(regions["outside12To36px"]), 0)
        self.assertFalse(
            np.any(regions["outerContour0To3px"] & regions["faceOver12px"])
        )
        self.assertFalse(np.any(regions["glass"] & regions["outside0To3px"]))
        self.assertFalse(
            np.any(regions["outside0To3px"] & regions["outside3To12px"])
        )

    def test_identical_capture_has_zero_stage_residuals(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            capture = Path(temporary) / "capture"
            capture.mkdir()
            for probe in "ABCD":
                image, _ = stage_metrics.render_probe(self.scene, probe)
                cv2.imwrite(
                    str(capture / f"{probe}.png"),
                    cv2.cvtColor(
                        np.clip(image * 255, 0, 255).astype(np.uint8),
                        cv2.COLOR_RGB2BGR,
                    ),
                )
            result = stage_metrics.measure(capture, capture, self.scene)
            self.assertIsNone(result["aggregateScore"])
            self.assertEqual(
                result["refraction"]["glass"]["vectorMeanAbsoluteErrorPixels"],
                0.0,
            )
            self.assertEqual(
                result["refraction"]["frequencyResponse"]
                ["candidateVsReferenceAbsoluteError"]["highRms"],
                0.0,
            )
            self.assertEqual(
                result["lighting"]["white"]["glass"]["meanAbsoluteError8Bit"],
                0.0,
            )
            self.assertEqual(
                result["lighting"]["knownFrostMixtureResidual"]["status"],
                "reported-not-optimized",
            )
            self.assertTrue(
                all(
                    entry["candidateVsReference"]["meanAbsoluteError8Bit"] == 0.0
                    for entry in result["color"].values()
                )
            )


if __name__ == "__main__":
    unittest.main()
