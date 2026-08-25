#!/usr/bin/env python3
"""Multi-seed candidate scan for one scene in a persistent Flutter session.

Evaluates hand-picked starting points (the current renderer's plausible
material basins) and reports the best. Used to fit scene-specific material
basins such as the loupe's ordinary glass edge/refraction settings.
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
    PINNED_DEVICE_NAME,
    PINNED_DEVICE_UDID,
    load_reference_probes,
    scene_crop,
)
from apple_match.metrics import WEIGHTS, read_rgb  # noqa: E402

REFERENCE_SET = "ios27-iphone17pro-light"
PINNED_RUNTIME = "iOS 27.0 (24A5408d)"
PINNED_RUNTIME_IDENTIFIER = "com.apple.CoreSimulator.SimRuntime.iOS-27-0"


def load_reference_metadata(
    path: Path, scene_id: str, candidate_udid: str | None = None
) -> dict:
    """Load and validate metadata for the pinned Apple reference set."""
    if not path.exists():
        raise ValueError(f"missing reference metadata: {path}")
    metadata = json.loads(path.read_text())
    required = (
        "runtime",
        "runtimeIdentifier",
        "udid",
        "device",
        "appearance",
        "api",
        "medianFrameCount",
        "scene",
    )
    missing = [key for key in required if key not in metadata]
    if missing:
        raise ValueError(f"reference metadata is missing {missing}: {path}")
    expected = {
        "runtime": PINNED_RUNTIME,
        "runtimeIdentifier": PINNED_RUNTIME_IDENTIFIER,
        "udid": PINNED_DEVICE_UDID,
        "scene": scene_id,
        "appearance": "light",
        "reduceMotion": True,
        "reduceTransparency": False,
    }
    mismatches = {
        key: {"expected": value, "actual": metadata.get(key)}
        for key, value in expected.items()
        if metadata.get(key) != value
    }
    if mismatches:
        raise ValueError(f"reference metadata is not pinned: {mismatches}")
    if metadata.get("device") != "iPhone 17 Pro":
        raise ValueError(
            "reference metadata device is not pinned to iPhone 17 Pro: "
            f"{metadata.get('device')}"
        )
    if not str(metadata.get("api", "")).startswith(
        "iOS 27 system text-selection loupe"
    ):
        raise ValueError(f"reference metadata API is not the system loupe: {metadata.get('api')}")
    if metadata.get("medianFrameCount", 0) < 3:
        raise ValueError("reference metadata medianFrameCount must be at least 3")
    if candidate_udid is not None and candidate_udid != metadata["udid"]:
        raise ValueError(
            "candidate UDID does not match reference metadata: "
            f"{candidate_udid} != {metadata['udid']}"
        )
    return metadata


def validate_reference_assets(reference_dir: Path, scene_id: str) -> dict:
    """Validate metadata and decode all four reference probes without simctl."""
    metadata_path = reference_dir / "metadata.json"
    metadata = load_reference_metadata(metadata_path, scene_id)
    for probe in "ABCD":
        path = reference_dir / f"{probe}.png"
        if not path.exists():
            raise ValueError(f"missing reference probe {probe}: {path}")
        read_rgb(path)
    return metadata


def apply_scene_geometry(scene: dict, baseline: dict) -> dict:
    """Copy the scene's effective shape into a candidate settings vector."""
    shape = scene["shape"]
    settings = dict(baseline)
    settings.update(
        {
            "shapeWidth": shape["width"],
            "shapeHeight": shape["height"],
            "shapeOffsetX": 0.0,
            "shapeOffsetY": 0.0,
            "cornerRadius": shape["cornerRadius"],
            "shapeProfile": "roundedRectangle",
        }
    )
    return settings


def validate_scene_geometry(scene: dict, settings: dict) -> None:
    expected = apply_scene_geometry(scene, {})
    for key in (
        "shapeWidth",
        "shapeHeight",
        "shapeOffsetX",
        "shapeOffsetY",
        "cornerRadius",
        "shapeProfile",
    ):
        if settings.get(key) != expected[key]:
            raise ValueError(
                f"seed geometry drifted for {key}: "
                f"{settings.get(key)} != {expected[key]}"
            )


def search_space(seeds: list[dict], profile_gate: bool) -> dict:
    axes = (
        "tintAlpha",
        "frost",
        "thickness",
        "edgeRefraction",
        "refractionSpread",
    )
    return {
        "mode": "profile-gate" if profile_gate else "ordinary-seed-grid",
        "axes": {
            key: sorted({seed[key] for seed in seeds})
            for key in axes
        },
    }


