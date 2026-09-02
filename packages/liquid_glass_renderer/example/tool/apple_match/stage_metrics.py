#!/usr/bin/env python3
"""Report high-signal material metrics without collapsing stages to one score."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import cv2
import numpy as np

from reference_provenance import validate_reference_for_scene


def read_rgb(path: Path) -> np.ndarray:
    image = cv2.imread(str(path), cv2.IMREAD_COLOR)
    if image is None:
        raise ValueError(f"could not read {path}")
    return cv2.cvtColor(image, cv2.COLOR_BGR2RGB).astype(np.float32) / 255.0


def luminance(image: np.ndarray) -> np.ndarray:
    return image[..., 0] * 0.2126 + image[..., 1] * 0.7152 + image[..., 2] * 0.0722


def _rgb(value: str) -> np.ndarray:
    number = int(value.removeprefix("#"), 16)
    return np.array(
        [(number >> 16) & 255, (number >> 8) & 255, number & 255],
        dtype=np.float32,
    ) / 255.0


def shape_mask(scene: dict) -> np.ndarray:
    scale = scene["canvas"]["scale"]
    canvas_width = round(scene["canvas"]["logicalWidth"] * scale)
    canvas_height = round(scene["canvas"]["logicalHeight"] * scale)
    shape = scene["shape"]
    x = shape["x"] * scale
    y = shape["y"] * scale
    width = shape["width"] * scale
    height = shape["height"] * scale
    yy, xx = np.mgrid[:canvas_height, :canvas_width].astype(np.float32)
    px = xx + 0.5 - (x + width / 2)
    py = yy + 0.5 - (y + height / 2)
    kind = shape["kind"]
    if kind == "circle":
        return px * px + py * py <= (min(width, height) / 2) ** 2

    radius = min(shape["cornerRadius"] * scale, width / 2, height / 2)
    if kind == "roundedSuperellipse":
        # A compact continuous-corner approximation is sufficient for stable
        # diagnostic bands; this mask is not used to score geometry fidelity.
        exponent = 4.0
        nx = np.abs(px) / max(width / 2, 1.0)
        ny = np.abs(py) / max(height / 2, 1.0)
        return nx**exponent + ny**exponent <= 1.0

    qx = np.abs(px) - (width / 2 - radius)
    qy = np.abs(py) - (height / 2 - radius)
    outside = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0))
    inside = np.minimum(np.maximum(qx, qy), 0)
    return outside + inside <= radius


def region_masks(scene: dict) -> dict[str, np.ndarray]:
    mask = shape_mask(scene)
    distance = cv2.distanceTransform(mask.astype(np.uint8), cv2.DIST_L2, 5)
    outside_distance = cv2.distanceTransform((~mask).astype(np.uint8), cv2.DIST_L2, 5)
    height, width = mask.shape
    yy, xx = np.mgrid[:height, :width]
    shape = scene["shape"]
    scale = scene["canvas"]["scale"]
    cx = (shape["x"] + shape["width"] / 2) * scale
    cy = (shape["y"] + shape["height"] / 2) * scale
    dx = xx - cx
    dy = yy - cy
    vertical = np.abs(dy) >= np.abs(dx)
    return {
        "glass": mask,
        "outerContour0To3px": mask & (distance <= 3),
        "innerBevel3To12px": mask & (distance > 3) & (distance <= 12),
        "faceOver12px": mask & (distance > 12),
        "outside0To3px": ~mask & (outside_distance <= 3),
        "outside3To12px": ~mask & (outside_distance > 3) & (outside_distance <= 12),
        "outside12To36px": ~mask
        & (outside_distance > 12)
        & (outside_distance <= 36),
        "outsideTop0To12px": ~mask
        & (outside_distance <= 12)
        & (dy < 0),
        "outsideBottom0To12px": ~mask
        & (outside_distance <= 12)
        & (dy >= 0),
        "topFacing": mask & vertical & (dy < 0),
        "bottomFacing": mask & vertical & (dy >= 0),
        "leftFacing": mask & ~vertical & (dx < 0),
        "rightFacing": mask & ~vertical & (dx >= 0),
    }


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

    # Legacy RGBW scenes use an algorithmic base layout plus a small marker
    # patch instead of an explicit repeating pattern. Reproduce the Flutter
    # and Swift painters exactly so the size-control scenes can use the same
    # refraction/color decomposition as the newer material scenes.
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


def apply_settings_geometry(scene: dict, settings: dict) -> dict:
    """Apply the exact Flutter candidate geometry to regional metric masks."""
    adjusted = json.loads(json.dumps(scene))
    shape = adjusted["shape"]
    center_x = float(shape["x"]) + float(shape["width"]) * 0.5
    center_y = float(shape["y"]) + float(shape["height"]) * 0.5
    width = float(settings.get("shapeWidth", shape["width"]))
    height = float(settings.get("shapeHeight", shape["height"]))
    center_x += float(settings.get("shapeOffsetX", 0.0))
    center_y += float(settings.get("shapeOffsetY", 0.0))
    shape.update(
        {
            "x": center_x - width * 0.5,
            "y": center_y - height * 0.5,
            "width": width,
            "height": height,
            "cornerRadius": float(
                settings.get("cornerRadius", shape["cornerRadius"])
            ),
        }
    )
    return adjusted


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
