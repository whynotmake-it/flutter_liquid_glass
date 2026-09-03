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

REFERENCE_SET = "ios27-iphone17pro-ground-truth-v2/slider-000"
RECORDED_BASELINE = ROOT / "out/stages/refinement/candidates/003"

STAGES = {
    "shape": {
        "shapeWidth": [223.0, 223.5, 224.0, 224.5, 225.0],
        "shapeHeight": [93.5, 94.0, 94.5],
        "shapeOffsetX": [-0.5, 0.0, 0.5],
        "shapeOffsetY": [-0.5, 0.0, 0.5],
        "cornerRadius": [49.0, 49.5, 50.0, 50.5, 51.0],
        "shapeProfile": ["roundedRectangle", "superellipse"],
    },
    "shapeProfile": {
        "shapeProfile": ["roundedRectangle", "superellipse"],
    },
    "subpixelRegistration": {
        "shapeWidth": [224.1667, 224.3333, 224.5, 224.6667, 224.8333],
        "shapeHeight": [93.6667, 93.8333, 94.0, 94.1667, 94.3333],
        "shapeOffsetX": [-0.3333, -0.1667, 0.0, 0.1667, 0.3333],
        "shapeOffsetY": [-0.3333, -0.1667, 0.0, 0.1667, 0.3333],
    },
    "subpixelVerticalRegistration": {
        "shapeOffsetY": [-0.3333, -0.1667, 0.0, 0.1667, 0.3333],
    },
    "refraction": {
        "thickness": [8.0, 10.0, 12.0, 14.0, 16.0],
        "edgeRefraction": [18.3, 22.85, 27.42, 32.0, 36.6],
        "refractionSpread": [0.0, 0.25, 0.5, 0.75, 1.0],
        "chromaticAberration": [0.0, 0.0025, 0.005, 0.0075, 0.01],
    },
    # The loupe's RawMagnifier owns enlargement; only these material controls
    # remain effective on its clear glass shell. Keep this bounded stage
    # separate from the ordinary pill search so a loupe fit cannot report
    # changes to controls that _MatchLoupe intentionally overrides.
    "loupeMaterial": {
        "thickness": [0.0, 8.0, 12.0, 20.0, 28.0, 36.0],
        "edgeRefraction": [
            0.0,
            20.0,
            40.0,
            80.0,
            120.0,
            180.0,
            240.0,
            300.0,
            400.0,
        ],
        "chromaticAberration": [0.0, 0.001, 0.0025, 0.005],
        "highlight": [0.0, 0.1, 0.2, 0.3, 0.5],
        "contourStrength": [0.0, 0.05, 0.1, 0.2, 0.35],
        "contourWidth": [0.5, 1.0, 1.5],
    },
    "blurMtf": {
        "frost": [5.0, 6.0, 7.0, 8.0, 9.0],
    },
    "tintColor": {
        "tintAlpha": [0.52, 0.525, 0.53, 0.535, 0.54],
        "tintRed": [251, 252, 253, 254],
        "tintGreen": [251, 252, 253, 254],
        "tintBlue": [251, 252, 253, 254],
    },
    "toneResponse": {
        "transmissionGamma": [0.85, 0.875, 0.90, 0.925, 0.95],
    },
    "vibrancy": {
        "vibrancy": [0.10, 0.125, 0.15, 0.175, 0.20],
        "saturation": [0.9, 0.95, 1.0, 1.05, 1.1],
    },
    "highlight": {
        "highlight": [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.8],
        "contourStrength": [0.1, 0.2, 0.3, 0.4, 0.5, 0.65, 0.8],
        "contourWidth": [0.5, 0.75, 1.0, 1.25, 1.5],
    },
    "ambientRim": {
        "ambientStrength": [0.0, 0.08, 0.15, 0.25, 0.4, 0.6, 0.8, 1.0],
    },
    "outline": {
        "edgeWidth": [0.0, 0.5, 1.0, 1.5, 2.0, 3.0],
        "edgeInset": [0.0, 0.25, 0.5, 0.75, 1.0],
        "edgeLuminance": [0, 64, 128, 192, 255],
        "edgeAlpha": [0.0, 0.1, 0.2, 0.35, 0.5],
    },
    "transmissionContour": {
        "edgeLuminance": [0],
        "edgeAlpha": [0.075, 0.1, 0.15, 0.2],
    },
    "darkOutline": {
        "edgeWidth": [0.5, 1.0, 1.5, 2.0],
        "edgeInset": [0.0, 0.25, 0.5, 0.75, 1.0],
        "edgeAlpha": [0.2, 0.35, 0.5, 0.65, 0.8],
    },
    "materialContour": {
        "outerContourWidth": [0.5, 0.75, 1.0, 1.25, 1.5, 2.0],
        "outerContourAlpha": [0.1, 0.15, 0.2, 0.25, 0.3, 0.35, 0.4],
        "outerContourLuminance": [0],
    },
    "innerShadow": {
        "innerShadowStrength": [
            0.0, 0.005, 0.01, 0.015, 0.02, 0.03, 0.04, 0.06, 0.08, 0.12
        ],
        "innerShadowDepth": [4.0, 6.0, 8.0, 10.0, 12.0, 16.0, 20.0, 24.0],
        "innerShadowDirectionality": [0.0, 0.15, 0.3, 0.5, 0.75, 1.0],
    },
    "exteriorShadow": {
        "shadowLuminance": [0, 32, 64, 96],
        "shadowAlpha": [0.0, 0.02, 0.04, 0.06, 0.08, 0.12],
        "shadowOffsetX": [0.0],
        "shadowOffsetY": [0.0, 1.0, 2.0, 3.0, 4.0],
        "shadowBlur": [2.0, 4.0, 6.0, 8.0, 10.0, 12.0],
        "shadowSpread": [-1.0, 0.0, 1.0],
    },
    "contactShadow": {
        "contactShadowAlpha": [
            0.0, 0.02, 0.04, 0.06, 0.08, 0.12, 0.16, 0.24
        ],
        "contactShadowBlur": [0.5, 1.0, 2.0, 3.0, 4.0],
        "contactShadowSpread": [-1.0, -0.5, 0.0, 0.5, 1.0],
    },
    "contactShadowPareto": {
        "contactShadowAlpha": [0.04],
        "contactShadowBlur": [1.0],
        "contactShadowSpread": [0.0],
    },
    "shadowLuminance": {
        "shadowLuminance": [0, 16, 32],
    },
    "castShadowBalance": {
        "shadowAlpha": [0.0, 0.02, 0.04, 0.06, 0.08, 0.12],
        "shadowOffsetY": [0.0, 1.0, 2.0, 3.0, 4.0],
        "shadowBlur": [4.0, 6.0, 8.0, 10.0, 12.0],
        "shadowSpread": [-2.0, -1.0, 0.0],
    },
    "layeredExteriorShadow": {
        "contactShadowAlpha": [0.02, 0.04, 0.06, 0.08, 0.12, 0.16],
        "contactShadowBlur": [0.0, 0.25, 0.5, 1.0, 1.5],
        "contactShadowSpread": [-1.0, -0.5, 0.0, 0.5],
        "shadowAlpha": [0.02, 0.04, 0.06, 0.08],
        "shadowOffsetY": [3.0, 4.0, 5.0, 6.0, 8.0],
        "shadowBlur": [6.0, 8.0, 10.0, 12.0],
    },
    "fineContactContour": {
        "contactShadowAlpha": [0.03, 0.04, 0.05, 0.06, 0.07],
        "contactShadowBlur": [0.5, 0.75, 1.0, 1.25],
        "contactShadowSpread": [-0.25, 0.0, 0.25],
    },
    "silhouetteLine": {
        "edgeAlpha": [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.65, 0.8],
        "edgeWidth": [0.5, 0.75, 1.0, 1.25, 1.5],
    },
    "layeredContour": {
        "edgeWidth": [0.5, 0.75, 1.0, 1.25, 1.5, 2.0],
        "edgeAlpha": [0.2, 0.35, 0.5, 0.65, 0.8],
        "lightIntensity": [0.2, 0.3, 0.4, 0.5, 0.6, 0.8],
        "highlightAlpha": [0.5, 0.65, 0.8, 1.0],
        "specularWrap": [0.05, 0.15, 0.25, 0.35],
        "bleedStrength": [0.0, 0.25, 0.5, 0.75],
    },
    "layeredBevel": {
        "innerShadowStrength": [0.0, 0.005, 0.01, 0.015, 0.02, 0.03, 0.04],
        "innerShadowDepth": [6.0, 8.0, 12.0, 16.0, 20.0, 24.0],
    },
    "coupledRim": {
        "edgeWidth": [0.25, 0.5, 0.75, 1.0, 1.25],
        "edgeInset": [0.0, 0.25, 0.5, 0.75, 1.0],
        "edgeLuminance": [0, 32, 64, 96, 128],
        "edgeAlpha": [0.05, 0.1, 0.15, 0.2, 0.3],
        "lightIntensity": [0.4, 0.5, 0.6, 0.7, 0.8],
        "specularWrap": [0.15, 0.25, 0.35, 0.45, 0.55],
        "bleedStrength": [0.25, 0.5, 0.75],
    },
}

