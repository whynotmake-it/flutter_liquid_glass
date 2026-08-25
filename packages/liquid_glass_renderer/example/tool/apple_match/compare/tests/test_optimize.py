"""Behavioral tests for the online optimization loop (no simulator)."""

import json
import queue
import signal
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

import cv2
import numpy as np

from apple_match.hotloop.evaluate import (
    Evaluator,
    PINNED_DEVICE_NAME,
    PINNED_DEVICE_UDID,
    ensure_pinned_simulator,
)
from apple_match.hotloop.optimize import coordinate_descent, neighbor_values
from apple_match.hotloop.session import (
    FlutterRunSession,
    SettleTimeout,
    SessionError,
    SignalReloadTrigger,
)
from hotloop_staged import has_optimization_wall, optimization_objective
from transparency_sweep import (
    audit_shared_vector,
    interpret_curve,
    is_monotonic,
    materialize,
)


class OptimizerTests(unittest.TestCase):
    """Fake-loss coordinate descent must converge on a known optimum."""

    def setUp(self):
        self.axes = {"x": [0.0, 1.0, 2.0, 3.0, 4.0, 5.0], "y": [0.0, 1.0, 2.0, 3.0, 4.0, 5.0]}
        self.optimum = {"x": 2.0, "y": 4.0}

    def fake_loss(self, params):
        return (params["x"] - 2.0) ** 2 + (params["y"] - 4.0) ** 2

    def test_converges_to_known_optimum(self):
        result = coordinate_descent(
            self.fake_loss, {"x": 5.0, "y": 0.0}, self.axes, max_iters=10
        )
        self.assertEqual(result["bestParams"], self.optimum)
        self.assertEqual(result["bestLoss"], 0.0)
        self.assertGreater(len(result["history"]), 1)
        self.assertTrue(result["history"][0]["isBest"])

    def test_respects_max_iters(self):
        result = coordinate_descent(
            self.fake_loss, {"x": 5.0, "y": 0.0}, self.axes, max_iters=1
        )
        iterations = {row["iteration"] for row in result["history"]}
        self.assertEqual(iterations, {0, 1})
        self.assertLess(result["bestLoss"], self.fake_loss({"x": 5.0, "y": 0.0}))
        accepted = [row for row in result["history"][1:] if row["isBest"]]
        self.assertEqual(len(accepted), 1)
        self.assertEqual(accepted[0]["loss"], result["bestLoss"])

    def test_stops_when_no_neighbor_improves(self):
        def flat_loss(params):
            return 0.0 if params == self.optimum else 1.0

        result = coordinate_descent(
            flat_loss, {"x": 0.0, "y": 0.0}, self.axes, max_iters=10
        )
        self.assertEqual(result["bestParams"], {"x": 0.0, "y": 0.0})
        self.assertEqual(result["bestLoss"], 1.0)
        self.assertEqual(max(row["iteration"] for row in result["history"]), 1)

    def test_wall_requires_consecutive_sub_threshold_stages(self):
        summaries = {
            "shape": {"improvement": 0.2},
            "refraction": {"improvement": 0.04},
            "blurMtf": {"improvement": 0.03},
        }
        self.assertTrue(
            has_optimization_wall(
                summaries,
                threshold=0.05,
                consecutive=2,
            )
        )
        summaries["blurMtf"]["improvement"] = 0.06
        self.assertFalse(
            has_optimization_wall(
                summaries,
                threshold=0.05,
                consecutive=2,
            )
        )

    def test_stage_objectives_isolate_known_blur_mismatch(self):
        result = SimpleNamespace(
            errors={"shape": 0.1, "flow": 0.2},
            details={
                "directPixelMeanAbsoluteError8Bit": 9.0,
                "pixelResiduals": {
                    "C": {
                        "glass": {"meanAbsoluteError8Bit": 2.0},
                        "core": {"meanAbsoluteError8Bit": 1.0},
                        "rim": {"meanAbsoluteError8Bit": 3.0},
                        "outerContour": {"meanAbsoluteError8Bit": 6.0},
                        "innerBevel": {"meanAbsoluteError8Bit": 2.5},
                        "topLip": {"meanAbsoluteError8Bit": 2.0},
                        "bottomLip": {"meanAbsoluteError8Bit": 1.0},
                        "topCenterLip": {"meanAbsoluteError8Bit": 2.0},
                        "bottomCenterLip": {"meanAbsoluteError8Bit": 1.0},
                        "topFace": {"meanAbsoluteError8Bit": 2.0},
                        "bottomFace": {"meanAbsoluteError8Bit": 1.0},
                    },
                    "D": {
                        "glass": {"meanAbsoluteError8Bit": 4.0},
                        "core": {"meanAbsoluteError8Bit": 2.0},
                        "rim": {"meanAbsoluteError8Bit": 5.0},
                        "outerContour": {"meanAbsoluteError8Bit": 7.0},
                        "innerBevel": {"meanAbsoluteError8Bit": 3.5},
                        "topLip": {"meanAbsoluteError8Bit": 4.0},
                        "bottomLip": {"meanAbsoluteError8Bit": 3.0},
                        "topCenterLip": {"meanAbsoluteError8Bit": 4.0},
                        "bottomCenterLip": {"meanAbsoluteError8Bit": 3.0},
                        "topFace": {"meanAbsoluteError8Bit": 4.0},
                        "bottomFace": {"meanAbsoluteError8Bit": 3.0},
                    },
                },
            },
        )
        self.assertEqual(optimization_objective("shape", result)[1], 25.5)
        self.assertEqual(optimization_objective("refraction", result)[1], 51.0)
        self.assertEqual(optimization_objective("tintColor", result)[1], 1.5)
        self.assertEqual(optimization_objective("highlight", result)[1], 6.0)
        self.assertEqual(optimization_objective("outline", result)[1], 7.0)
        self.assertEqual(
            optimization_objective("faceShading", result)[1], 3.5
        )
        self.assertEqual(optimization_objective("blurMtf", result)[1], 9.0)

    def test_transparency_curve_interpretation(self):
        self.assertTrue(is_monotonic([0.1, 0.25, 0.5, 0.75, 0.9]))
        self.assertTrue(is_monotonic([0.9, 0.75, 0.5, 0.25, 0.1]))
        self.assertEqual(
            interpret_curve([0.1, 0.25, 0.5, 0.75, 0.9])["status"],
            "confirmed",
        )
        self.assertEqual(
            interpret_curve([1.0, 1.0, 1.0, 1.0, 1.0])["status"],
            "rejected",
        )
        self.assertEqual(
            interpret_curve([0.2, 0.8, 0.3, 0.9, 0.4])["status"],
            "inconclusive",
        )

    def test_transparency_materialize_preserves_shared_tint_color(self):
        tint_color = (253, 252, 253)
        first = materialize({"tintAlpha": 0.2, "frost": 1.0}, tint_color)
        second = materialize({"tintAlpha": 0.8, "frost": 7.0}, tint_color)
        self.assertEqual(first["tintRed"], 253)
        self.assertEqual(first["tintGreen"], 252)
        self.assertEqual(first["tintBlue"], 253)
        self.assertEqual(
            [first[key] for key in ("tintRed", "tintGreen", "tintBlue")],
            [second[key] for key in ("tintRed", "tintGreen", "tintBlue")],
        )
        self.assertNotEqual(first["tintAlpha"], second["tintAlpha"])
        self.assertNotIn("tintLevel", first)

    def test_transparency_shared_vector_audit_rejects_unauthorized_drift(self):
        base = {"thickness": 10.0, "tintRed": 253, "tintGreen": 252, "tintBlue": 253,
                "tintAlpha": 0.2, "frost": 1.0}
        passed = audit_shared_vector([
            base,
            {**base, "tintAlpha": 0.8, "frost": 7.0},
        ])
        self.assertEqual(passed["status"], "passed")
        self.assertEqual(
            passed["observedVaryingKeys"], ["frost", "tintAlpha"]
        )
        failed = audit_shared_vector([
            base,
            {**base, "tintAlpha": 0.8, "tintRed": 240},
        ])
        self.assertEqual(failed["status"], "failed")
        self.assertEqual(failed["unauthorizedVaryingKeys"], ["tintRed"])

    def test_neighbor_values_clamp_at_bounds(self):
        values = [1.0, 2.0, 3.0]
        self.assertEqual(neighbor_values(values, 1.0), [2.0])
        self.assertEqual(neighbor_values(values, 3.0), [2.0])
        self.assertEqual(neighbor_values(values, 2.0), [1.0, 3.0])
        self.assertEqual(neighbor_values(values, 2.4), [2.0, 3.0])

    def test_pinned_booted_device_prevents_second_simulator_boot(self):
        calls = []
        duplicate_udid = "6FD8103D-E490-42A6-8735-0151BC22C5F7"

        def fake_simctl(*arguments):
            calls.append(arguments)
            if arguments == ("list", "devices", "-j"):
                return json.dumps(
                    {
                        "devices": {
                            "iOS 27.0": [
                                {
                                    "name": PINNED_DEVICE_NAME,
                                    "udid": PINNED_DEVICE_UDID,
                                    "state": "Booted",
                                    "isAvailable": True,
                                },
                                {
                                    "name": "AppleMatch-Optimizer-iPhone17Pro-iOS27",
                                    "udid": duplicate_udid,
                                    "state": "Shutdown",
                                    "isAvailable": True,
                                },
                            ]
                        }
                    }
                )
            return ""

        with self.assertRaisesRegex(RuntimeError, "refusing requested simulator"):
            ensure_pinned_simulator(duplicate_udid, simctl_fn=fake_simctl)
        self.assertFalse(any(call[0] == "boot" for call in calls))
        calls.clear()
        ensure_pinned_simulator(PINNED_DEVICE_UDID, simctl_fn=fake_simctl)
        self.assertFalse(any(call[0] == "boot" for call in calls))


