#!/usr/bin/env python3
"""Offline regression tests for the Android bench tooling.

Software-contract tests only: no device, adb, or real Perfetto trace.
"""
import importlib
import json
import os
import sys
import types
import unittest
from contextlib import ExitStack
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


class _ForbiddenTraceProcessor:
    """Both analyzers import this; tests stub every path that could reach it."""

    def __init__(self, *args, **kwargs):
        raise AssertionError("TraceProcessor banned in offline tests")


_fake_perfetto = types.ModuleType("perfetto")
_fake_trace_processor = types.ModuleType("perfetto.trace_processor")
_fake_trace_processor.TraceProcessor = _ForbiddenTraceProcessor
_fake_perfetto.trace_processor = _fake_trace_processor

# Fake perfetto is visible only during module import; the imported modules
# keep the forbidden TraceProcessor afterwards.
with mock.patch.dict(sys.modules, {
        "perfetto": _fake_perfetto,
        "perfetto.trace_processor": _fake_trace_processor}):
    ab_analyze = importlib.import_module("android_ab_analyze")
    ab_bench = importlib.import_module("android_ab_bench")
    gpu_analyze = importlib.import_module("android_gpu_bench_analyze")

ANALYZER_PATH = Path(ab_analyze.__file__).resolve()
SHARED_ANALYZER_PATH = ANALYZER_PATH.with_name("android_gpu_bench_analyze.py")

OK_RUN = {"arm": "on", "scenario": "scene", "rep": 1,
          "status": "ok", "summary": {"frameCount": 720}}
INPUT_UPDATES = {
    "on__scene__r1/run.json": json.dumps(OK_RUN | {"v": 2}),
    "on__scene__r1/trace.pftrace": "other",
    "on__scene__r1/meminfo.txt": "meminfo-v2",
    "meta.json": json.dumps({"measure": 12, "v": 2}),
}
PIXEL_SUITE = ("pxButtonStatic pxButtonStretch pxPillStretch pxBlend5Motion "
               "resizeAnimated pxSheetResize pxMultiLayer colorsBlendStatic "
               "colorsBlendMotion").split()


def _write_run(out, name, run):
    run_dir = out / name
    run_dir.mkdir(parents=True, exist_ok=True)
    (run_dir / "run.json").write_text(json.dumps(run))
    (run_dir / "trace.pftrace").write_bytes(b"trace")
    (run_dir / "meminfo.txt").write_text("meminfo")
    return run_dir


def _out_dir(tmp):
    out = Path(tmp) / "out"
    _write_run(out, "on__scene__r1", OK_RUN)
    (out / "meta.json").write_text(json.dumps({"measure": 12}))
    return out


def _ok_result(run_dir):
    run = json.loads((Path(run_dir) / "run.json").read_text())
    return {"arm": run.get("arm"), "scenario": run.get("scenario"),
            "rep": run.get("rep"), "status": "ok", "fps": 60.0}


def _spoof_file_fingerprint(target_path, sentinel):
    """Only target_path's hash changes; other files keep their real one."""
    original = ab_analyze._file_fingerprint
    return lambda path: (sentinel if Path(path).resolve() == target_path
                         else original(path))


def _headline(md):
    return md.split("## Headline", 1)[1].split("## Flutter frames", 1)[0]


