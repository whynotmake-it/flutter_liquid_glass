#!/usr/bin/env python3
"""One-shot scorecard eval: evaluate settings dicts inside one live session.

Usage:
  PYTHONPATH=compare .venv/bin/python eval_once.py --scene toolbar_capsule \
      --settings settings/baseline.json [more.json ...] --out out/eval
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
COMPARE = ROOT / "compare"
sys.path.insert(0, str(COMPARE))

from apple_match.hotloop import (  # noqa: E402
    CaptureSession,
    Evaluator,
    load_reference_probes,
    scene_crop,
)
from apple_match.geometry import apply_settings_geometry  # noqa: E402
from apple_match.hotloop.evaluate import (  # noqa: E402
    atomic_write_json,
    read_json_file,
    simctl,
    validate_settings,
)
from apple_match.scene import load_scene, metric_family, probe_ids  # noqa: E402
from apple_match.solid_color import measure_solid_palette  # noqa: E402

REFERENCE_SET = "ios27-iphone17pro-reduce-motion-off/slider-000"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--udid", default=os.environ.get("IOS_27_UDID"))
    parser.add_argument(
        "--flutter-bin",
        default=os.environ.get(
            "FLUTTER_BIN",
            str(ROOT.parents[4] / ".fvm/flutter_sdk/bin/flutter"),
        ),
    )
    parser.add_argument("--scene", default="toolbar_capsule")
    parser.add_argument("--reference", type=Path)
    parser.add_argument("--settings", type=Path, nargs="+", required=True)
    parser.add_argument("--out", type=Path, default=ROOT / "out/eval")
    args = parser.parse_args()
    if not args.udid:
        parser.error("--udid or IOS_27_UDID is required")

    scene_path = ROOT / "scenes" / f"{args.scene}.json"
    scene = load_scene(scene_path)
    probes = probe_ids(scene)
    crop = scene_crop(scene)
    family = metric_family(scene)
    reference_dir = (
        args.reference.resolve()
        if args.reference
        else ROOT / "references" / REFERENCE_SET / scene["id"]
    )
    reference = (
        load_reference_probes(reference_dir, crop, probes)
        if family == "scorecard"
        else None
    )
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    global _REFERENCE_DIR
    _REFERENCE_DIR = reference_dir

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
        evaluator = (
            Evaluator(
                session=session,
                reference=reference,
                crop=crop,
                scene=scene,
                probes=probes,
                capture_dir=out / "live",
            )
            if family == "scorecard"
            else None
        )
        print(
            f"SESSION_READY startup={session.startup_seconds:.1f}s",
            flush=True,
        )
        for settings_path in args.settings:
            settings = json.loads(settings_path.read_text())
            validate_settings(settings)
            name = settings_path.stem
            capture = out / name
            capture.mkdir(parents=True, exist_ok=True)
            if family == "solidColor":
                report = _capture_solid(session, scene, probes, settings, capture)
                (capture / "solid_color.json").write_text(
                    json.dumps(report, indent=2) + "\n"
                )
                _print_solid(name, report)
                continue
            loss = evaluator.evaluate(settings)
            result = evaluator.last_result
            import shutil

            for probe in probes:
                shutil.copy2(
                    evaluator.capture_dir / f"{probe}.png",
                    capture / f"{probe}.png",
                )
            (capture / "scorecard.json").write_text(
                json.dumps(
                    {
                        "score": result.score,
                        "errors": result.errors,
                        "details": result.details,
                    },
                    indent=2,
                )
                + "\n"
            )
            print(
                f"{name}: score={result.score:.4f} loss={loss:.4f} "
                f"errors={json.dumps(result.errors)}",
                flush=True,
            )


_SERIAL = 0


def _capture_solid(session, scene, probes, settings, capture: Path) -> dict:
    """Screenshot each probe, then grade against the solid-palette measure."""
    global _SERIAL
    for probe in probes:
        _SERIAL += 1
        serial = _SERIAL
        payload = {
            "candidateId": f"eval-{serial:05d}",
            "probe": probe,
            "serial": serial,
            "settleFrames": 4,
            "settings": settings,
        }
        try:
            atomic_write_json(session.candidate_path, payload)
        except FileNotFoundError:
            session.refresh_paths()
            atomic_write_json(session.candidate_path, payload)
        status = session.session.request_settle(
            candidate_id=payload["candidateId"],
            probe=probe,
            serial=serial,
            read_status=lambda: read_json_file(session.status_path),
            settle_timeout=30.0,
            restart_timeout=90.0,
        )
        if status["reloadMode"] == "hotRestart":
            session.refresh_paths()
        simctl("io", session.udid, "screenshot", str(capture / f"{probe}.png"))
    adjusted = apply_settings_geometry(scene, settings)
    return measure_solid_palette(adjusted, _REFERENCE_DIR, capture)


_REFERENCE_DIR: Path = Path()


def _print_solid(name: str, report: dict) -> None:
    print(f"{name}: objective={json.dumps(report['objective'])}", flush=True)
    for probe, entry in report["color"].items():
        print(
            f"  {probe}: faceMae={entry['meanAbsoluteError8Bit']:.3f} "
            f"transmissionMae={entry['transmissionMae8Bit']:.3f} "
            f"lumDelta ref={entry['referenceLuminanceDelta8Bit']:.2f} "
            f"can={entry['candidateLuminanceDelta8Bit']:.2f} "
            f"satDelta ref={entry['referenceSaturationDelta']:.3f} "
            f"can={entry['candidateSaturationDelta']:.3f}",
            flush=True,
        )


if __name__ == "__main__":
    main()
