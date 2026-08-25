#!/usr/bin/env python3
"""Test shared canonical material fields across differently sized controls."""

import argparse
import json
import os
import shutil
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent

import sys

sys.path.insert(0, str(ROOT / "compare"))

from apple_match.hotloop import CaptureSession, Evaluator, coordinate_descent
from apple_match.hotloop.evaluate import (
    load_reference_probes,
    scene_crop,
)
from apple_match.metrics import WEIGHTS, read_rgb, verify_background_registration, write_diagnostics


REFERENCE_SET = "ios27-iphone17pro-light"
TRAINING_SCENES = ("small_capsule", "large_capsule")
HOLDOUT_SCENE = "tab_bar_holdout"


def fit_loss(result):
    errors = result.errors
    return 100.0 * (
        0.4 * min(errors["shape"] / 0.2, 1.0)
        + 0.35 * min(errors["flow"], 1.0)
        + 0.25 * min(errors["combined"] / 0.25, 1.0)
    )


def save_evidence(directory, settings, evaluator, reference):
    directory.mkdir(parents=True, exist_ok=True)
    capture = directory / "capture"
    capture.mkdir(exist_ok=True)
    for probe in "ABCD":
        shutil.copy2(evaluator.capture_dir / f"{probe}.png", capture / f"{probe}.png")
    write_diagnostics(directory, reference, evaluator.last_images)
    (directory / "settings.json").write_text(json.dumps(settings, indent=2) + "\n")
    (directory / "scorecard.json").write_text(
        json.dumps(
            {
                "score": evaluator.last_result.score,
                "fitLoss": fit_loss(evaluator.last_result),
                "errors": evaluator.last_result.errors,
                "measurements": evaluator.last_result.details,
                "weights": WEIGHTS,
                "settings": settings,
                "reloadModes": evaluator.last_modes,
                "evaluationSeconds": evaluator.last_seconds,
            },
            indent=2,
        )
        + "\n"
    )


def axes_for(scene, quick=False):
    shape = scene["shape"]
    width = float(shape["width"])
    height = float(shape["height"])
    radius = float(shape["cornerRadius"])
    if quick:
        # A bounded smoke fit for pinned-device CI and handoff validation.
        # It still exercises the shared-vector constraint while avoiding the
        # full coordinate-descent neighborhood used for a final fit.
        return {
            "shapeWidth": [width],
            "shapeHeight": [height],
            "shapeOffsetX": [0.0],
            "shapeOffsetY": [0.0],
            "cornerRadius": [radius],
        }
    return {
        "shapeWidth": [width - 4, width - 1.333, width, width + 2],
        "shapeHeight": [
            height - 10,
            height - 7,
            height - 4,
            height,
        ],
        "shapeOffsetX": [0.0, 0.667, 1.333, 2.0],
        "shapeOffsetY": [0.0, 1.333, 2.667, 4.0],
        "cornerRadius": [
            radius - 8,
            radius - 6,
            radius - 4,
            radius - 2,
            radius,
        ],
    }


