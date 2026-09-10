#!/usr/bin/env python3
"""Fit the attached SDF contour on black/white probes without shadows."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from stage_metrics import luminance, read_rgb, region_masks, residual_stats
from reference_provenance import validate_reference_for_scene


ROOT = Path(__file__).resolve().parent


def _values(raw: str) -> list[float]:
    return [float(value) for value in raw.split(",")]


def _slug(
    strength: float,
    width: float,
    offset: float,
    transmittance: float,
    curvature: float,
    bevel_strength: float,
    bevel_depth: float,
    bevel_offset: float,
    bevel_directionality: float,
    bevel_size_response: float,
    exterior_shadow_size_response: float,
    highlight_wrap: float,
    highlight_width: float,
    highlight_opposite_strength: float,
    highlight: float,
    shadow_alpha: float,
    shadow_offset_y: float,
    shadow_blur: float,
    shadow_spread: float,
) -> str:
    def part(value: float) -> str:
        # Lighting strengths routinely live below 0.001. Three decimals made
        # distinct candidates such as 0.0005 and 0.001 share a directory,
        # silently replacing the first candidate's images before comparison.
        return f"{value:.6f}".rstrip("0").rstrip(".").replace(".", "p")

    return (
        f"s{part(strength)}-w{part(width)}-o{part(offset)}-t{part(transmittance)}-"
        f"c{part(curvature)}-b{part(bevel_strength)}-"
        f"bd{part(bevel_depth)}-bo{part(bevel_offset)}-"
        f"q{part(bevel_directionality)}-bs{part(bevel_size_response)}-"
        f"es{part(exterior_shadow_size_response)}-"
        f"hw{part(highlight_wrap)}-hz{part(highlight_width)}-"
        f"ho{part(highlight_opposite_strength)}-"
        f"h{part(highlight)}-sa{part(shadow_alpha)}-sy{part(shadow_offset_y)}-"
        f"sb{part(shadow_blur)}-ss{part(shadow_spread)}"
    )


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


def _metric(
    reference: dict[str, np.ndarray],
    candidate_dir: Path,
    scene: dict,
    objective_mode: str,
) -> dict:
    candidate = {probe: read_rgb(candidate_dir / f"{probe}.png") for probe in "CD"}
    masks = region_masks(scene)
    values = {}
    for label, probe in (("black", "C"), ("white", "D")):
        delta = candidate[probe] - reference[probe]
        values[label] = {
            region: residual_stats(delta, masks[region])["meanAbsoluteError8Bit"]
            for region in (
                "outerContour0To3px",
                "outside0To3px",
                "innerBevel3To12px",
                "faceOver12px",
            )
        }
        values[label]["topInnerBevel3To12px"] = residual_stats(
            delta,
            masks["innerBevel3To12px"] & masks["topFacing"],
        )["meanAbsoluteError8Bit"]
        values[label]["bottomInnerBevel3To12px"] = residual_stats(
            delta,
            masks["innerBevel3To12px"] & masks["bottomFacing"],
        )["meanAbsoluteError8Bit"]
        values[label]["topOuterContour0To3px"] = residual_stats(
            delta,
            masks["outerContour0To3px"] & masks["topFacing"],
        )["meanAbsoluteError8Bit"]
        values[label]["bottomOuterContour0To3px"] = residual_stats(
            delta,
            masks["outerContour0To3px"] & masks["bottomFacing"],
        )["meanAbsoluteError8Bit"]
        values[label]["topFaceOver12px"] = residual_stats(
            delta,
            masks["faceOver12px"] & masks["topFacing"],
        )["meanAbsoluteError8Bit"]
        top_face = masks["faceOver12px"] & masks["topFacing"]
        bottom_face = masks["faceOver12px"] & masks["bottomFacing"]
        reference_contrast = (
            float(np.mean(luminance(reference[probe][top_face])))
            - float(np.mean(luminance(reference[probe][bottom_face])))
        ) * 255
        candidate_contrast = (
            float(np.mean(luminance(candidate[probe][top_face])))
            - float(np.mean(luminance(candidate[probe][bottom_face])))
        ) * 255
        values[label]["directionalFaceContrast8Bit"] = {
            "reference": reference_contrast,
            "candidate": candidate_contrast,
            "absoluteError": abs(candidate_contrast - reference_contrast),
        }
    if objective_mode == "highlight":
        # Fit both directional rim lobes on black and white while guarding the
        # broad inner band and matte. This prevents a contour-dominated score
        # from promoting an intense, narrow highlight that looks worse.
        objective = (
            values["black"]["topOuterContour0To3px"] * 0.20
            + values["black"]["bottomOuterContour0To3px"] * 0.20
            + values["white"]["topOuterContour0To3px"] * 0.20
            + values["white"]["bottomOuterContour0To3px"] * 0.20
            + values["black"]["innerBevel3To12px"] * 0.05
            + values["white"]["innerBevel3To12px"] * 0.05
            + values["black"]["faceOver12px"] * 0.05
            + values["white"]["faceOver12px"] * 0.05
        )
    elif objective_mode == "bevel":
        # Rank the complete SDF-following inner band on both backgrounds.
        # This is intentionally sign/side independent: a directional bevel
        # must explain both light-axis extrema rather than overfit the top crop.
        objective = (
            values["black"]["innerBevel3To12px"] * 0.35
            + values["white"]["innerBevel3To12px"] * 0.35
            + values["black"]["outerContour0To3px"] * 0.10
            + values["white"]["outerContour0To3px"] * 0.10
            + values["black"]["faceOver12px"] * 0.05
            + values["white"]["faceOver12px"] * 0.05
        )
    else:
        # White boundary placement is the primary contour fit. Black is a
        # guard against turning the attached contour into a dark silhouette.
        objective = (
            values["white"]["outside0To3px"] * 0.45
            + values["white"]["outerContour0To3px"] * 0.30
            + values["black"]["outside0To3px"] * 0.10
            + values["black"]["outerContour0To3px"] * 0.10
            + values["black"]["faceOver12px"] * 0.025
            + values["white"]["faceOver12px"] * 0.025
        )
    return {"objective": objective, "regions": values}


def _crop(image: Image.Image, scene: dict) -> Image.Image:
    scale = scene["canvas"]["scale"]
    shape = scene["shape"]
    margin = 12 * scale
    box = (
        round(shape["x"] * scale - margin),
        round(shape["y"] * scale - margin),
        round((shape["x"] + shape["width"]) * scale + margin),
        round((shape["y"] + shape["height"]) * scale + margin),
    )
    return image.crop(box)


def _atlas(
    reference_dir: Path,
    rows: list[dict],
    scene: dict,
    output: Path,
    title: str,
    objective_mode: str,
) -> None:
    winners = rows[:4]
    columns = [("APPLE GROUND TRUTH", reference_dir)] + [
        (row["id"], Path(row["candidateDir"])) for row in winners
    ]
    samples = {
        (label, probe): _crop(Image.open(directory / f"{probe}.png").convert("RGB"), scene)
        for label, directory in columns
        for probe in "CD"
    }
    width, height = next(iter(samples.values())).size
    zoom = 2
    cell_width = width * zoom
    cell_height = height * zoom
    header = 92
    row_label = 44
    canvas = Image.new(
        "RGB",
        (cell_width * len(columns), header + (cell_height + row_label) * 3),
        (25, 27, 31),
    )
    draw = ImageDraw.Draw(canvas)
    draw.text((16, 10), title, font=_font(22), fill="white")
    draw.text(
        (16, 45),
        (
            "Ranked by paired directional rim residual with bevel/interior "
            "guards; nearest-neighbor 2× crops"
            if objective_mode == "highlight"
            else (
                "Ranked by complete black/white inner-bevel residual with "
                "contour/interior guards; nearest-neighbor 2× crops"
                if objective_mode == "bevel"
                else "Ranked by white boundary residual with black/interior guards; "
                "nearest-neighbor 2× crops"
            )
        ),
        font=_font(15),
        fill=(205, 211, 220),
    )
    for column, (label, _) in enumerate(columns):
        draw.text((column * cell_width + 12, header - 24), label, font=_font(15), fill=(255, 255, 255))

    reference_white = samples[(columns[0][0], "D")]
    for row_index, (row_label_text, probe) in enumerate(
        (("BLACK", "C"), ("WHITE", "D"), ("WHITE RESIDUAL ×4", "D"))
    ):
        top = header + row_index * (cell_height + row_label)
        draw.text((12, top + 9), row_label_text, font=_font(16), fill=(255, 255, 255))
        image_top = top + row_label
        for column, (label, _) in enumerate(columns):
            sample = samples[(label, probe)]
            if row_index == 2:
                if column == 0:
                    sample = Image.new("RGB", sample.size, (128, 128, 128))
                else:
                    candidate = np.asarray(sample, dtype=np.float32)
                    reference = np.asarray(reference_white, dtype=np.float32)
                    signed = np.clip((candidate - reference) * 4 + 128, 0, 255).astype(np.uint8)
                    sample = Image.fromarray(signed)
            sample = sample.resize((cell_width, cell_height), Image.Resampling.NEAREST)
            canvas.paste(sample, (column * cell_width, image_top))
    output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scene", type=Path, required=True)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--base-settings", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--strengths", default="0.3,0.45,0.6")
    parser.add_argument("--widths", default="0.5")
    parser.add_argument("--offsets", default="0,0.167,0.333,0.5")
    parser.add_argument(
        "--contour-transmittances",
        help="Optional diagnostic sweep of contourTransmittance.",
    )
    parser.add_argument("--curvatures", default="0")
    parser.add_argument(
        "--bevel-strength",
        type=float,
        help="Override bevelShadowStrength while isolating face lighting.",
    )
    parser.add_argument(
        "--bevel-strengths",
        help="Optional diagnostic sweep of bevelShadowStrength.",
    )
    parser.add_argument(
        "--bevel-depths",
        help="Optional diagnostic sweep of bevelShadowDepth.",
    )
    parser.add_argument(
        "--bevel-offsets",
        help="Optional diagnostic sweep of bevelShadowOffset.",
    )
    parser.add_argument(
        "--bevel-directionalities",
        help="Optional diagnostic sweep of bevelShadowDirectionality.",
    )
    parser.add_argument(
        "--bevel-size-responses",
        help="Optional diagnostic sweep of bevelShadowSizeResponse.",
    )
    parser.add_argument(
        "--exterior-shadow-size-responses",
        help="Optional diagnostic sweep of exteriorShadowSizeResponse.",
    )
    parser.add_argument(
        "--highlight-wraps",
        help="Optional diagnostic sweep of highlightWrap.",
    )
    parser.add_argument(
        "--highlight-widths",
        help="Optional diagnostic sweep of highlightWidth.",
    )
    parser.add_argument(
        "--highlight-opposite-strengths",
        help="Optional diagnostic sweep of highlightOppositeStrength.",
    )
    parser.add_argument(
        "--highlights",
        help="Optional diagnostic sweep of highlight strength.",
    )
    parser.add_argument("--shadow-alpha", type=float)
    parser.add_argument("--shadow-alphas")
    parser.add_argument("--shadow-offset-y", type=float)
    parser.add_argument("--shadow-offset-ys")
    parser.add_argument("--shadow-blur", type=float)
    parser.add_argument("--shadow-blurs")
    parser.add_argument("--shadow-spread", type=float)
    parser.add_argument("--shadow-spreads")
    parser.add_argument(
        "--objective-mode",
        choices=("contour", "highlight", "bevel"),
        default="contour",
        help="Rank either attached-contour or directional-face residuals.",
    )
    parser.add_argument("--skip-capture", action="store_true")
    parser.add_argument(
        "--title",
        default="ATTACHED CONTOUR FIT · NO SHADOW",
    )
    args = parser.parse_args()
    validate_reference_for_scene(args.reference, args.scene)

    scene = json.loads(args.scene.read_text())
    base = json.loads(args.base_settings.read_text())
    contour_transmittances = (
        _values(args.contour_transmittances)
        if args.contour_transmittances is not None
        else [float(base.get("contourTransmittance", 0.8))]
    )
    bevel_strengths = (
        _values(args.bevel_strengths)
        if args.bevel_strengths is not None
        else [
            args.bevel_strength
            if args.bevel_strength is not None
            else float(base.get("bevelShadowStrength", 0.0))
        ]
    )
    bevel_depths = (
        _values(args.bevel_depths)
        if args.bevel_depths is not None
        else [float(base.get("bevelShadowDepth", 0.0))]
    )
    bevel_offsets = (
        _values(args.bevel_offsets)
        if args.bevel_offsets is not None
        else [float(base.get("bevelShadowOffset", 0.0))]
    )
    bevel_directionalities = (
        _values(args.bevel_directionalities)
        if args.bevel_directionalities is not None
        else [float(base.get("bevelShadowDirectionality", 0.0))]
    )
    bevel_size_responses = (
        _values(args.bevel_size_responses)
        if args.bevel_size_responses is not None
        else [float(base.get("bevelShadowSizeResponse", 0.0))]
    )
    exterior_shadow_size_responses = (
        _values(args.exterior_shadow_size_responses)
        if args.exterior_shadow_size_responses is not None
        else [float(base.get("exteriorShadowSizeResponse", 0.0))]
    )
    highlight_wraps = (
        _values(args.highlight_wraps)
        if args.highlight_wraps is not None
        else [float(base.get("highlightWrap", 0.25))]
    )
    highlight_widths = (
        _values(args.highlight_widths)
        if args.highlight_widths is not None
        else [float(base.get("highlightWidth", 0.0))]
    )
    highlight_opposite_strengths = (
        _values(args.highlight_opposite_strengths)
        if args.highlight_opposite_strengths is not None
        else [float(base.get("highlightOppositeStrength", 1.0))]
    )
    highlights = (
        _values(args.highlights)
        if args.highlights is not None
        else [float(base.get("highlight", 1.0))]
    )
    shadow_alphas = (
        _values(args.shadow_alphas)
        if args.shadow_alphas is not None
        else [args.shadow_alpha if args.shadow_alpha is not None else float(base.get("shadowAlpha", 0.0))]
    )
    shadow_offset_ys = (
        _values(args.shadow_offset_ys)
        if args.shadow_offset_ys is not None
        else [args.shadow_offset_y if args.shadow_offset_y is not None else float(base.get("shadowOffsetY", 0.0))]
    )
    shadow_blurs = (
        _values(args.shadow_blurs)
        if args.shadow_blurs is not None
        else [args.shadow_blur if args.shadow_blur is not None else float(base.get("shadowBlur", 0.0))]
    )
    shadow_spreads = (
        _values(args.shadow_spreads)
        if args.shadow_spreads is not None
        else [args.shadow_spread if args.shadow_spread is not None else float(base.get("shadowSpread", 0.0))]
    )
    reference = {probe: read_rgb(args.reference / f"{probe}.png") for probe in "CD"}
    configs = args.out / "configs"
    candidates = args.out / "candidates"
    configs.mkdir(parents=True, exist_ok=True)
    candidates.mkdir(parents=True, exist_ok=True)

    rows = []
    combinations = [
        (
            strength,
            width,
            offset,
            transmittance,
            curvature,
            bevel_strength,
            bevel_depth,
            bevel_offset,
            bevel_directionality,
            bevel_size_response,
            exterior_shadow_size_response,
            highlight_wrap,
            highlight_width,
            highlight_opposite_strength,
            highlight,
            shadow_alpha,
            shadow_offset_y,
            shadow_blur,
            shadow_spread,
        )
        for strength in _values(args.strengths)
        for width in _values(args.widths)
        for offset in _values(args.offsets)
        for transmittance in contour_transmittances
        for curvature in _values(args.curvatures)
        for bevel_strength in bevel_strengths
        for bevel_depth in bevel_depths
        for bevel_offset in bevel_offsets
        for bevel_directionality in bevel_directionalities
        for bevel_size_response in bevel_size_responses
        for exterior_shadow_size_response in exterior_shadow_size_responses
        for highlight_wrap in highlight_wraps
        for highlight_width in highlight_widths
        for highlight_opposite_strength in highlight_opposite_strengths
        for highlight in highlights
        for shadow_alpha in shadow_alphas
        for shadow_offset_y in shadow_offset_ys
        for shadow_blur in shadow_blurs
        for shadow_spread in shadow_spreads
    ]
    for index, (
        strength,
        width,
        offset,
        transmittance,
        curvature,
        bevel_strength,
        bevel_depth,
        bevel_offset,
        bevel_directionality,
        bevel_size_response,
        exterior_shadow_size_response,
        highlight_wrap,
        highlight_width,
        highlight_opposite_strength,
        highlight,
        shadow_alpha,
        shadow_offset_y,
        shadow_blur,
        shadow_spread,
    ) in enumerate(
        combinations, start=1
    ):
        identifier = _slug(
            strength,
            width,
            offset,
            transmittance,
            curvature,
            bevel_strength,
            bevel_depth,
            bevel_offset,
            bevel_directionality,
            bevel_size_response,
            exterior_shadow_size_response,
            highlight_wrap,
            highlight_width,
            highlight_opposite_strength,
            highlight,
            shadow_alpha,
            shadow_offset_y,
            shadow_blur,
            shadow_spread,
        )
        config = dict(base)
        config.update(
            {
                "contourStrength": strength,
                "contourWidth": width,
                "contourOffset": offset,
                "contourTransmittance": transmittance,
                "curvatureLighting": curvature,
                "bevelShadowStrength": bevel_strength,
                "bevelShadowDepth": bevel_depth,
                "bevelShadowOffset": bevel_offset,
                "bevelShadowDirectionality": bevel_directionality,
                "bevelShadowSizeResponse": bevel_size_response,
                "exteriorShadowSizeResponse": exterior_shadow_size_response,
                "highlightWrap": highlight_wrap,
                "highlightWidth": highlight_width,
                "highlightOppositeStrength": highlight_opposite_strength,
                "highlight": highlight,
                "shadowAlpha": shadow_alpha,
                "shadowOffsetY": shadow_offset_y,
                "shadowBlur": shadow_blur,
                "shadowSpread": shadow_spread,
                "contactShadowAlpha": 0.0,
            }
        )
        config_path = configs / f"{identifier}.json"
        candidate_dir = candidates / identifier
        config_path.write_text(json.dumps(config, indent=2) + "\n")
        if not args.skip_capture:
            env = os.environ | {
                "CAPTURE_PROBES": "C D",
                "SETTINGS_FILE": str(config_path.resolve()),
                "SCENE_FILE": str(args.scene.resolve()),
                "CANDIDATE_OUT": str(candidate_dir.resolve()),
            }
            print(f"[{index}/{len(combinations)}] {identifier}", flush=True)
            subprocess.run(
                ["bash", "flutter/host_capture.sh"],
                cwd=ROOT,
                env=env,
                check=True,
                stdout=subprocess.DEVNULL,
            )
        result = _metric(reference, candidate_dir, scene, args.objective_mode)
        rows.append(
            {
                "id": identifier,
                "strength": strength,
                "width": width,
                "offset": offset,
                "contourTransmittance": transmittance,
                "curvatureLighting": curvature,
                "bevelShadowStrength": bevel_strength,
                "bevelShadowDepth": bevel_depth,
                "bevelShadowOffset": bevel_offset,
                "bevelShadowDirectionality": bevel_directionality,
                "bevelShadowSizeResponse": bevel_size_response,
                "exteriorShadowSizeResponse": exterior_shadow_size_response,
                "highlightWrap": highlight_wrap,
                "highlightWidth": highlight_width,
                "highlightOppositeStrength": highlight_opposite_strength,
                "highlight": highlight,
                "shadowAlpha": shadow_alpha,
                "shadowOffsetY": shadow_offset_y,
                "shadowBlur": shadow_blur,
                "shadowSpread": shadow_spread,
                "candidateDir": str(candidate_dir.resolve()),
                **result,
            }
        )

    rows.sort(key=lambda row: row["objective"])
    summary = {
        "schemaVersion": 1,
        "capturePlatform": "macos-host-golden-metal",
        "shadows": {
            "contact": "disabled",
            "castAlpha": args.shadow_alpha,
            "castOffsetY": args.shadow_offset_y,
            "castBlur": args.shadow_blur,
            "castSpread": args.shadow_spread,
        },
        "objective": (
            "paired black/white directional rims; bevel and interior guarded"
            if args.objective_mode == "highlight"
            else (
                "complete black/white inner bevel; contour and interior guarded"
                if args.objective_mode == "bevel"
                else "white boundary primary; black boundary and interior guarded"
            )
        ),
        "candidates": rows,
    }
    (args.out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    _atlas(
        args.reference,
        rows,
        scene,
        args.out / "comparison-grid.png",
        args.title,
        args.objective_mode,
    )
    print(json.dumps(rows[:5], indent=2))


if __name__ == "__main__":
    main()