def synthetic(blur=0.0, size=128):
    """Grid background with a blurred superellipse, mirroring test_pipeline."""
    yy, xx = np.mgrid[:size, :size]
    grid = (((xx // 8 + yy // 8) % 2) * 0.6 + 0.2).astype(np.float32)
    mask = (((xx - 64) / 42) ** 8 + ((yy - 64) / 22) ** 8 <= 1).astype(np.float32)
    a = np.repeat(grid[..., None], 3, axis=2)
    if blur:
        blurred = cv2.GaussianBlur(a, (0, 0), blur)
        a = a * (1 - mask[..., None]) + blurred * mask[..., None]
    b = np.full_like(a, 0.5)
    c = np.repeat((mask * 0.35)[..., None], 3, axis=2)
    d = np.ones_like(a)
    return {
        key: np.clip(value, 0, 1)
        for key, value in zip("ABCD", (a, b, c, d))
    }


class EvaluatorTests(unittest.TestCase):
    """Params flow through the session to screenshots and a scalar loss."""

    def make_evaluator(self, root: Path, reference_blur: float):
        candidate_path = root / "candidate.json"
        settle = SimpleNamespace(calls=[])

        def request_settle(**kwargs):
            settle.calls.append(kwargs)
            return {"reloadMode": "hotReload", "reloadRetries": 0}

        def screenshot(png: Path):
            params = json.loads(candidate_path.read_text())["settings"]
            probe = json.loads(candidate_path.read_text())["probe"]
            image = synthetic(blur=params.get("blur", 0.0))[probe]
            bgr = cv2.cvtColor((image * 255).astype(np.uint8), cv2.COLOR_RGB2BGR)
            cv2.imwrite(str(png), bgr)

        session = SimpleNamespace(
            candidate_path=candidate_path,
            status_path=root / "status.json",
            session=SimpleNamespace(request_settle=request_settle),
            udid="fake",
        )
        evaluator = Evaluator(
            session=session,
            reference=synthetic(blur=reference_blur),
            crop=(0, 0, 128, 128),
            capture_dir=root / "captures",
            screenshot=screenshot,
        )
        return evaluator, settle

    def test_params_drive_screenshots_and_loss(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            evaluator, settle = self.make_evaluator(root, reference_blur=1.5)
            matching = evaluator.evaluate({"blur": 1.5})
            off = evaluator.evaluate({"blur": 6.0})
            self.assertNotEqual(matching, off)
            # 8-bit PNG quantization keeps an exact match slightly above 0.
            self.assertLess(matching, 1.0)
            self.assertGreater(off, matching + 1.0)
            # Four probes per evaluation, serials strictly increasing.
            self.assertEqual(len(settle.calls), 8)
            serials = [call["serial"] for call in settle.calls]
            self.assertEqual(serials, sorted(serials))
            self.assertEqual(len(set(serials)), 8)
            # The candidate file carried the params through.
            written = json.loads(
                evaluator.session.candidate_path.read_text()
            )
            self.assertEqual(written["settings"], {"blur": 6.0})
            self.assertEqual(evaluator.last_modes, dict.fromkeys("ABCD", "hotReload"))


class FakeClock:
    def __init__(self):
        self.now = 0.0

    def monotonic(self):
        return self.now

    def sleep(self, seconds):
        self.now += seconds

    def advance(self, seconds):
        self.now += seconds


class FakeTransport:
    def __init__(self):
        self.lines = queue.Queue()
        self.exited = False

    def poll(self):
        return 0 if self.exited else None

    def read_line(self, timeout=0):
        try:
            return self.lines.get(timeout=timeout)
        except queue.Empty:
            return None

    def tail_text(self):
        return "fake-transport"

    def terminate(self):
        self.exited = True


class FakeTrigger:
    def __init__(self):
        self.calls = []

    def hot_reload(self):
        self.calls.append("reload")

    def hot_restart(self):
        self.calls.append("restart")


class SessionSettleTests(unittest.TestCase):
    def make_session(self, trigger):
        clock = FakeClock()
        return (
            FlutterRunSession(
                FakeTransport(),
                trigger,
                monotonic=clock.monotonic,
                sleep=clock.sleep,
                poll_interval=0.05,
            ),
            clock,
        )

    def settled(self, serial):
        return {
            "state": "settled",
            "candidateId": "c",
            "probe": "A",
            "serial": serial,
        }

    def test_signal_trigger_uses_documented_signals(self):
        sent = []
        trigger = SignalReloadTrigger(4242, kill=lambda pid, sig: sent.append((pid, sig)))
        trigger.hot_reload()
        trigger.hot_restart()
        self.assertEqual(sent, [(4242, signal.SIGUSR1), (4242, signal.SIGUSR2)])

    def test_happy_path_records_hot_reload(self):
        trigger = FakeTrigger()
        session, _ = self.make_session(trigger)
        status = session.request_settle(
            candidate_id="c", probe="A", serial=1, read_status=lambda: self.settled(1)
        )
        self.assertEqual(status["reloadMode"], "hotReload")
        self.assertEqual(status["reloadRetries"], 0)
        self.assertEqual(trigger.calls, ["reload"])

    def test_escalates_to_hot_restart_and_records_mode(self):
        trigger = FakeTrigger()
        session, clock = self.make_session(trigger)

        def read_status():
            if trigger.calls.count("restart"):
                return self.settled(1)
            clock.advance(0.05)
            return None

        status = session.request_settle(
            candidate_id="c",
            probe="A",
            serial=1,
            read_status=read_status,
            settle_timeout=1.0,
            restart_timeout=5.0,
        )
        self.assertEqual(status["reloadMode"], "hotRestart")
        self.assertEqual(trigger.calls, ["reload", "reload", "restart"])

    def test_stale_serial_is_not_accepted(self):
        trigger = FakeTrigger()
        session, clock = self.make_session(trigger)
        statuses = iter([self.settled(0), self.settled(1)])

        def read_status():
            clock.advance(0.05)
            return next(statuses)

        status = session.request_settle(
            candidate_id="c", probe="A", serial=1, read_status=read_status
        )
        self.assertEqual(status["serial"], 1)

    def test_timeout_after_escalation_raises(self):
        trigger = FakeTrigger()
        session, clock = self.make_session(trigger)

        def read_status():
            clock.advance(0.05)
            return None

        with self.assertRaises(SettleTimeout):
            session.request_settle(
                candidate_id="c",
                probe="A",
                serial=1,
                read_status=read_status,
                settle_timeout=0.5,
                restart_timeout=0.5,
            )
        self.assertEqual(trigger.calls, ["reload", "reload", "restart"])

    def test_process_exit_raises_session_error(self):
        trigger = FakeTrigger()
        session, _ = self.make_session(trigger)
        session.transport.exited = True
        with self.assertRaises(SessionError):
            session.request_settle(
                candidate_id="c", probe="A", serial=1, read_status=lambda: None
            )

    def test_wait_for_output_matches_queued_line(self):
        trigger = FakeTrigger()
        session, _ = self.make_session(trigger)
        session.transport.lines.put("A Dart VM Service on device is available\n")
        line = session.wait_for_output(("Flutter run key commands", "Dart VM Service"))
        self.assertIn("Dart VM Service", line)

    def test_wait_for_output_raises_when_process_exits(self):
        trigger = FakeTrigger()
        session, _ = self.make_session(trigger)
        session.transport.exited = True
        with self.assertRaises(SessionError):
            session.wait_for_output(("Dart VM Service",), timeout=5.0)


if __name__ == "__main__":
    unittest.main()
