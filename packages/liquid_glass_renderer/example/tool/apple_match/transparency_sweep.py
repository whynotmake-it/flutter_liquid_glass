#!/usr/bin/env python3
"""Capture and fit the iOS Liquid Glass Tint Amount sweep."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import cv2
import numpy as np

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
from apple_match.metrics import WEIGHTS, write_diagnostics  # noqa: E402

POSITIONS = (0.0, 0.25, 0.5, 0.75, 1.0)
REFERENCE_SET = "ios27-iphone17pro-light-transparency"
CONTROL_METHOD = (
    "simctl defaults write com.apple.UIKit UIViewGlassTintAmount "
    "(Settings → Appearance → Liquid Glass Tint Amount backing key)"
)


def position_id(position: float) -> str:
    return f"slider-{round(position * 100):03d}"


def parse_positions(value: str) -> tuple[float, ...]:
    positions = tuple(sorted({round(float(item), 6) for item in value.split(",")}))
    if not positions or any(position < 0.0 or position > 1.0 for position in positions):
        raise argparse.ArgumentTypeError(
            "positions must be comma-separated values in the range 0..1"
        )
    return positions


def reference_dir(position: float) -> Path:
    return (
        ROOT
        / "references"
        / REFERENCE_SET
        / position_id(position)
        / "toolbar_capsule"
    )


def capture_references(args) -> None:
    env = os.environ.copy()
    env["IOS_27_UDID"] = args.udid
    env["CAPTURE_FRAMES"] = str(args.frames)
    env["SCENE_ID"] = "toolbar_capsule"
    env["FORCE_REFERENCE"] = "1" if args.force_reference else "0"
    env.setdefault(
        "DEVELOPER_DIR",
        "/Applications/Xcode-27.0.0-Beta.5.app/Contents/Developer",
    )
    env["LIQUID_GLASS_TINT_CONTROL_METHOD"] = CONTROL_METHOD
    for position in args.positions:
        subprocess.run(
            [str(ROOT / "apple/set_transparency_slider.sh"), str(position)],
            check=True,
            env=env,
        )
        position_env = {
            **env,
            "REFERENCE_SET": f"{REFERENCE_SET}/{position_id(position)}",
            "LIQUID_GLASS_TINT_POSITION": str(position),
        }
        subprocess.run(
            [str(ROOT / "apple/capture.sh")],
            check=True,
            env=position_env,
        )
    subprocess.run(
        [str(ROOT / "apple/set_transparency_slider.sh"), "0.5"],
        check=True,
        env=env,
    )


def materialize(virtual: dict) -> dict:
    settings = dict(virtual)
    # The slider fit intentionally shares one canonical material vector. Only
    # these two documented transmission scalars are allowed to vary per
    # position: tint alpha and frost. No legacy blurMix/glassAlpha knobs are
    # sent to the renderer.
    tint_level = round(float(settings.pop("tintLevel", 255.0)))
    settings.update({
        "tintRed": tint_level,
        "tintGreen": tint_level,
        "tintBlue": tint_level,
    })
    return settings


def fit_objective(evaluator: Evaluator) -> float:
    scores = evaluator.last_result.details["stageScores"]
    return (
        0.80 * (100.0 - scores["refraction"])
        + 0.20 * (100.0 - scores["tintColor"])
    )


def fine_values(center: float, radius: float, step: float, low: float, high: float):
    start = max(low, center - radius)
    stop = min(high, center + radius)
    values = np.arange(start, stop + step * 0.5, step)
    result = sorted({round(float(value), 6) for value in values} | {float(center)})
    return [value for value in result if low <= value <= high]


def save_fit(
    directory: Path,
    *,
    position: float,
    virtual: dict,
    evaluator: Evaluator,
    reference: dict,
    history: list,
) -> dict:
    directory.mkdir(parents=True, exist_ok=True)
    settings = materialize(virtual)
    capture = directory / "capture"
    capture.mkdir(exist_ok=True)
    references = directory / "reference"
    references.mkdir(exist_ok=True)
    source_reference = reference_dir(position)
    for probe in "ABCD":
        shutil.copy2(evaluator.capture_dir / f"{probe}.png", capture / f"{probe}.png")
        shutil.copy2(source_reference / f"{probe}.png", references / f"{probe}.png")
    write_diagnostics(directory, reference, evaluator.last_images)
    scorecard = {
        "schemaVersion": 1,
        "sliderPosition": position,
        "sliderPercent": round(position * 100),
        "sliderControlMethod": CONTROL_METHOD,
        "score": evaluator.last_result.score,
        "fitObjective": fit_objective(evaluator),
        "errors": evaluator.last_result.errors,
        "measurements": evaluator.last_result.details,
        "weights": WEIGHTS,
        "sharedVector": {
            key: settings[key]
            for key in (
                "thickness", "edgeRefraction", "refractionSpread", "frost",
                "chromaticAberration", "saturation", "transmissionGamma",
                "vibrancy", "highlight", "contourStrength", "contourWidth",
            )
        },
        "fitted": {
            "tintAlpha": settings["tintAlpha"],
            "frost": settings["frost"],
            "tintLevel": virtual["tintLevel"],
            "tintColor": [
                settings["tintRed"],
                settings["tintGreen"],
                settings["tintBlue"],
            ],
        },
        "settings": settings,
        "reloadModes": evaluator.last_modes,
        "evaluationSeconds": evaluator.last_seconds,
        "history": history,
        "evidence": {
            "reference": str((references / "A.png").resolve()),
            "candidate": str((capture / "A.png").resolve()),
            "signedDiff": str((directory / "signed_diff_x4.png").resolve()),
        },
    }
    (directory / "settings.json").write_text(json.dumps(settings, indent=2) + "\n")
    (directory / "scorecard.json").write_text(
        json.dumps(scorecard, indent=2) + "\n"
    )
    return scorecard


def is_monotonic(values: list[float], tolerance: float = 0.051) -> bool:
    differences = np.diff(np.asarray(values, dtype=np.float64))
    return bool(
        np.all(differences >= -tolerance) or np.all(differences <= tolerance)
    )


def interpret_curve(values: list[float], label: str = "curve") -> dict:
    spread = max(values) - min(values)
    monotonic = is_monotonic(values)
    if spread < 0.02:
        status = "rejected"
        reason = f"fitted {label} does not materially respond to Tint Amount"
    elif monotonic:
        status = "confirmed"
        reason = f"fitted {label} varies monotonically with Tint Amount"
    else:
        status = "inconclusive"
        reason = f"fitted {label} is not materially monotonic"
    return {
        "status": status,
        "reason": reason,
        "monotonic": monotonic,
        "spread": spread,
        "label": label,
    }


def write_curve_plot(path: Path, rows: list[dict]) -> None:
    width, height = 1100, 680
    left, right, top, bottom = 100, 55, 85, 100
    image = np.full((height, width, 3), 248, dtype=np.uint8)
    plot_width = width - left - right
    plot_height = height - top - bottom
    cv2.rectangle(
        image,
        (left, top),
        (left + plot_width, top + plot_height),
        (60, 60, 60),
        2,
    )
    for index in range(5):
        value = index / 4
        y = round(top + (1.0 - value) * plot_height)
        cv2.line(image, (left, y), (left + plot_width, y), (220, 220, 220), 1)
        cv2.putText(
            image,
            f"{value:.2f}",
            (35, y + 7),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.55,
            (60, 60, 60),
            1,
            cv2.LINE_AA,
        )
    for row in rows:
        x = round(left + row["sliderPosition"] * plot_width)
        cv2.line(
            image,
            (x, top),
            (x, top + plot_height),
            (230, 230, 230),
            1,
        )
        cv2.putText(
            image,
            f"{row['sliderPosition']:.2f}",
            (x - 20, top + plot_height + 35),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.55,
            (60, 60, 60),
            1,
            cv2.LINE_AA,
        )

    series = (
        ("tint alpha", [row["tintAlpha"] for row in rows], (40, 150, 40)),
        ("tintLevel / 255", [row["tintLevel"] / 255.0 for row in rows], (40, 40, 210)),
    )
    for label, values, color in series:
        points = np.asarray(
            [
                (
                    round(left + row["sliderPosition"] * plot_width),
                    round(top + (1.0 - value) * plot_height),
                )
                for row, value in zip(rows, values)
            ],
            dtype=np.int32,
        )
        cv2.polylines(image, [points], False, color, 4, cv2.LINE_AA)
        for point in points:
            cv2.circle(image, tuple(point), 7, color, -1, cv2.LINE_AA)
    cv2.putText(
        image,
        "iOS 27 Liquid Glass transparency/tint fit",
        (left, 48),
        cv2.FONT_HERSHEY_SIMPLEX,
        1.0,
        (30, 30, 30),
        2,
        cv2.LINE_AA,
    )
    cv2.putText(
        image,
        "Settings slider position",
        (left + plot_width // 2 - 100, height - 28),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.65,
        (50, 50, 50),
        2,
        cv2.LINE_AA,
    )
    legend_x = left + 35
    for label, _, color in series:
        cv2.line(image, (legend_x, 66), (legend_x + 34, 66), color, 4)
        cv2.putText(
            image,
            label,
            (legend_x + 43, 72),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.52,
            (45, 45, 45),
            1,
            cv2.LINE_AA,
        )
        legend_x += 250
    cv2.imwrite(str(path), image)


def load_baseline(path: Path) -> dict:
    payload = json.loads(path.read_text())
    if "currentBest" in payload:
        return payload["currentBest"]["settings"]
    return payload


def fit_sweep(args) -> dict:
    scene_path = ROOT / "scenes/toolbar_capsule.json"
    scene = json.loads(scene_path.read_text())
    crop = scene_crop(scene)
    baseline = load_baseline(args.baseline.resolve())
    baseline_virtual = {
        **baseline,
        "tintLevel": float(
            np.mean(
                [
                    baseline["tintRed"],
                    baseline["tintGreen"],
                    baseline["tintBlue"],
                ]
            )
        ),
    }
    positions = args.positions
    references = {
        position: load_reference_probes(reference_dir(position), crop)
        for position in positions
    }
    out = args.out.resolve()
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True)
    env = os.environ.copy()
    env["PATH"] = f"{ROOT / 'compat/bin'}:{env['PATH']}"
    cards = []
    print(
        "TRANSPARENCY_FIT_SESSION_STARTING "
        f"udid={args.udid} positions={list(positions)}",
        flush=True,
    )
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
            reference=references[POSITIONS[0]],
            crop=crop,
            capture_dir=out / "live",
        )
        for position in positions:
            evaluator.reference = references[position]
            evaluation_rows = []

            def evaluate(virtual):
                evaluator.evaluate(materialize(virtual))
                row = {
                    "params": {
                        "tintAlpha": virtual["tintAlpha"],
                        "frost": virtual["frost"],
                        "tintLevel": virtual["tintLevel"],
                    },
                    "objective": fit_objective(evaluator),
                    "score": evaluator.last_result.score,
                }
                evaluation_rows.append(row)
                return row["objective"]

            coarse = coordinate_descent(
                evaluate,
                baseline_virtual,
                {
                    "tintAlpha": [0.05, 0.18, 0.38, 0.58, 0.72, 0.86],
                    "frost": [0.0, 2.0, 5.0, 7.0, 10.0],
                    "tintLevel": [215.0, 235.0, 255.0],
                },
                max_iters=args.max_iters,
                min_improvement=0.01,
            )
            coarse_best = coarse["bestParams"]
            fine = coordinate_descent(
                evaluate,
                coarse_best,
                {
                    "tintAlpha": fine_values(
                        coarse_best["tintAlpha"], 0.20, 0.04, 0.02, 0.98
                    ),
                    "frost": fine_values(coarse_best["frost"], 3.0, 1.0, 0.0, 12.0),
                    "tintLevel": fine_values(
                        coarse_best["tintLevel"], 24.0, 8.0, 191.0, 255.0
                    ),
                },
                max_iters=args.fine_max_iters,
                min_improvement=0.005,
            )
            best = fine["bestParams"]
            evaluator.evaluate(materialize(best))
            card = save_fit(
                out / position_id(position),
                position=position,
                virtual=best,
                evaluator=evaluator,
                reference=references[position],
                history=evaluation_rows,
            )
            cards.append(card)
            print(
                f"TRANSPARENCY_FIT position={position:.2f} "
                f"alpha={card['fitted']['tintAlpha']:.3f} "
                f"frost={card['fitted']['frost']:.3f} "
                f"tint={card['fitted']['tintLevel']:.1f} "
                f"score={card['score']:.4f}",
                flush=True,
            )

    rows = [
        {
            "sliderPosition": card["sliderPosition"],
            "tintAlpha": card["fitted"]["tintAlpha"],
            "frost": card["fitted"]["frost"],
            "tintLevel": card["fitted"]["tintLevel"],
            "score": card["score"],
            "fitObjective": card["fitObjective"],
            "scorecard": str(
                (out / position_id(card["sliderPosition"]) / "scorecard.json").resolve()
            ),
            "evidence": card["evidence"],
        }
        for card in cards
    ]
    interpretation = {
        "status": "shared-vector-with-two-scalars",
        "reason": "All material fields are shared; only tint alpha and frost vary per slider position.",
        "allowedPerPositionScalars": ["tintAlpha", "frost"],
        "tintAlpha": interpret_curve([row["tintAlpha"] for row in rows], "tintAlpha"),
        "frost": interpret_curve([row["frost"] for row in rows], "frost"),
    }
    plot = out / "blur_mix_mapping.png"
    write_curve_plot(plot, rows)
    summary = {
        "schemaVersion": 1,
        "scene": "toolbar_capsule",
        "runtime": "iOS 27.0 (24A5408d)",
        "udid": args.udid,
        "sliderControlMethod": CONTROL_METHOD,
        "medianFrameCount": args.frames,
        "sharedVector": {
            key: baseline[key]
            for key in (
                "thickness", "edgeRefraction", "refractionSpread", "chromaticAberration",
                "saturation", "transmissionGamma", "vibrancy", "highlight",
                "contourStrength", "contourWidth",
            )
        },
        "positions": list(positions),
        "curve": rows,
        "interpretation": interpretation,
        "plot": str(plot.resolve()),
        "defaultPositionCorrection": (
            "The redesign fits a shared material vector and reports only the "
            "two permitted per-position transmission scalars."
        ),
        "visualInspection": (
            "The signed diffs measure the transparent-slider transmission and "
            "tint response only. Blur is intentionally held out of this fit; "
            "the endpoint captures are retained for later visual review."
        ),
    }
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    update_wall_report(args.wall_report, summary)
    print(json.dumps(summary, indent=2))
    return summary


def update_wall_report(path: Path, summary: dict) -> None:
    if not path.exists():
        return
    report = json.loads(path.read_text())
    report["transparencySweep"] = {
        "status": summary["interpretation"]["status"],
        "reason": summary["interpretation"]["reason"],
        "summary": str((Path(summary["plot"]).parent / "summary.json").resolve()),
        "plot": summary["plot"],
        "curve": summary["curve"],
        "defaultPositionCorrection": summary["defaultPositionCorrection"],
        "visualInspection": summary["visualInspection"],
    }
    path.write_text(json.dumps(report, indent=2) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--udid", default=os.environ.get("IOS_27_UDID"))
    parser.add_argument(
        "--flutter-bin",
        default=os.environ.get(
            "FLUTTER_BIN", str(Path.home() / "fvm/versions/3.47.1/bin/flutter")
        ),
    )
    parser.add_argument("--frames", type=int, default=3)
    parser.add_argument(
        "--positions",
        type=parse_positions,
        default=POSITIONS,
        help="Comma-separated slider positions to fit (default: all five)",
    )
    parser.add_argument(
        "--max-iters", type=int, default=10,
        help="Coarse coordinate-descent iterations per position",
    )
    parser.add_argument(
        "--fine-max-iters", type=int, default=16,
        help="Fine coordinate-descent iterations per position",
    )
    parser.add_argument("--force-reference", action="store_true")
    parser.add_argument("--capture-only", action="store_true")
    parser.add_argument("--fit-only", action="store_true")
    parser.add_argument(
        "--baseline",
        type=Path,
        default=ROOT / "settings/baseline.json",
    )
    parser.add_argument(
        "--wall-report",
        type=Path,
        default=ROOT / "out/approved-renderer/wall_report.json",
    )
    parser.add_argument("--out", type=Path, default=ROOT / "out/transparency-sweep")
    args = parser.parse_args()
    if not args.udid:
        parser.error("--udid or IOS_27_UDID is required")
    if args.capture_only and args.fit_only:
        parser.error("--capture-only and --fit-only are mutually exclusive")
    if not args.fit_only:
        capture_references(args)
    if not args.capture_only:
        fit_sweep(args)


if __name__ == "__main__":
    main()
