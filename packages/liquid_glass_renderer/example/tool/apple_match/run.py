#!/usr/bin/env python3
"""Capture references/candidates, search settings, and emit the best scorecard."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
COMPARE = ROOT / "compare"
sys.path.insert(0, str(COMPARE))

from apple_match.schema import validate_scene  # noqa: E402


def run(command, *, env=None, cwd=ROOT):
    subprocess.run(command, check=True, cwd=cwd, env=env)


def compare(reference: Path, candidate: Path, output: Path, settings: Path):
    run(
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
            str(ROOT / "scenes/toolbar_capsule.json"),
        ],
        cwd=COMPARE,
    )
    return json.loads((output / "scorecard.json").read_text())


def capture_flutter(
    udid: str,
    settings: Path,
    output: Path,
    *,
    prepare_app: bool,
    frames: int = 1,
):
    env = os.environ.copy()
    env.update(
        IOS_27_UDID=udid,
        SETTINGS_FILE=str(settings),
        CANDIDATE_OUT=str(output),
        PREPARE_APP="1" if prepare_app else "0",
        CAPTURE_FRAMES=str(frames),
    )
    run(["bash", str(ROOT / "flutter/capture.sh")], env=env, cwd=ROOT / "flutter")


def capture_matches(output: Path, settings: dict, *, frames: int = 1) -> bool:
    settings_path = output / "settings.json"
    return (
        settings_path.exists()
        and json.loads(settings_path.read_text()) == settings
        and all((output / f"{probe}.png").exists() for probe in "ABCD")
        and all(
            (output / "frames" / f"{probe}_{frame}.png").exists()
            for probe in "ABCD"
            for frame in range(1, frames + 1)
        )
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--udid", default=os.environ.get("IOS_27_UDID"))
    parser.add_argument("--reference-set", default="ios27-iphone17pro-light")
    parser.add_argument("--skip-reference-capture", action="store_true")
    parser.add_argument("--reuse-captures", action="store_true")
    args = parser.parse_args()
    if not args.udid:
        parser.error("--udid or IOS_27_UDID is required")

    validate_scene(ROOT / "scenes/toolbar_capsule.json", ROOT / "scenes/schema.json")
    reference = ROOT / "references" / args.reference_set / "toolbar_capsule"
    if not reference.exists() and not args.skip_reference_capture:
        env = os.environ.copy()
        env.update(IOS_27_UDID=args.udid, REFERENCE_SET=args.reference_set)
        run(["bash", str(ROOT / "apple/capture.sh")], env=env)
    if not reference.exists():
        raise SystemExit(f"Missing pinned reference: {reference}")

    out = ROOT / "out"
    staged = out / "stages"
    baseline_settings = ROOT / "settings/baseline.json"
    baseline = json.loads(baseline_settings.read_text())
    baseline_capture = staged / "baseline/capture"
    if not (
        args.reuse_captures
        and capture_matches(baseline_capture, baseline, frames=3)
    ):
        capture_flutter(
            args.udid,
            baseline_settings,
            baseline_capture,
            prepare_app=True,
            frames=3,
        )
    baseline_card = compare(
        reference, baseline_capture, staged / "baseline", baseline_settings
    )

    current = dict(baseline)
    current.update(
        {
            "thickness": 0.0,
            "blur": 0.0,
            "lightIntensity": 0.0,
            "ambientStrength": 0.0,
            "refractiveIndex": 1.0,
            "saturation": 1.0,
            "chromaticAberration": 0.0,
        }
    )
    current_capture = None
    stages_config = json.loads((ROOT / "settings/stages.json").read_text())
    stage_summaries = {}
    for stage_name in ("shape", "refraction", "blurMtf", "tintColor", "highlight"):
        stage_root = staged / stage_name
        neutral_settings = stage_root / "baseline/settings.json"
        neutral_settings.parent.mkdir(parents=True, exist_ok=True)
        neutral_settings.write_text(json.dumps(current, indent=2) + "\n")
        if current_capture is None:
            current_capture = stage_root / "baseline/capture"
            capture_flutter(
                args.udid,
                neutral_settings,
                current_capture,
                prepare_app=False,
            )
        stage_baseline = compare(
            reference,
            current_capture,
            stage_root / "baseline",
            neutral_settings,
        )
        stage_key = stage_name
        best_card = stage_baseline
        best_settings_data = current
        best_capture = current_capture
        for index, overrides in enumerate(stages_config[stage_name]):
            candidate = dict(current)
            candidate.update(overrides)
            settings_path = stage_root / "candidates" / f"{index:03d}/settings.json"
            settings_path.parent.mkdir(parents=True, exist_ok=True)
            settings_path.write_text(json.dumps(candidate, indent=2) + "\n")
            capture = stage_root / "candidates" / f"{index:03d}/capture"
            if not (
                args.reuse_captures
                and capture_matches(capture, candidate)
            ):
                capture_flutter(
                    args.udid,
                    settings_path,
                    capture,
                    prepare_app=False,
                )
            card = compare(
                reference,
                capture,
                stage_root / "candidates" / f"{index:03d}",
                settings_path,
            )
            candidate_score = card["measurements"]["stageScores"][stage_key]
            best_score = best_card["measurements"]["stageScores"][stage_key]
            if candidate_score > best_score:
                best_card = card
                best_settings_data = candidate
                best_capture = capture
        best_dir = stage_root / "best"
        best_dir.mkdir(parents=True, exist_ok=True)
        (best_dir / "settings.json").write_text(
            json.dumps(best_settings_data, indent=2) + "\n"
        )
        compare(
            reference,
            best_capture,
            best_dir,
            best_dir / "settings.json",
        )
        stage_summaries[stage_name] = {
            "baselineStageScore": stage_baseline["measurements"]["stageScores"][
                stage_key
            ],
            "bestStageScore": best_card["measurements"]["stageScores"][stage_key],
            "baselineOverallScore": stage_baseline["score"],
            "bestOverallScore": best_card["score"],
            "bestSettings": best_settings_data,
            "holdoutScore": best_card["measurements"]["stageScores"]["holdout"],
        }
        current = best_settings_data
        current_capture = best_capture

    final_settings = staged / "final/settings.json"
    final_settings.parent.mkdir(parents=True, exist_ok=True)
    final_settings.write_text(json.dumps(current, indent=2) + "\n")
    final_capture = staged / "final/capture"
    capture_flutter(
        args.udid,
        final_settings,
        final_capture,
        prepare_app=False,
        frames=3,
    )
    final_card = compare(reference, final_capture, staged / "final", final_settings)

    (out / "best").mkdir(parents=True, exist_ok=True)
    shutil.copy2(final_settings, out / "best/settings.json")
    compare(reference, final_capture, out / "best", out / "best/settings.json")
    improvement = final_card["score"] - baseline_card["score"]
    baseline_uncertainty = baseline_card["temporalScore"]["confidence95HalfWidth"]
    best_uncertainty = final_card["temporalScore"]["confidence95HalfWidth"]
    improvement_uncertainty = (
        baseline_uncertainty**2 + best_uncertainty**2
    ) ** 0.5
    summary = {
        "baselineScore": baseline_card["score"],
        "bestScore": final_card["score"],
        "absoluteImprovement": improvement,
        "relativeImprovementPercent": (
            100 * improvement / baseline_card["score"] if baseline_card["score"] else None
        ),
        "improvementConfidence95HalfWidth": improvement_uncertainty,
        "relativeImprovementConfidence95HalfWidthPercent": (
            100 * improvement_uncertainty / baseline_card["score"]
            if baseline_card["score"]
            else None
        ),
        "bestCandidate": str(final_capture),
        "stages": stage_summaries,
        "registration": final_card["registration"],
        "holdoutScore": final_card["measurements"]["stageScores"]["holdout"],
        "uncertaintyMethod": "Propagation of three-frame temporal score intervals.",
    }
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
