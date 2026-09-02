#!/usr/bin/env python3
"""Create pixel-preserving outline crops from a solid-lighting composite."""

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


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--title", required=True)
    parser.add_argument("--subtitle", default="")
    parser.add_argument("--scale", type=int, default=3)
    args = parser.parse_args()

    source = Image.open(args.input).convert("RGB")
    if source.width % 3 != 0 or source.height % 2 != 0:
        raise ValueError("expected three columns and two solid-probe rows")

    panel_width = source.width // 3
    row_height = source.height // 2
    crop_width = 250
    crop_height = 165
    regions = (
        ("BLACK · upper-left transition", 60, 70, 0),
        ("BLACK · lower-right transition", 570, 250, 0),
        ("WHITE · upper-left transition", 60, 70, row_height),
        ("WHITE · lower-right transition", 570, 250, row_height),
    )
    labels = ("APPLE GROUND TRUTH", "FLUTTER CANDIDATE", "SIGNED DIFF ×3")
    scaled_width = crop_width * args.scale
    scaled_height = crop_height * args.scale
    header_height = 88
    label_height = 36
    region_label_width = 290
    row_stride = scaled_height + label_height
    result = Image.new(
        "RGB",
        (
            region_label_width + 3 * scaled_width,
            header_height + len(regions) * row_stride,
        ),
        (28, 30, 34),
    )
    draw = ImageDraw.Draw(result)
    draw.text((16, 10), args.title, font=_font(24), fill="white")
    draw.text((16, 48), args.subtitle, font=_font(15), fill=(205, 211, 219))

    for column, label in enumerate(labels):
        x = region_label_width + column * scaled_width
        draw.text(
            (x + 12, header_height + 7),
            label,
            font=_font(15),
            fill=(130, 190, 255) if column == 1 else "white",
        )

    for row, (region_label, left, top, row_offset) in enumerate(regions):
        y = header_height + row * row_stride + label_height
        draw.text(
            (16, y + 12),
            region_label,
            font=_font(17),
            fill="white",
        )
        for column in range(3):
            panel_left = column * panel_width
            crop = source.crop(
                (
                    panel_left + left,
                    row_offset + top,
                    panel_left + left + crop_width,
                    row_offset + top + crop_height,
                )
            ).resize(
                (scaled_width, scaled_height),
                Image.Resampling.NEAREST,
            )
            x = region_label_width + column * scaled_width
            result.paste(crop, (x, y))
            draw.rectangle(
                (x, y, x + scaled_width - 1, y + scaled_height - 1),
                outline=(245, 245, 245),
                width=1,
            )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    result.save(args.output)


if __name__ == "__main__":
    main()