def scan_summary(
    *,
    rows: list[dict],
    all_seed_settings: list[dict],
    all_seed_count: int,
    scene_id: str,
    scene_path: Path,
    baseline_path: Path,
    reference_metadata: dict,
    reference_metadata_path: Path,
    out: Path,
    profile_gate: bool,
    scene_shape: dict,
) -> dict:
    """Build a self-describing loupe example-composition result."""
    if not rows:
        raise ValueError("seed scan produced no rows")
    best = rows[0]
    return {
        "schemaVersion": 2,
        "evidenceRole": "loupe-example-composition-seed-scan",
        "comparisonContract": {
            "s0Status": "retired",
            "reason": (
                "Intentional pre-shader RawMagnifier enlargement is evaluated "
                "as example composition, not as a renderer-only S0."
            ),
        },
        "scene": scene_id,
        "sceneShape": scene_shape,
        "scenePath": str(scene_path.resolve()),
        "baselinePath": str(baseline_path.resolve()),
        "referenceSet": REFERENCE_SET,
        "referenceMetadataPath": str(reference_metadata_path.resolve()),
        "referenceMetadata": reference_metadata,
        "referenceAssets": {
            probe: str((reference_metadata_path.parent / f"{probe}.png").resolve())
            for probe in "ABCD"
        },
        "targetUdid": reference_metadata["udid"],
        "pinnedSimulator": {
            "name": PINNED_DEVICE_NAME,
            "udid": PINNED_DEVICE_UDID,
        },
        "composition": {
            "preShaderMagnification": True,
            "magnificationScale": 1.55,
            "shaderLevelMagnification": False,
        },
        "search": search_space(all_seed_settings, profile_gate),
        "metric": {"name": "paired-AB-optical-flow-score", "weights": WEIGHTS},
        "best": {
            "score": best["score"],
            "loss": best["loss"],
            "directMae8Bit": best["directMae8Bit"],
            "settings": best["settings"],
            "registrationStatus": best.get("registrationStatus"),
            "settingsPath": str((out / "best/settings.json").resolve()),
            "framesPath": str((out / "best/frames").resolve()),
        },
        "evaluatedSeedCount": len(rows),
        "totalSeedCount": all_seed_count,
        "partial": len(rows) != all_seed_count,
        "scanPath": str((out / "scan.json").resolve()),
    }


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
        "--spread",
        type=float,
        default=0.0,
        help=(
            "Profile reach for the ordinary seed scan; defaults to 0 for a "
            "fair pre-redesign baseline"
        ),
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
    reference_metadata_path = reference_dir / "metadata.json"
    try:
        reference_metadata = load_reference_metadata(
            reference_metadata_path, scene["id"], candidate_udid=args.udid
        )
    except ValueError as error:
        parser.error(str(error))
    try:
        validate_reference_assets(reference_dir, scene["id"])
    except ValueError as error:
        parser.error(str(error))
    reference = load_reference_probes(reference_dir, crop)
    base = json.loads(args.baseline.resolve().read_text())
    # Every scene has its own logical shape. Never reuse the toolbar geometry
    # for the loupe: doing so compares the right material against the wrong
    # silhouette and makes the baseline meaningless.
    base = apply_scene_geometry(scene, base)

    all_seeds = []
    if args.profile_gate:
        seed_specs = (
            (0.05, 0.0, 12.0, edge, spread)
            for edge, spread in itertools.product(
                [25.0, 35.0, 45.0, 55.0], [0.75, 1.0]
            )
        )
    else:
        if not 0.0 <= args.spread <= 1.0:
            parser.error("--spread must be between 0 and 1")
        seed_specs = (
            (
                alpha,
                frost,
                thickness,
                8.0 * thickness * (max(0.0, ri * ri - 1.0) ** 0.5),
                args.spread,
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
    for seed in all_seeds:
        validate_scene_geometry(scene, seed)
    try:
        seeds = evenly_sample_seeds(all_seeds, args.max_seeds)
    except ValueError as error:
        parser.error(str(error))

    out = args.out.resolve()
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True)
    (out / "reference_metadata.json").write_text(
        json.dumps(reference_metadata, indent=2) + "\n"
    )
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
        best_score = float("-inf")
        best_live = out / "best" / "frames"
        best_live.mkdir(parents=True, exist_ok=True)
        for index, seed in enumerate(seeds):
            loss = float(evaluator.evaluate(seed))
            result = evaluator.last_result
            score = float(result.score)
            if score > best_score:
                best_score = score
                for probe in "ABCD":
                    live_frame = out / "live" / f"{probe}.png"
                    if live_frame.exists():
                        shutil.copy2(live_frame, best_live / f"{probe}.png")
            rows.append(
                {
                    "index": index,
                    "score": score,
                    "loss": loss,
                    "settings": seed,
                    "directMae8Bit": result.details[
                        "directPixelMeanAbsoluteError8Bit"
                    ],
                    "registrationStatus": "candidate-capture-scored",
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
    best_dir.mkdir(exist_ok=True)
    (best_dir / "settings.json").write_text(
        json.dumps(rows[0]["settings"], indent=2) + "\n"
    )
    summary = scan_summary(
        rows=rows,
        all_seed_settings=all_seeds,
        all_seed_count=len(all_seeds),
        scene_id=scene["id"],
        scene_path=scene_path,
        baseline_path=args.baseline,
        reference_metadata=reference_metadata,
        reference_metadata_path=reference_metadata_path,
        out=out,
        profile_gate=args.profile_gate,
        scene_shape=scene["shape"],
    )
    (best_dir / "scorecard.json").write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "source": "seed_scan",
                "evidenceRole": summary["evidenceRole"],
                "score": rows[0]["score"],
                "loss": rows[0]["loss"],
                "measurements": {
                    "directPixelMeanAbsoluteError8Bit": rows[0]["directMae8Bit"]
                },
                "settings": rows[0]["settings"],
                "referenceMetadata": reference_metadata,
            },
            indent=2,
        )
        + "\n"
    )
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
