#!/usr/bin/env python3
"""Multi-seed candidate scan for one scene in a persistent Flutter session.

Evaluates hand-picked starting points (the current renderer's plausible
material basins) and reports the best. Used to establish a fair pre-redesign
baseline score for scenes whose material differs strongly from the toolbar
seed, e.g. the loupe.
"""

from __future__ import annotations

import argparse
import itertools
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
from apple_match.metrics import read_rgb  # noqa: E402

REFERENCE_SET = "ios27-iphone17pro-light"


def evenly_sample_seeds(seeds: list[dict], max_seeds: int | None) -> list[dict]:
    """Select a deterministic, range-covering subset for a bounded smoke scan."""
    if max_seeds is None or max_seeds >= len(seeds):
        return seeds
    if max_seeds < 1:
        raise ValueError("max_seeds must be at least 1")
    if max_seeds == 1:
        return [seeds[0]]
    last = len(seeds) - 1
    indices = [round(index * last / (max_seeds - 1)) for index in range(max_seeds)]
    return [seeds[index] for index in indices]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--udid", default=os.environ.get("IOS_27_UDID"))
    parser.add_argument(
        "--flutter-bin",
        default=os.environ.get(
            "FLUTTER_BIN", str(Path.home() / "fvm/versions/3.47.1/bin/flutter")
        ),
    )
    parser.add_argument("--scene-id", default="loupe")
    parser.add_argument("--baseline", type=Path, default=ROOT / "settings/baseline.json")
    parser.add_argument("--out", type=Path, default=ROOT / "out/seed-scan")
    parser.add_argument(
        "--max-seeds",
        type=int,
        help="Evaluate an evenly spaced subset of the full grid (partial scan)",
    )
    parser.add_argument(
        "--profile-gate",
        action="store_true",
        help="Run the bounded loupe profile gate (E={25,35,45,55}, spread={.75,1})",
    )
    args = parser.parse_args()
    if not args.udid:
        parser.error("--udid or IOS_27_UDID is required")

    scene_path = ROOT / "scenes" / f"{args.scene_id}.json"
    scene = json.loads(scene_path.read_text())
    crop = scene_crop(scene)
    reference_dir = ROOT / "references" / REFERENCE_SET / scene["id"]
    reference = load_reference_probes(reference_dir, crop)
    base = json.loads(args.baseline.resolve().read_text())
    # Every scene has its own logical shape. Never reuse the toolbar geometry
    # for the loupe: doing so compares the right material against the wrong
    # silhouette and makes the baseline meaningless.
    shape = scene["shape"]
    base.update(
        {
            "shapeWidth": shape["width"],
            "shapeHeight": shape["height"],
            "shapeOffsetX": 0.0,
            "shapeOffsetY": 0.0,
            "cornerRadius": shape["cornerRadius"],
            "shapeProfile": "roundedRectangle",
        }
    )

    all_seeds = []
    if args.profile_gate:
        seed_specs = (
            (0.05, 0.0, 12.0, edge, spread)
            for edge, spread in itertools.product([25.0, 35.0, 45.0, 55.0], [0.75, 1.0])
        )
    else:
        seed_specs = (
            (
                alpha,
                frost,
                thickness,
                8.0 * thickness * (max(0.0, ri * ri - 1.0) ** 0.5),
                1.0,
            )
            for alpha, frost, thickness, ri in itertools.product(
                [0.05, 0.12, 0.25, 0.4],
                [0.0, 2.0, 7.0],
                [12.0, 20.0, 28.0],
                [1.08, 1.2, 1.6, 2.5],
            )
        )
    for alpha, frost, thickness, edge_refraction, spread in seed_specs:
        seed = dict(base)
        seed.update(
            {
                "tintAlpha": alpha,
                "frost": frost,
                "thickness": thickness,
                "edgeRefraction": edge_refraction,
                "refractionSpread": spread,
                "contourStrength": 0.35,
                "contourWidth": 1.0,
                "highlight": 0.5,
            }
        )
        all_seeds.append(seed)
    try:
        seeds = evenly_sample_seeds(all_seeds, args.max_seeds)
    except ValueError as error:
        parser.error(str(error))

    out = args.out.resolve()
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True)
    env = os.environ.copy()
    env["PATH"] = f"{ROOT / 'compat/bin'}:{env['PATH']}"

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
            f"SEED_SCAN_READY udid={args.udid} "
            f"startupSeconds={session.startup_seconds:.2f}",
            flush=True,
        )
        rows = []
        for index, seed in enumerate(seeds):
            loss = float(evaluator.evaluate(seed))
            result = evaluator.last_result
            score = float(result.score)
            rows.append(
                {
                    "index": index,
                    "score": score,
                    "loss": loss,
                    "settings": seed,
                    "directMae8Bit": result.details[
                        "directPixelMeanAbsoluteError8Bit"
                    ],
                }
            )
            print(
                f"SEED {index:02d} score={score:.4f} "
                f"alpha={seed['tintAlpha']} frost={seed['frost']} "
                f"thickness={seed['thickness']} edge={seed['edgeRefraction']:.2f} "
                f"spread={seed['refractionSpread']}",
                flush=True,
            )

    rows.sort(key=lambda row: row["score"], reverse=True)
    (out / "scan.json").write_text(json.dumps(rows, indent=2) + "\n")
    best_dir = out / "best"
    best_dir.mkdir()
    (best_dir / "settings.json").write_text(
        json.dumps(rows[0]["settings"], indent=2) + "\n"
    )
    print(
        json.dumps(
            {
                "bestScore": rows[0]["score"],
                "best": rows[0]["settings"],
                "evaluatedSeedCount": len(seeds),
                "totalSeedCount": len(all_seeds),
                "partial": len(seeds) != len(all_seeds),
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
