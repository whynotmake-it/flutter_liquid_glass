#!/usr/bin/env python3
"""Create a compact, pixel-preserving visual-diagnostic atlas by scene stage."""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from reference_provenance import validate_reference_for_scene


@dataclass(frozen=True)
class Region:
    name: str
    probe: str
    box: tuple[int, int, int, int]
    zoom: int


def _font(size: int) -> ImageFont.ImageFont:
    for path in (
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
    ):
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            pass
    return ImageFont.load_default()


def _clamp_box(
    box: tuple[float, float, float, float],
    canvas: tuple[int, int],
) -> tuple[int, int, int, int]:
    left, top, right, bottom = box
    width, height = canvas
    return (
        max(0, round(left)),
        max(0, round(top)),
        min(width, round(right)),
        min(height, round(bottom)),
    )


def derive_regions(scene: dict, stage: str, detail_zoom: int = 3) -> list[Region]:
    scale = scene["canvas"]["scale"]
    canvas = (
        round(scene["canvas"]["logicalWidth"] * scale),
        round(scene["canvas"]["logicalHeight"] * scale),
    )
    shape = scene["shape"]
    x = shape["x"] * scale
    y = shape["y"] * scale
    width = shape["width"] * scale
    height = shape["height"] * scale
    radius = shape["cornerRadius"] * scale
    margin = 14 * scale

    whole = _clamp_box(
        (x - margin, y - margin, x + width + margin, y + height + margin),
        canvas,
    )
    top_light = _clamp_box(
        (x + width * 0.22, y - 5 * scale, x + width * 0.78, y + height * 0.34),
        canvas,
    )
    bottom_shade = _clamp_box(
        (
            x + width * 0.22,
            y + height * 0.66,
            x + width * 0.78,
            y + height + 5 * scale,
        ),
        canvas,
    )
    side_contour = _clamp_box(
        (
            x + width * 0.78,
            y + height * 0.28,
            x + width + 5 * scale,
            y + height * 0.72,
        ),
        canvas,
    )
    face = _clamp_box(
        (
            x + width * 0.30,
            y + height * 0.30,
            x + width * 0.70,
            y + height * 0.70,
        ),
        canvas,
    )
    transition_extent = min(max(radius * 1.25, height * 0.42), width * 0.55)
    corner = _clamp_box(
        (
            x - 5 * scale,
            y - 5 * scale,
            x + transition_extent,
            y + transition_extent,
        ),
        canvas,
    )
    transition_name = (
        "upper-left curvature"
        if shape["kind"] == "circle"
        else "straight-to-corner transition"
    )

    if stage == "refraction":
        return [
            Region("whole coordinate field", "A", whole, 1),
            Region(transition_name, "A", corner, detail_zoom),
            Region("side refraction", "A", side_contour, detail_zoom),
            Region("interior refraction", "A", face, detail_zoom),
        ]
    if stage == "color":
        return [
            Region("whole color chart", "B", whole, 1),
            Region("light-facing color response", "B", top_light, detail_zoom),
            Region("interior color response", "B", face, detail_zoom),
        ]
    if stage == "lighting":
        return [
            Region("whole · black", "C", whole, 1),
            Region("whole · white", "D", whole, 1),
            Region("light-facing highlight · black", "C", top_light, detail_zoom),
            Region("light-facing highlight · white", "D", top_light, detail_zoom),
            Region("lower internal shading · white", "D", bottom_shade, detail_zoom),
            Region("dark outer contour · white", "D", side_contour, detail_zoom),
            Region(f"{transition_name} · black", "C", corner, detail_zoom),
            Region(f"{transition_name} · white", "D", corner, detail_zoom),
            Region("interior lighting · white", "D", face, detail_zoom),
        ]
    raise ValueError(f"unsupported stage: {stage}")


def _signed_residual(reference: Image.Image, candidate: Image.Image) -> Image.Image:
    ref = np.asarray(reference, dtype=np.float32) / 255.0
    can = np.asarray(candidate, dtype=np.float32) / 255.0
    signed = np.clip((can - ref) * 4.0 * 0.5 + 0.5, 0.0, 1.0)
    return Image.fromarray((signed * 255).round().astype(np.uint8))


