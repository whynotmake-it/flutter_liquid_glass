import json
import unittest
from pathlib import Path

from apple_match.hotloop.evaluate import validate_settings
from apple_match.scene import load_scene, metric_family, probe_ids, scene_crop


ROOT = Path(__file__).resolve().parents[2]


class SceneTests(unittest.TestCase):
    def test_checked_in_baselines_use_contract_settings(self):
        for name in (
            "baseline.json",
            "fake_glass_baseline.json",
            "loupe-clear-axes.json",
        ):
            with self.subTest(settings=name):
                values = json.loads((ROOT / "settings" / name).read_text())
                validate_settings(values)

    def test_loads_scene_and_preserves_declared_probe_order(self):
        scene = load_scene(ROOT / "scenes/toolbar_capsule.json")
        self.assertEqual(probe_ids(scene), ("A", "B", "C", "D"))
        self.assertEqual(metric_family(scene), "scorecard")

    def test_tint_roles_select_solid_color_metrics(self):
        scene = {
            "id": "tint",
            "probes": [{"id": "K"}, {"id": "W"}],
            "roles": {"sameHue": "R", "complement": "C"},
        }
        self.assertEqual(metric_family(scene), "solidColor")

    def test_scene_crop_unions_merge_shape_bounds(self):
        scene = load_scene(ROOT / "scenes/merge_rect_circle.json")
        scale = scene["canvas"]["scale"]
        shapes = [scene["shape"], scene["mergeShape"]]
        left = min(shape["x"] for shape in shapes)
        top = min(shape["y"] for shape in shapes)
        right = max(shape["x"] + shape["width"] for shape in shapes)
        bottom = max(shape["y"] + shape["height"] for shape in shapes)
        self.assertEqual(
            scene_crop(scene),
            (
                round((left - 30) * scale),
                round((top - 30) * scale),
                round((right - left + 60) * scale),
                round((bottom - top + 60) * scale),
            ),
        )

    def test_unknown_metric_family_names_scene_and_probes(self):
        scene = {"id": "unknown", "probes": [{"id": "K"}]}
        with self.assertRaisesRegex(ValueError, "unknown.*K"):
            metric_family(scene)


if __name__ == "__main__":
    unittest.main()
