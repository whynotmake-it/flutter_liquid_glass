#!/usr/bin/env python3
"""Report high-signal material metrics without collapsing stages to one score."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import cv2
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent / "compare"))

from apple_match.geometry import (
    apply_settings_geometry,
    region_masks,
)
from apple_match.metrics import luminance, read_rgb
from apple_match.scene import metric_family
from reference_provenance import validate_reference_for_scene


def _rgb(value: str) -> np.ndarray:
    number = int(value.removeprefix("#"), 16)
    return np.array(
        [(number >> 16) & 255, (number >> 8) & 255, number & 255],
        dtype=np.float32,
    ) / 255.0


def residual_stats(delta: np.ndarray, mask: np.ndarray) -> dict[str, object]:
    values = delta[mask]
    if values.size == 0:
        return {"pixelCount": 0}
    absolute = np.abs(values)
    return {
        "pixelCount": int(values.shape[0]),
        "meanAbsoluteError8Bit": float(np.mean(absolute) * 255),
        "p95AbsoluteError8Bit": float(np.percentile(absolute, 95) * 255),
        "signedMean8Bit": {
            "red": float(np.mean(values[:, 0]) * 255),
            "green": float(np.mean(values[:, 1]) * 255),
            "blue": float(np.mean(values[:, 2]) * 255),
        },
        "signedLuminanceMean8Bit": float(np.mean(luminance(values)) * 255),
    }


def render_probe(scene: dict, probe_id: str) -> tuple[np.ndarray, np.ndarray]:
    """Return exact deterministic source image and palette-symbol map."""
    probe = next(item for item in scene["probes"] if item["id"] == probe_id)
    spec = probe["background"]
    scale = scene["canvas"]["scale"]
    width = round(scene["canvas"]["logicalWidth"] * scale)
    height = round(scene["canvas"]["logicalHeight"] * scale)
    symbols = np.full((height, width), "", dtype="<U1")
    if spec["kind"] == "solid":
        image = np.broadcast_to(_rgb(spec["color"]), (height, width, 3)).copy()
        return image, symbols

    yy, xx = np.mgrid[:height, :width]
    logical_x = xx / scale
    logical_y = yy / scale
    columns = np.floor(logical_x / spec["cellSize"]).astype(np.int32)
    rows = np.floor(logical_y / spec["cellSize"]).astype(np.int32)
    gutter = (
        np.mod(logical_x, spec["cellSize"]) >= spec["cellSize"] - spec["gutter"]
    ) | (
        np.mod(logical_y, spec["cellSize"]) >= spec["cellSize"] - spec["gutter"]
    )
    image = np.broadcast_to(_rgb(spec["gutterColor"]), (height, width, 3)).copy()
    if spec["kind"] == "tileGrid":
        pattern = spec["pattern"]
        palette = spec["palette"]
        for row_index, pattern_row in enumerate(pattern):
            for column_index, symbol in enumerate(pattern_row):
                tile = (
                    (rows % len(pattern) == row_index)
                    & (columns % len(pattern_row) == column_index)
                    & ~gutter
                )
                image[tile] = _rgb(palette[symbol])
                symbols[tile] = symbol
        return image, symbols

    # RGBW scenes use an algorithmic base layout plus a small marker
    # patch instead of an explicit repeating pattern. Reproduce the Flutter
    # and Swift painters exactly so the size-control scenes can use the same
    # refraction/color decomposition as the material scenes.
    palette_symbols = "RGBW"
    palette = spec["colors"]
    if spec["layout"] == "primary":
        color_indices = (columns + 2 * rows + rows // 4) % 4
    else:
        color_indices = (3 * columns + rows + columns // 5) % 4
    marker = spec["marker"]
    marker_row = rows - int(spec["markerRow"])
    marker_column = columns - int(spec["markerColumn"])
    for marker_y, marker_pattern in enumerate(marker):
        for marker_x, marker_symbol in enumerate(marker_pattern):
            marker_mask = (marker_row == marker_y) & (marker_column == marker_x)
            color_indices[marker_mask] = palette_symbols.index(marker_symbol)
    for index, symbol in enumerate(palette_symbols):
        tile = (color_indices == index) & ~gutter
        image[tile] = _rgb(palette[index])
        symbols[tile] = symbol
    return image, symbols


def _flow(source: np.ndarray, captured: np.ndarray) -> np.ndarray:
    source_u8 = np.clip(luminance(source) * 255, 0, 255).astype(np.uint8)
    capture_u8 = np.clip(luminance(captured) * 255, 0, 255).astype(np.uint8)
    return cv2.calcOpticalFlowFarneback(
        source_u8, capture_u8, None, 0.5, 4, 21, 5, 7, 1.5, 0
    )


def frequency_response(image: np.ndarray, mask: np.ndarray) -> dict[str, float]:
    gray = luminance(image)
    sigma1 = cv2.GaussianBlur(gray, (0, 0), 1.0)
    sigma3 = cv2.GaussianBlur(gray, (0, 0), 3.0)
    sigma9 = cv2.GaussianBlur(gray, (0, 0), 9.0)

    def rms(band: np.ndarray) -> float:
        values = band[mask]
        return float(np.sqrt(np.mean(values * values)))

    return {
        "highRms": rms(gray - sigma1),
        "midRms": rms(sigma1 - sigma3),
        "lowRms": rms(sigma3 - sigma9),
    }


def refraction_metrics(
    scene: dict, reference: np.ndarray, candidate: np.ndarray
) -> dict[str, object]:
    source, _ = render_probe(scene, "A")
    ref_flow = _flow(source, reference)
    can_flow = _flow(source, candidate)
    delta = can_flow - ref_flow
    masks = region_masks(scene)
    result: dict[str, object] = {}
    for name in (
        "glass",
        "outerContour0To3px",
        "innerBevel3To12px",
        "faceOver12px",
    ):
        mask = masks[name]
        ref_magnitude = np.linalg.norm(ref_flow[mask], axis=1)
        can_magnitude = np.linalg.norm(can_flow[mask], axis=1)
        delta_magnitude = np.linalg.norm(delta[mask], axis=1)
        result[name] = {
            "referenceMeanMagnitudePixels": float(np.mean(ref_magnitude)),
            "candidateMeanMagnitudePixels": float(np.mean(can_magnitude)),
            "vectorMeanAbsoluteErrorPixels": float(np.mean(delta_magnitude)),
            "vectorP95AbsoluteErrorPixels": float(np.percentile(delta_magnitude, 95)),
        }
    face = masks["faceOver12px"]
    source_frequency = frequency_response(source, face)
    reference_frequency = frequency_response(reference, face)
    candidate_frequency = frequency_response(candidate, face)
    result["frequencyResponse"] = {
        "source": source_frequency,
        "reference": reference_frequency,
        "candidate": candidate_frequency,
        "candidateVsReferenceAbsoluteError": {
            key: abs(candidate_frequency[key] - reference_frequency[key])
            for key in reference_frequency
        },
        "note": "Separates retained sharp, mid, and broad structure; it does not treat Apple’s clear/frost mixture as a Gaussian sigma.",
    }
    return result


def _saturation(pixels: np.ndarray) -> float:
    return float(np.mean(np.max(pixels, axis=1) - np.min(pixels, axis=1)))


def color_metrics(
    scene: dict, reference: np.ndarray, candidate: np.ndarray
) -> dict[str, object]:
    source, symbols = render_probe(scene, "B")
    face = region_masks(scene)["faceOver12px"]
    spec = next(
        probe["background"] for probe in scene["probes"] if probe["id"] == "B"
    )
    palette = spec["palette"] if "palette" in spec else "RGBW"
    sample_inset = round(float(spec.get("sampleInset", 0.0)) * scene["canvas"]["scale"])
    result: dict[str, object] = {}
    for symbol in palette:
        symbol_mask = (symbols == symbol).astype(np.uint8)
        if sample_inset > 0:
            distance = cv2.distanceTransform(symbol_mask, cv2.DIST_L2, 5)
            symbol_mask = distance > sample_inset
        else:
            symbol_mask = symbol_mask.astype(bool)
        mask = face & symbol_mask
        if not np.any(mask):
            continue
        src = source[mask]
        ref = reference[mask]
        can = candidate[mask]
        result[symbol] = {
            "sampleCount": int(np.count_nonzero(mask)),
            "sourceMeanRGB": np.mean(src, axis=0).tolist(),
            "referenceResponseRGB8Bit": (np.mean(ref - src, axis=0) * 255).tolist(),
            "candidateResponseRGB8Bit": (np.mean(can - src, axis=0) * 255).tolist(),
            "referenceLuminanceDelta8Bit": float(np.mean(luminance(ref - src)) * 255),
            "candidateLuminanceDelta8Bit": float(np.mean(luminance(can - src)) * 255),
            "referenceSaturationDelta": _saturation(ref) - _saturation(src),
            "candidateSaturationDelta": _saturation(can) - _saturation(src),
            "candidateVsReference": residual_stats(can - ref, np.ones(can.shape[0], dtype=bool)),
        }
    return result


def lighting_metrics(
    reference: dict[str, np.ndarray], candidate: dict[str, np.ndarray], scene: dict
) -> dict[str, object]:
    masks = region_masks(scene)
    result: dict[str, object] = {"black": {}, "white": {}}
    for label, probe in (("black", "C"), ("white", "D")):
        delta = candidate[probe] - reference[probe]
        for name, mask in masks.items():
            result[label][name] = residual_stats(delta, mask)
    ref_emission = reference["C"]
    can_emission = candidate["C"]
    ref_transmission = reference["D"] - reference["C"]
    can_transmission = candidate["D"] - candidate["C"]
    result["decomposition"] = {
        "emissionResidual": {
            name: residual_stats(can_emission - ref_emission, mask)
            for name, mask in masks.items()
        },
        "transmissionResidual": {
            name: residual_stats(can_transmission - ref_transmission, mask)
            for name, mask in masks.items()
        },
    }
    result["knownFrostMixtureResidual"] = {
        "status": "reported-not-optimized",
        "reason": "Apple mixes clear and frosted backdrops; the single-pass renderer cannot exactly reproduce that interior transfer.",
        "faceTransmission": residual_stats(
            can_transmission - ref_transmission, masks["faceOver12px"]
        ),
    }
    return result


def measure(reference_dir: Path, candidate_dir: Path, scene: dict) -> dict:
    family = metric_family(scene)
    if family != "scorecard":
        raise ValueError(
            f"stage_metrics supports only scorecard scenes; "
            f"{scene.get('id', '<unknown>')!r} is {family!r}"
        )
    reference = {probe: read_rgb(reference_dir / f"{probe}.png") for probe in "ABCD"}
    candidate = {probe: read_rgb(candidate_dir / f"{probe}.png") for probe in "ABCD"}
    if any(reference[p].shape != candidate[p].shape for p in "ABCD"):
        raise ValueError("reference and candidate dimensions disagree")
    return {
        "schemaVersion": 1,
        "scene": scene["id"],
        "shapeKind": scene["shape"]["kind"],
        "captureEncoding": "SDR tone-mapped 8-bit PNG",
        "aggregateScore": None,
        "refraction": refraction_metrics(scene, reference["A"], candidate["A"]),
        "color": color_metrics(scene, reference["B"], candidate["B"]),
        "lighting": lighting_metrics(reference, candidate, scene),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--scene", type=Path, required=True)
    parser.add_argument(
        "--settings",
        type=Path,
        help="Optional candidate settings JSON used to align regional masks.",
    )
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    validate_reference_for_scene(args.reference, args.scene)
    scene = json.loads(args.scene.read_text())
    if args.settings is not None:
        scene = apply_settings_geometry(scene, json.loads(args.settings.read_text()))
    result = measure(args.reference, args.candidate, scene)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
