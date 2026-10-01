import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).parents[2]
SPEC = importlib.util.spec_from_file_location("zoom_atlas", ROOT / "zoom_atlas.py")
zoom_atlas = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = zoom_atlas
SPEC.loader.exec_module(zoom_atlas)


class ZoomAtlasTests(unittest.TestCase):
    def test_regions_are_shape_aware_and_inside_canvas(self):
        for scene_id in ("material_capsule", "material_circle", "material_card"):
            scene = json.loads((ROOT / "scenes" / f"{scene_id}.json").read_text())
            regions = zoom_atlas.derive_regions(scene, "lighting")
            canvas_width = scene["canvas"]["logicalWidth"] * scene["canvas"]["scale"]
            canvas_height = scene["canvas"]["logicalHeight"] * scene["canvas"]["scale"]
            self.assertEqual(len(regions), 9)
            for region in regions:
                left, top, right, bottom = region.box
                self.assertGreater(right, left)
                self.assertGreater(bottom, top)
                self.assertGreaterEqual(left, 0)
                self.assertGreaterEqual(top, 0)
                self.assertLessEqual(right, canvas_width)
                self.assertLessEqual(bottom, canvas_height)
            transition = regions[-2].name
            if scene["shape"]["kind"] == "circle":
                self.assertIn("curvature", transition)
            else:
                self.assertIn("straight-to-corner", transition)

    def test_writes_annotated_atlas_and_machine_manifest(self):
        scene = json.loads((ROOT / "scenes/material_circle.json").read_text())
        size = (
            scene["canvas"]["logicalWidth"] * scene["canvas"]["scale"],
            scene["canvas"]["logicalHeight"] * scene["canvas"]["scale"],
        )
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            reference = root / "reference"
            candidate = root / "candidate"
            reference.mkdir()
            candidate.mkdir()
            for probe, color in zip("ABCD", ("gray", "red", "black", "white")):
                Image.new("RGB", size, color).save(reference / f"{probe}.png")
                Image.new("RGB", size, color).save(candidate / f"{probe}.png")
            output = root / "lighting.png"
            manifest = zoom_atlas.create_atlas(
                reference_dir=reference,
                candidate_dir=candidate,
                scene=scene,
                stage="lighting",
                output=output,
                title="test",
                subtitle="test",
            )
            self.assertTrue(output.exists())
            self.assertTrue(output.with_suffix(".json").exists())
            self.assertEqual(manifest["shapeKind"], "circle")
            self.assertEqual(manifest["captureEncoding"], "SDR tone-mapped 8-bit PNG")


if __name__ == "__main__":
    unittest.main()
