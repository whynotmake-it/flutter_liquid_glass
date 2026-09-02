#!/usr/bin/env python3
"""Coupled host-GPU fit for the four scalar color-transfer controls."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
from pathlib import Path

import cv2
import numpy as np

from solid_color_metrics import measure_solid_palette

ROOT = Path(__file__).resolve().parent


def _objective(metrics: dict) -> float:
    objective = metrics["objective"]
    guards = metrics["guards"]
    # Palette transmission is primary. Luminance/saturation and neutral guards
    # keep the optimizer from fixing one hue by washing out the entire card.
    return (
        objective["paletteMeanFaceMae8Bit"] * 0.45
        + objective["paletteWorstFaceMae8Bit"] * 0.20
        + objective["paletteMeanLuminanceMae8Bit"] * 0.10
        + objective["paletteMeanSaturationMae8Bit"] * 0.10
        + objective["luminanceMeanFaceMae8Bit"] * 0.05
        + guards["blackFaceMae8Bit"] * 0.05
        + guards["whiteFaceMae8Bit"] * 0.05
    )


def _gradient_inner_mae(scene: dict, reference_dir: Path, candidate_dir: Path) -> float:
    """Measure color residual away from the holdout shape's rim."""
    shape = scene["shape"]
    scale = scene["canvas"]["scale"]
    inset = round(10 * scale)
    left = round(shape["x"] * scale) + inset
    top = round(shape["y"] * scale) + inset
    right = round((shape["x"] + shape["width"]) * scale) - inset
    bottom = round((shape["y"] + shape["height"]) * scale) - inset
    errors = []
    for probe in scene["probes"]:
        probe_id = probe["id"]
        reference = cv2.cvtColor(
            cv2.imread(str(reference_dir / f"{probe_id}.png")), cv2.COLOR_BGR2RGB
        ).astype(np.float32)
        candidate = cv2.cvtColor(
            cv2.imread(str(candidate_dir / f"{probe_id}.png")), cv2.COLOR_BGR2RGB
        ).astype(np.float32)
        errors.append(
            float(
                np.mean(
                    np.abs(
                        candidate[top:bottom, left:right]
                        - reference[top:bottom, left:right]
                    )
                )
            )
        )
    return float(np.mean(errors))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scene", type=Path, required=True)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--base-settings", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--max-iters", type=int, default=6)
    parser.add_argument("--learning-rate", type=float, default=0.08)
    parser.add_argument("--perturbation", type=float, default=0.02)
    parser.add_argument("--seed", type=int, default=17)
    parser.add_argument("--holdout-scene", type=Path)
    parser.add_argument("--holdout-reference", type=Path)
    parser.add_argument("--holdout-weight", type=float, default=0.5)
    args = parser.parse_args()
    scene = json.loads(args.scene.read_text())
    holdout_scene = (
        json.loads(args.holdout_scene.read_text()) if args.holdout_scene else None
    )
    if (holdout_scene is None) != (args.holdout_reference is None):
        parser.error("--holdout-scene and --holdout-reference must be provided together")
    base = json.loads(args.base_settings.read_text())
    probes = " ".join(probe["id"] for probe in scene["probes"])
    args.out.mkdir(parents=True, exist_ok=True)
    settings_dir = args.out / "settings"
    settings_dir.mkdir(exist_ok=True)
    evaluations = []
    serial = 0

    bounds = {
        "tintAlpha": (0.20, 0.65),
        "saturation": (0.50, 3.50),
        "transmissionGamma": (0.45, 1.60),
        "vibrancy": (0.0, 0.50),
    }

    def evaluate(params: dict) -> float:
        nonlocal serial
        serial += 1
        identifier = f"eval-{serial:03d}"
        settings = {**base, **{key: float(params[key]) for key in bounds}}
        settings_path = settings_dir / f"{identifier}.json"
        candidate_dir = args.out / identifier
        settings_path.write_text(json.dumps(settings, indent=2) + "\n")
        env = os.environ | {
            "CAPTURE_PROBES": probes,
            "SETTINGS_FILE": str(settings_path.resolve()),
            "SCENE_FILE": str(args.scene.resolve()),
            "CANDIDATE_OUT": str(candidate_dir.resolve()),
        }
        subprocess.run(
            ["bash", "flutter/host_capture.sh"],
            cwd=ROOT,
            env=env,
            check=True,
            stdout=subprocess.DEVNULL,
        )
        metrics = measure_solid_palette(scene, args.reference, candidate_dir)
        score = _objective(metrics)
        holdout_mae = None
        if holdout_scene is not None:
            holdout_dir = args.out / f"{identifier}-holdout"
            holdout_env = os.environ | {
                "CAPTURE_PROBES": " ".join(probe["id"] for probe in holdout_scene["probes"]),
                "SETTINGS_FILE": str(settings_path.resolve()),
                "SCENE_FILE": str(args.holdout_scene.resolve()),
                "CANDIDATE_OUT": str(holdout_dir.resolve()),
            }
            subprocess.run(
                ["bash", "flutter/host_capture.sh"],
                cwd=ROOT,
                env=holdout_env,
                check=True,
                stdout=subprocess.DEVNULL,
            )
            holdout_mae = _gradient_inner_mae(
                holdout_scene, args.holdout_reference, holdout_dir
            )
            score += args.holdout_weight * holdout_mae
        evaluations.append(
            {
                "id": identifier,
                "params": settings,
                "objective": score,
                "metrics": metrics,
                "holdoutInnerMae8Bit": holdout_mae,
                "candidate": str(candidate_dir.resolve()),
            }
        )
        print(f"{identifier}: {score:.4f}", flush=True)
        return score

    # Import after the script's local module path is established.
    import sys

    sys.path.insert(0, str(ROOT / "compare"))
    from apple_match.hotloop.optimize import spsa_descent

    result = spsa_descent(
        evaluate,
        base,
        bounds,
        max_iters=args.max_iters,
        learning_rate=args.learning_rate,
        perturbation=args.perturbation,
        seed=args.seed,
        on_step=lambda row: print(
            f"iteration {row['iteration']}: {'accepted' if row['accepted'] else 'rejected'}",
            flush=True,
        ),
    )
    best = min(evaluations, key=lambda evaluation: evaluation["objective"])
    # The optimizer's internal best loss is the best accepted iterate, while
    # `evaluations` also contains rejected probes. Report the actual minimum
    # evaluation so the summary cannot claim a different objective than the
    # candidate and metrics it points to.
    best_params = {
        key: best["params"][key]
        for key in bounds
    }
    summary = {
        "schemaVersion": 1,
        "scene": scene["id"],
        "optimizer": "spsa",
        "bounds": bounds,
        "bestParams": best_params,
        "bestObjective": best["objective"],
        "bestEvaluation": best,
        "evaluations": evaluations,
        "history": result["history"],
    }
    (args.out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps({"bestParams": result["bestParams"], "bestObjective": result["bestLoss"]}, indent=2))


if __name__ == "__main__":
    main()
