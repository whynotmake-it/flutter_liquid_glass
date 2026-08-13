#!/usr/bin/env python3
"""Resume the Apple-match stages in one persistent Flutter hot-reload session."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import statistics
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
COMPARE = ROOT / "compare"
sys.path.insert(0, str(COMPARE))

from apple_match.hotloop import (  # noqa: E402
    CaptureSession,
    Evaluator,
    coordinate_descent,
    load_reference_probes,
    scene_crop,
)
from apple_match.metrics import (  # noqa: E402
    WEIGHTS,
    read_rgb,
    verify_background_registration,
    write_diagnostics,
)

REFERENCE_SET = "ios27-iphone17pro-light"
RECORDED_BASELINE = ROOT / "out/stages/refinement/candidates/003"

STAGES = {
    "shape": {
        "shapeWidth": [222.0, 223.0, 224.0, 225.0, 226.0],
        "shapeHeight": [92.0, 93.0, 94.0, 95.0, 96.0],
        "shapeOffsetY": [-1.0, 0.0, 1.0],
        "cornerRadius": [45.0, 46.0, 47.0, 48.0],
        "shapeProfile": ["roundedRectangle", "superellipse"],
    },
    "refraction": {
        "thickness": [2.0, 4.0, 6.0, 8.0, 10.0, 12.0],
        "refractiveIndex": [1.03, 1.05, 1.08, 1.10, 1.15],
        "chromaticAberration": [0.0, 0.005, 0.01],
    },
    "blurMtf": {
        "blur": [4.0, 6.0, 8.0, 10.0, 12.0],
        "blurMix": [0.0, 0.25, 0.5, 0.75, 1.0],
    },
    "tintColor": {
        "glassAlpha": [0.44, 0.48, 0.52, 0.56, 0.60],
        "saturation": [0.8, 1.0, 1.2, 1.4, 1.6],
        "glassRed": [232, 240, 248, 255],
        "glassGreen": [232, 240, 248, 255],
        "glassBlue": [232, 240, 248, 255],
    },
    "highlight": {
        "lightIntensity": [0.0, 0.1, 0.2, 0.3],
        "ambientStrength": [0.0, 0.02, 0.04],
        "lightAngle": [
            0.7853981633974483,
            1.5707963267948966,
            2.356194490192345,
        ],
        "faceWhite": [0.80, 0.88, 0.92, 0.96, 1.0],
        "faceBlack": [0.40, 0.55, 0.62, 0.75],
        "faceFill": [0.0, 0.02, 0.05],
        "innerShadowOpacity": [0.0, 0.12, 0.22, 0.32, 0.45],
        "brightRimWidth": [0.5, 1.0, 1.5, 2.0, 3.0],
        "brightRimIntensity": [0.0, 0.2, 0.4, 0.6, 0.8],
        "brightRimRed": [220, 240, 255],
        "brightRimGreen": [220, 240, 255],
        "brightRimBlue": [220, 240, 255],
        "darkRimWidth": [0.5, 1.0, 1.5, 2.0, 3.0],
        "darkRimIntensity": [0.0, 0.2, 0.4, 0.6, 0.8],
        "darkRimRed": [0, 16, 32, 64],
        "darkRimGreen": [0, 16, 32, 64],
        "darkRimBlue": [0, 16, 32, 64],
    },
}

WALL_EXIT_CODE = 42


class OptimizationWall(RuntimeError):
    pass


def has_optimization_wall(
    stage_summaries,
    *,
    threshold,
    consecutive,
):
    improvements = [
        summary["improvement"] for summary in stage_summaries.values()
    ]
    return len(improvements) >= consecutive and all(
        improvement < threshold for improvement in improvements[-consecutive:]
    )


def result_json(result, settings, evaluator):
    return {
        "score": result.score,
        "errors": result.errors,
        "measurements": result.details,
        "weights": WEIGHTS,
        "settings": settings,
        "reloadModes": evaluator.last_modes,
        "evaluationSeconds": evaluator.last_seconds,
    }


def save_best(directory, settings, evaluator, reference):
    directory.mkdir(parents=True, exist_ok=True)
    capture = directory / "capture"
    capture.mkdir(parents=True, exist_ok=True)
    for probe in "ABCD":
        shutil.copy2(evaluator.capture_dir / f"{probe}.png", capture / f"{probe}.png")
    write_diagnostics(directory, reference, evaluator.last_images)
    (directory / "settings.json").write_text(json.dumps(settings, indent=2) + "\n")
    (directory / "scorecard.json").write_text(
        json.dumps(
            result_json(evaluator.last_result, settings, evaluator),
            indent=2,
        )
        + "\n"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--udid", default=os.environ.get("IOS_27_UDID"))
    parser.add_argument(
        "--flutter-bin",
        default=os.environ.get(
            "FLUTTER_BIN", str(Path.home() / "fvm/versions/3.44.1/bin/flutter")
        ),
    )
    parser.add_argument("--max-iters", type=int, default=2)
    parser.add_argument(
        "--baseline",
        type=Path,
        default=RECORDED_BASELINE / "settings.json",
    )
    parser.add_argument(
        "--stages",
        default="shape,refraction,blurMtf,tintColor,highlight",
        help="Comma-separated ordered stage names.",
    )
    parser.add_argument("--out", type=Path, default=ROOT / "out/hotloop")
    parser.add_argument("--wall-threshold", type=float, default=0.05)
    parser.add_argument("--wall-consecutive", type=int, default=2)
    args = parser.parse_args()
    if not args.udid:
        parser.error("--udid or IOS_27_UDID is required")

    scene_path = ROOT / "scenes/toolbar_capsule.json"
    scene = json.loads(scene_path.read_text())
    crop = scene_crop(scene)
    reference_dir = ROOT / "references" / REFERENCE_SET / scene["id"]
    reference = load_reference_probes(reference_dir, crop)
    baseline = json.loads(args.baseline.resolve().read_text())
    baseline.update(
        {
            "blurMix": baseline.get("blurMix", 1.0),
            "brightRimRed": baseline.get("brightRimRed", 255),
            "brightRimGreen": baseline.get("brightRimGreen", 255),
            "brightRimBlue": baseline.get("brightRimBlue", 255),
            "brightRimAlpha": baseline.get("brightRimAlpha", 1.0),
            "brightRimWidth": baseline.get("brightRimWidth", 1.0),
            "brightRimIntensity": baseline.get("brightRimIntensity", 0.0),
            "darkRimRed": baseline.get("darkRimRed", 0),
            "darkRimGreen": baseline.get("darkRimGreen", 0),
            "darkRimBlue": baseline.get("darkRimBlue", 0),
            "darkRimAlpha": baseline.get("darkRimAlpha", 1.0),
            "darkRimWidth": baseline.get("darkRimWidth", 1.0),
            "darkRimIntensity": baseline.get("darkRimIntensity", 0.35),
            "faceWhite": baseline.get("faceWhite", 0.993),
            "faceBlack": baseline.get("faceBlack", 0.53),
            "faceFill": baseline.get("faceFill", 0.0),
            "innerShadowOpacity": baseline.get("innerShadowOpacity", 0.12),
        }
    )
    selected_stages = [stage for stage in args.stages.split(",") if stage]
    unknown = set(selected_stages) - set(STAGES)
    if unknown:
        parser.error(f"unknown stages: {sorted(unknown)}")
    out = args.out.resolve()
    shutil.rmtree(out, ignore_errors=True)
    if RECORDED_BASELINE.exists():
        shutil.copytree(RECORDED_BASELINE, out / "baseline")
    (out / "baseline/refinement-baseline.json").write_text(
        json.dumps(
            {
                "source": str(args.baseline.resolve()),
                "settings": baseline,
            },
            indent=2,
        )
        + "\n"
    )

    env = os.environ.copy()
    env["PATH"] = f"{ROOT / 'compat/bin'}:{env['PATH']}"
    timings = []
    stage_summaries = {}
    with CaptureSession(
        udid=args.udid,
        flutter_bin=args.flutter_bin,
        flutter_project=ROOT / "flutter",
        scene_path=scene_path,
        work_dir=out / "session",
        env=env,
    ) as session:
        evaluator = Evaluator(
            session=session,
            reference=reference,
            crop=crop,
            capture_dir=out / "live",
        )
        print(
            f"HOTLOOP_SESSION_READY udid={args.udid} "
            f"startupSeconds={session.startup_seconds:.2f}",
            flush=True,
        )

        def optimize_stage(stage_name, initial):
            stage_dir = out / "stages" / stage_name
            best_loss = float("inf")
            best_params = None
            baseline_stage_score = None

            def evaluate(params):
                nonlocal best_loss, best_params, baseline_stage_score
                evaluator.evaluate(params)
                timings.append(evaluator.last_seconds)
                stage_score = evaluator.last_result.details["stageScores"][stage_name]
                if baseline_stage_score is None:
                    baseline_stage_score = stage_score
                loss = 100.0 - stage_score
                candidate_dir = stage_dir / "candidates" / f"{evaluator.evaluations:04d}"
                candidate_dir.mkdir(parents=True, exist_ok=True)
                (candidate_dir / "scorecard.json").write_text(
                    json.dumps(
                        result_json(evaluator.last_result, params, evaluator),
                        indent=2,
                    )
                    + "\n"
                )
                if loss < best_loss:
                    best_loss = loss
                    best_params = dict(params)
                    save_best(stage_dir / "best", best_params, evaluator, reference)
                return loss

            result = coordinate_descent(
                evaluate,
                initial,
                STAGES[stage_name],
                max_iters=args.max_iters,
                min_improvement=0.02,
            )
            summary = {
                "baselineStageScore": baseline_stage_score,
                "bestStageScore": 100.0 - result["bestLoss"],
                "improvement": 100.0
                - result["bestLoss"]
                - baseline_stage_score,
                "bestSettings": result["bestParams"],
                "evaluations": len(result["history"]),
                "bestEvidence": str((stage_dir / "best").resolve()),
            }
            (stage_dir / "summary.json").write_text(
                json.dumps(summary, indent=2) + "\n"
            )
            stage_summaries[stage_name] = summary
            print(
                f"HOTLOOP_STAGE_COMPLETE stage={stage_name} "
                f"score={summary['bestStageScore']:.4f}",
                flush=True,
            )
            if has_optimization_wall(
                stage_summaries,
                threshold=args.wall_threshold,
                consecutive=args.wall_consecutive,
            ):
                best_dir = stage_dir / "best"
                best_card = json.loads((best_dir / "scorecard.json").read_text())
                edge_parameters = {}
                for name, values in STAGES[stage_name].items():
                    value = result["bestParams"].get(name)
                    if value in (values[0], values[-1]):
                        edge_parameters[name] = {
                            "value": value,
                            "minimum": values[0],
                            "maximum": values[-1],
                        }
                report = {
                    "schemaVersion": 1,
                    "reason": "consecutive staged improvements below threshold",
                    "exitCode": WALL_EXIT_CODE,
                    "stage": stage_name,
                    "threshold": args.wall_threshold,
                    "consecutiveStages": args.wall_consecutive,
                    "currentBest": {
                        "score": best_card["score"],
                        "settings": result["bestParams"],
                    },
                    "componentResiduals": best_card["errors"],
                    "parametersAtRangeEdges": edge_parameters,
                    "diagnosticImagePaths": [
                        str(path.resolve())
                        for path in sorted(best_dir.rglob("*.png"))
                    ],
                    "stageSummaries": stage_summaries,
                }
                (out / "wall_report.json").write_text(
                    json.dumps(report, indent=2) + "\n"
                )
                raise OptimizationWall(
                    f"optimization wall after {stage_name}; "
                    f"see {out / 'wall_report.json'}"
                )
            return result["bestParams"]

        current = dict(baseline)
        if "shape" in selected_stages:
            neutral = {
                **baseline,
                "thickness": 28.0,
                "blur": 0.0,
                "blurMix": 0.0,
                "lightIntensity": 0.0,
                "ambientStrength": 0.0,
                "glassAlpha": 0.53,
                "refractiveIndex": 1.2,
                "saturation": 1.0,
                "chromaticAberration": 0.0,
            }
            shape_best = optimize_stage("shape", neutral)
            geometry_keys = (
                "shapeWidth",
                "shapeHeight",
                "shapeOffsetX",
                "shapeOffsetY",
                "cornerRadius",
                "shapeProfile",
            )
            current.update({key: shape_best[key] for key in geometry_keys})
        for stage_name in selected_stages:
            if stage_name == "shape":
                continue
            current = optimize_stage(stage_name, current)

        evaluator.evaluate(current)
        timings.append(evaluator.last_seconds)
        save_best(out / "final", current, evaluator, reference)
        full_reference = read_rgb(reference_dir / "A.png")
        full_candidate = read_rgb(out / "final/capture/A.png")
        registration = verify_background_registration(
            full_reference, full_candidate, crop
        )
        final_card = result_json(evaluator.last_result, current, evaluator)
        final_card["registration"] = registration
        (out / "final/scorecard.json").write_text(
            json.dumps(final_card, indent=2) + "\n"
        )

    summary = {
        "baselineSettings": baseline,
        "finalScore": final_card["score"],
        "startupSeconds": session.startup_seconds,
        "candidateSecondsMedian": statistics.median(timings),
        "candidateSecondsMinimum": min(timings),
        "candidateSecondsMaximum": max(timings),
        "oldRestartLoopSecondsApprox": 60.0,
        "speedupVsRestartMedian": 60.0 / statistics.median(timings),
        "evaluations": len(timings),
        "reloadModes": final_card["reloadModes"],
        "stages": stage_summaries,
        "finalSettings": current,
    }
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    try:
        main()
    except OptimizationWall as error:
        print(f"HOTLOOP_WALL {error}", flush=True)
        raise SystemExit(WALL_EXIT_CODE) from error
