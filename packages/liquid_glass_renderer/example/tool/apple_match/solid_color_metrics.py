#!/usr/bin/env python3
"""Measure isolated full-face color-transfer probes.

Unlike the tile-card metric, every hue is captured in its own scene probe, so
the face statistic cannot be contaminated by neighboring colors or blur
crossing a tile edge. The script is intentionally small and reports raw
per-probe values before computing a mean/worst objective.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np

from stage_metrics import apply_settings_geometry, read_rgb, region_masks, luminance


def _rgb(value: str) -> np.ndarray:
    number = int(value.removeprefix("#"), 16)
    return np.array(
        [(number >> 16) & 255, (number >> 8) & 255, number & 255],
        dtype=np.float32,
    ) / 255.0


def _mean_saturation(pixels: np.ndarray) -> float:
    return float(np.mean(np.max(pixels, axis=1) - np.min(pixels, axis=1)))


def measure_solid_palette(
    scene: dict, reference_dir: Path, candidate_dir: Path
) -> dict:
    roles = scene.get("roles", {})
    palette = roles.get("palette", [])
    if not palette:
        raise ValueError("scene roles.palette must contain at least one probe id")
    probes = {probe["id"]: probe["background"] for probe in scene["probes"]}
    face = region_masks(scene)["faceOver12px"]
    black_id = roles.get("black", "K")
    if black_id not in probes:
        raise ValueError(f"scene is missing declared black probe {black_id}")
    black_reference = read_rgb(reference_dir / f"{black_id}.png")[face]
    black_candidate = read_rgb(candidate_dir / f"{black_id}.png")[face]
    black_reference_mean = np.mean(black_reference, axis=0)
    black_candidate_mean = np.mean(black_candidate, axis=0)
    entries: dict[str, dict[str, object]] = {}
    luminance_probes = roles.get("luminance", [])
    for probe_id in [
        *palette,
        *luminance_probes,
        roles.get("black", "K"),
        roles.get("white", "W"),
    ]:
        if probe_id in entries:
            continue
        if probe_id not in probes:
            raise ValueError(f"scene is missing declared probe {probe_id}")
        spec = probes[probe_id]
        if spec.get("kind") != "solid":
            raise ValueError(f"probe {probe_id} is not a solid background")
        source = _rgb(spec["color"])
        reference = read_rgb(reference_dir / f"{probe_id}.png")
        candidate = read_rgb(candidate_dir / f"{probe_id}.png")
        if reference.shape != candidate.shape:
            raise ValueError(f"reference and candidate dimensions disagree for {probe_id}")
        ref_face = reference[face]
        can_face = candidate[face]
        ref_mean = np.mean(ref_face, axis=0)
        can_mean = np.mean(can_face, axis=0)
        ref_delta = ref_mean - source
        can_delta = can_mean - source
        # Remove the material's black-background emission so color fitting is
        # driven by transmitted hue rather than Apple/candidate lighting.
        ref_transmission = ref_mean - black_reference_mean
        can_transmission = can_mean - black_candidate_mean
        entries[probe_id] = {
            "sourceRGB8Bit": (source * 255).tolist(),
            "referenceResponseRGB8Bit": (ref_delta * 255).tolist(),
            "candidateResponseRGB8Bit": (can_delta * 255).tolist(),
            "referenceTransmissionRGB8Bit": (ref_transmission * 255).tolist(),
            "candidateTransmissionRGB8Bit": (can_transmission * 255).tolist(),
            "transmissionMae8Bit": float(np.mean(np.abs(can_transmission - ref_transmission)) * 255),
            "meanAbsoluteError8Bit": float(np.mean(np.abs(can_face - ref_face)) * 255),
            "referenceLuminanceDelta8Bit": float(np.mean(luminance(ref_face - source)) * 255),
            "candidateLuminanceDelta8Bit": float(np.mean(luminance(can_face - source)) * 255),
            "referenceSaturationDelta": _mean_saturation(ref_face) - _mean_saturation(np.broadcast_to(source, ref_face.shape)),
            "candidateSaturationDelta": _mean_saturation(can_face) - _mean_saturation(np.broadcast_to(source, can_face.shape)),
        }
    palette_entries = [entries[probe_id] for probe_id in palette]
    luminance_entries = [entries[probe_id] for probe_id in luminance_probes]
    errors = [float(entry["transmissionMae8Bit"]) for entry in palette_entries]
    return {
        "schemaVersion": 1,
        "scene": scene["id"],
        "shapeKind": scene["shape"]["kind"],
        "frostPolicy": "frost-free-solid-probes",
        "color": entries,
        "objective": {
            "paletteMeanFaceMae8Bit": float(np.mean(errors)),
            "paletteWorstFaceMae8Bit": float(np.max(errors)),
            "paletteMeanLuminanceMae8Bit": float(np.mean([
                abs(float(e["candidateLuminanceDelta8Bit"]) - float(e["referenceLuminanceDelta8Bit"]))
                for e in palette_entries
            ])),
            "paletteMeanSaturationMae8Bit": float(np.mean([
                abs(float(e["candidateSaturationDelta"]) - float(e["referenceSaturationDelta"])) * 255
                for e in palette_entries
            ])),
            "luminanceMeanFaceMae8Bit": float(np.mean([
                float(entry["meanAbsoluteError8Bit"]) for entry in luminance_entries
            ])),
        },
        "guards": {
            "blackFaceMae8Bit": float(entries[roles.get("black", "K")]["meanAbsoluteError8Bit"]),
            "whiteFaceMae8Bit": float(entries[roles.get("white", "W")]["meanAbsoluteError8Bit"]),
            "luminanceMeanFaceMae8Bit": float(np.mean([
                float(entry["meanAbsoluteError8Bit"]) for entry in luminance_entries
            ])),
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scene", type=Path, required=True)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--settings", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    scene = json.loads(args.scene.read_text())
    if args.settings is not None:
        scene = apply_settings_geometry(scene, json.loads(args.settings.read_text()))
    result = measure_solid_palette(scene, args.reference, args.candidate)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
