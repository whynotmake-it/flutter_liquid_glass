#!/usr/bin/env python3
"""Compose the real-Impeller per-shape captures into one annotated atlas."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


PANELS = (
    ("default-light.png", "DEFAULT · LIGHT", "automatic iOS 27 toolbar appearance"),
    ("default-dark.png", "DEFAULT · DARK", "automatic iOS 27 toolbar appearance"),
    (
        "color-response.png",
        "COLOR RESPONSE · SEPARATED",
        "top-left tint · top-right saturation · bottom-left gamma · bottom-right vibrancy",
    ),
    (
        "merged-visibility.png",
        "MERGED CONTRIBUTORS · VISIBILITY",
        "white + blue + coral · half visibility at right · zero visibility leaves no surface",
    ),
)


def font(size: int, *, bold: bool = False) -> ImageFont.FreeTypeFont:
    loaded = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", size)
    if bold:
        loaded.set_variation_by_name("Bold")
    return loaded


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("panels", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    images = [Image.open(args.panels / name).convert("RGB") for name, _, _ in PANELS]
    width, height = images[0].size
    if any(image.size != (width, height) for image in images):
        raise ValueError("all per-shape panels must have identical dimensions")

    gutter = 24
    header = 96
    canvas = Image.new(
        "RGB",
        (width * 2 + gutter * 3, (height + header) * 2 + gutter * 3),
        "#111318",
    )
    draw = ImageDraw.Draw(canvas)
    title_font = font(25, bold=True)
    detail_font = font(18)

    for index, (image, (_, title, detail)) in enumerate(zip(images, PANELS)):
        column = index % 2
        row = index // 2
        x = gutter + column * (width + gutter)
        y = gutter + row * (height + header + gutter)
        draw.rounded_rectangle(
            (x, y, x + width, y + height + header),
            radius=28,
            fill="#20242c",
        )
        draw.text((x + 26, y + 17), title, font=title_font, fill="#eef4ff")
        draw.text((x + 26, y + 53), detail, font=detail_font, fill="#aeb8ca")
        canvas.paste(image, (x, y + header))

    args.output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(args.output, optimize=True)


if __name__ == "__main__":
    main()
