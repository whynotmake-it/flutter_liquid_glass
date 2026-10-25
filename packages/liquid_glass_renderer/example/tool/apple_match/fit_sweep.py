#!/usr/bin/env python3
"""Sweep capture + score helper for host-side parameter fits."""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
TOOL = ROOT
FLUTTER = os.environ.get(
    "FLUTTER_BIN",
    str(ROOT.parents[4] / ".fvm/flutter_sdk/bin/flutter"),
)


def run_sweep(scene: Path, sweep, out: Path, probes: list[str], fake=False):
    out.mkdir(parents=True, exist_ok=True)
    sweep_path = out / "sweep.json"
    sweep_path.write_text(json.dumps(sweep))
    cmd = [
        FLUTTER, "test",
        "--enable-impeller", "--enable-flutter-gpu", "--update-goldens",
        f"--dart-define=HOST_CAPTURE_SCENE={scene}",
        f"--dart-define=HOST_CAPTURE_SWEEP={sweep_path}",
        f"--dart-define=HOST_CAPTURE_OUT={out}",
        f"--dart-define=HOST_CAPTURE_PROBES={' '.join(probes)}",
        f"--dart-define=HOST_CAPTURE_FAKE={'true' if fake else 'false'}",
        "test/sweep_capture_test.dart",
    ]
    result = subprocess.run(cmd, cwd=TOOL / "flutter", capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stdout[-4000:])
        print(result.stderr[-4000:])
        raise SystemExit(f"sweep failed for {scene}")


def score(scene: Path, ref: Path, cand: Path, settings: Path, out: Path):
    out.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["PYTHONPATH"] = str(TOOL / "compare")
    cmd = [
        str(TOOL / "compare/.venv/bin/python"), "-m", "apple_match.cli",
        "--host-capture",
        "--reference", str(ref),
        "--candidate", str(cand),
        "--output", str(out),
        "--settings", str(settings),
        "--scene", str(scene),
    ]
    result = subprocess.run(cmd, cwd=TOOL, env=env, capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stdout[-2000:])
        print(result.stderr[-2000:])
        return None
    return json.loads((out / "scorecard.json").read_text())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--scene", type=Path, required=True)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--sweep", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--probes", default="A B C D")
    parser.add_argument("--fake", action="store_true")
    parser.add_argument("--no-run", action="store_true")
    args = parser.parse_args()
    probes = args.probes.split()
    sweep = json.loads(args.sweep.read_text())
    args.scene = args.scene.resolve()
    args.reference = args.reference.resolve()
    args.out = args.out.resolve()
    if not args.no_run:
        run_sweep(args.scene, sweep, args.out, probes, args.fake)
    rows = []
    for entry in sweep:
        name = entry["name"]
        cand = args.out / name
        if not (cand / f"{probes[0]}.png").exists():
            continue
        result = score(
            args.scene,
            args.reference,
            cand,
            cand / "settings.json",
            args.out / f"score-{name}",
        )
        if result is None:
            continue
        errs = result["errors"]
        rows.append((name, result["score"], errs))
        print(
            f"{name:24s} score {result['score']:7.3f}  "
            + " ".join(f"{k} {v:.4f}" for k, v in errs.items()),
            flush=True,
        )
    rows.sort(key=lambda row: row[1], reverse=True)
    print("\nBEST")
    for name, total, errs in rows[:10]:
        print(name, round(total, 3), {k: round(v, 4) for k, v in errs.items()})


if __name__ == "__main__":
    main()
