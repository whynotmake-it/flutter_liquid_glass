import importlib.util
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[2]
SPEC = importlib.util.spec_from_file_location("contour_fit", ROOT / "contour_fit.py")
contour_fit = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = contour_fit
SPEC.loader.exec_module(contour_fit)


class ContourFitTests(unittest.TestCase):
    def test_slug_preserves_sub_milliscale_lighting_candidates(self):
        def slug(bevel_strength):
            return contour_fit._slug(
                0.15,
                0.65,
                0.25,
                0.8,
                0,
                bevel_strength,
                18,
                4,
                1,
                0.25,
                1,
                0,
                0.75,
                1,
                0.4,
                0,
                0,
                0,
                0,
            )

        self.assertNotEqual(slug(0.0005), slug(0.001))
        self.assertIn("b0p0005", slug(0.0005))


if __name__ == "__main__":
    unittest.main()
