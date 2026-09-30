#!/usr/bin/env python3
"""Rim/glint/border scorecard and annotated before/after composites.

Scores candidates against an Apple reference using only the solid black (C)
and white (D) probes, where refraction and blur cannot move content. That
keeps the lighting and color verdict independent of blur, which Apple mixes
per clearness level and the Flutter renderer does not attempt to reproduce.

The composite shows full crops of C, D and the RGBW grid (A) followed by 5x
nearest-neighbour detail crops of the top glint, the end-cap border and the
45-degree corner for every probe, so judgments never rest on full frames.

Usage:
  compare/.venv/bin/python rim_report.py \
    --reference references/.../toolbar_capsule \
    --candidate before=out/.../before --candidate after=out/.../after \
    --title "Toolbar, light" --output out/rim/toolbar-light.png
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent / "compare"))

from apple_match import rim  # noqa: E402
from apple_match.metrics import read_rgb  # noqa: E402

ZOOM = 5
DETAIL = (36, 24)  # physical pixels before zoom
COMPACT_DETAIL = (30, 16)


def _font(size: int) -> ImageFont.ImageFont:
    for path in (
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    ):
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            pass
    return ImageFont.load_default()


def _load(directory: Path, probe: str) -> Image.Image:
    return Image.open(directory / f"{probe}.png").convert("RGB")


def _detail_points(mask: np.ndarray) -> dict[str, tuple[int, int]]:
    ys, xs = np.where(mask)
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    cy = (y0 + y1) // 2
    radius = min((x1 - x0), (y1 - y0)) / 2
    corner = (
        int(round(x0 + radius - radius * 0.7071)),
        int(round(y0 + radius - radius * 0.7071)),
    )
    return {
        "top glint": ((x0 + x1) // 2, int(y0)),
        "end-cap border": (int(x0), int(cy)),
        "45deg corner": corner,
    }


def _crop(
    image: Image.Image,
    center: tuple[int, int],
    detail: tuple[int, int] = DETAIL,
) -> Image.Image:
    w, h = detail
    x, y = center
    box = (x - w // 2, y - h // 2, x + w // 2, y + h // 2)
    return image.crop(box).resize((w * ZOOM, h * ZOOM), Image.NEAREST)


def compose(
    reference: Path,
    candidates: list[tuple[str, Path]],
    title: str,
    subtitle: str,
    output: Path,
    probes: tuple[str, ...] = ("C", "D", "A"),
) -> None:
    ref_black = read_rgb(reference / "C.png")
    ref_white = read_rgb(reference / "D.png")
    mask = rim.silhouette_mask(ref_black, ref_white)
    ys, xs = np.where(mask)
    margin = 30
    box = (
        int(xs.min()) - margin,
        int(ys.min()) - margin,
        int(xs.max()) + margin,
        int(ys.max()) + margin,
    )
    points = _detail_points(mask)
    columns = [("APPLE GROUND TRUTH", reference), *candidates]
    full_w = box[2] - box[0]
    full_h = box[3] - box[1]
    detail_w = DETAIL[0] * ZOOM
    detail_h = DETAIL[1] * ZOOM
    detail_row_w = detail_w * len(points) + 8 * (len(points) - 1)
    column_w = max(full_w // 2, detail_row_w)
    row_full_h = int(full_h * column_w / full_w)
    header = 92
    label_h = 30
    gap = 14
    per_probe = row_full_h + detail_h + label_h + gap * 2
    canvas = Image.new(
        "RGB",
        (column_w * len(columns) + gap * (len(columns) + 1), header + per_probe * len(probes) + gap),
        (28, 30, 34),
    )
    draw = ImageDraw.Draw(canvas)
    draw.text((gap, 8), title, font=_font(22), fill="white")
    draw.text((gap, 40), subtitle, font=_font(14), fill=(206, 211, 219))
    probe_names = {"A": "RGBW grid", "B": "holdout grid", "C": "black", "D": "white"}
    for ci, (label, directory) in enumerate(columns):
        left = gap + ci * (column_w + gap)
        for pi, probe in enumerate(probes):
            top = header + pi * per_probe
            image = _load(directory, probe)
            full = image.crop(box).resize((column_w, row_full_h), Image.LANCZOS)
            canvas.paste(full, (left, top + label_h))
            draw.text(
                (left + 4, top + 6),
                f"{label} | {probe_names.get(probe, probe)}",
                font=_font(15),
                fill=(255, 214, 102) if ci == 0 else "white",
            )
            detail_top = top + label_h + row_full_h + gap
            for di, (name, center) in enumerate(points.items()):
                x = left + di * (detail_w + 8)
                canvas.paste(_crop(image, center), (x, detail_top))
                draw.text((x + 3, detail_top + 2), f"5x {name}", font=_font(11), fill=(255, 64, 160))
    output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output)


def compose_compact(
    reference: Path,
    candidates: list[tuple[str, Path]],
    title: str,
    subtitle: str,
    output: Path,
    probes: tuple[str, ...] = ("C", "D"),
) -> None:
    """Small review JPEG: thumbnails plus 5x crops, one column per source."""
    mask = rim.silhouette_mask(read_rgb(reference / "C.png"), read_rgb(reference / "D.png"))
    ys, xs = np.where(mask)
    margin = 20
    box = (int(xs.min()) - margin, int(ys.min()) - margin, int(xs.max()) + margin, int(ys.max()) + margin)
    points = _detail_points(mask)
    columns = [("APPLE", reference), *candidates]
    cell_w, cell_h = COMPACT_DETAIL[0] * ZOOM, COMPACT_DETAIL[1] * ZOOM
    gap = 6
    label_w = 92
    header = 58
    thumb_h = int((box[3] - box[1]) * cell_w / (box[2] - box[0]))
    rows = [("thumb", probe, None) for probe in probes] + [
        ("crop", probe, name) for probe in probes for name in points
    ]
    height = header + 22 + sum((thumb_h if kind == "thumb" else cell_h) + gap for kind, _, _ in rows)
    width = label_w + len(columns) * (cell_w + gap)
    canvas = Image.new("RGB", (width, height), (28, 30, 34))
    draw = ImageDraw.Draw(canvas)
    draw.text((gap, 4), title, font=_font(16), fill="white")
    draw.text((gap, 26), subtitle, font=_font(11), fill=(206, 211, 219))
    for ci, (label, _) in enumerate(columns):
        draw.text((label_w + ci * (cell_w + gap), header), label, font=_font(13),
                  fill=(255, 214, 102) if ci == 0 else "white")
    names = {"C": "black", "D": "white", "A": "RGBW"}
    top = header + 22
    for kind, probe, name in rows:
        h = thumb_h if kind == "thumb" else cell_h
        draw.text((gap, top + 4), f"{names.get(probe, probe)}", font=_font(11), fill="white")
        draw.text((gap, top + 18), "full" if kind == "thumb" else f"5x {name}", font=_font(10), fill=(255, 64, 160))
        for ci, (_, directory) in enumerate(columns):
            image = _load(directory, probe)
            tile = (
                image.crop(box).resize((cell_w, thumb_h), Image.LANCZOS)
                if kind == "thumb"
                else _crop(image, points[name], COMPACT_DETAIL)
            )
            canvas.paste(tile, (label_w + ci * (cell_w + gap), top))
        top += h + gap
    output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output, quality=82, optimize=True)


def compose_palette(
    reference: Path,
    candidates: list[tuple[str, Path]],
    probes: list[str],
    title: str,
    subtitle: str,
    output: Path,
    face_half_width: int = 60,
    detail: tuple[int, int] = DETAIL,
) -> None:
    """One row per solid probe: face crop plus a 5x glint crop per column."""
    mask = rim.silhouette_mask(read_rgb(reference / "K.png"), read_rgb(reference / "W.png"))
    ys, xs = np.where(mask)
    y0 = int(ys.min())
    cx = (int(xs.min()) + int(xs.max())) // 2
    glint_center = (cx, y0)
    face_box = (cx - face_half_width, y0 - 12, cx + face_half_width, y0 + 48)
    columns = [("APPLE", reference), *candidates]
    cell_w = detail[0] * ZOOM
    face_w = face_box[2] - face_box[0]
    row_h = detail[1] * ZOOM
    gap = 10
    header = 96
    col_w = face_w + cell_w + gap
    canvas = Image.new(
        "RGB",
        (60 + len(columns) * (col_w + gap), header + len(probes) * (row_h + gap) + 30),
        (28, 30, 34),
    )
    draw = ImageDraw.Draw(canvas)
    draw.text((gap, 8), title, font=_font(22), fill="white")
    draw.text((gap, 40), subtitle, font=_font(14), fill=(206, 211, 219))
    for ci, (label, _) in enumerate(columns):
        draw.text((60 + ci * (col_w + gap), header - 4), label, font=_font(15),
                  fill=(255, 214, 102) if ci == 0 else "white")
    for pi, probe in enumerate(probes):
        top = header + 18 + pi * (row_h + gap)
        draw.text((gap, top + row_h // 2 - 8), probe, font=_font(18), fill="white")
        for ci, (_, directory) in enumerate(columns):
            image = _load(directory, probe)
            left = 60 + ci * (col_w + gap)
            face = image.crop(face_box).resize((face_w, row_h), Image.NEAREST)
            canvas.paste(face, (left, top))
            canvas.paste(
                _crop(image, glint_center, detail),
                (left + face_w + gap, top),
            )
    output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output, quality=82, optimize=True)


def score(reference: Path, candidate: Path) -> dict[str, float]:
    ref = rim.rim_table(read_rgb(reference / "C.png"), read_rgb(reference / "D.png"))
    can = rim.rim_table(read_rgb(candidate / "C.png"), read_rgb(candidate / "D.png"))
    return rim.compare_tables(ref, can)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--candidate", action="append", required=True, help="label=dir")
    parser.add_argument("--title", required=True)
    parser.add_argument("--subtitle", default="")
    parser.add_argument("--note", default="", help="extra provenance line under the subtitle")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--probe", action="append", help="probes to show (default C D A)")
    parser.add_argument(
        "--compact",
        action="store_true",
        help="small review image (JPEG when --output ends in .jpg)",
    )
    parser.add_argument(
        "--palette",
        nargs="+",
        help="score isolated solid-color probes (needs K and W) instead of C/D",
    )
    args = parser.parse_args()
    candidates = []
    for item in args.candidate:
        label, _, directory = item.partition("=")
        candidates.append((label, Path(directory)))
    if args.palette:
        def load_all(directory: Path) -> dict[str, np.ndarray]:
            return {p: read_rgb(directory / f"{p}.png") for p in args.palette}

        reference = load_all(args.reference)
        scores = {
            label: rim.palette_errors(reference, load_all(directory))
            for label, directory in candidates
        }
        subtitle = args.subtitle or "  ".join(
            f"{label}: face MAE {s['paletteFaceMae8']:.1f} (worst {s['paletteFaceWorst8']:.1f}), "
            f"glint MAE {s['paletteGlintMae8']:.1f} (worst {s['paletteGlintWorst8']:.1f})"
            for label, s in scores.items()
        )
        if args.note:
            subtitle = f"{subtitle}\n{args.note}"
        compose_palette(
            args.reference,
            candidates,
            args.palette,
            args.title,
            subtitle,
            args.output,
            face_half_width=30 if args.compact else 60,
            detail=COMPACT_DETAIL if args.compact else DETAIL,
        )
        args.output.with_suffix(".json").write_text(json.dumps(scores, indent=2) + "\n")
        print(json.dumps({k: {m: v for m, v in s.items() if m != "probes"} for k, s in scores.items()}, indent=2))
        return
    scores = {label: score(args.reference, directory) for label, directory in candidates}
    subtitle = args.subtitle
    if not subtitle:
        subtitle = "  ".join(
            f"{label}: glint RMS {s['glintShapeRms8']:.1f}, rim E RMS {s['rimEmissionRms8']:.1f}, "
            f"rim T RMS {s['rimTransmittanceRms']:.3f}"
            for label, s in scores.items()
        )
    if args.note:
        subtitle = f"{subtitle}\n{args.note}"
    if args.compact:
        compose_compact(
            args.reference,
            candidates,
            args.title,
            subtitle,
            args.output,
            tuple(args.probe) if args.probe else ("C", "D"),
        )
        args.output.with_suffix(".json").write_text(json.dumps(scores, indent=2) + "\n")
        print(json.dumps(scores, indent=2))
        return
    compose(
        args.reference,
        candidates,
        args.title,
        subtitle,
        args.output,
        tuple(args.probe) if args.probe else ("C", "D", "A"),
    )
    args.output.with_suffix(".json").write_text(json.dumps(scores, indent=2) + "\n")
    print(json.dumps(scores, indent=2))


if __name__ == "__main__":
    main()
