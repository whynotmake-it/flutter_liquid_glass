"""Command-line scorecard generator."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

import numpy as np

from .geometry import apply_settings_geometry
from .metrics import (
    WEIGHTS,
    read_rgb,
    score_images,
    verify_background_registration,
    write_diagnostics,
)
from .scene import load_scene, metric_family, probe_ids, scene_crop
from .solid_color import measure_solid_palette


def load_probes(directory: Path, probes, crop=None):
    images = {
        probe: read_rgb(directory / f"{probe}.png")
        for probe in probes
    }
    if crop is None:
        return images
    x, y, width, height = crop
    return {
        probe: image[y : y + height, x : x + width]
        for probe, image in images.items()
    }


def load_frame_probes(directory: Path, index: str, probes, crop=None):
    frame_dir = directory / "frames"
    images = {
        probe: read_rgb(frame_dir / f"{probe}_{index}.png")
        for probe in probes
    }
    if crop is None:
        return images
    x, y, width, height = crop
    return {
        probe: image[y : y + height, x : x + width]
        for probe, image in images.items()
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--settings", type=Path)
    parser.add_argument("--scene", type=Path, required=True)
    parser.add_argument(
        "--host-capture",
        action="store_true",
        help="Exclude the pinned simulator's four-pixel display-corner clip.",
    )
    args = parser.parse_args()

    scene = load_scene(args.scene)
    probes = probe_ids(scene)
    family = metric_family(scene)
    if family == "solidColor":
        settings = json.loads(args.settings.read_text()) if args.settings else {}
        adjusted_scene = apply_settings_geometry(scene, settings)
        result = measure_solid_palette(
            adjusted_scene,
            args.reference,
            args.candidate,
        )
        args.output.mkdir(parents=True, exist_ok=True)
        (args.output / "solid_color.json").write_text(
            json.dumps(result, indent=2) + "\n"
        )
        print(json.dumps(result, indent=2))
        return
    if family != "scorecard":
        raise ValueError(f"Unsupported metric family {family!r}")

    crop = scene_crop(scene)
    registration_rect = None
    registration_exclusions = ()
    registration_rect = crop
    canvas = scene["canvas"]
    scale = canvas["scale"]
    system_ui_height = round(40 * scale)
    registration_exclusions = (
        (
            0,
            round(canvas["logicalHeight"] * scale) - system_ui_height,
            round(canvas["logicalWidth"] * scale),
            system_ui_height,
        ),
    )
    if args.host_capture:
        width = round(canvas["logicalWidth"] * scale)
        registration_exclusions += (
            (0, 0, 4, 4),
            (width - 4, 0, 4, 4),
        )
    gradient_registration_tolerance = 2.0 / 255.0
    if any(
        probe["background"].get("kind") == "linearGradient"
        for probe in scene["probes"]
    ):
        # SwiftUI and Flutter use slightly different interpolation spaces for
        # gradients. Keep solid/grid registration exact, but allow the known
        # few-level gradient transfer difference so the shape is still scored.
        gradient_registration_tolerance = 16.0 / 255.0
    full_reference = load_probes(args.reference, probes)
    full_candidate = load_probes(args.candidate, probes)
    registration = verify_background_registration(
        full_reference["A"],
        full_candidate["A"],
        registration_rect or (0, 0, 0, 0),
        registration_exclusions,
        maximum_residual=gradient_registration_tolerance,
    )
    reference = load_probes(args.reference, probes, crop)
    candidate = load_probes(args.candidate, probes, crop)
    result = score_images(reference, candidate)
    reference_indices = {
        path.stem.split("_")[-1]
        for path in (args.reference / "frames").glob("A_*.png")
    }
    candidate_indices = {
        path.stem.split("_")[-1]
        for path in (args.candidate / "frames").glob("A_*.png")
    }
    temporal_scores = [
        score_images(
            load_frame_probes(args.reference, index, probes, crop),
            load_frame_probes(args.candidate, index, probes, crop),
        ).score
        for index in sorted(reference_indices & candidate_indices)
    ]
    temporal = None
    if temporal_scores:
        standard_deviation = (
            float(np.std(temporal_scores, ddof=1))
            if len(temporal_scores) > 1
            else 0.0
        )
        t95 = 4.303 if len(temporal_scores) == 3 else 1.96
        temporal = {
            "samples": temporal_scores,
            "mean": float(np.mean(temporal_scores)),
            "standardDeviation": standard_deviation,
            "confidence95HalfWidth": (
                t95 * standard_deviation / np.sqrt(len(temporal_scores))
            ),
        }
    args.output.mkdir(parents=True, exist_ok=True)
    write_diagnostics(args.output, reference, candidate)
    scorecard = {
        "schemaVersion": 1,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "reference": str(args.reference.resolve()),
        "candidate": str(args.candidate.resolve()),
        "score": result.score,
        "errors": result.errors,
        "weights": WEIGHTS,
        "normalizationThresholds": {
            "shape": 0.20,
            "combined": 0.25,
            "flow": 1.0,
            "sharpness": 1.0,
            "channel": 0.25,
            "specular": 0.25,
            "holdout": 0.25,
        },
        "registration": registration,
        "capturePlatform": "macos-host-golden" if args.host_capture else "device",
        "measurements": result.details,
        "alignmentShiftPixels": {"x": result.shift[0], "y": result.shift[1]},
        "cropPixels": crop,
        "temporalScore": temporal,
        "settings": json.loads(args.settings.read_text()) if args.settings else None,
    }
    (args.output / "scorecard.json").write_text(
        json.dumps(scorecard, indent=2) + "\n"
    )
    print(json.dumps({"score": result.score, "errors": result.errors}, indent=2))


if __name__ == "__main__":
    main()
