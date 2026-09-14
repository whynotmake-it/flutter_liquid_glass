#!/usr/bin/env python3
"""Render an annotated visual sanity atlas for the canonical Apple corpus."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parent
REFERENCE = ROOT / "references/ios27-iphone17pro-ground-truth-v2"
OUTPUT = ROOT / "out/ground-truth-v2-audit"


def font(size: int) -> ImageFont.ImageFont:
    for path in ("/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/Helvetica.ttc"):
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            pass
    return ImageFont.load_default()


def crop(scene_id: str, capture: Path, probe: str, zoom: int = 2) -> Image.Image:
    scene = json.loads((ROOT / "scenes" / f"{scene_id}.json").read_text())
    shape = scene["shape"]
    scale = scene["canvas"]["scale"]
    margin = 14 * scale
    box = (
        round(shape["x"] * scale - margin), round(shape["y"] * scale - margin),
        round((shape["x"] + shape["width"]) * scale + margin),
        round((shape["y"] + shape["height"]) * scale + margin),
    )
    image = Image.open(capture / f"{probe}.png").convert("RGB").crop(box)
    return image.resize((image.width * zoom, image.height * zoom), Image.Resampling.NEAREST)


def row_atlas(rows: list[tuple[str, list[tuple[str, Image.Image]]]], output: Path, title: str, subtitle: str) -> None:
    label_width = 260
    cell_width = max(image.width for _, panels in rows for _, image in panels)
    row_height = max(image.height for _, panels in rows for _, image in panels) + 46
    columns = max(len(panels) for _, panels in rows)
    header = 100
    canvas = Image.new("RGB", (label_width + columns * cell_width, header + len(rows) * row_height), (25, 27, 31))
    draw = ImageDraw.Draw(canvas)
    draw.text((16, 10), title, font=font(24), fill="white")
    draw.text((16, 48), subtitle, font=font(14), fill=(205, 211, 220))
    for row_index, (row_label, panels) in enumerate(rows):
        y = header + row_index * row_height
        draw.text((16, y + 12), row_label, font=font(16), fill="white")
        for column, (label, image) in enumerate(panels):
            x = label_width + column * cell_width
            draw.text((x + 8, y + 8), label, font=font(14), fill=(170, 215, 255))
            canvas.paste(image, (x, y + 42))
            draw.rectangle((x, y + 42, x + image.width - 1, y + 42 + image.height - 1), outline="white")
    output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output)


def main() -> None:
    slider_rows = [
        (
            "SIZE · SLIDER 0 · PROBE A",
            [
                ("APPLE · SMALL", crop("small_capsule", REFERENCE / "slider-000/small_capsule", "A")),
                ("APPLE · TOOLBAR", crop("toolbar_capsule", REFERENCE / "slider-000/toolbar_capsule", "A")),
                ("APPLE · LARGE", crop("large_capsule", REFERENCE / "slider-000/large_capsule", "A")),
            ],
        ),
        (
            "LIGHT · TOOLBAR · PROBE A",
            [
                ("APPLE · SLIDER 0.0", crop("toolbar_capsule", REFERENCE / "slider-000/toolbar_capsule", "A")),
                ("APPLE · SLIDER 0.5", crop("toolbar_capsule", REFERENCE / "slider-050/toolbar_capsule", "A")),
                ("APPLE · SLIDER 1.0", crop("toolbar_capsule", REFERENCE / "slider-100/toolbar_capsule", "A")),
            ],
        ),
        (
            "DARK · TOOLBAR · PROBE A",
            [
                ("APPLE · SLIDER 0.0", crop("toolbar_capsule_dark", REFERENCE / "slider-000/toolbar_capsule_dark", "A")),
                ("APPLE · SLIDER 0.5", crop("toolbar_capsule_dark", REFERENCE / "slider-050/toolbar_capsule_dark", "A")),
                ("APPLE · SLIDER 1.0", crop("toolbar_capsule_dark", REFERENCE / "slider-100/toolbar_capsule_dark", "A")),
            ],
        ),
    ]
    row_atlas(
        slider_rows, OUTPUT / "size-slider-atlas.png",
        "CANONICAL APPLE GROUND TRUTH · SIZE + SLIDER",
        "Apple only · iOS 27.0 (24A5408d) · iPhone 17 Pro · exact readback · Probe A · 2× nearest-neighbor",
    )
    lighting_rows = [
        (
            "LIGHT · SLIDER 0",
            [
                ("APPLE · BLACK (C)", crop("toolbar_capsule", REFERENCE / "slider-000/toolbar_capsule", "C", 3)),
                ("APPLE · WHITE (D)", crop("toolbar_capsule", REFERENCE / "slider-000/toolbar_capsule", "D", 3)),
            ],
        ),
        (
            "DARK · SLIDER 0",
            [
                ("APPLE · BLACK (C)", crop("toolbar_capsule_dark", REFERENCE / "slider-000/toolbar_capsule_dark", "C", 3)),
                ("APPLE · WHITE (D)", crop("toolbar_capsule_dark", REFERENCE / "slider-000/toolbar_capsule_dark", "D", 3)),
            ],
        ),
    ]
    row_atlas(
        lighting_rows, OUTPUT / "lighting-atlas.png",
        "CANONICAL APPLE GROUND TRUTH · BLACK / WHITE LIGHTING",
        "Apple only · slider readback 0.000 · toolbar .buttonStyle(.glass) · 3× nearest-neighbor",
    )
    print(OUTPUT)


if __name__ == "__main__":
    main()
