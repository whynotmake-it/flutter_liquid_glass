#!/usr/bin/env python3
"""Build a compact Apple-only atlas that isolates size from material and shape API."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from stage_metrics import frequency_response, read_rgb, region_masks, render_probe


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


def _shape_box(scene: dict, margin_points: float = 14) -> tuple[int, int, int, int]:
    scale = scene["canvas"]["scale"]
    shape = scene["shape"]
    margin = margin_points * scale
    return (
        round(shape["x"] * scale - margin),
        round(shape["y"] * scale - margin),
        round((shape["x"] + shape["width"]) * scale + margin),
        round((shape["y"] + shape["height"]) * scale + margin),
    )


def _face_box(scene: dict, width_points: float = 100, height_points: float = 34) -> tuple[int, int, int, int]:
    scale = scene["canvas"]["scale"]
    shape = scene["shape"]
    cx = (shape["x"] + shape["width"] / 2) * scale
    cy = (shape["y"] + shape["height"] / 2) * scale
    half_width = width_points * scale / 2
    half_height = height_points * scale / 2
    return (
        round(cx - half_width),
        round(cy - half_height),
        round(cx + half_width),
        round(cy + half_height),
    )


def _frequency(scene: dict, capture_dir: Path) -> dict[str, dict[str, float]]:
    reference = read_rgb(capture_dir / "A.png")
    source, _ = render_probe(scene, "A")
    face = region_masks(scene)["faceOver12px"]
    source_response = frequency_response(source, face)
    apple_response = frequency_response(reference, face)
    return {
        "source": source_response,
        "apple": apple_response,
        "retainedFraction": {
            key: apple_response[key] / source_response[key] for key in source_response
        },
    }


def _readback(capture_dir: Path) -> float:
    metadata = json.loads((capture_dir / "metadata.json").read_text())
    value = metadata.get("liquidGlassTintPositionReadback")
    if value is None:
        raise ValueError(f"capture lacks slider readback: {capture_dir}")
    return float(value)


def create_atlas(
    *,
    first_scene: dict,
    first_capture: Path,
    second_scene: dict,
    second_capture: Path,
    output: Path,
    title: str,
) -> dict:
    if first_scene["shape"]["kind"] != second_scene["shape"]["kind"]:
        raise ValueError("size control requires the same shape primitive")
    first_readback = _readback(first_capture)
    second_readback = _readback(second_capture)
    if first_readback != second_readback:
        raise ValueError("size control requires identical slider readback")

    scenes = (first_scene, second_scene)
    captures = (first_capture, second_capture)
    images = tuple(Image.open(path / "A.png").convert("RGB") for path in captures)
    frequencies = tuple(_frequency(scene, path) for scene, path in zip(scenes, captures))
    whole = tuple(image.crop(_shape_box(scene)) for image, scene in zip(images, scenes))
    face = tuple(image.crop(_face_box(scene)) for image, scene in zip(images, scenes))

    cell_width = max(*(image.width for image in whole), *(image.width * 3 for image in face))
    whole_height = max(image.height for image in whole)
    face_height = max(image.height * 3 for image in face)
    header_height = 172
    column_label_height = 42
    row_label_width = 300
    row_gap = 18
    total_height = header_height + column_label_height + whole_height + row_gap + face_height + row_gap
    result = Image.new("RGB", (row_label_width + 2 * cell_width, total_height), (28, 30, 34))
    draw = ImageDraw.Draw(result)
    draw.text((16, 10), title, font=_font(24), fill="white")
    draw.text(
        (16, 49),
        f"Apple ground truth only · same SwiftUI .glassEffect(.regular) · same Capsule · Tint readback {first_readback:.3f}",
        font=_font(14),
        fill=(205, 211, 219),
    )
    draw.text(
        (16, 77),
        "Only capsule height changes. Retained energy is Apple output / unfiltered source (lower = smoother).",
        font=_font(14),
        fill=(205, 211, 219),
    )
    for index, (scene, metrics) in enumerate(zip(scenes, frequencies)):
        retained = metrics["retainedFraction"]
        line = (
            f"{scene['shape']['width']}×{scene['shape']['height']} pt: "
            f"high {retained['highRms'] * 100:.2f}% · mid {retained['midRms'] * 100:.2f}% · "
            f"low {retained['lowRms'] * 100:.2f}%"
        )
        draw.text((16, 108 + index * 24), line, font=_font(14), fill=(150, 205, 255))

    for column, scene in enumerate(scenes):
        label = f"APPLE · {scene['shape']['width']}×{scene['shape']['height']} PT CAPSULE"
        draw.text(
            (row_label_width + column * cell_width + 10, header_height + 9),
            label,
            font=_font(15),
            fill="white",
        )

    y = header_height + column_label_height
    draw.text((16, y + 8), "whole shape", font=_font(17), fill="white")
    draw.text((16, y + 36), "probe A · native pixels", font=_font(13), fill=(180, 188, 200))
    for column, panel in enumerate(whole):
        x = row_label_width + column * cell_width
        result.paste(panel, (x, y))
        draw.rectangle((x, y, x + panel.width - 1, y + panel.height - 1), outline="white", width=1)

    y += whole_height + row_gap
    draw.text((16, y + 8), "center face", font=_font(17), fill="white")
    draw.text((16, y + 36), "same 100×34 pt crop · 3× nearest-neighbor", font=_font(13), fill=(180, 188, 200))
    for column, panel in enumerate(face):
        panel = panel.resize((panel.width * 3, panel.height * 3), Image.Resampling.NEAREST)
        x = row_label_width + column * cell_width
        result.paste(panel, (x, y))
        draw.rectangle((x, y, x + panel.width - 1, y + panel.height - 1), outline="white", width=1)

    output.parent.mkdir(parents=True, exist_ok=True)
    result.save(output)
    manifest = {
        "schemaVersion": 1,
        "captureEncoding": "SDR tone-mapped 8-bit PNG",
        "control": "same Apple effect and shape primitive; only size differs",
        "sliderReadback": first_readback,
        "captures": [
            {
                "scene": scene["id"],
                "shape": scene["shape"],
                "capture": str(path.resolve()),
                "frequencyResponse": metrics,
            }
            for scene, path, metrics in zip(scenes, captures, frequencies)
        ],
        "atlas": str(output.resolve()),
    }
    output.with_suffix(".json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--first-scene", type=Path, required=True)
    parser.add_argument("--first-capture", type=Path, required=True)
    parser.add_argument("--second-scene", type=Path, required=True)
    parser.add_argument("--second-capture", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--title", default="Apple same-primitive size control")
    args = parser.parse_args()
    manifest = create_atlas(
        first_scene=json.loads(args.first_scene.read_text()),
        first_capture=args.first_capture,
        second_scene=json.loads(args.second_scene.read_text()),
        second_capture=args.second_capture,
        output=args.output,
        title=args.title,
    )
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
