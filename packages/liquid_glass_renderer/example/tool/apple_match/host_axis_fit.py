#!/usr/bin/env python3
"""Fast one-probe host-GPU fit for frost and optical material axes."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from stage_metrics import (
    apply_settings_geometry,
    read_rgb,
    refraction_metrics,
)
from reference_provenance import validate_reference_for_scene


ROOT = Path(__file__).resolve().parent


def values(raw: str) -> list[float]:
    return [float(value) for value in raw.split(",")]


def slug(value: float) -> str:
    return f"{value:g}".replace("-", "m").replace(".", "p")


def font(size: int) -> ImageFont.ImageFont:
    for path in (
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
    ):
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            pass
    return ImageFont.load_default()


def objective(metrics: dict, mode: str) -> float:
    if mode == "frost":
        error = metrics["frequencyResponse"][
            "candidateVsReferenceAbsoluteError"
        ]
        # Apple mixes clear and frosted backdrop contributions. One Gaussian
        # sigma cannot fit the retained fine detail and broad low-frequency
        # wash simultaneously, so optimize the reproducible high/mid detail
        # and keep lowRms as an explicit, non-optimized model residual.
        return error["highRms"] * 0.55 + error["midRms"] * 0.45
    return (
        metrics["outerContour0To3px"]["vectorMeanAbsoluteErrorPixels"] * 0.30
        + metrics["innerBevel3To12px"]["vectorMeanAbsoluteErrorPixels"] * 0.35
        + metrics["faceOver12px"]["vectorMeanAbsoluteErrorPixels"] * 0.25
        + metrics["glass"]["vectorMeanAbsoluteErrorPixels"] * 0.10
    )


def crop(image: Image.Image, scene: dict) -> Image.Image:
    scale = scene["canvas"]["scale"]
    shape = scene["shape"]
    margin = 12 * scale
    return image.crop(
        (
            round(shape["x"] * scale - margin),
            round(shape["y"] * scale - margin),
            round((shape["x"] + shape["width"]) * scale + margin),
            round((shape["y"] + shape["height"]) * scale + margin),
        )
    )


def atlas(
    reference_dir: Path,
    rows: list[dict],
    scene: dict,
    output: Path,
    title: str,
) -> None:
    winners = rows[:4]
    columns = [("APPLE GROUND TRUTH", reference_dir)] + [
        (row["id"], Path(row["candidateDir"])) for row in winners
    ]
    samples = {
        label: crop(Image.open(directory / "A.png").convert("RGB"), scene)
        for label, directory in columns
    }
    width, height = next(iter(samples.values())).size
    zoom = 2
    cell_width = width * zoom
    cell_height = height * zoom
    header = 92
    label_height = 34
    result = Image.new(
        "RGB",
        (cell_width * len(columns), header + 2 * (cell_height + label_height)),
        (25, 27, 31),
    )
    draw = ImageDraw.Draw(result)
    draw.text((16, 10), title, font=font(22), fill="white")
    draw.text(
        (16, 45),
        "Probe A · ranked quantitatively · nearest-neighbor 2× crops",
        font=font(15),
        fill=(205, 211, 220),
    )
    reference = np.asarray(samples[columns[0][0]], dtype=np.float32)
    for column, (label, _) in enumerate(columns):
        draw.text(
            (column * cell_width + 12, header - 24),
            label,
            font=font(14),
            fill="white",
        )
    for row_index, row_label in enumerate(("PATTERN", "SIGNED RESIDUAL ×4")):
        top = header + row_index * (cell_height + label_height)
        draw.text((12, top + 8), row_label, font=font(15), fill="white")
        for column, (label, _) in enumerate(columns):
            sample = samples[label]
            if row_index == 1:
                if column == 0:
                    sample = Image.new("RGB", sample.size, (128, 128, 128))
                else:
                    candidate = np.asarray(sample, dtype=np.float32)
                    signed = np.clip((candidate - reference) * 4 + 128, 0, 255)
                    sample = Image.fromarray(signed.astype(np.uint8))
            result.paste(
                sample.resize((cell_width, cell_height), Image.Resampling.NEAREST),
                (column * cell_width, top + label_height),
            )
    output.parent.mkdir(parents=True, exist_ok=True)
    result.save(output)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scene", type=Path, required=True)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--base-settings", type=Path, required=True)
    parser.add_argument("--axis", required=True)
    parser.add_argument("--values", required=True)
    parser.add_argument("--objective", choices=("frost", "flow"), required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--title", required=True)
    parser.add_argument("--skip-capture", action="store_true")
    args = parser.parse_args()

    validate_reference_for_scene(args.reference, args.scene)
    raw_scene = json.loads(args.scene.read_text())
    base = json.loads(args.base_settings.read_text())
    adjusted_scene = apply_settings_geometry(raw_scene, base)
    reference = read_rgb(args.reference / "A.png")
    configs = args.out / "configs"
    candidates = args.out / "candidates"
    configs.mkdir(parents=True, exist_ok=True)
    candidates.mkdir(parents=True, exist_ok=True)
    rows = []
    candidates_values = values(args.values)
    for index, value in enumerate(candidates_values, start=1):
        identifier = f"{args.axis}-{slug(value)}"
        config = dict(base)
        config[args.axis] = value
        config_path = configs / f"{identifier}.json"
        candidate_dir = candidates / identifier
        config_path.write_text(json.dumps(config, indent=2) + "\n")
        if not args.skip_capture:
            env = os.environ | {
                "CAPTURE_PROBES": "A",
                "SETTINGS_FILE": str(config_path.resolve()),
                "SCENE_FILE": str(args.scene.resolve()),
                "CANDIDATE_OUT": str(candidate_dir.resolve()),
            }
            print(f"[{index}/{len(candidates_values)}] {identifier}", flush=True)
            subprocess.run(
                ["bash", "flutter/host_capture.sh"],
                cwd=ROOT,
                env=env,
                check=True,
                stdout=subprocess.DEVNULL,
            )
        metrics = refraction_metrics(
            adjusted_scene,
            reference,
            read_rgb(candidate_dir / "A.png"),
        )
        rows.append(
            {
                "id": identifier,
                "axis": args.axis,
                "value": value,
                "objective": objective(metrics, args.objective),
                "candidateDir": str(candidate_dir.resolve()),
                "metrics": metrics,
            }
        )
    rows.sort(key=lambda row: row["objective"])
    summary = {
        "schemaVersion": 1,
        "capturePlatform": "macos-host-golden-metal",
        "probe": "A",
        "axis": args.axis,
        "objectiveMode": args.objective,
        "candidates": rows,
    }
    (args.out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    atlas(
        args.reference,
        rows,
        adjusted_scene,
        args.out / "comparison-grid.png",
        args.title,
    )
    print(json.dumps(rows[:5], indent=2))


if __name__ == "__main__":
    main()
