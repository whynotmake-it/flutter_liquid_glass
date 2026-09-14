import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).parents[2]
SPEC = importlib.util.spec_from_file_location(
    "size_control_atlas", ROOT / "size_control_atlas.py"
)
size_control_atlas = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = size_control_atlas
SPEC.loader.exec_module(size_control_atlas)


class SizeControlAtlasTests(unittest.TestCase):
    def test_writes_annotated_atlas_for_same_primitive_and_readback(self):
        first_scene = json.loads((ROOT / "scenes/material_capsule.json").read_text())
        second_scene = json.loads(
            (ROOT / "scenes/material_capsule_tall.json").read_text()
        )
        size = (
            first_scene["canvas"]["logicalWidth"]
            * first_scene["canvas"]["scale"],
            first_scene["canvas"]["logicalHeight"]
            * first_scene["canvas"]["scale"],
        )
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            captures = []
            for name in ("first", "second"):
                capture = root / name
                capture.mkdir()
                Image.new("RGB", size, "gray").save(capture / "A.png")
                (capture / "metadata.json").write_text(
                    json.dumps({"liquidGlassTintPositionReadback": 0.0})
                )
                captures.append(capture)
            output = root / "size-control.png"
            manifest = size_control_atlas.create_atlas(
                first_scene=first_scene,
                first_capture=captures[0],
                second_scene=second_scene,
                second_capture=captures[1],
                output=output,
                title="test",
            )
            self.assertTrue(output.exists())
            self.assertTrue(output.with_suffix(".json").exists())
            self.assertEqual(manifest["sliderReadback"], 0.0)
            self.assertEqual(len(manifest["captures"]), 2)

    def test_rejects_different_shape_primitives(self):
        first_scene = json.loads((ROOT / "scenes/material_capsule.json").read_text())
        second_scene = json.loads((ROOT / "scenes/material_circle.json").read_text())
        with self.assertRaisesRegex(ValueError, "same shape primitive"):
            size_control_atlas.create_atlas(
                first_scene=first_scene,
                first_capture=Path("unused"),
                second_scene=second_scene,
                second_capture=Path("unused"),
                output=Path("unused"),
                title="test",
            )


if __name__ == "__main__":
    unittest.main()
