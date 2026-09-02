#!/usr/bin/env python3
"""Fit one material axis against isolated full-face Apple probes."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
from pathlib import Path

from solid_color_metrics import measure_solid_palette


ROOT = Path(__file__).resolve().parent


def values(raw: str) -> list[float]:
    return [float(value) for value in raw.split(",")]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scene", type=Path, required=True)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--base-settings", type=Path, required=True)
    parser.add_argument("--axis", required=True)
    parser.add_argument("--values", required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    scene = json.loads(args.scene.read_text())
    base = json.loads(args.base_settings.read_text())
    probe_ids = " ".join(probe["id"] for probe in scene["probes"])
    args.out.mkdir(parents=True, exist_ok=True)
    rows = []
    for value in values(args.values):
        identifier = f"{args.axis}-{value:g}".replace(".", "p")
        settings = dict(base)
        if args.axis == "tintLuminance":
            settings.update({"tintRed": value, "tintGreen": value, "tintBlue": value})
        else:
            settings[args.axis] = value
        settings_path = args.out / f"{identifier}.settings.json"
        candidate = args.out / identifier
        settings_path.write_text(json.dumps(settings, indent=2) + "\n")
        env = os.environ | {
            "CAPTURE_PROBES": probe_ids,
            "SETTINGS_FILE": str(settings_path.resolve()),
            "SCENE_FILE": str(args.scene.resolve()),
            "CANDIDATE_OUT": str(candidate.resolve()),
        }
        print(f"[{value:g}] capturing", flush=True)
        subprocess.run(["bash", "flutter/host_capture.sh"], cwd=ROOT, env=env, check=True)
        metrics = measure_solid_palette(scene, args.reference, candidate)
        score = (
            metrics["objective"]["paletteMeanFaceMae8Bit"] * 0.55
            + metrics["objective"]["paletteWorstFaceMae8Bit"] * 0.25
            + metrics["objective"]["paletteMeanLuminanceMae8Bit"] * 0.10
            + metrics["objective"]["paletteMeanSaturationMae8Bit"] * 0.10
        )
        rows.append({"value": value, "score": score, "metrics": metrics, "candidate": str(candidate)})
    rows.sort(key=lambda row: row["score"])
    (args.out / "summary.json").write_text(json.dumps({"axis": args.axis, "candidates": rows}, indent=2) + "\n")
    for row in rows:
        print(row["value"], row["score"], row["metrics"]["objective"])


if __name__ == "__main__":
    main()
