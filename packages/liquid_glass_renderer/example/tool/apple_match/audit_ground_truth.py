#!/usr/bin/env python3
"""Audit the complete compact iOS 27 Apple ground-truth matrix."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import cv2
import numpy as np

from reference_provenance import validate_reference_for_scene
from stage_metrics import shape_mask


ROOT = Path(__file__).resolve().parent
EXPECTED = {
    "slider-000": (
        "small_capsule", "toolbar_capsule", "large_capsule",
        "material_capsule", "material_circle", "material_card",
        "toolbar_capsule_dark", "material_card_dark",
        "tab_bar_holdout",
    ),
    "slider-050": ("toolbar_capsule", "toolbar_capsule_dark"),
    "slider-100": ("toolbar_capsule", "toolbar_capsule_dark"),
}


def read(path: Path) -> np.ndarray:
    image = cv2.imread(str(path), cv2.IMREAD_COLOR)
    if image is None:
        raise ValueError(f"cannot read {path}")
    return image


def outside_glass_mae(first: Path, second: Path, scene_path: Path) -> float:
    scene = json.loads(scene_path.read_text())
    mask = shape_mask(scene).astype(np.uint8)
    scale = scene["canvas"]["scale"]
    margin = round(24 * scale)
    expanded = cv2.dilate(mask, np.ones((margin * 2 + 1, margin * 2 + 1), np.uint8))
    outside = expanded == 0
    delta = np.abs(read(first).astype(np.float32) - read(second).astype(np.float32))
    return float(delta[outside].mean())


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference-root", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    report = {"schemaVersion": 1, "status": "passed", "captures": [], "crossChecks": []}
    source_vectors = set()
    for slider_dir, scenes in EXPECTED.items():
        expected_slider = int(slider_dir.removeprefix("slider-")) / 100
        for scene_id in scenes:
            capture = args.reference_root / slider_dir / scene_id
            scene_path = ROOT / "scenes" / f"{scene_id}.json"
            metadata = validate_reference_for_scene(capture, scene_path)
            if abs(metadata["liquidGlassTintPositionReadback"] - expected_slider) > 0.001:
                raise ValueError(f"folder/readback mismatch: {capture}")
            source_vectors.add((
                metadata["appleSourceSha256"], metadata["sceneModelSha256"],
                metadata["infoPlistSha256"],
                metadata["runtime"], metadata["runtimeIdentifier"], metadata["udid"],
            ))
            report["captures"].append({
                "slider": expected_slider,
                "scene": scene_id,
                "appearance": metadata["appearance"],
                "api": metadata["api"],
                "frameStability": metadata["frameStability"],
                "metadata": str((capture / "metadata.json").resolve()),
            })
    if len(source_vectors) != 1:
        raise ValueError("ground-truth captures do not share one source/runtime vector")
    for scene_id in ("toolbar_capsule", "toolbar_capsule_dark"):
        scene_path = ROOT / "scenes" / f"{scene_id}.json"
        captures = [args.reference_root / slider / scene_id for slider in EXPECTED]
        for probe in "ABCD":
            outside_errors = [
                outside_glass_mae(captures[0] / f"{probe}.png", capture / f"{probe}.png", scene_path)
                for capture in captures[1:]
            ]
            if max(outside_errors) > 0.25:
                raise ValueError(
                    f"{scene_id} probe {probe} background changed across slider captures: {outside_errors}"
                )
            report["crossChecks"].append({
                "scene": scene_id,
                "probe": probe,
                "check": "outside-glass background invariant across slider",
                "meanAbsoluteError8Bit": outside_errors,
                "status": "passed",
            })
        glass_differences = []
        mask = shape_mask(json.loads(scene_path.read_text()))
        baseline = read(captures[0] / "A.png").astype(np.float32)
        for capture in captures[1:]:
            candidate = read(capture / "A.png").astype(np.float32)
            glass_differences.append(float(np.abs(candidate - baseline)[mask].mean()))
        if min(glass_differences) < 0.25:
            raise ValueError(f"{scene_id} slider captures are visually indistinguishable: {glass_differences}")
        report["crossChecks"].append({
            "scene": scene_id,
            "probe": "A",
            "check": "slider changes glass pixels",
            "meanAbsoluteDifference8Bit": glass_differences,
            "status": "passed",
        })
    output = args.output or args.reference_root / "ground_truth_audit.json"
    output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"status": "passed", "captures": len(report["captures"]), "report": str(output.resolve())}))


if __name__ == "__main__":
    main()
