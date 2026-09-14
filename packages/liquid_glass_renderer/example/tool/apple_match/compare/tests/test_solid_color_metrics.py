import tempfile
import unittest
from pathlib import Path

import cv2
import numpy as np

from solid_color_metrics import measure_solid_palette


class SolidColorMetricsTests(unittest.TestCase):
    def test_reports_each_full_face_probe_and_guards(self):
        scene = {
            "id": "solid",
            "shape": {"kind": "circle", "x": 10, "y": 10, "width": 60, "height": 60, "cornerRadius": 0},
            "canvas": {"logicalWidth": 80, "logicalHeight": 80, "scale": 1},
            "roles": {"palette": ["R", "C"], "black": "K", "white": "W"},
            "probes": [
                {"id": "R", "background": {"kind": "solid", "color": "#ff0000"}},
                {"id": "C", "background": {"kind": "solid", "color": "#00ffff"}},
                {"id": "K", "background": {"kind": "solid", "color": "#000000"}},
                {"id": "W", "background": {"kind": "solid", "color": "#ffffff"}},
            ],
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            reference = root / "reference"
            candidate = root / "candidate"
            reference.mkdir()
            candidate.mkdir()
            for probe, color in (("R", (0, 0, 255)), ("C", (255, 255, 0)), ("K", (0, 0, 0)), ("W", (255, 255, 255))):
                image = np.full((80, 80, 3), color, np.uint8)
                cv2.imwrite(str(reference / f"{probe}.png"), image)
                cv2.imwrite(str(candidate / f"{probe}.png"), image)
            result = measure_solid_palette(scene, reference, candidate)
            self.assertEqual(set(result["color"]), {"R", "C", "K", "W"})
            self.assertEqual(result["objective"]["paletteMeanFaceMae8Bit"], 0)
            self.assertEqual(result["guards"]["blackFaceMae8Bit"], 0)


if __name__ == "__main__":
    unittest.main()