def run_scene(*, scene_id, base, args, out, fit):
    scene_path = ROOT / "scenes" / f"{scene_id}.json"
    scene = json.loads(scene_path.read_text())
    crop = scene_crop(scene)
    reference_dir = ROOT / "references" / REFERENCE_SET / scene_id
    reference = load_reference_probes(reference_dir, crop)
    shape = scene["shape"]
    initial = {
        **base,
        "shapeWidth": float(shape["width"]),
        "shapeHeight": float(shape["height"]),
        "shapeOffsetX": 0.0,
        "shapeOffsetY": 0.0,
        "cornerRadius": float(shape["cornerRadius"]),
    }
    env = os.environ.copy()
    env["PATH"] = f"{ROOT / 'compat/bin'}:{env['PATH']}"
    scene_out = out / scene_id
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
        if fit:
            def shape_loss(params):
                evaluator.evaluate(params)
                # Keep the geometry objective continuous above the scorecard's
                # normalization threshold.  The previous clamp made every
                # starting control whose shape error exceeded .2 have the
                # same loss, preventing coordinate descent from reaching the
                # measured subpixel/size basin.
                return 100.0 * evaluator.last_result.errors["shape"]

            geometry = coordinate_descent(
                shape_loss,
                initial,
                axes_for(scene, args.quick),
                max_iters=args.max_iters,
                min_improvement=0.02,
            )
            best_params = geometry["bestParams"]
            evaluator.evaluate(best_params)
            save_evidence(
                scene_out / "stages/geometry/best",
                best_params,
                evaluator,
                reference,
            )

            def optics_loss(params):
                evaluator.evaluate(params)
                errors = evaluator.last_result.errors
                return 100.0 * (
                    0.6 * min(errors["flow"], 1.0)
                    + 0.4 * min(errors["combined"] / 0.25, 1.0)
                )

            optics = coordinate_descent(
                optics_loss,
                best_params,
                {
                    "thickness": [best_params["thickness"]]
                    if args.quick
                    else [2.0, 4.0, 6.0, 8.0, 10.0, 12.0, 16.0]
                },
                max_iters=args.max_iters,
                min_improvement=0.02,
            )
            best_params = optics["bestParams"]
            evaluator.evaluate(best_params)
            save_evidence(
                scene_out / "stages/thickness/best",
                best_params,
                evaluator,
                reference,
            )
        else:
            evaluator.evaluate(initial)
            best_params = initial
        save_evidence(scene_out / "final", best_params, evaluator, reference)
        registration = verify_background_registration(
            read_rgb(reference_dir / "A.png"),
            read_rgb(scene_out / "final/capture/A.png"),
            crop,
        )
        card_path = scene_out / "final/scorecard.json"
        card = json.loads(card_path.read_text())
        card["registration"] = registration
        card_path.write_text(json.dumps(card, indent=2) + "\n")
        return card


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--udid", default=os.environ.get("IOS_27_UDID"))
    parser.add_argument(
        "--flutter-bin",
        default=os.environ.get(
            "FLUTTER_BIN", str(Path.home() / "fvm/versions/3.47.1/bin/flutter")
        ),
    )
    parser.add_argument(
        "--settings",
        type=Path,
        default=ROOT / "settings/baseline.json",
    )
    parser.add_argument(
        "--toolbar-card",
        type=Path,
        default=ROOT / "out/redesign-refraction/stages/refraction/best/scorecard.json",
        help="Toolbar scorecard used only for the relative comparability gate.",
    )
    parser.add_argument("--out", type=Path, default=ROOT / "out/generalization")
    parser.add_argument("--holdout-card", type=Path)
    parser.add_argument("--max-iters", type=int, default=2)
    parser.add_argument(
        "--quick",
        action="store_true",
        help="Run one pinned smoke evaluation per geometry scene.",
    )
    args = parser.parse_args()
    if not args.udid:
        parser.error("--udid or IOS_27_UDID is required")

    base = json.loads(args.settings.resolve().read_text())
    shared = {
        key: base[key]
        for key in (
            "shapeProfile",
            "edgeRefraction",
            "refractionSpread",
            "frost",
            "tintRed",
            "tintGreen",
            "tintBlue",
            "tintAlpha",
            "saturation",
            "transmissionGamma",
            "vibrancy",
            "chromaticAberration",
            "highlight",
            "contourStrength",
            "contourWidth",
        )
    }
    out = args.out.resolve()
    shutil.rmtree(out, ignore_errors=True)
    results = {}
    for scene_id in TRAINING_SCENES:
        results[scene_id] = run_scene(
            scene_id=scene_id,
            base=base,
            args=args,
            out=out,
            fit=True,
        )
        for key, value in shared.items():
            if results[scene_id]["settings"][key] != value:
                raise RuntimeError(f"frozen shared parameter changed: {key}")
    if args.holdout_card:
        results[HOLDOUT_SCENE] = json.loads(
            args.holdout_card.resolve().read_text()
        )
    else:
        results[HOLDOUT_SCENE] = run_scene(
            scene_id=HOLDOUT_SCENE,
            base=base,
            args=args,
            out=out,
            fit=False,
        )

    toolbar_card = json.loads(args.toolbar_card.resolve().read_text())
    toolbar_settings = toolbar_card.get("settings", {})
    points = [
        (
            float(toolbar_settings.get("shapeHeight", 94.0)),
            float(toolbar_settings.get("thickness", 12.0)),
        ),
        *[
            (
                results[scene_id]["settings"]["shapeHeight"],
                results[scene_id]["settings"]["thickness"],
            )
            for scene_id in TRAINING_SCENES
        ],
    ]
    heights = np.asarray([point[0] for point in points])
    thicknesses = np.asarray([point[1] for point in points])
    slope, intercept = np.polyfit(heights, thicknesses, 1)
    residual = float(
        np.sqrt(np.mean((thicknesses - (slope * heights + intercept)) ** 2))
    )
    comparable = all(
        results[scene_id]["errors"]["flow"] <= toolbar_card["errors"]["flow"] * 1.25
        and results[scene_id]["errors"]["shape"] <= toolbar_card["errors"]["shape"] * 1.25
        and results[scene_id]["errors"]["combined"]
        <= toolbar_card["errors"]["combined"] * 1.25
        for scene_id in TRAINING_SCENES
    )
    unique_thicknesses = sorted(set(float(value) for value in thicknesses))
    scaling = (
        "discrete"
        if len(unique_thicknesses) < len(points) or residual > 0.75
        else "approximatelyLinear"
    )
    summary = {
        "sharedFrozenSettings": shared,
        "toolbar": {
            "score": toolbar_card["score"],
            "errors": toolbar_card["errors"],
            "height": float(toolbar_settings.get("shapeHeight", 94.0)),
            "thickness": float(toolbar_settings.get("thickness", 12.0)),
        },
        "controls": {
            scene_id: {
                "score": results[scene_id]["score"],
                "fitLoss": results[scene_id]["fitLoss"],
                "errors": results[scene_id]["errors"],
                "height": results[scene_id]["settings"]["shapeHeight"],
                "thickness": results[scene_id]["settings"]["thickness"],
                "evidence": str((out / scene_id / "final").resolve()),
            }
            for scene_id in TRAINING_SCENES
        },
        "tabBarHoldout": {
            "score": results[HOLDOUT_SCENE]["score"],
            "errors": results[HOLDOUT_SCENE]["errors"],
            "evidence": str(
                (
                    args.holdout_card.resolve().parent
                    if args.holdout_card
                    else out / HOLDOUT_SCENE / "final"
                ).resolve()
            ),
            "optimized": False,
        },
        "frozenRiGeneralizes": comparable,
        "thicknessScaling": {
            "classification": scaling,
            "linearSlope": float(slope),
            "linearIntercept": float(intercept),
            "rmse": residual,
            "points": [
                {"height": float(height), "thickness": float(thickness)}
                for height, thickness in points
            ],
        },
        "proposalIfRejected": None
        if comparable
        else {
            "status": "requires user sign-off; not implemented",
            "change": (
                "Add a shared normalized SDF-distance remap profile with "
                "innerRefractionHeight and innerRefractionAmount controls."
            ),
        },
    }
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
