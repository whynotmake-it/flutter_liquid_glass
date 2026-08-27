#!/usr/bin/env python3
"""Create and strictly validate Apple ground-truth capture provenance."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import cv2
import numpy as np


SCHEMA_VERSION = 2
CAPTURE_ENCODING = "SDR tone-mapped 8-bit PNG"
PINNED_RUNTIME_IDENTIFIER = "com.apple.CoreSimulator.SimRuntime.iOS-27-0"
PINNED_UDID = "DB4F41F3-1C36-476D-B775-AFDC3686C75B"
PINNED_DEVICE = "iPhone 17 Pro"


def validate_reference_for_scene(capture_dir: Path, scene_path: Path) -> dict:
    """Validate a repository Apple reference against current capture sources."""
    root = Path(__file__).resolve().parent
    return validate_reference(
        capture_dir,
        scene_path,
        source_path=root / "apple/Sources/AppleMatchApp.swift",
        capture_script=root / "apple/capture.sh",
    )


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_png(path: Path) -> np.ndarray:
    image = cv2.imread(str(path), cv2.IMREAD_UNCHANGED)
    if image is None:
        raise ValueError(f"cannot decode PNG: {path}")
    if image.ndim != 3 or image.shape[2] not in (3, 4):
        raise ValueError(f"unexpected PNG format {image.shape}: {path}")
    return image[:, :, :3]


def expected_api(profile: str) -> str:
    if profile == "material_shape":
        return "SwiftUI View.glassEffect(_:in:)"
    if profile == "tab_bar_holdout":
        return "SwiftUI TabView system tab bar"
    if profile == "loupe":
        return "iOS 27 system text-selection loupe (UITextView long-press)"
    return "SwiftUI PrimitiveButtonStyle.glass"


def expected_construction(profile: str) -> str:
    if profile == "material_shape":
        return "Color.clear.frame(scene.shape).glassEffect(.regular,in:ReferenceGlassShape)"
    if profile == "tab_bar_holdout":
        return "SwiftUI TabView system tab bar"
    if profile == "loupe":
        return "UIKit UITextView system text-selection loupe"
    return "Button{Color.clear.frame(shape-insets)}.buttonStyle(.glass)"


def frame_stability(capture_dir: Path, frame_count: int) -> dict:
    result: dict[str, dict[str, float]] = {}
    for probe in "ABCD":
        frames = [
            read_png(capture_dir / "frames" / f"{probe}_{index}.png")
            for index in range(1, frame_count + 1)
        ]
        if len({frame.shape for frame in frames}) != 1:
            raise ValueError(f"inconsistent frame sizes for probe {probe}")
        stack = np.stack(frames).astype(np.float32)
        median = np.median(stack, axis=0)
        deviations = np.abs(stack - median)
        result[probe] = {
            "meanAbsoluteDeviation8Bit": float(deviations.mean()),
            "p99AbsoluteDeviation8Bit": float(np.percentile(deviations, 99)),
            "maxAbsoluteDeviation8Bit": float(deviations.max()),
        }
    return result


def build_metadata(
    capture_dir: Path,
    scene_path: Path,
    source_path: Path,
    capture_script: Path,
    *,
    runtime: str,
    runtime_identifier: str,
    udid: str,
    device: str,
    appearance: str,
    slider_position: float,
    slider_readback: float,
    slider_method: str,
    frame_count: int,
) -> dict:
    scene = json.loads(scene_path.read_text())
    profile = scene["profile"]
    apple_root = source_path.parent.parent
    scene_model_path = source_path.parent / "SceneModel.swift"
    info_plist_path = apple_root / "Info.plist"
    executable_path = apple_root / "build/AppleMatch.app/AppleMatch"
    frame_validator_path = apple_root.parent / "validate_probe_frame.py"
    provenance_tool_path = Path(__file__).resolve()
    files = {
        str(path.relative_to(capture_dir)): sha256(path)
        for path in sorted(capture_dir.rglob("*.png"))
    }
    first = read_png(capture_dir / "A.png")
    return {
        "schemaVersion": SCHEMA_VERSION,
        "status": "validated-ground-truth",
        "runtime": runtime,
        "runtimeIdentifier": runtime_identifier,
        "udid": udid,
        "device": device,
        "orientation": "portrait",
        "appearance": appearance,
        "captureEncoding": CAPTURE_ENCODING,
        "pixelWidth": int(first.shape[1]),
        "pixelHeight": int(first.shape[0]),
        "reduceMotion": True,
        "reduceTransparency": False,
        "increaseContrast": False,
        "contentSize": "large",
        "medianFrameCount": frame_count,
        "liquidGlassTintPosition": slider_position,
        "liquidGlassTintPositionReadback": slider_readback,
        "liquidGlassTintControlMethod": slider_method,
        "api": expected_api(profile),
        "apiConstruction": expected_construction(profile),
        "scene": scene["id"],
        "sceneProfile": profile,
        "sceneSha256": sha256(scene_path),
        "appleSourceSha256": sha256(source_path),
        "sceneModelSha256": sha256(scene_model_path),
        "infoPlistSha256": sha256(info_plist_path),
        "captureAppExecutableSha256": sha256(executable_path),
        "captureScriptSha256": sha256(capture_script),
        "frameValidatorSha256": sha256(frame_validator_path),
        "provenanceToolSha256": sha256(provenance_tool_path),
        "probeAndFrameSha256": files,
        "frameStability": frame_stability(capture_dir, frame_count),
    }


def validate_reference(
    capture_dir: Path,
    scene_path: Path,
    *,
    source_path: Path | None = None,
    capture_script: Path | None = None,
    max_mean_frame_deviation: float = 0.35,
) -> dict:
    metadata_path = capture_dir / "metadata.json"
    if not metadata_path.exists():
        raise ValueError(f"missing metadata: {metadata_path}")
    metadata = json.loads(metadata_path.read_text())
    scene = json.loads(scene_path.read_text())
    required = (
        "schemaVersion", "status", "runtime", "runtimeIdentifier", "udid",
        "device", "appearance", "captureEncoding", "pixelWidth", "pixelHeight",
        "reduceMotion", "reduceTransparency", "increaseContrast", "contentSize",
        "medianFrameCount", "liquidGlassTintPosition",
        "liquidGlassTintPositionReadback", "liquidGlassTintControlMethod", "api",
        "apiConstruction", "scene", "sceneProfile", "sceneSha256",
        "appleSourceSha256", "sceneModelSha256", "infoPlistSha256",
        "captureAppExecutableSha256", "captureScriptSha256", "probeAndFrameSha256",
        "frameValidatorSha256", "provenanceToolSha256", "frameStability",
    )
    missing = [key for key in required if key not in metadata]
    if missing:
        raise ValueError(f"metadata is missing {missing}: {metadata_path}")
    expected = {
        "schemaVersion": SCHEMA_VERSION,
        "status": "validated-ground-truth",
        "runtimeIdentifier": PINNED_RUNTIME_IDENTIFIER,
        "udid": PINNED_UDID,
        "device": PINNED_DEVICE,
        "appearance": scene["appearance"],
        "captureEncoding": CAPTURE_ENCODING,
        "reduceMotion": True,
        "reduceTransparency": False,
        "increaseContrast": False,
        "contentSize": "large",
        "scene": scene["id"],
        "sceneProfile": scene["profile"],
        "sceneSha256": sha256(scene_path),
        "api": expected_api(scene["profile"]),
        "apiConstruction": expected_construction(scene["profile"]),
    }
    if source_path is not None:
        expected["appleSourceSha256"] = sha256(source_path)
        expected["sceneModelSha256"] = sha256(source_path.parent / "SceneModel.swift")
        expected["infoPlistSha256"] = sha256(source_path.parent.parent / "Info.plist")
    # Capture-tool hashes are immutable provenance for reproducing a capture,
    # not a requirement that future harness refactors byte-match the old tool.
    # Scene and Apple rendering-source hashes above *are* current validity
    # requirements because they determine the reference pixels.
    mismatches = {
        key: {"expected": value, "actual": metadata.get(key)}
        for key, value in expected.items()
        if metadata.get(key) != value
    }
    if mismatches:
        raise ValueError(f"reference provenance mismatch: {mismatches}")
    declared = float(metadata["liquidGlassTintPosition"])
    readback = float(metadata["liquidGlassTintPositionReadback"])
    if abs(declared - readback) > 0.001:
        raise ValueError(f"slider declaration/readback mismatch: {declared} != {readback}")
    if not 0.0 <= readback <= 1.0:
        raise ValueError(f"slider readback is out of range: {readback}")
    if metadata["medianFrameCount"] < 3:
        raise ValueError("medianFrameCount must be at least 3")
    hashes = metadata["probeAndFrameSha256"]
    required_files = [f"{probe}.png" for probe in "ABCD"] + [
        f"frames/{probe}_{index}.png"
        for probe in "ABCD"
        for index in range(1, metadata["medianFrameCount"] + 1)
    ]
    if sorted(hashes) != sorted(required_files):
        raise ValueError("probe/frame checksum manifest is incomplete or has extra files")
    image_shape = None
    for relative in required_files:
        path = capture_dir / relative
        if not path.exists() or sha256(path) != hashes[relative]:
            raise ValueError(f"missing or checksum-mismatched asset: {path}")
        shape = read_png(path).shape[:2]
        image_shape = image_shape or shape
        if shape != image_shape:
            raise ValueError(f"inconsistent image dimensions: {path} is {shape}, expected {image_shape}")
    if image_shape != (metadata["pixelHeight"], metadata["pixelWidth"]):
        raise ValueError("metadata pixel dimensions do not match assets")
    for probe, stability in metadata["frameStability"].items():
        if stability["meanAbsoluteDeviation8Bit"] > max_mean_frame_deviation:
            raise ValueError(f"unstable {probe} frames: {stability}")
    return metadata


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture_dir", type=Path)
    parser.add_argument("scene", type=Path)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--capture-script", type=Path, required=True)
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--runtime")
    parser.add_argument("--runtime-identifier")
    parser.add_argument("--udid")
    parser.add_argument("--device")
    parser.add_argument("--appearance")
    parser.add_argument("--slider", type=float)
    parser.add_argument("--slider-readback", type=float)
    parser.add_argument("--slider-method")
    parser.add_argument("--frames", type=int, default=3)
    args = parser.parse_args()
    if args.write:
        needed = ("runtime", "runtime_identifier", "udid", "device", "appearance", "slider", "slider_readback", "slider_method")
        missing = [name for name in needed if getattr(args, name) is None]
        if missing:
            parser.error(f"--write requires values for {missing}")
        metadata = build_metadata(
            args.capture_dir, args.scene, args.source, args.capture_script,
            runtime=args.runtime, runtime_identifier=args.runtime_identifier,
            udid=args.udid, device=args.device, appearance=args.appearance,
            slider_position=args.slider, slider_readback=args.slider_readback,
            slider_method=args.slider_method, frame_count=args.frames,
        )
        (args.capture_dir / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
    validated = validate_reference(
        args.capture_dir, args.scene, source_path=args.source,
        capture_script=args.capture_script,
    )
    print(json.dumps({"status": "passed", "scene": validated["scene"], "slider": validated["liquidGlassTintPositionReadback"]}))


if __name__ == "__main__":
    main()
