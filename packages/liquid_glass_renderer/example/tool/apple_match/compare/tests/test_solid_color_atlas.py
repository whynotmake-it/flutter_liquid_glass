import tempfile
import unittest
from pathlib import Path

import cv2
import numpy as np

from solid_color_atlas import write_atlas


class SolidColorAtlasTests(unittest.TestCase):
    def test_writes_annotated_all_probe_atlas(self):
        scene = {
            "id": "solid",
            "shape": {"kind": "circle", "x": 10, "y": 10, "width": 40, "height": 40},
            "canvas": {"logicalWidth": 60, "logicalHeight": 60, "scale": 1},
            "probes": [{"id": probe, "background": {"kind": "solid", "color": "#000000"}} for probe in ("R", "C", "K", "W")],
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            reference = root / "reference"
            candidate = root / "candidate"
            reference.mkdir()
            candidate.mkdir()
            for probe in ("R", "C", "K", "W"):
                image = np.full((60, 60, 3), 128, np.uint8)
                cv2.imwrite(str(reference / f"{probe}.png"), image)
                cv2.imwrite(str(candidate / f"{probe}.png"), image)
            output = root / "atlas.png"
            write_atlas(scene, reference, candidate, output, 1)
            self.assertTrue(output.exists())
            self.assertGreater(output.stat().st_size, 100)


if __name__ == "__main__":
    unittest.main()
