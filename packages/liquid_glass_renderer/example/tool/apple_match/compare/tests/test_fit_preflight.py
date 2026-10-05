"""Offline tests for the staged fitter's input preflight (no simulator)."""

import io
import sys
import unittest
from contextlib import redirect_stderr
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

import hotloop_staged  # noqa: E402
from apple_match.scene import load_scene  # noqa: E402

SCENES = ROOT / "scenes"


class ValidateFitInputsTests(unittest.TestCase):
    def setUp(self):
        self.scene_path = SCENES / "toolbar_capsule.json"
        self.scene = load_scene(self.scene_path)
        self.reference_dir = Path("/fake/reference")

    def test_reduce_motion_blocks_refraction_stages(self):
        with mock.patch.object(
            hotloop_staged,
            "validate_reference_for_scene",
            return_value={"reduceMotion": True},
        ):
            for stages in (["refraction"], ["loupeMaterial"]):
                with self.subTest(stages=stages):
                    with self.assertRaisesRegex(ValueError, "Reduce Motion-off"):
                        hotloop_staged.validate_fit_inputs(
                            self.scene_path,
                            self.scene,
                            self.reference_dir,
                            stages,
                        )
            result = hotloop_staged.validate_fit_inputs(
                self.scene_path, self.scene, self.reference_dir, ["shape"]
            )
            self.assertEqual(result, {"reduceMotion": True})
        with mock.patch.object(
            hotloop_staged,
            "validate_reference_for_scene",
            return_value={"reduceMotion": False},
        ):
            result = hotloop_staged.validate_fit_inputs(
                self.scene_path, self.scene, self.reference_dir, ["refraction"]
            )
            self.assertEqual(result, {"reduceMotion": False})


class MainPreflightTests(unittest.TestCase):
    def test_color_scene_rejects_before_touching_output(self):
        with TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            reference = tmp_path / "reference"
            reference.mkdir()
            out = tmp_path / "out"
            out.mkdir()
            sentinel = out / "sentinel.txt"
            sentinel.write_text("keep me")
            argv = [
                "hotloop_staged.py",
                "--udid",
                "dummy",
                "--scene",
                "material_solid_palette",
                "--reference",
                str(reference),
                "--out",
                str(out),
                "--overwrite",
            ]
            stderr = io.StringIO()
            with mock.patch.object(sys, "argv", argv), mock.patch.object(
                hotloop_staged, "CaptureSession"
            ) as session, mock.patch.object(
                hotloop_staged,
                "load_reference_probes",
                side_effect=AssertionError("probes must not load"),
            ), mock.patch.object(
                hotloop_staged, "validate_reference_for_scene"
            ) as validator, redirect_stderr(stderr):
                with self.assertRaises(SystemExit) as context:
                    hotloop_staged.main()
            self.assertEqual(context.exception.code, 2)
            self.assertIn("scorecard", stderr.getvalue())
            self.assertTrue(sentinel.is_file())
            session.assert_not_called()
            validator.assert_not_called()


if __name__ == "__main__":
    unittest.main()
