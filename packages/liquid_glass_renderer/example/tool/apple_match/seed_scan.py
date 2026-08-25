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
    args = parser.parse_args()
    if not args.udid:
        parser.error("--udid or IOS_27_UDID is required")

    scene_path = ROOT / "scenes" / f"{args.scene_id}.json"
    scene = json.loads(scene_path.read_text())
    crop = scene_crop(scene)
    reference_dir = ROOT / "references" / REFERENCE_SET / scene["id"]
    reference = load_reference_probes(reference_dir, crop)
    base = json.loads(args.baseline.resolve().read_text())

    all_seeds = []
    for alpha, blur, thickness, ri in itertools.product(
        [0.05, 0.12, 0.25, 0.4], [0.0, 2.0, 7.0], [12.0, 20.0, 28.0], [1.08, 1.2]
    ):
        seed = dict(base)
        seed.update(
            {
                "glassAlpha": alpha,
                "blur": blur,
                "thickness": thickness,
                "refractiveIndex": ri,
                "edgeAlpha": 0.35,
                "edgeWidth": 1.0,
                "lightIntensity": 0.5,
                "ambientStrength": 0.0,
                "faceShadingStrength": 0.0,
                "innerShadowStrength": 0.0,
                "bleedStrength": 0.25,
                "specularWrap": 0.35,
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
                f"alpha={seed['glassAlpha']} blur={seed['blur']} "
                f"thickness={seed['thickness']} ri={seed['refractiveIndex']}",
                flush=True,
            )

    rows.sort(key=lambda row: row["score"], reverse=True)
    (out / "scan.json").write_text(json.dumps(rows, indent=2) + "\n")
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