def create_atlas(
    *,
    reference_dir: Path,
    candidate_dir: Path,
    scene: dict,
    stage: str,
    output: Path,
    title: str,
    subtitle: str,
) -> dict:
    regions = derive_regions(scene, stage)
    images = {
        role: {
            probe: Image.open(directory / f"{probe}.png").convert("RGB")
            for probe in {region.probe for region in regions}
        }
        for role, directory in (
            ("reference", reference_dir),
            ("candidate", candidate_dir),
        )
    }
    for probe in images["reference"]:
        if images["reference"][probe].size != images["candidate"][probe].size:
            raise ValueError(f"probe {probe} dimensions disagree")

    row_sizes = []
    for region in regions:
        left, top, right, bottom = region.box
        row_sizes.append(((right - left) * region.zoom, (bottom - top) * region.zoom))
    cell_width = max(width for width, _ in row_sizes)
    header_height = 112
    column_label_height = 34
    row_label_width = 330
    row_gap = 14
    total_height = header_height + column_label_height + sum(
        height + row_gap for _, height in row_sizes
    )
    result = Image.new(
        "RGB",
        (row_label_width + 3 * cell_width, total_height),
        (28, 30, 34),
    )
    draw = ImageDraw.Draw(result)
    draw.text((16, 10), title, font=_font(24), fill="white")
    draw.text((16, 48), subtitle, font=_font(15), fill=(205, 211, 219))
    draw.text(
        (16, 76),
        "Residual encoding: gray = equal, red = Flutter brighter, blue = Flutter darker",
        font=_font(13),
        fill=(180, 188, 200),
    )
    labels = ("APPLE GROUND TRUTH", "FLUTTER CANDIDATE", "SIGNED DIFF ×4")
    for column, label in enumerate(labels):
        draw.text(
            (row_label_width + column * cell_width + 10, header_height + 7),
            label,
            font=_font(15),
            fill=(130, 190, 255) if column == 1 else "white",
        )

    y = header_height + column_label_height
    manifest_regions = []
    for region, (display_width, display_height) in zip(regions, row_sizes):
        reference = images["reference"][region.probe].crop(region.box)
        candidate = images["candidate"][region.probe].crop(region.box)
        residual = _signed_residual(reference, candidate)
        panels = (reference, candidate, residual)
        draw.text((16, y + 8), region.name, font=_font(17), fill="white")
        draw.text(
            (16, y + 36),
            f"probe {region.probe} · {region.zoom}× nearest-neighbor",
            font=_font(13),
            fill=(180, 188, 200),
        )
        for column, panel in enumerate(panels):
            if region.zoom != 1:
                panel = panel.resize(
                    (display_width, display_height), Image.Resampling.NEAREST
                )
            x = row_label_width + column * cell_width
            result.paste(panel, (x, y))
            draw.rectangle(
                (x, y, x + display_width - 1, y + display_height - 1),
                outline=(235, 235, 235),
                width=1,
            )
        manifest_regions.append(
            {
                "name": region.name,
                "probe": region.probe,
                "boxPixels": list(region.box),
                "zoom": region.zoom,
            }
        )
        y += display_height + row_gap

    output.parent.mkdir(parents=True, exist_ok=True)
    result.save(output)
    manifest = {
        "schemaVersion": 1,
        "scene": scene["id"],
        "shapeKind": scene["shape"]["kind"],
        "stage": stage,
        "captureEncoding": "SDR tone-mapped 8-bit PNG",
        "reference": str(reference_dir.resolve()),
        "candidate": str(candidate_dir.resolve()),
        "atlas": str(output.resolve()),
        "regions": manifest_regions,
    }
    output.with_suffix(".json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--scene", type=Path, required=True)
    parser.add_argument("--stage", choices=("refraction", "color", "lighting"), required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--title", required=True)
    parser.add_argument("--subtitle", default="")
    args = parser.parse_args()
    validate_reference_for_scene(args.reference, args.scene)
    scene = json.loads(args.scene.read_text())
    manifest = create_atlas(
        reference_dir=args.reference,
        candidate_dir=args.candidate,
        scene=scene,
        stage=args.stage,
        output=args.output,
        title=args.title,
        subtitle=args.subtitle,
    )
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
