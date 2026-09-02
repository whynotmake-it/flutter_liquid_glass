#!/usr/bin/env python3
"""Probe shared profile reach with the already-permitted thickness scaling.

This is a read-only fitting experiment.  ``refractionSpread`` is shared across
all scenes; thickness is selected independently for each geometry, matching
the frozen-vector generalization contract.  Every candidate capture is copied
to a unique directory so the evidence cannot be confused with the next row.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "compare"))

from apple_match.hotloop import (  # noqa: E402
    CaptureSession,
    Evaluator,
    load_reference_probes,
    scene_crop,
)
from apple_match.metrics import write_diagnostics  # noqa: E402

REFERENCE_SET = "ios27-iphone17pro-ground-truth-v2/slider-000"
SCENES = ("toolbar_capsule", "small_capsule", "large_capsule")
DEFAULT_SPREADS = (0.0, 0.25, 0.5, 0.75, 1.0)
DEFAULT_THICKNESSES = (2.0, 4.0, 6.0, 8.0, 10.0, 12.0, 16.0)
GEOMETRY_KEYS = (
    "shapeWidth",
    "shapeHeight",
    "shapeOffsetX",
    "shapeOffsetY",
    "cornerRadius",
    "shapeProfile",
    "thickness",
)


def load_card(path: Path) -> dict:
    value = json.loads(path.read_text())
    return value.get("settings", value)


def candidate_settings(toolbar: dict, geometry: dict, spread: float, thickness: float) -> dict:
    settings = dict(toolbar)
    for key in GEOMETRY_KEYS:
        settings[key] = geometry[key]
    settings["thickness"] = thickness
    settings["refractionSpread"] = spread
    return settings


def optics_loss(errors: dict) -> float:
    return 0.6 * min(float(errors["flow"]), 1.0) + 0.4 * min(
        float(errors["combined"]) / 0.25, 1.0
    )


def format_value(value: float) -> str:
    return f"{value:g}".replace("-", "m").replace(".", "p")


def copy_capture(evaluator: Evaluator, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    for probe in "ABCD":
        shutil.copy2(evaluator.capture_dir / f"{probe}.png", destination / f"{probe}.png")


def evaluate_scene(
    *,
    scene_id: str,
    toolbar: dict,
    geometry: dict,
    spreads: list[float],
    thicknesses: list[float],
    repetitions: int,
    args: argparse.Namespace,
    out: Path,
) -> list[dict]:
    scene_path = ROOT / "scenes" / f"{scene_id}.json"
    scene = json.loads(scene_path.read_text())
    crop = scene_crop(scene)
    reference_dir = ROOT / "references" / REFERENCE_SET / scene_id
    reference = load_reference_probes(reference_dir, crop)
    scene_out = out / scene_id
    env = os.environ.copy()
    env["PATH"] = f"{ROOT / 'compat/bin'}:{env['PATH']}"
    rows: list[dict] = []
    with CaptureSession(
        udid=args.udid,
        flutter_bin=args.flutter_bin,
        flutter_project=ROOT / "flutter",
        scene_path=scene_path,
        work_dir=scene_out / "session",
        env=env,
    ) as session:
        evaluator = Evaluator(
            session=session,
            reference=reference,
            crop=crop,
            capture_dir=scene_out / "live",
        )
        print(
            f"COUPLED_SCENE_READY scene={scene_id} "
            f"startupSeconds={session.startup_seconds:.2f}",
            flush=True,
        )
        for spread in spreads:
            for thickness in thicknesses:
                for repetition in range(1, repetitions + 1):
                    settings = candidate_settings(toolbar, geometry, spread, thickness)
                    evaluator.evaluate(settings)
                    result = evaluator.last_result
                    capture_dir = (
                        scene_out
                        / "candidates"
                        / f"spread-{format_value(spread)}"
                        / f"thickness-{format_value(thickness)}"
                        / f"rep-{repetition}"
                    )
                    copy_capture(evaluator, capture_dir)
                    write_diagnostics(capture_dir, reference, evaluator.last_images)
                    row = {
                        "scene": scene_id,
                        "spread": spread,
                        "thickness": thickness,
                        "repetition": repetition,
                        "score": result.score,
                        "fitLoss": optics_loss(result.errors),
                        "errors": result.errors,
                        "directMae8Bit": result.details[
                            "directPixelMeanAbsoluteError8Bit"
                        ],
                        "capture": str(capture_dir.resolve()),
                    }
                    rows.append(row)
                    print(
                        f"COUPLED scene={scene_id} spread={spread:g} "
                        f"thickness={thickness:g} rep={repetition} "
                        f"score={result.score:.4f} "
                        f"combined={result.errors['combined']:.6f} "
                        f"flow={result.errors['flow']:.6f}",
                        flush=True,
                    )
    return rows


def median(values: list[float]) -> float:
    ordered = sorted(float(value) for value in values)
    middle = len(ordered) // 2
    if len(ordered) % 2:
        return ordered[middle]
    return (ordered[middle - 1] + ordered[middle]) / 2.0


def summarize(rows: list[dict], spreads: list[float], thicknesses: list[float]) -> dict:
    grouped: dict[tuple[str, float, float], list[dict]] = {}
    for row in rows:
        key = (row["scene"], float(row["spread"]), float(row["thickness"]))
        grouped.setdefault(key, []).append(row)

    candidates = {}
    for scene_id in SCENES:
        for spread in spreads:
            options = []
            for thickness in thicknesses:
                values = grouped[(scene_id, spread, thickness)]
                errors = {
                    key: median([value["errors"][key] for value in values])
                    for key in ("shape", "combined", "flow")
                }
                options.append(
                    {
                        "thickness": thickness,
                        "scoreMedian": median([value["score"] for value in values]),
                        "fitLossMedian": median([value["fitLoss"] for value in values]),
                        "directMae8BitMedian": median(
                            [value["directMae8Bit"] for value in values]
                        ),
                        "errorsMedian": errors,
                        "rows": values,
                    }
                )
            best = min(options, key=lambda option: option["fitLossMedian"])
            candidates[f"{scene_id}|spread={spread:g}"] = {
                "scene": scene_id,
                "spread": spread,
                "best": best,
                "allThicknesses": options,
            }

    by_spread = {}
    for spread in spreads:
        selected = {
            scene_id: candidates[f"{scene_id}|spread={spread:g}"]["best"]
            for scene_id in SCENES
        }
        toolbar = selected["toolbar_capsule"]
        small = selected["small_capsule"]
        large = selected["large_capsule"]
        toolbar_error = toolbar["errorsMedian"]["combined"]
        by_spread[str(spread)] = {
            "toolbar": toolbar,
            "small_capsule": small,
            "large_capsule": large,
            "smallCombinedRatioToToolbar": small["errorsMedian"]["combined"]
            / max(toolbar_error, 1e-9),
            "largeCombinedRatioToToolbar": large["errorsMedian"]["combined"]
            / max(toolbar_error, 1e-9),
            "smallCombinedWithin125x": small["errorsMedian"]["combined"]
            <= toolbar_error * 1.25,
            "smallScoreAtLeastHistorical": small["scoreMedian"] >= 86.3452,
            "toolbarWithinFivePercentOfBaseline": toolbar["scoreMedian"] >= 91.7814 * 0.95,
            "largeAtLeastHistorical": large["scoreMedian"] >= 80.6343,
        }
    return {
        "schemaVersion": 1,
        "evidenceRole": "coupled-shared-refraction-spread-thickness-scan",
        "spreads": spreads,
        "thicknesses": thicknesses,
        "selectedBySpread": by_spread,
        "candidateSelections": candidates,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--udid", default=os.environ.get("IOS_27_UDID"))
    parser.add_argument(
        "--flutter-bin",
        default=os.environ.get(
            "FLUTTER_BIN", str(Path.home() / "fvm/versions/3.47.1/bin/flutter")
        ),
    )
    parser.add_argument(
        "--toolbar-card",
        type=Path,
        default=ROOT / "out/metric-ab-audit/toolbar/scorecard.json",
    )
    parser.add_argument(
        "--small-card",
        type=Path,
        default=ROOT / "out/generalization-toolbar-vector/small_capsule/final/scorecard.json",
    )
    parser.add_argument(
        "--large-card",
        type=Path,
        default=ROOT / "out/generalization-toolbar-vector/large_capsule/final/scorecard.json",
    )
    parser.add_argument("--out", type=Path, default=ROOT / "out/coupled-spread-scan")
    parser.add_argument("--repetitions", type=int, default=1)
    parser.add_argument("--spreads", type=float, nargs="+", default=list(DEFAULT_SPREADS))
    parser.add_argument(
        "--thicknesses", type=float, nargs="+", default=list(DEFAULT_THICKNESSES)
    )
    args = parser.parse_args()
    if not args.udid:
        parser.error("--udid or IOS_27_UDID is required")
    if args.repetitions < 1:
        parser.error("--repetitions must be at least 1")
    if any(not 0.0 <= value <= 1.0 for value in args.spreads):
        parser.error("--spreads must be between 0 and 1")
    if any(not math.isfinite(value) or value <= 0.0 for value in args.thicknesses):
        parser.error("--thicknesses must be positive finite values")

    toolbar = load_card(args.toolbar_card.resolve())
    geometry = {
        "toolbar_capsule": toolbar,
        "small_capsule": load_card(args.small_card.resolve()),
        "large_capsule": load_card(args.large_card.resolve()),
    }
    spreads = list(dict.fromkeys(args.spreads))
    thicknesses = list(dict.fromkeys(args.thicknesses))
    out = args.out.resolve()
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True)
    rows = []
    for scene_id in SCENES:
        rows.extend(
            evaluate_scene(
                scene_id=scene_id,
                toolbar=toolbar,
                geometry=geometry[scene_id],
                spreads=spreads,
                thicknesses=thicknesses,
                repetitions=args.repetitions,
                args=args,
                out=out,
            )
        )
    summary = summarize(rows, spreads, thicknesses)
    summary["repetitions"] = args.repetitions
    summary["geometrySource"] = {
        scene_id: str(path.resolve())
        for scene_id, path in {
            "toolbar_capsule": args.toolbar_card,
            "small_capsule": args.small_card,
            "large_capsule": args.large_card,
        }.items()
    }
    summary["rows"] = rows
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
