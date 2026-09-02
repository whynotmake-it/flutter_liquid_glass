#!/usr/bin/env python3
"""Fit one color-transmission axis with isolated host-Metal captures."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from reference_provenance import validate_reference_for_scene
from stage_metrics import apply_settings_geometry, measure


ROOT = Path(__file__).resolve().parent


def _values(raw: str) -> list[float]:
    return [float(value) for value in raw.split(",")]


def _slug(value: float) -> str:
    return f"{value:g}".replace("-", "m").replace(".", "p")


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


def _objective(
    metrics: dict, symbols: set[str] | None = None
) -> tuple[float, dict[str, float]]:
    # Compare the mean material response of each deterministic color patch,
    # not corresponding pixels. Apple has a frosted/clear backdrop mixture
    # and different refraction, so pixel MAE would leak two later stages into
    # the color fit even though the patch-average transfer is still valid.
    response_errors = []
    luminance_errors = []
    saturation_errors = []
    entries = {
        symbol: entry
        for symbol, entry in metrics["color"].items()
        if symbols is None or symbol in symbols
    }
    if not entries:
        raise ValueError("color objective contains no palette symbols")
    for entry in entries.values():
        reference_response = np.asarray(entry["referenceResponseRGB8Bit"])
        candidate_response = np.asarray(entry["candidateResponseRGB8Bit"])
        response_errors.append(float(np.mean(np.abs(candidate_response - reference_response))))
        luminance_errors.append(
            abs(entry["candidateLuminanceDelta8Bit"] - entry["referenceLuminanceDelta8Bit"])
        )
        saturation_errors.append(
            abs(entry["candidateSaturationDelta"] - entry["referenceSaturationDelta"]) * 255
        )
    response_mae = float(np.mean(response_errors))
    luminance_mae = float(np.mean(luminance_errors))
    saturation_mae = float(np.mean(saturation_errors))
    worst_response_mae = float(np.max(response_errors))
    worst_luminance_mae = float(np.max(luminance_errors))
    worst_saturation_mae = float(np.max(saturation_errors))
    color_mae = response_mae * 0.55 + luminance_mae * 0.25 + saturation_mae * 0.20
    lighting = metrics["lighting"]
    transmission_mae = lighting["decomposition"]["transmissionResidual"][
        "faceOver12px"
    ]["meanAbsoluteError8Bit"]
    emission_mae = lighting["decomposition"]["emissionResidual"][
        "faceOver12px"
    ]["meanAbsoluteError8Bit"]
    black_mae = lighting["black"]["faceOver12px"]["meanAbsoluteError8Bit"]
    white_mae = lighting["white"]["faceOver12px"]["meanAbsoluteError8Bit"]
    components = {
        "paletteTransferObjective8Bit": color_mae,
        "paletteMeanResponseMae8Bit": response_mae,
        "paletteMeanLuminanceMae8Bit": luminance_mae,
        "paletteMeanSaturationMae8Bit": saturation_mae,
        "paletteWorstResponseMae8Bit": worst_response_mae,
        "paletteWorstLuminanceMae8Bit": worst_luminance_mae,
        "paletteWorstSaturationMae8Bit": worst_saturation_mae,
        "solidTransmissionFaceMae8Bit": transmission_mae,
        "solidEmissionFaceMae8Bit": emission_mae,
        "blackFaceMae8Bit": black_mae,
        "whiteFaceMae8Bit": white_mae,
    }
    # Patch colors and solid transmission are primary. Black emission guards
    # tint/opacity fits from matching white solely by adding a constant wash.
    score = (
        color_mae * 0.30
        + worst_response_mae * 0.075
        + worst_luminance_mae * 0.05
        + worst_saturation_mae * 0.025
        + transmission_mae * 0.25
        + emission_mae * 0.15
        + black_mae * 0.075
        + white_mae * 0.075
    )
    return score, components


def _validate_color_coverage(metrics: dict, scene: dict) -> None:
    color_spec = next(
        probe["background"] for probe in scene["probes"] if probe["id"] == "B"
    )
    declared_symbols = set(
        color_spec["palette"] if "palette" in color_spec else "RGBW"
    )
    missing_symbols = declared_symbols - set(metrics["color"])
    if missing_symbols:
        raise ValueError(
            f"color objective is missing declared hues: {sorted(missing_symbols)}"
        )


def _crop(image: Image.Image, scene: dict) -> Image.Image:
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


def _atlas(reference_dir: Path, rows: list[dict], scene: dict, output: Path, title: str) -> None:
    winners = rows[:4]
    columns = [("APPLE GROUND TRUTH", reference_dir)] + [
        (row["id"], Path(row["candidateDir"])) for row in winners
    ]
    probes = (("B", "SATURATED PATCHES"), ("C", "BLACK"), ("D", "WHITE"))
    sample = _crop(Image.open(reference_dir / "B.png").convert("RGB"), scene)
    cell_width, cell_height = sample.size
    header = 108
    label_height = 30
    result = Image.new(
        "RGB",
        (cell_width * len(columns), header + len(probes) * 2 * (cell_height + label_height)),
        (25, 27, 31),
    )
    draw = ImageDraw.Draw(result)
    draw.text((16, 10), title, font=_font(22), fill="white")
    draw.text(
        (16, 44),
        "APPLE LEFT · ranked by patches + solid transmission/emission · FROST 0",
        font=_font(15),
        fill=(205, 211, 220),
    )
    for column, (label, _) in enumerate(columns):
        draw.text((column * cell_width + 10, 78), label, font=_font(13), fill="white")
    top = header
    for probe, probe_label in probes:
        reference = np.asarray(
            _crop(Image.open(reference_dir / f"{probe}.png").convert("RGB"), scene),
            dtype=np.float32,
        )
        for residual in (False, True):
            row_label = f"{probe_label} · {'SIGNED RESIDUAL ×4' if residual else 'CAPTURE'}"
            draw.text((10, top + 6), row_label, font=_font(14), fill="white")
            for column, (_, directory) in enumerate(columns):
                image = _crop(Image.open(directory / f"{probe}.png").convert("RGB"), scene)
                if residual:
                    if column == 0:
                        image = Image.new("RGB", image.size, (128, 128, 128))
                    else:
                        candidate = np.asarray(image, dtype=np.float32)
                        signed = np.clip((candidate - reference) * 4 + 128, 0, 255)
                        image = Image.fromarray(signed.astype(np.uint8))
                result.paste(image, (column * cell_width, top + label_height))
            top += cell_height + label_height
    output.parent.mkdir(parents=True, exist_ok=True)
    result.save(output)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scene", type=Path, required=True)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--base-settings", type=Path, required=True)
    parser.add_argument("--axis", required=True)
    parser.add_argument("--values", required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--title", required=True)
    parser.add_argument(
        "--objective-symbols",
        help="Optional palette symbols used for ranking; remaining symbols are reported as a holdout.",
    )
    parser.add_argument("--skip-capture", action="store_true")
    args = parser.parse_args()

    validate_reference_for_scene(args.reference, args.scene)
    raw_scene = json.loads(args.scene.read_text())
    base = json.loads(args.base_settings.read_text())
    scene = apply_settings_geometry(raw_scene, base)
    # Keep samples away from tile transitions while ensuring every declared
    # hue is represented inside the material face. The former 18px inset
    # silently omitted cyan and yellow from the dark color-card objective.
    color_probe = next(
        probe for probe in scene["probes"] if probe["id"] == "B"
    )
    color_probe["background"]["sampleInset"] = min(
        float(color_probe["background"].get("sampleInset", 0)), 6.0
    )
    configs = args.out / "configs"
    candidates = args.out / "candidates"
    configs.mkdir(parents=True, exist_ok=True)
    candidates.mkdir(parents=True, exist_ok=True)
    rows = []
    objective_symbols = set(args.objective_symbols) if args.objective_symbols else None
    for index, value in enumerate(_values(args.values), start=1):
        identifier = f"{args.axis}-{_slug(value)}"
        config = dict(base)
        if args.axis == "tintLuminance":
            config.update(
                {"tintRed": value, "tintGreen": value, "tintBlue": value}
            )
        elif args.axis == "neutralOpacityAt32":
            # Preserve the measured ~32/255 black emission while changing
            # backdrop transmission: tintRGB * tintAlpha remains constant.
            neutral = 32.0 / max(value, 0.001)
            config.update(
                {
                    "tintAlpha": value,
                    "tintRed": neutral,
                    "tintGreen": neutral,
                    "tintBlue": neutral,
                }
            )
        else:
            config[args.axis] = value
        config_path = configs / f"{identifier}.json"
        candidate_dir = candidates / identifier
        config_path.write_text(json.dumps(config, indent=2) + "\n")
        if not args.skip_capture:
            env = os.environ | {
                "CAPTURE_PROBES": "A B C D",
                "SETTINGS_FILE": str(config_path.resolve()),
                "SCENE_FILE": str(args.scene.resolve()),
                "CANDIDATE_OUT": str(candidate_dir.resolve()),
            }
            print(f"[{index}/{len(_values(args.values))}] {identifier}", flush=True)
            subprocess.run(
                ["bash", "flutter/host_capture.sh"],
                cwd=ROOT,
                env=env,
                check=True,
                stdout=subprocess.DEVNULL,
            )
        metrics = measure(args.reference, candidate_dir, scene)
        _validate_color_coverage(metrics, scene)
        score, components = _objective(metrics, objective_symbols)
        all_symbols = set(metrics["color"])
        holdout_symbols = all_symbols - (objective_symbols or all_symbols)
        holdout = None
        if holdout_symbols:
            holdout_score, holdout_components = _objective(metrics, holdout_symbols)
            holdout = {
                "symbols": sorted(holdout_symbols),
                "objective": holdout_score,
                "components": holdout_components,
            }
        rows.append(
            {
                "id": identifier,
                "axis": args.axis,
                "value": value,
                "objective": score,
                "components": components,
                "objectiveSymbols": sorted(objective_symbols) if objective_symbols else sorted(all_symbols),
                "holdout": holdout,
                "candidateDir": str(candidate_dir.resolve()),
            }
        )
    rows.sort(key=lambda row: row["objective"])
    summary = {
        "schemaVersion": 1,
        "capturePlatform": "macos-host-golden-metal",
        "probes": ["A", "B", "C", "D"],
        "frostPolicy": "fixed-at-base-settings",
        "fixedFrost": base.get("frost", 0),
        "axis": args.axis,
        "objectiveSymbols": sorted(objective_symbols) if objective_symbols else None,
        "candidates": rows,
    }
    (args.out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    _atlas(args.reference, rows, scene, args.out / "comparison-grid.png", args.title)
    print(json.dumps(rows, indent=2))


if __name__ == "__main__":
    main()
