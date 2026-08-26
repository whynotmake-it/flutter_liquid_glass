import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import cv2
import jsonschema
import numpy as np

from apple_match.metrics import (
    fixed_blur_mix,
    score_images,
    verify_background_registration,
)
from apple_match.hotloop.evaluate import validate_settings
from apple_match.schema import validate_scene


ROOT = Path(__file__).parents[2]


def synthetic(
    blur=0,
    highlight=0.35,
    tint=(0.0, 0.0, 0.0),
    shape_scale=1.0,
):
    size = 128
    yy, xx = np.mgrid[:size, :size]
    grid = (((xx // 8 + yy // 8) % 2) * 0.6 + 0.2).astype(np.float32)
    mask = (
        ((xx - 64) / (42 * shape_scale)) ** 8
        + ((yy - 64) / (22 * shape_scale)) ** 8
        <= 1
    ).astype(np.float32)
    a = np.repeat(grid[..., None], 3, axis=2)
    if blur:
        blurred = cv2.GaussianBlur(a, (0, 0), blur)
        a = a * (1 - mask[..., None]) + blurred * mask[..., None]
    b = np.full_like(a, 0.5)
    c = np.repeat((mask * highlight)[..., None], 3, axis=2)
    d = np.ones_like(a)
    d += mask[..., None] * np.asarray(tint, dtype=np.float32)
    return {key: np.clip(value, 0, 1) for key, value in zip("ABCD", (a, b, c, d))}


class SchemaTests(unittest.TestCase):
    def test_checked_in_scenes_are_valid(self):
        paths = sorted((ROOT / "scenes").glob("*.json"))
        scene_paths = [path for path in paths if path.name != "schema.json"]
        self.assertGreaterEqual(len(scene_paths), 4)
        for path in scene_paths:
            with self.subTest(scene=path.stem):
                scene = validate_scene(path, ROOT / "scenes/schema.json")
                self.assertEqual([p["id"] for p in scene["probes"]], list("ABCD"))

    def test_rejects_missing_probe(self):
        scene_path = ROOT / "scenes/toolbar_capsule.json"
        scene = json.loads(scene_path.read_text())
        scene["probes"].pop()
        with tempfile.TemporaryDirectory() as directory:
            invalid = Path(directory) / "invalid.json"
            invalid.write_text(json.dumps(scene))
            with self.assertRaises(jsonschema.ValidationError):
                validate_scene(invalid, ROOT / "scenes/schema.json")


class MetricTests(unittest.TestCase):
    def test_cli_writes_exact_scorecard_and_diagnostics(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            reference_dir = root / "reference"
            candidate_dir = root / "candidate"
            output_dir = root / "output"
            reference_dir.mkdir()
            candidate_dir.mkdir()
            for probe, image in synthetic(blur=1.5).items():
                encoded = cv2.cvtColor(
                    (image * 255).astype(np.uint8), cv2.COLOR_RGB2BGR
                )
                cv2.imwrite(str(reference_dir / f"{probe}.png"), encoded)
                cv2.imwrite(str(candidate_dir / f"{probe}.png"), encoded)
            environment = os.environ.copy()
            environment["PYTHONPATH"] = str(ROOT / "compare")
            completed = subprocess.run(
                [
                    sys.executable,
                    "-m",
                    "apple_match.cli",
                    "--reference",
                    str(reference_dir),
                    "--candidate",
                    str(candidate_dir),
                    "--output",
                    str(output_dir),
                ],
                cwd=ROOT / "compare",
                env=environment,
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertIn('"score"', completed.stdout)
            scorecard = json.loads((output_dir / "scorecard.json").read_text())
            self.assertAlmostEqual(scorecard["score"], 100.0, places=4)
            self.assertTrue((output_dir / "signed_diff_x4.png").exists())
            self.assertTrue((output_dir / "solid_lighting_comparison.png").exists())

    def test_rejects_blank_renderer_output(self):
        reference = synthetic()
        blank = synthetic(highlight=0.0)
        with self.assertRaisesRegex(ValueError, "no measurable glass silhouette"):
            score_images(reference, blank)

    def test_rejects_settings_not_wired_to_live_renderer(self):
        validate_settings({"blur": 6.0, "shapeProfile": "roundedRectangle"})
        with self.assertRaisesRegex(ValueError, "not wired"):
            validate_settings({"blur": 6.0, "faceFill": 0.2})
        with self.assertRaisesRegex(ValueError, "shapeProfile"):
            validate_settings({"shapeProfile": "squircle-ish"})

    def test_pixel_residuals_are_exact_and_region_aware(self) -> None:
        reference = synthetic()
        exact = score_images(reference, reference)
        exact_pixels = exact.details["pixelResiduals"]
        self.assertEqual(exact.details["directPixelMeanAbsoluteError8Bit"], 0.0)
        self.assertEqual(exact.details["directPixelScore"], 100.0)
        self.assertEqual(exact_pixels["A"]["crop"]["meanAbsoluteError8Bit"], 0.0)
        self.assertEqual(exact_pixels["A"]["glass"]["meanAbsoluteError8Bit"], 0.0)
        self.assertEqual(exact_pixels["C"]["rim"]["p99AbsoluteError8Bit"], 0.0)
        self.assertEqual(
            exact_pixels["A"]["exteriorShadowAnnulus2To20"]
            ["meanAbsoluteError8Bit"],
            0.0,
        )
        self.assertEqual(
            exact_pixels["A"]["directionalExteriorShadowAnnulus2To20"]
            ["top"]["meanAbsoluteError8Bit"],
            0.0,
        )
        transfer = exact_pixels["solidTransfer"]
        self.assertEqual(
            transfer["emission"]["outerContour"]["meanAbsoluteError8Bit"],
            0.0,
        )
        self.assertEqual(
            transfer["transmission"]["innerBevel"]["meanAbsoluteError8Bit"],
            0.0,
        )
        self.assertTrue(exact.details["lightingRegressionGate"]["passed"])
        self.assertEqual(exact.details["lightingRegressionGate"]["failures"], {})

        changed = {key: image.copy() for key, image in reference.items()}
        changed["A"][56:72, 56:72, :] = np.clip(
            changed["A"][56:72, 56:72, :] + 8.0 / 255.0, 0.0, 1.0
        )
        pixels = score_images(reference, changed).details["pixelResiduals"]["A"]
        self.assertGreater(pixels["crop"]["meanAbsoluteError8Bit"], 0.0)
        self.assertGreater(pixels["glass"]["meanAbsoluteError8Bit"], 0.0)
        self.assertGreater(pixels["glass"]["mismatchedPixelFraction2Of255"], 0.0)
        self.assertEqual(pixels["rim"]["meanAbsoluteError8Bit"], 0.0)

    def test_lighting_regression_gate_cannot_be_hidden_by_headline_score(self):
        reference = synthetic(blur=1)
        candidate = synthetic(blur=1, highlight=0.30)

        result = score_images(reference, candidate)

        self.assertGreater(result.score, 90.0)
        gate = result.details["lightingRegressionGate"]
        self.assertFalse(gate["passed"])
        self.assertFalse(gate["weightedScoreCanOverride"])
        self.assertIn("specular", gate["failures"])

    def test_fixed_blur_mix_has_linear_endpoints(self):
        image = synthetic()["A"]
        blurred = cv2.GaussianBlur(image, (0, 0), 3.0)
        np.testing.assert_allclose(
            fixed_blur_mix(image, sigma=3.0, mix=0.0),
            image,
        )
        np.testing.assert_allclose(
            fixed_blur_mix(image, sigma=3.0, mix=1.0),
            blurred,
        )
        np.testing.assert_allclose(
            fixed_blur_mix(image, sigma=3.0, mix=0.25),
            image * 0.75 + blurred * 0.25,
        )

    def test_exact_match_scores_higher_than_perturbation(self):
        reference = synthetic(blur=1.5)
        exact = score_images(reference, reference)
        perturbed = score_images(reference, synthetic(blur=6, highlight=0.05, tint=(-0.2, 0, 0.1)))
        self.assertGreater(exact.score, perturbed.score)
        self.assertAlmostEqual(exact.score, 100.0, places=4)

    def test_parameter_changes_alter_decomposed_metrics(self):
        reference = synthetic(blur=1)
        blur_result = score_images(reference, synthetic(blur=5))
        light_result = score_images(reference, synthetic(blur=1, highlight=0.05))
        tint_result = score_images(reference, synthetic(blur=1, tint=(-0.2, 0, 0.1)))
        self.assertGreater(blur_result.errors["sharpness"], 0)
        self.assertGreater(light_result.errors["specular"], 0)
        self.assertGreater(tint_result.errors["channel"], 0)

    def test_shape_mismatch_reduces_shape_stage(self):
        reference = synthetic(blur=1)
        result = score_images(reference, synthetic(blur=1, shape_scale=0.8))
        self.assertGreater(result.errors["shape"], 0)
        self.assertLess(result.details["stageScores"]["shape"], 100)

    def test_registration_rejects_background_offset(self):
        reference = synthetic()["A"]
        shifted = np.roll(reference, 2, axis=1)
        with self.assertRaises(ValueError):
            verify_background_registration(reference, shifted, (40, 40, 48, 48))


if __name__ == "__main__":
    unittest.main()
