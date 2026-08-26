#!/usr/bin/env python3
"""Measure the existing shared refraction-spread axis across three scenes.

This is an evidence probe, not a fitting shortcut: every spread value gets a
fresh toolbar capture and the same candidate is then evaluated on both capsule
sizes with their recovered geometry/thickness held fixed.
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

REFERENCE_SET = "ios27-iphone17pro-light"
SCENES = ("toolbar_capsule", "small_capsule", "large_capsule")
DEFAULT_SPREADS = (0.0, 0.0625, 0.125, 0.25, 0.5)


def _load_card(path: Path) -> dict:
    value = json.loads(path.read_text())
    return value.get("settings", value)


def _settings_for_scene(
    toolbar: dict, scene_card: dict, spread: float
) -> dict:
    settings = dict(toolbar)
    for key in (
        "shapeWidth",
        "shapeHeight",
        "shapeOffsetX",
        "shapeOffsetY",
        "cornerRadius",
        "shapeProfile",
        "thickness",
    ):
        settings[key] = scene_card[key]
    settings["refractionSpread"] = spread
    return settings


def _evaluate_scene(
    *,
    scene_id: str,
    candidates: dict[float, dict],
    args: argparse.Namespace,
    out: Path,
) -> dict[float, list[dict]]:
    scene_path = ROOT / "scenes" / f"{scene_id}.json"
    scene = json.loads(scene_path.read_text())
    crop = scene_crop(scene)
    reference_dir = ROOT / "references" / REFERENCE_SET / scene_id
    reference = load_reference_probes(reference_dir, crop)
    scene_out = out / scene_id
    env = os.environ.copy()
    env["PATH"] = f"{ROOT / 'compat/bin'}:{env['PATH']}"
    rows: dict[float, list[dict]] = {spread: [] for spread in candidates}
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
            f"SPREAD_SCENE_READY scene={scene_id} "
            f"startupSeconds={session.startup_seconds:.2f}",
            flush=True,
        )
        for spread, settings in candidates.items():
            for repetition in range(1, args.repetitions + 1):
                evaluator.evaluate(settings)
                result = evaluator.last_result
                rows[spread].append(
                    {
                        "repetition": repetition,
                        "score": result.score,
                        "errors": result.errors,
                        "directMae8Bit": result.details[
                            "directPixelMeanAbsoluteError8Bit"
                        ],
                    }
                )
                print(
                    f"SPREAD scene={scene_id} value={spread} "
                    f"rep={repetition} score={result.score:.4f} "
                    f"combined={result.errors['combined']:.6f} "
                    f"flow={result.errors['flow']:.6f}",
                    flush=True,
                )
    return rows


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
    parser.add_argument("--out", type=Path, default=ROOT / "out/spread-grid")
    parser.add_argument("--repetitions", type=int, default=2)
    parser.add_argument(
        "--spreads",
        type=float,
        nargs="+",
        default=list(DEFAULT_SPREADS),
    )
    args = parser.parse_args()
    if not args.udid:
        parser.error("--udid or IOS_27_UDID is required")
    if args.repetitions < 1:
        parser.error("--repetitions must be at least 1")
    if any(not 0.0 <= spread <= 1.0 for spread in args.spreads):
        parser.error("--spreads must be between 0 and 1")

    toolbar = _load_card(args.toolbar_card.resolve())
    scene_cards = {
        "toolbar_capsule": toolbar,
        "small_capsule": _load_card(args.small_card.resolve()),
        "large_capsule": _load_card(args.large_card.resolve()),
    }
    spreads = list(dict.fromkeys(args.spreads))
    candidates = {
        scene_id: {
            spread: _settings_for_scene(toolbar, scene_cards[scene_id], spread)
            for spread in spreads
        }
        for scene_id in SCENES
    }
    out = args.out.resolve()
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True)
    scene_rows = {
        scene_id: _evaluate_scene(
            scene_id=scene_id,
            candidates=candidates[scene_id],
            args=args,
            out=out,
        )
        for scene_id in SCENES
    }

    def median(rows: list[dict], key: str) -> float:
        values = sorted(float(row[key]) for row in rows)
        middle = len(values) // 2
        if len(values) % 2:
            return values[middle]
        return (values[middle - 1] + values[middle]) / 2.0

    by_spread = {}
    for spread in spreads:
        toolbar_rows = scene_rows["toolbar_capsule"][spread]
        toolbar_errors = {
            key: median([{"value": row["errors"][key]} for row in toolbar_rows], "value")
            for key in ("shape", "combined", "flow")
        }
        scene_summary = {}
        for scene_id in SCENES:
            rows = scene_rows[scene_id][spread]
            scene_summary[scene_id] = {
                "scoreMedian": median(rows, "score"),
                "directMae8BitMedian": median(rows, "directMae8Bit"),
                "errorsMedian": {
                    key: median(
                        [{"value": row["errors"][key]} for row in rows], "value"
                    )
                    for key in ("shape", "combined", "flow")
                },
                "rows": rows,
            }
        small_errors = scene_summary["small_capsule"]["errorsMedian"]
        large_errors = scene_summary["large_capsule"]["errorsMedian"]
        by_spread[str(spread)] = {
            "toolbar": scene_summary["toolbar_capsule"],
            "small_capsule": scene_summary["small_capsule"],
            "large_capsule": scene_summary["large_capsule"],
            "toolbarErrors": toolbar_errors,
            "smallCombinedWithin125x": small_errors["combined"]
            <= toolbar_errors["combined"] * 1.25,
            "largeCombinedWithin125x": large_errors["combined"]
            <= toolbar_errors["combined"] * 1.25,
            "smallFlowWithin125x": small_errors["flow"]
            <= toolbar_errors["flow"] * 1.25,
            "largeFlowWithin125x": large_errors["flow"]
            <= toolbar_errors["flow"] * 1.25,
        }
    summary = {
        "schemaVersion": 1,
        "evidenceRole": "shared-refraction-spread-grid",
        "sceneGeometrySource": {
            scene_id: str(path.resolve())
            for scene_id, path in {
                "toolbar_capsule": args.toolbar_card,
                "small_capsule": args.small_card,
                "large_capsule": args.large_card,
            }.items()
        },
        "repetitions": args.repetitions,
        "spreads": spreads,
        "results": by_spread,
    }
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