WALL_EXIT_CODE = 42


class OptimizationWall(RuntimeError):
    pass


def diagnostic_stage_name(stage_name):
    return {
        "outline": "highlight",
        "toneResponse": "tintColor",
        "vibrancy": "tintColor",
        "innerShadow": "highlight",
        "ambientRim": "highlight",
        "darkOutline": "highlight",
        "materialContour": "highlight",
        "transmissionContour": "highlight",
        "shapeProfile": "shape",
        "loupeMaterial": "refinement",
        "subpixelRegistration": "shape",
        "subpixelVerticalRegistration": "shape",
        "exteriorShadow": "highlight",
        "contactShadow": "highlight",
        "contactShadowPareto": "highlight",
        "shadowLuminance": "highlight",
        "castShadowBalance": "highlight",
        "layeredExteriorShadow": "highlight",
        "fineContactContour": "highlight",
        "silhouetteLine": "highlight",
        "layeredContour": "highlight",
        "layeredBevel": "highlight",
        "coupledRim": "highlight",
    }.get(stage_name, stage_name)


def optimization_objective(stage_name, result):
    """Return an interpretable stage-specific loss in 8-bit-like units.

    Apple mixes blurred and unblurred backdrop content, which this harness does
    not currently reproduce. A whole-image residual therefore biases unrelated
    material parameters toward compensating for the known blur mismatch. Shape
    and flow metrics isolate geometry/refraction; neutral solid probes isolate
    transmission and rim lighting without backdrop-frequency ambiguity.
    """
    details = result.details
    if stage_name in ("shape", "shapeProfile"):
        return "shapeError8BitEquivalent", result.errors["shape"] * 255.0
    if stage_name == "refraction":
        return "flowError8BitEquivalent", result.errors["flow"] * 255.0
    residuals = details["pixelResiduals"]
    if stage_name in ("subpixelRegistration", "subpixelVerticalRegistration"):
        return (
            "solidRimRegistrationMeanAbsoluteError8Bit",
            (
                residuals["C"]["rim"]["meanAbsoluteError8Bit"] +
                residuals["D"]["rim"]["meanAbsoluteError8Bit"]
            ) / 2.0,
        )
    if stage_name == "tintColor":
        loss = sum(
            residuals[probe]["core"]["meanAbsoluteError8Bit"]
            for probe in "CD"
        ) / 2.0
        return "solidCoreMeanAbsoluteError8Bit", loss
    if stage_name in ("highlight", "ambientRim"):
        # A bright specular rim is observable without being washed out only
        # on the solid-black probe.
        return (
            "blackBackgroundBrightRimMeanAbsoluteError8Bit",
            residuals["C"]["outerContour"]["meanAbsoluteError8Bit"],
        )
    if stage_name in (
        "outline",
        "darkOutline",
        "outerContour",
        "materialContour",
    ):
        # Conversely, Apple's dark containment edge is isolated by white.
        return (
            "whiteBackgroundDarkRimMeanAbsoluteError8Bit",
            residuals["D"]["outerContour"]["meanAbsoluteError8Bit"],
        )
    if stage_name == "innerShadow":
        white = residuals["D"]
        face = (
            white["topFace"]["meanAbsoluteError8Bit"] +
            white["bottomFace"]["meanAbsoluteError8Bit"]
        ) / 2.0
        return (
            "whiteInnerBevelMeanAbsoluteError8Bit",
            white["innerBevel"]["meanAbsoluteError8Bit"] * 0.6 + face * 0.4,
        )
    if stage_name == "exteriorShadow":
        return (
            "whiteExteriorMeanAbsoluteError8Bit",
            residuals["D"]["exterior"]["meanAbsoluteError8Bit"],
        )
    if stage_name in ("contactShadow", "contactShadowPareto"):
        white_exterior = residuals["D"]["exteriorContour"]
        direct = details["directPixelMeanAbsoluteError8Bit"]
        return (
            "whiteContactShadowAndDirectMeanAbsoluteError8Bit",
            white_exterior["meanAbsoluteError8Bit"] + direct,
        )
    if stage_name == "shadowLuminance":
        exterior = sum(
            residuals[probe]["exteriorContour"]["meanAbsoluteError8Bit"]
            for probe in "CD"
        ) / 2.0
        direct = details["directPixelMeanAbsoluteError8Bit"]
        return "neutralExteriorShadowAndDirectMeanAbsoluteError8Bit", exterior + direct
    if stage_name == "castShadowBalance":
        silhouette = sum(
            residuals[probe]["silhouetteLine"]["meanAbsoluteError8Bit"]
            for probe in "CD"
        ) / 2.0
        exterior = sum(
            residuals[probe]["exteriorContour"]["meanAbsoluteError8Bit"]
            for probe in "CD"
        ) / 2.0
        direct = details["directPixelMeanAbsoluteError8Bit"]
        return (
            "castShadowRadialBandsAndDirectMeanAbsoluteError8Bit",
            silhouette * 0.4 + exterior * 0.4 + direct * 0.2,
        )
    if stage_name == "layeredExteriorShadow":
        exterior = residuals["D"]["directionalExteriorBands"]
        contact_names = [name for name in exterior if "Exterior0To1" in name]
        near_names = [name for name in exterior if "Exterior1To2" in name]
        far_names = [
            name for name in exterior
            if "Exterior2To4" in name or "Exterior4To8" in name
        ]
        contact = sum(exterior[name]["meanAbsoluteError8Bit"] for name in contact_names) / len(contact_names)
        near = sum(exterior[name]["meanAbsoluteError8Bit"] for name in near_names) / len(near_names)
        far = sum(exterior[name]["meanAbsoluteError8Bit"] for name in far_names) / len(far_names)
        direct = details["directPixelMeanAbsoluteError8Bit"]
        return "layeredExteriorShadowAndDirectMeanAbsoluteError8Bit", (
            contact * 0.35 + near * 0.25 + far * 0.2 + direct * 0.2
        )
    if stage_name == "fineContactContour":
        exterior = residuals["D"]["directionalExteriorBands"]
        contact_names = [name for name in exterior if "Exterior0To1" in name]
        near_names = [name for name in exterior if "Exterior1To2" in name]
        contact = sum(
            exterior[name]["meanAbsoluteError8Bit"] for name in contact_names
        ) / len(contact_names)
        near = sum(
            exterior[name]["meanAbsoluteError8Bit"] for name in near_names
        ) / len(near_names)
        direct = details["directPixelMeanAbsoluteError8Bit"]
        return "fineContactContourParetoMeanAbsoluteError8Bit", (
            contact * 0.2 + near * 0.15 + direct * 0.65
        )
    if stage_name == "silhouetteLine":
        line = sum(
            residuals[probe]["silhouetteLine"]["meanAbsoluteError8Bit"]
            for probe in "CD"
        ) / 2.0
        direct = details["directPixelMeanAbsoluteError8Bit"]
        return "silhouetteLineAndDirectMeanAbsoluteError8Bit", line + direct
    if stage_name == "layeredContour":
        band_names = residuals["C"]["directionalDistanceBands"].keys()
        contour_names = [name for name in band_names if "Contour0To1" in name]
        inner_names = [name for name in band_names if "Contour1To2" in name]
        contour = sum(
            residuals[probe]["directionalDistanceBands"][name][
                "meanAbsoluteError8Bit"
            ]
            for probe in "CD"
            for name in contour_names
        ) / (2.0 * len(contour_names))
        inner = sum(
            residuals[probe]["directionalDistanceBands"][name][
                "meanAbsoluteError8Bit"
            ]
            for probe in "CD"
            for name in inner_names
        ) / (2.0 * len(inner_names))
        direct = details["directPixelMeanAbsoluteError8Bit"]
        return "layeredContourAndDirectMeanAbsoluteError8Bit", (
            contour * 0.7 + inner * 0.15 + direct * 0.15
        )
    if stage_name == "layeredBevel":
        band_names = residuals["C"]["directionalDistanceBands"].keys()
        bevel_names = [name for name in band_names if "Bevel" in name]
        black = sum(
            residuals["C"]["directionalDistanceBands"][name][
                "meanAbsoluteError8Bit"
            ]
            for name in bevel_names
        ) / len(bevel_names)
        white = sum(
            residuals["D"]["directionalDistanceBands"][name][
                "meanAbsoluteError8Bit"
            ]
            for name in bevel_names
        ) / len(bevel_names)
        direct = details["directPixelMeanAbsoluteError8Bit"]
        return "layeredBevelAndDirectMeanAbsoluteError8Bit", (
            black * 0.2 + white * 0.6 + direct * 0.2
        )
    if stage_name == "transmissionContour":
        transfer = residuals["solidTransfer"]["transmission"]
        outer = transfer["outerContour"]
        inner = transfer["innerRim"]
        return "solidTransmissionContourMeanAbsoluteError8Bit", (
            outer["meanAbsoluteError8Bit"]
            + abs(outer["meanSignedLuminanceError8Bit"])
            + inner["meanAbsoluteError8Bit"] * 0.25
        )
    if stage_name == "coupledRim":
        outer = sum(
            residuals[probe]["outerContour"]["meanAbsoluteError8Bit"]
            for probe in "CD"
        ) / 2.0
        direct = details["directPixelMeanAbsoluteError8Bit"]
        return "coupledBlackWhiteRimAndDirectMeanAbsoluteError8Bit", (
            outer * 0.9 + direct * 0.1
        )
    return (
        "directPixelMeanAbsoluteError8Bit",
        details["directPixelMeanAbsoluteError8Bit"],
    )


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
        "runtimeCapabilities": evaluator.session.runtime_capabilities,
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
            "FLUTTER_BIN", str(Path.home() / "fvm/versions/3.47.1/bin/flutter")
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
        default=(
            "shape,refraction,tintColor,highlight,outline,exteriorShadow"
        ),
        help="Comma-separated ordered stage names.",
    )
    parser.add_argument("--out", type=Path, default=ROOT / "out/hotloop")
    parser.add_argument(
        "--scene-id",
        default="toolbar_capsule",
        help="Scene id under scenes/ (default toolbar_capsule).",
    )
    parser.add_argument("--wall-threshold", type=float, default=0.05)
    parser.add_argument("--wall-consecutive", type=int, default=2)
    args = parser.parse_args()
    if not args.udid:
        parser.error("--udid or IOS_27_UDID is required")

    scene_path = ROOT / "scenes" / f"{args.scene_id}.json"
    scene = json.loads(scene_path.read_text())
    crop = scene_crop(scene)
    reference_dir = ROOT / "references" / REFERENCE_SET / scene["id"]
    reference = load_reference_probes(reference_dir, crop)
    baseline = json.loads(args.baseline.resolve().read_text())
    selected_stages = [stage for stage in args.stages.split(",") if stage]
    unknown = set(selected_stages) - set(STAGES)
    if unknown:
        parser.error(f"unknown stages: {sorted(unknown)}")
    out = args.out.resolve()
    shutil.rmtree(out, ignore_errors=True)
    if RECORDED_BASELINE.exists():
        shutil.copytree(RECORDED_BASELINE, out / "baseline")
    else:
        (out / "baseline").mkdir(parents=True, exist_ok=True)
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
            stage_evaluations = 0
            baseline_stage_score = None
            baseline_direct_mae = None
            baseline_objective = None
            objective_name = None

            def evaluate(params):
                nonlocal best_loss, best_params, baseline_stage_score
                nonlocal baseline_direct_mae, baseline_objective
                nonlocal objective_name, stage_evaluations
                evaluator.evaluate(params)
                stage_evaluations += 1
                timings.append(evaluator.last_seconds)
                diagnostic_stage = diagnostic_stage_name(stage_name)
                stage_score = evaluator.last_result.details["stageScores"][
                    diagnostic_stage
                ]
                direct_mae = evaluator.last_result.details[
                    "directPixelMeanAbsoluteError8Bit"
                ]
                candidate_objective_name, loss = optimization_objective(
                    stage_name, evaluator.last_result
                )
                if baseline_stage_score is None:
                    baseline_stage_score = stage_score
                    baseline_direct_mae = direct_mae
                    baseline_objective = loss
                    objective_name = candidate_objective_name
                elif candidate_objective_name != objective_name:
                    raise RuntimeError("optimization objective changed within a stage")
                candidate_dir = stage_dir / "candidates" / f"{evaluator.evaluations:04d}"
                candidate_dir.mkdir(parents=True, exist_ok=True)
                (candidate_dir / "scorecard.json").write_text(
                    json.dumps(
                        result_json(evaluator.last_result, params, evaluator),
                        indent=2,
                    )
                    + "\n"
                )
                if loss < best_loss - 0.0001:
                    best_loss = loss
                    best_params = dict(params)
                    save_best(stage_dir / "best", best_params, evaluator, reference)
                return loss

            if stage_name == "materialContour":
                # Add explicit zero-valued axes when comparing against an old
                # settings file. This keeps the no-material-contour baseline
                # in the same optimization domain as the new layer.
                initial = {
                    **initial,
                    "outerContourWidth": initial.get("outerContourWidth", 1.0),
                    "outerContourAlpha": initial.get("outerContourAlpha", 0.0),
                    "outerContourLuminance": initial.get(
                        "outerContourLuminance", 0
                    ),
                }

            # Edge occlusion is intentionally a product of width and opacity.
            # Starting from the transparent default makes one-at-a-time
            # coordinate descent see both axes as flat, so test a small set of
            # physically plausible coupled seeds before refining each axis.
            if stage_name == "outline":
                transparent = dict(initial)
                transparent_loss = evaluate(transparent)
                seeded = []
                for edge_width in (0.5, 1.0, 1.5):
                    for edge_inset in (0.25, 0.5, 0.75):
                        for edge_alpha in (0.1, 0.2):
                            candidate = {
                                **initial,
                                "edgeWidth": edge_width,
                                "edgeInset": edge_inset,
                                "edgeLuminance": 0,
                                "edgeAlpha": edge_alpha,
                            }
                            seeded.append((evaluate(candidate), candidate))
                seed_loss, initial = min(seeded, key=lambda item: item[0])
                # Preserve the transparent treatment when every coupled edge
                # candidate is worse than the input image.
                if transparent_loss <= seed_loss:
                    initial = transparent

            if stage_name == "exteriorShadow":
                transparent = dict(initial)
                transparent_loss = evaluate(transparent)
                seeded = []
                for shadow_alpha in (0.02, 0.04, 0.08):
                    for shadow_blur in (4.0, 8.0, 12.0):
                        candidate = {
                            **initial,
                            "shadowLuminance": 0,
                            "shadowAlpha": shadow_alpha,
                            "shadowOffsetX": 0.0,
                            "shadowOffsetY": 2.0,
                            "shadowBlur": shadow_blur,
                            "shadowSpread": 0.0,
                        }
                        seeded.append((evaluate(candidate), candidate))
                seed_loss, initial = min(seeded, key=lambda item: item[0])
                if transparent_loss <= seed_loss:
                    initial = transparent

            result = coordinate_descent(
                evaluate,
                initial,
                STAGES[stage_name],
                max_iters=args.max_iters,
                # Direct MAE is measured in 8-bit code values. At the final
                # fitting scale, 0.01-level improvements are repeatable and
                # visually material across hundreds of thousands of pixels.
                min_improvement=0.0001,
            )
            best_card = json.loads(
                (stage_dir / "best" / "scorecard.json").read_text()
            )
            diagnostic_stage = diagnostic_stage_name(stage_name)
            summary = {
                "baselineStageScore": baseline_stage_score,
                "bestStageScore": best_card["measurements"]["stageScores"][
                    diagnostic_stage
                ],
                "baselineDirectPixelMae8Bit": baseline_direct_mae,
                "bestDirectPixelMae8Bit": best_card["measurements"][
                    "directPixelMeanAbsoluteError8Bit"
                ],
                "directPixelImprovement8Bit": baseline_direct_mae
                - best_card["measurements"]["directPixelMeanAbsoluteError8Bit"],
                "objectiveName": objective_name,
                "baselineObjective": baseline_objective,
                "bestObjective": best_loss,
                "improvement": baseline_objective - best_loss,
                "bestSettings": best_params,
                "evaluations": stage_evaluations,
                "bestEvidence": str((stage_dir / "best").resolve()),
            }
            (stage_dir / "summary.json").write_text(
                json.dumps(summary, indent=2) + "\n"
            )
            stage_summaries[stage_name] = summary
            print(
                f"HOTLOOP_STAGE_COMPLETE stage={stage_name} "
                f"objective={objective_name} value={best_loss:.4f} "
                f"directMae8Bit={summary['bestDirectPixelMae8Bit']:.4f}",
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
                    value = best_params.get(name)
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
                        "settings": best_params,
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
            return best_params

        current = dict(baseline)
        if "shape" in selected_stages:
            shape_best = optimize_stage("shape", current)
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
            full_reference,
            full_candidate,
            crop,
            extra_excluded_rects=(
                (
                    round(138.3333 * scene["canvas"]["scale"]) - 1,
                    round(14.0 * scene["canvas"]["scale"]) - 1,
                    round(125.3333 * scene["canvas"]["scale"]) + 2,
                    round(36.6667 * scene["canvas"]["scale"]) + 2,
                ),
                (0, 0, 5, 5),
            )
            if args.scene_id == "loupe"
            else (),
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
