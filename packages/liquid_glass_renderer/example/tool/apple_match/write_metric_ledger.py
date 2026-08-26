#!/usr/bin/env python3
"""Rebuild the detailed metric ledger from retained attribution captures.

The live attribution scanner keeps compact rows so a scan can be streamed.  A
row's retained A/B/C/D captures are sufficient to recover the complete
scorecard later, without rerunning Flutter or touching any simulator.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "compare"))

from apple_match.cli import load_probes  # noqa: E402
from apple_match.hotloop import load_reference_probes, scene_crop  # noqa: E402
from apple_match.metrics import score_images  # noqa: E402

REFERENCE_SET = "ios27-iphone17pro-light"
SCENES = ("toolbar_capsule", "small_capsule", "large_capsule")


def _fmt(value: float) -> str:
    return f"{value:.6f}"


def collect(out: Path) -> list[dict]:
    result: list[dict] = []
    references: dict[str, dict] = {}
    crops: dict[str, tuple[int, int, int, int]] = {}
    for scene_id in SCENES:
        scene = json.loads((ROOT / "scenes" / f"{scene_id}.json").read_text())
        crop = scene_crop(scene)
        crops[scene_id] = crop
        references[scene_id] = load_reference_probes(
            ROOT / "references" / REFERENCE_SET / scene_id, crop
        )

    for summary_path in sorted(out.glob("material-attribution-*/summary.json")):
        summary = json.loads(summary_path.read_text())
        axis = summary.get("axis")
        if not axis:
            continue
        for row in summary.get("rows", []):
            scene_id = row["scene"]
            capture = Path(row["capture"])
            score = score_images(
                references[scene_id], load_probes(capture, crops[scene_id])
            )
            measurements = score.details
            pixels = measurements["pixelResiduals"]
            record = {
                "scan": summary_path.parent.name,
                "axis": axis,
                "scene": scene_id,
                "value": row["value"],
                "repetition": row["repetition"],
                "capture": str(capture),
                "score": score.score,
                "errors": score.errors,
                "directMae8Bit": measurements["directPixelMeanAbsoluteError8Bit"],
                "stageScores": measurements["stageScores"],
                "luminance": {
                    "blackResponseError": measurements["blackResponseError"],
                    "whiteResponseError": measurements["whiteResponseError"],
                    "blackSpecularError": measurements["blackSpecularError"],
                    "meanSignedBlack8Bit": pixels["C"]["glass"]["meanSignedLuminanceError8Bit"],
                    "meanSignedWhite8Bit": pixels["D"]["glass"]["meanSignedLuminanceError8Bit"],
                },
                "refraction": {
                    "flowError": score.errors["flow"],
                    "stageScore": measurements["stageScores"]["refraction"],
                    "boundaryPositionMaePx": measurements[
                        "transmissionBoundaryProfile"
                    ]["positionMeanAbsoluteErrorPixels"],
                    "boundaryTangentMaeRad": measurements[
                        "transmissionBoundaryProfile"
                    ]["tangentMeanAbsoluteErrorRadians"],
                    "boundaryCurvatureMae": measurements[
                        "transmissionBoundaryProfile"
                    ]["curvatureMeanAbsoluteErrorPerPixel"],
                },
                "lighting": {
                    "specularError": score.errors["specular"],
                    "rgbwRimError": measurements["rgbwRimError"],
                    "channelError": score.errors["channel"],
                },
            }
            result.append(record)
    return result


def write_markdown(records: list[dict], path: Path) -> None:
    lines = [
        "# Detailed harness metric ledger",
        "",
        "Generated from retained attribution A/B/C/D captures; no simulator or",
        "Flutter run is required. `score` is the historical weighted score.",
        "`flowError`/`stageScore` are the refraction measurements, and the",
        "luminance fields are independently computed from the black/white probes.",
        "",
        "| scan | scene | value | score | direct MAE8 | shape | combined | flow | blur MTF | tint | highlight | holdout | refraction | black ΔL* | white ΔL* | rim | boundary px | image |",
        "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |",
    ]
    for record in records:
        e = record["errors"]
        s = record["stageScores"]
        l = record["luminance"]
        r = record["refraction"]
        light = record["lighting"]
        scan = record["scan"]
        scene = record["scene"]
        value = str(record["value"]).replace(".", "p")
        image_scan = scan
        image_path = ROOT / "out" / "annotated-comparisons" / "iterations" / image_scan / scene / f"{value}-rep{record['repetition']}.png"
        # The historical non-cutoff CA scan is byte-for-byte duplicated by the
        # retained cutoff scan; point both rows at the single annotated image.
        if not image_path.exists() and scan == "material-attribution-chromaticAberration":
            image_scan = "material-attribution-chromaticAberration-cutoff"
        image = f"out/annotated-comparisons/iterations/{image_scan}/{scene}/{value}-rep{record['repetition']}.png"
        lines.append(
            f"| {scan} | {scene} | {record['value']:g} | {_fmt(record['score'])} | "
            f"{_fmt(record['directMae8Bit'])} | {_fmt(e['shape'])} | {_fmt(e['combined'])} | "
            f"{_fmt(e['flow'])} | {_fmt(s['blurMtf'])} | {_fmt(e['channel'])} | "
            f"{_fmt(e['specular'])} | {_fmt(e['holdout'])} | {_fmt(s['refraction'])} | "
            f"{_fmt(l['meanSignedBlack8Bit'])} | {_fmt(l['meanSignedWhite8Bit'])} | "
            f"{_fmt(light['rgbwRimError'])} | {_fmt(r['boundaryPositionMaePx'])} | "
            f"[annotated]({image}) |"
        )
    path.write_text("\n".join(lines) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=ROOT / "out")
    parser.add_argument("--json", type=Path)
    parser.add_argument("--markdown", type=Path)
    args = parser.parse_args()
    records = collect(args.out)
    json_path = args.json or args.out / "annotated-comparisons" / "iterations" / "METRIC_LEDGER.json"
    markdown_path = args.markdown or args.out / "annotated-comparisons" / "iterations" / "METRIC_LEDGER.md"
    json_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(json.dumps(records, indent=2) + "\n")
    markdown_path.parent.mkdir(parents=True, exist_ok=True)
    write_markdown(records, markdown_path)
    print(f"wrote {len(records)} rows to {json_path} and {markdown_path}")


if __name__ == "__main__":
    main()
