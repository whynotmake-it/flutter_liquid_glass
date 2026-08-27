#!/usr/bin/env python3
"""Online settings optimization against the pinned Apple reference.

One persistent Flutter session; each iteration hot-reloads a small local
neighborhood of parameter values, measures the comparator loss, and moves to
the best candidate. References are never touched: recapture them only via
`bash apple/capture.sh` (FORCE_REFERENCE=1) or `python3 run.py`.

    python3 optimize.py --scene scenes/toolbar_capsule.json --max-iters 8
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
COMPARE = ROOT / "compare"
sys.path.insert(0, str(COMPARE))

from apple_match.hotloop import (  # noqa: E402
    CaptureSession,
    DEFAULT_AXES,
    Evaluator,
    PINNED_DEVICE_UDID,
    coordinate_descent,
    load_reference_probes,
    scene_crop,
)
from apple_match.hotloop.evaluate import simctl  # noqa: E402
from apple_match.schema import validate_scene  # noqa: E402

FLUTTER_PROJECT = ROOT / "flutter"


def device_metadata(udid: str) -> dict:
    """Runtime identifier and device-type name for a simulator UDID."""
    devices = json.loads(simctl("list", "devices", "-j"))["devices"]
    for runtime, entries in devices.items():
        for entry in entries:
            if entry.get("udid") == udid:
                types = json.loads(simctl("list", "devicetypes", "-j"))[
                    "devicetypes"
                ]
                name = next(
                    (
                        t["name"]
                        for t in types
                        if t["identifier"] == entry.get("deviceTypeIdentifier")
                    ),
                    None,
                )
                return {"runtimeIdentifier": runtime, "device": name}
    return {}


def compare_best(reference: Path, candidate: Path, output: Path, settings: Path, scene: Path):
    subprocess.run(
        [
            sys.executable,
            "-m",
            "apple_match.cli",
            "--reference",
            str(reference),
            "--candidate",
            str(candidate),
            "--output",
            str(output),
            "--settings",
            str(settings),
            "--scene",
            str(scene),
        ],
        check=True,
        cwd=COMPARE,
    )
    return json.loads((output / "scorecard.json").read_text())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--udid", default=os.environ.get("IOS_27_UDID"))
    parser.add_argument("--scene", type=Path, default=ROOT / "scenes/toolbar_capsule.json")
    parser.add_argument("--reference-set", default="ios27-iphone17pro-ground-truth-v2/slider-000")
    parser.add_argument("--baseline", type=Path, default=ROOT / "settings/baseline.json")
    parser.add_argument("--axes", type=Path, help="JSON object of axis -> ordered values")
    parser.add_argument("--max-iters", type=int, default=8)
    parser.add_argument("--settle-frames", type=int, default=4)
    parser.add_argument("--out", type=Path, default=ROOT / "out/optimize")
    args = parser.parse_args()
    if not args.udid:
        parser.error("--udid or IOS_27_UDID is required")
    args.scene = args.scene.resolve()
    args.baseline = args.baseline.resolve()
    args.out = args.out.resolve()

    scene = validate_scene(args.scene, ROOT / "scenes/schema.json")
    reference = ROOT / "references" / args.reference_set / scene["id"]
    metadata_path = reference / "metadata.json"
    if not metadata_path.exists():
        raise SystemExit(
            f"Missing pinned reference: {reference}. The optimizer never "
            "captures references; run `python3 run.py` first."
        )
    metadata = json.loads(metadata_path.read_text())
    if args.udid != PINNED_DEVICE_UDID or metadata.get("udid") != args.udid:
        raise SystemExit(
            f"References and candidates must use pinned simulator "
            f"{PINNED_DEVICE_UDID}; got {args.udid}."
        )
    device_meta = device_metadata(args.udid)
    for key in ("runtimeIdentifier", "device"):
        if metadata.get(key) != device_meta.get(key):
            raise SystemExit(
                f"Reference set is pinned to {metadata.get(key)}, but --udid "
                f"{args.udid} is {device_meta.get(key)}. Recapture references "
                "with `python3 run.py` for this device class."
            )
    baseline = json.loads(args.baseline.read_text())
    axes = json.loads(args.axes.read_text()) if args.axes else DEFAULT_AXES
    flutter_bin = os.environ.get(
        "FLUTTER_BIN", str(Path.home() / "fvm/versions/3.47.1/bin/flutter")
    )
    env = os.environ.copy()
    env["PATH"] = f"{ROOT / 'compat/bin'}:{env['PATH']}"

    args.out.mkdir(parents=True, exist_ok=True)
    crop = scene_crop(scene)
    reference_probes = load_reference_probes(reference, crop)

    started = time.monotonic()
    timings = []
    with CaptureSession(
        udid=args.udid,
        flutter_bin=flutter_bin,
        flutter_project=FLUTTER_PROJECT,
        scene_path=args.scene,
        work_dir=args.out / "session",
        env=env,
    ) as session:
        evaluator = Evaluator(
            session=session,
            reference=reference_probes,
            crop=crop,
            capture_dir=args.out / "last",
            settle_frames=args.settle_frames,
        )

        def timed_evaluate(params):
            eval_started = time.monotonic()
            loss = evaluator.evaluate(params)
            timings.append(time.monotonic() - eval_started)
            return loss

        def on_step(row):
            marker = "*" if row["isBest"] else " "
            print(
                f"[it {row['iteration']}]{marker} loss={row['loss']:.4f} "
                f"(score={100.0 - row['loss']:.4f})",
                flush=True,
            )

        result = coordinate_descent(
            timed_evaluate, baseline, axes, max_iters=args.max_iters, on_step=on_step
        )

        # Re-render the best params into out/optimize/best for evidence and a
        # full comparator scorecard.
        best_dir = args.out / "best"
        evaluator.capture_dir = best_dir
        best_loss = evaluator.evaluate(result["bestParams"])
        settings_path = best_dir / "settings.json"
        settings_path.write_text(json.dumps(result["bestParams"], indent=2) + "\n")
        scorecard = compare_best(reference, best_dir, best_dir, settings_path, args.scene)

    summary = {
        "baseline": baseline,
        "baselineLoss": result["history"][0]["loss"],
        "bestParams": result["bestParams"],
        "bestLoss": result["bestLoss"],
        "bestScore": scorecard["score"],
        "rerenderedBestLoss": best_loss,
        "iterations": result["history"][-1]["iteration"],
        "evaluations": evaluator.evaluations,
        "history": result["history"],
        "timing": {
            "startupSeconds": session.startup_seconds,
            "evalSeconds": timings,
            "meanEvalSeconds": sum(timings) / len(timings) if timings else None,
            "totalSeconds": time.monotonic() - started,
        },
    }
    (args.out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(
        f"best loss {result['bestLoss']:.4f} (score {scorecard['score']:.4f}) "
        f"after {evaluator.evaluations} evals; best params -> {best_dir / 'settings.json'}"
    )


if __name__ == "__main__":
    main()
