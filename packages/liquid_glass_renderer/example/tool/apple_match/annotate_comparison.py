#!/usr/bin/env python3
"""Add deterministic provenance labels to harness comparison composites.

The input pixels are copied unchanged below a small metadata header. This is
intended for comparison images posted in reviews, where the left/right panel
roles and the exact candidate settings must remain obvious.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


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


def annotate(
    source: Path,
    destination: Path,
    labels: list[str],
    title: str,
    subtitle: str,
) -> None:
    image = Image.open(source).convert("RGB")
    if image.width % len(labels) != 0:
        raise ValueError("source width must divide evenly by the panel count")

    panel_width = image.width // len(labels)
    header_height = 68
    result = Image.new("RGB", (image.width, image.height + header_height), (28, 30, 34))
    result.paste(image, (0, header_height))
    draw = ImageDraw.Draw(result)
    title_font = _font(22)
    subtitle_font = _font(14)
    label_font = _font(18)
    draw.text((16, 8), title, font=title_font, fill="white")
    draw.text((16, 39), subtitle, font=subtitle_font, fill=(206, 211, 219))

    outline_colors = ((76, 175, 80), (66, 133, 244), (244, 130, 48), (180, 80, 200))
    for index, label in enumerate(labels):
        left = index * panel_width
        if index:
            draw.line(
                (left, header_height, left, result.height),
                fill="white",
                width=2,
            )
        top = header_height + 10
        bottom = header_height + 42
        draw.rounded_rectangle(
            (left + 12, top, left + panel_width - 12, bottom),
            radius=7,
            fill="black",
            outline=outline_colors[index % len(outline_colors)],
            width=2,
        )
        bounds = draw.textbbox((0, 0), label, font=label_font)
        text_width = bounds[2] - bounds[0]
        draw.text(
            (left + (panel_width - text_width) / 2, header_height + 15),
            label,
            font=label_font,
            fill="white",
        )

    destination.parent.mkdir(parents=True, exist_ok=True)
    result.save(destination)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--title", required=True)
    parser.add_argument("--subtitle", default="")
    parser.add_argument("--label", action="append", required=True)
    args = parser.parse_args()
    annotate(args.input, args.output, args.label, args.title, args.subtitle)


if __name__ == "__main__":
    main()
