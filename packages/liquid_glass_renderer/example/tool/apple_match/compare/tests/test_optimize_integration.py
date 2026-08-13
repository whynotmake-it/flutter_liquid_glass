"""End-to-end smoke test: two online candidates through one live session.

Gated behind APPLE_MATCH_SMOKE=1 and IOS_27_UDID (needs the pinned booted
iOS 27 simulator and a full Flutter build). Run from the tool root:

    APPLE_MATCH_SMOKE=1 IOS_27_UDID=<udid> \
    DEVELOPER_DIR=/Applications/Xcode-27.0.0-Beta.5.app/Contents/Developer \
    PYTHONPATH=compare python3 -m unittest tests.test_optimize_integration -v
"""

from __future__ import annotations

import json
import os
import unittest
from pathlib import Path

from apple_match.hotloop import (
    CaptureSession,
    Evaluator,
    load_reference_probes,
    scene_crop,
)

ROOT = Path(__file__).resolve().parents[2]

SMOKE_ENABLED = os.environ.get("APPLE_MATCH_SMOKE") == "1" and bool(
    os.environ.get("IOS_27_UDID")
)


@unittest.skipUnless(SMOKE_ENABLED, "requires APPLE_MATCH_SMOKE=1 and IOS_27_UDID")
class OnlineLoopSmokeTests(unittest.TestCase):
    def test_two_candidates_one_session_distinct_losses(self):
        udid = os.environ["IOS_27_UDID"]
        scene_path = ROOT / "scenes/toolbar_capsule.json"
        scene = json.loads(scene_path.read_text())
        reference_dir = (
            ROOT / "references" / "ios27-iphone17pro-light" / scene["id"]
        )
        baseline = json.loads(
            (ROOT / "settings/baseline.json").read_text()
        )
        flat = {
            **baseline,
            "thickness": 0.0,
            "blur": 0.0,
            "lightIntensity": 0.0,
            "glassAlpha": 0.0,
            "refractiveIndex": 1.0,
            "saturation": 1.0,
            "chromaticAberration": 0.0,
        }
        flutter_bin = os.environ.get(
            "FLUTTER_BIN", str(Path.home() / "fvm/versions/3.44.1/bin/flutter")
        )
        env = os.environ.copy()
        env["PATH"] = f"{ROOT / 'compat/bin'}:{env['PATH']}"
        out = ROOT / "out/optimize-smoke"
        crop = scene_crop(scene)
        with CaptureSession(
            udid=udid,
            flutter_bin=flutter_bin,
            flutter_project=ROOT / "flutter",
            scene_path=scene_path,
            work_dir=out / "session",
            env=env,
        ) as session:
            evaluator = Evaluator(
                session=session,
                reference=load_reference_probes(reference_dir, crop),
                crop=crop,
                capture_dir=out / "last",
            )
            first = evaluator.evaluate(baseline)
            second = evaluator.evaluate(flat)
        self.assertEqual(evaluator.evaluations, 2)
        self.assertNotEqual(
            first, second, "two online candidates produced identical losses"
        )
        self.assertNotEqual(
            (out / "last" / "A.png").read_bytes(),
            b"",
        )
        self.assertGreater(session.startup_seconds, 0)
        print(
            f"smoke: baseline loss={first:.4f} flat loss={second:.4f} "
            f"startup={session.startup_seconds:.1f}s"
        )


if __name__ == "__main__":
    unittest.main()
