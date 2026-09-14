"""Strict ground-truth provenance tests (no simulator)."""

import json
import tempfile
import unittest
from pathlib import Path

import cv2
import numpy as np

from reference_provenance import build_metadata, validate_reference


class ReferenceProvenanceTests(unittest.TestCase):
    def make_capture(self, root: Path) -> tuple[Path, Path, Path, Path]:
        capture = root / "capture"
        frames = capture / "frames"
        frames.mkdir(parents=True)
        scene = root / "scene.json"
        source = root / "AppleMatchApp.swift"
        apple_root = root / "apple"
        source = apple_root / "Sources/AppleMatchApp.swift"
        source.parent.mkdir(parents=True)
        (source.parent / "SceneModel.swift").write_text("struct SceneModel {}\n")
        (apple_root / "Info.plist").write_text("<plist/>\n")
        executable = apple_root / "build/AppleMatch.app/AppleMatch"
        executable.parent.mkdir(parents=True)
        executable.write_bytes(b"test executable")
        script = apple_root / "capture.sh"
        script.write_text("#!/bin/sh\n")
        (root / "validate_probe_frame.py").write_text("# validator\n")
        scene.write_text(json.dumps({
            "id": "small_capsule",
            "profile": "small_capsule",
            "appearance": "light",
        }))
        source.write_text("Button {}.buttonStyle(.glass)\n")
        for probe_index, probe in enumerate("ABCD"):
            images = []
            for frame in range(1, 4):
                image = np.full((12, 18, 3), 30 * probe_index + frame, np.uint8)
                images.append(image)
                cv2.imwrite(str(frames / f"{probe}_{frame}.png"), image)
            cv2.imwrite(str(capture / f"{probe}.png"), images[1])
        metadata = build_metadata(
            capture, scene, source, script,
            runtime="iOS 27.0 (24A5408d)",
            runtime_identifier="com.apple.CoreSimulator.SimRuntime.iOS-27-0",
            udid="DB4F41F3-1C36-476D-B775-AFDC3686C75B",
            device="iPhone 17 Pro", appearance="light",
            slider_position=0.0, slider_readback=0.0,
            slider_method="simctl defaults write com.apple.UIKit UIViewGlassTintAmount",
            frame_count=3,
        )
        (capture / "metadata.json").write_text(json.dumps(metadata))
        return capture, scene, source, script

    def test_complete_capture_passes(self):
        with tempfile.TemporaryDirectory() as directory:
            capture, scene, source, script = self.make_capture(Path(directory))
            metadata = validate_reference(
                capture, scene, source_path=source, capture_script=script,
                max_mean_frame_deviation=2.0,
            )
            self.assertEqual(metadata["status"], "validated-ground-truth")

    def test_legacy_metadata_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            capture, scene, source, script = self.make_capture(Path(directory))
            (capture / "metadata.json").write_text(json.dumps({"scene": "small_capsule"}))
            with self.assertRaisesRegex(ValueError, "metadata is missing"):
                validate_reference(capture, scene, source_path=source, capture_script=script)

    def test_slider_readback_mismatch_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            capture, scene, source, script = self.make_capture(Path(directory))
            metadata_path = capture / "metadata.json"
            metadata = json.loads(metadata_path.read_text())
            metadata["liquidGlassTintPositionReadback"] = 0.5
            metadata_path.write_text(json.dumps(metadata))
            with self.assertRaisesRegex(ValueError, "slider declaration/readback mismatch"):
                validate_reference(capture, scene, source_path=source, capture_script=script)

    def test_asset_mutation_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            capture, scene, source, script = self.make_capture(Path(directory))
            cv2.imwrite(str(capture / "A.png"), np.zeros((12, 18, 3), np.uint8))
            with self.assertRaisesRegex(ValueError, "checksum-mismatched"):
                validate_reference(capture, scene, source_path=source, capture_script=script)

    def test_later_capture_host_changes_do_not_invalidate_reference(self):
        with tempfile.TemporaryDirectory() as directory:
            capture, scene, source, script = self.make_capture(Path(directory))
            source.write_text(
                source.read_text() + "// support an unrelated scene primitive\n"
            )
            (source.parent / "SceneModel.swift").write_text(
                "struct SceneModel {}\n// unrelated schema extension\n"
            )
            metadata = validate_reference(
                capture, scene, source_path=source, capture_script=script,
                max_mean_frame_deviation=2.0,
            )
            self.assertEqual(metadata["status"], "validated-ground-truth")

    def test_scene_mutation_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            capture, scene, source, script = self.make_capture(Path(directory))
            payload = json.loads(scene.read_text())
            payload["profile"] = "large_capsule"
            scene.write_text(json.dumps(payload))
            with self.assertRaisesRegex(ValueError, "provenance mismatch"):
                validate_reference(
                    capture, scene, source_path=source, capture_script=script,
                    max_mean_frame_deviation=2.0,
                )

    def test_committed_medians_validate_without_raw_frames(self):
        with tempfile.TemporaryDirectory() as directory:
            capture, scene, source, script = self.make_capture(Path(directory))
            for frame in (capture / "frames").iterdir():
                frame.unlink()
            metadata = validate_reference(
                capture, scene, source_path=source, capture_script=script,
                max_mean_frame_deviation=2.0,
            )
            self.assertEqual(metadata["medianFrameCount"], 3)


if __name__ == "__main__":
    unittest.main()
