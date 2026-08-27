#!/usr/bin/env python3
"""Measure one shared material axis across the three fitted capsule scenes.

This is an evidence-only probe: geometry and every other material field stay
fixed to the authoritative toolbar vector. Each candidate is copied out of
the persistent session with its diagnostics so a later row cannot overwrite
the evidence used to accept or reject an axis.
"""

from __future__ import annotations

import argparse
import json
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
GEOMETRY_KEYS = (
    "shapeWidth",
    "shapeHeight",
    "shapeOffsetX",
    "shapeOffsetY",
    "cornerRadius",
    "shapeProfile",
    "thickness",
)
AXES = {
    # Include the clear endpoint explicitly: visual inspection can suggest
    # that a small control wants no compositor blur, and the attribution scan
    # must test that hypothesis rather than assuming the toolbar range.
    "frost": (0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0),
    "transmissionGamma": (0.80, 0.85, 0.875, 0.90, 0.925, 0.95, 1.0),
    "edgeRefraction": (0.0, 8.0, 12.0, 18.3, 24.0, 32.0),
    "vibrancy": (0.0, 0.075, 0.15, 0.225, 0.30),
    "tintAlpha": (0.48, 0.505, 0.53, 0.555, 0.58),
    # Zero selects the final shader's one-backdrop-sample path; .005 is the
    # authoritative toolbar/capsule default and must remain in the grid.
    # The upper values test whether the current relative-displacement
    # parameterization is simply too weak to be visually observable.
    "chromaticAberration": (0.0, 0.001, 0.0025, 0.005, 0.01, 0.025, 0.05, 0.1),
}


def load_card(path: Path) -> dict:
    value = json.loads(path.read_text())
    return value.get("settings", value)


def candidate_settings(toolbar: dict, geometry: dict, axis: str, value: float) -> dict:
    settings = dict(toolbar)
    for key in GEOMETRY_KEYS:
        settings[key] = geometry[key]
    settings[axis] = value
    settings["refractionSpread"] = 0.0
    return settings


def format_value(value: float) -> str:
    return f"{value:g}".replace("-", "m").replace(".", "p")


def copy_capture(evaluator: Evaluator, destination: Path, reference: dict) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    for probe in "ABCD":
        shutil.copy2(evaluator.capture_dir / f"{probe}.png", destination / f"{probe}.png")
    write_diagnostics(destination, reference, evaluator.last_images)


