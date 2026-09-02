#!/usr/bin/env python3
"""Create an annotated Apple/Flutter/residual atlas for solid color probes."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parent


def _font(size: int) -> ImageFont.ImageFont:
    for path in ("/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/Helvetica.ttc"):
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            pass
    return ImageFont.load_default()


def _crop(path: Path, scene: dict, zoom: int) -> Image.Image:
    shape = scene["shape"]
    scale = scene["canvas"]["scale"]
    margin = 12 * scale
    box = (
        round(shape["x"] * scale - margin),
        round(shape["y"] * scale - margin),
        round((shape["x"] + shape["width"]) * scale + margin),
        round((shape["y"] + shape["height"]) * scale + margin),
    )
    image = Image.open(path).convert("RGB").crop(box)
    return image.resize((image.width * zoom, image.height * zoom), Image.Resampling.NEAREST)


def write_atlas(scene: dict, reference: Path, candidate: Path, output: Path, zoom: int) -> None:
    probes = [probe["id"] for probe in scene["probes"]]
    sample = _crop(reference / f"{probes[0]}.png", scene, zoom)
    label_width = 190
    cell_width = sample.width
    label_height = 34
    row_height = label_height + sample.height
    header = 92
    canvas = Image.new(
        "RGB",
        (label_width + cell_width * 3, header + row_height * len(probes)),
        (24, 26, 30),
    )
    draw = ImageDraw.Draw(canvas)
    draw.text((14, 10), f"SOLID COLOR FIT · {scene['id']}", font=_font(22), fill="white")
    draw.text(
        (14, 46),
        "APPLE LEFT · FLUTTER CENTER · SIGNED RESIDUAL ×4 RIGHT · FROST 0",
        font=_font(13),
        fill=(205, 211, 220),
    )
    columns = ("APPLE GROUND TRUTH", "FLUTTER CANDIDATE", "SIGNED DIFF ×4")
    for column, label in enumerate(columns):
        draw.text((label_width + column * cell_width + 8, 70), label, font=_font(13), fill=(170, 215, 255))

    for row, probe in enumerate(probes):
        top = header + row * row_height
        draw.text((14, top + 10), f"PROBE {probe}", font=_font(17), fill="white")
        reference_image = _crop(reference / f"{probe}.png", scene, zoom)
        candidate_image = _crop(candidate / f"{probe}.png", scene, zoom)
        reference_pixels = np.asarray(reference_image, dtype=np.int16)
        candidate_pixels = np.asarray(candidate_image, dtype=np.int16)
        residual = Image.fromarray(
            np.clip((candidate_pixels - reference_pixels) * 4 + 128, 0, 255).astype(np.uint8)
        )
        for column, image in enumerate((reference_image, candidate_image, residual)):
            x = label_width + column * cell_width
            canvas.paste(image, (x, top + label_height))
            draw.rectangle((x, top + label_height, x + image.width - 1, top + label_height + image.height - 1), outline="white")
    output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scene", type=Path, required=True)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--zoom", type=int, default=2)
    args = parser.parse_args()
    write_atlas(json.loads(args.scene.read_text()), args.reference, args.candidate, args.output, args.zoom)


if __name__ == "__main__":
    main()