class AbAnalyzeCacheTests(unittest.TestCase):
    # Cache, retry and failure-exclusion flows share one fixture.
    def _start(self, patcher):
        self.addCleanup(patcher.stop)
        return patcher.start()

    def setUp(self):
        tmp = TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.out = _out_dir(tmp.name)
        self.calls = []
        self.analyze_run = self._start(mock.patch.object(
            ab_analyze, "analyze_run"))
        self.analyze_run.side_effect = self._record
        self._start(mock.patch.object(sys, "argv",
                                      ["android_ab_analyze.py", str(self.out)]))

    def _record(self, run):
        self.calls.append(Path(run).name)
        return _ok_result(run)

    def test_inputs_sources_and_cache_shape(self):
        ab_analyze.main()
        self.assertEqual(self.calls, ["on__scene__r1"])
        ab_analyze.main()
        self.assertEqual(len(self.calls), 1)  # unchanged inputs: cache hit

        # Same-length rewrites with restored mtime must still invalidate.
        for expected, (relative, contents) in enumerate(
                INPUT_UPDATES.items(), start=2):
            path = self.out / relative
            stat = path.stat()
            path.write_text(contents)
            os.utime(path, ns=(stat.st_atime_ns, stat.st_mtime_ns))
            ab_analyze.main()
            self.assertEqual(len(self.calls), expected)

        for expected, sentinel_path in ((6, ANALYZER_PATH),
                                        (7, SHARED_ANALYZER_PATH)):
            with mock.patch.object(
                    ab_analyze, "_file_fingerprint",
                    _spoof_file_fingerprint(sentinel_path, "changed")):
                ab_analyze.main()
            self.assertEqual(len(self.calls), expected)

        # Back to real fingerprints: one re-analysis, then hits again.
        ab_analyze.main()
        self.assertEqual(len(self.calls), 8)
        ab_analyze.main()
        self.assertEqual(len(self.calls), 8)

    def test_failed_analysis_is_retried(self):
        def flaky(run):
            self.calls.append(Path(run).name)
            if len(self.calls) == 1:
                raise RuntimeError("boom")
            return _ok_result(run)

        self.analyze_run.side_effect = flaky
        summary = lambda: json.loads((self.out / "summary.json").read_text())
        ab_analyze.main()
        self.assertIn("failed:analysis",
                      [f["status"] for f in summary()["failures"]])

        ab_analyze.main()
        self.assertEqual(len(self.calls), 2)
        self.assertEqual(summary()["failures"], [])
        self.assertEqual(summary()["scene|on"]["fps"], 60.0)

    def test_thermal_failure_excluded_and_cached(self):
        _write_run(self.out, "off__scene__r1", {
            "arm": "off", "scenario": "scene", "rep": 1,
            "status": "failed:thermal",
            "failureReason": "thermal gate was not reached",
            "summary": {"frameCount": 999999999}})
        summary = lambda: json.loads((self.out / "summary.json").read_text())
        statuses = lambda: [f["status"] for f in summary()["failures"]]
        ab_analyze.main()
        self.assertEqual(self.calls, ["on__scene__r1"])
        self.assertEqual(summary()["scene|on"]["fps"], 60.0)
        self.assertNotIn("scene|off", summary())
        self.assertEqual(statuses(), ["failed:thermal"])
        markdown = (self.out / "summary.md").read_text()
        self.assertIn("### Failures", markdown)
        self.assertIn("failed:thermal", markdown)
        self.assertIn("thermal gate was not reached", markdown)

        # The failure row is cached too: still excluded, no re-analysis.
        ab_analyze.main()
        self.assertEqual(self.calls, ["on__scene__r1"])
        self.assertNotIn("scene|off", summary())
        self.assertEqual(statuses(), ["failed:thermal"])


class GpuMarkdownTests(unittest.TestCase):
    def test_headline_excludes_failed_runs(self):
        runs = [
            {"dir": "on__scene__r1", "scenario": "scene", "repetition": 1,
             "status": "ok", "fps": 60.0, "gpu_mw": 100.0},
            {"dir": "off__scene__r2", "scenario": "scene", "repetition": 2,
             "status": "failed:thermal",
             "failureReason": "thermal gate was not reached",
             "fps": 9999.0, "gpu_mw": 99999.0},
        ]
        md = gpu_analyze._build_markdown(Path("out"), runs)
        headline = _headline(md)
        self.assertIn("60.0", headline)
        self.assertIn("100", headline)
        self.assertNotIn("9999", headline)
        self.assertNotIn("99999", headline)
        self.assertIn("thermal gate was not reached",
                      md.split("## Failures", 1)[1])
        self.assertIn("failed:thermal", md)  # appendix keeps the status


class ThermalGateTests(unittest.TestCase):
    def test_run_once_thermal_failure_touches_no_device(self):
        with TemporaryDirectory() as tmp, ExitStack() as stack:
            out = Path(tmp)
            mocks = {n: stack.enter_context(mock.patch.object(ab_bench, n))
                     for n in ("unlock", "Logcat", "adb", "sh")}
            stack.enter_context(mock.patch.object(
                ab_bench, "wait_cool", return_value=(1, 40.0, 905, False)))
            result = ab_bench.run_once(
                out, "on", "com.example.on", "MainActivity",
                "scene", 1, 4, 12, [], (31.5, 15))
            self.assertEqual(result["status"], "failed:thermal")
            run_json = (out / "on__scene__r1" / "run.json").read_text()
            self.assertEqual(json.loads(run_json)["status"], "failed:thermal")
            for device_call in mocks.values():
                device_call.assert_not_called()


class ScenarioRegistryTests(unittest.TestCase):
    def test_pixel_suite(self):
        self.assertEqual(ab_bench.resolve_scenarios("pixel"), PIXEL_SUITE)

    def test_unknown_scene_rejected(self):
        with self.assertRaises(ValueError):
            ab_bench.resolve_scenarios("noSuchScene")


if __name__ == "__main__":
    unittest.main()