def evaluate_scene(
    *,
    scene_id: str,
    toolbar: dict,
    geometry: dict,
    axis: str,
    values: tuple[float, ...],
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
            f"MATERIAL_SCENE_READY scene={scene_id} "
            f"startupSeconds={session.startup_seconds:.2f}",
            flush=True,
        )
        for value in values:
            for repetition in range(1, repetitions + 1):
                settings = candidate_settings(toolbar, geometry, axis, value)
                evaluator.evaluate(settings)
                result = evaluator.last_result
                capture_dir = (
                    scene_out
                    / "candidates"
                    / f"{axis}-{format_value(value)}"
                    / f"rep-{repetition}"
                )
                copy_capture(evaluator, capture_dir, reference)
                rows.append(
                    {
                        "scene": scene_id,
                        "axis": axis,
                        "value": value,
                        "repetition": repetition,
                        "score": result.score,
                        "errors": result.errors,
                        "directMae8Bit": result.details[
                            "directPixelMeanAbsoluteError8Bit"
                        ],
                        "capture": str(capture_dir.resolve()),
                    }
                )
                print(
                    f"MATERIAL scene={scene_id} {axis}={value:g} "
                    f"rep={repetition} score={result.score:.4f} "
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


def summarize(
    rows: list[dict],
    axis: str,
    values: tuple[float, ...],
    repetitions: int,
    baseline_value: float,
) -> dict:
    grouped: dict[tuple[str, float], list[dict]] = {}
    for row in rows:
        grouped.setdefault((row["scene"], float(row["value"])), []).append(row)

    candidates = {}
    for scene_id in SCENES:
        options = []
        for value in values:
            selected = grouped[(scene_id, value)]
            errors = {
                key: median([row["errors"][key] for row in selected])
                for key in ("shape", "combined", "flow", "channel", "specular")
            }
            options.append(
                {
                    "value": value,
                    "scoreMedian": median([row["score"] for row in selected]),
                    "directMae8BitMedian": median([row["directMae8Bit"] for row in selected]),
                    "errorsMedian": errors,
                    "rows": selected,
                }
            )
        candidates[scene_id] = {
            "scene": scene_id,
            "bestCombined": min(options, key=lambda option: option["errorsMedian"]["combined"]),
            "bestFlow": min(options, key=lambda option: option["errorsMedian"]["flow"]),
            "bestScore": max(options, key=lambda option: option["scoreMedian"]),
            "allValues": options,
        }

    baselines = {
        scene_id: next(
            option
            for option in candidates[scene_id]["allValues"]
            if option["value"] == baseline_value
        )
        for scene_id in SCENES
    }
    baseline = next(
        option for option in candidates["toolbar_capsule"]["allValues"]
        if option["value"] == baseline_value
    ) if baseline_value in values else None
    small_baseline = baselines["small_capsule"]
    large_baseline = baselines["large_capsule"]
    small_best = candidates["small_capsule"]["bestCombined"]
    toolbar_best = candidates["toolbar_capsule"]["bestCombined"]
    large_best = candidates["large_capsule"]["bestCombined"]
    baseline_ratio = small_baseline["errorsMedian"]["combined"] / max(
        baseline["errorsMedian"]["combined"], 1e-9
    )
    selected_ratio = small_best["errorsMedian"]["combined"] / max(
        toolbar_best["errorsMedian"]["combined"], 1e-9
    )
    return {
        "schemaVersion": 1,
        "evidenceRole": "shared-material-axis-attribution",
        "axis": axis,
        "values": list(values),
        "repetitions": repetitions,
        "baselineValue": baseline_value,
        "baselineByScene": baselines,
        "candidateSelections": candidates,
        "screening": {
            "smallCombinedReductionAtLeast10Percent": (
                small_best["errorsMedian"]["combined"]
                <= 0.9 * small_baseline["errorsMedian"]["combined"]
            ),
            "smallFlowReductionAtLeast20Percent": (
                small_best["errorsMedian"]["flow"]
                <= 0.8 * small_baseline["errorsMedian"]["flow"]
            ),
            "smallRatioImprovementAtLeast015": (
                selected_ratio <= baseline_ratio - 0.15
            ),
            "toolbarLargeCombinedRegressionAtMost5Percent": all(
                option["errorsMedian"]["combined"] <= 1.05 * baseline_for_scene
                for option, baseline_for_scene in (
                    (toolbar_best, baseline["errorsMedian"]["combined"]),
                    (large_best, large_baseline["errorsMedian"]["combined"]),
                )
            ),
            "baselineSmallToToolbarCombinedRatio": baseline_ratio,
            "selectedSmallToToolbarCombinedRatio": selected_ratio,
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--axis", choices=sorted(AXES), default="frost")
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
    parser.add_argument("--out", type=Path)
    parser.add_argument("--repetitions", type=int, default=1)
    args = parser.parse_args()
    if not args.udid:
        parser.error("--udid or IOS_27_UDID is required")
    if args.repetitions < 1:
        parser.error("--repetitions must be at least 1")
    values = AXES[args.axis]
    toolbar = load_card(args.toolbar_card.resolve())
    geometry = {
        "toolbar_capsule": toolbar,
        "small_capsule": load_card(args.small_card.resolve()),
        "large_capsule": load_card(args.large_card.resolve()),
    }
    out = (args.out or ROOT / "out" / f"material-attribution-{args.axis}").resolve()
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True)
    rows = []
    for scene_id in SCENES:
        rows.extend(
            evaluate_scene(
                scene_id=scene_id,
                toolbar=toolbar,
                geometry=geometry[scene_id],
                axis=args.axis,
                values=values,
                repetitions=args.repetitions,
                args=args,
                out=out,
            )
        )
    baseline_value = float(toolbar[args.axis])
    if baseline_value not in values:
        raise RuntimeError(
            f"authoritative {args.axis}={baseline_value:g} is not in the scan grid"
        )
    summary = summarize(rows, args.axis, values, args.repetitions, baseline_value)
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
