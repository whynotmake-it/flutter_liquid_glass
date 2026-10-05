#!/usr/bin/env python3
"""Interleaved A/B runner for Android (profile APKs of benchmark_test.dart).

Every arm is an installed package built from integration_test/benchmark_test.dart
(`flutter build apk --profile -t integration_test/benchmark_test.dart`). Give each
arm its own applicationId in the local, gitignored android/app/build.gradle.kts
before building, so all arms can be installed side by side. Arms run interleaved
and in reversed order on every other repetition, each run behind a thermal gate,
with a Perfetto trace (power rails, GPU work periods and frequency, GPU memory,
app atrace) over the measure window.

    python3 tool/android_ab_bench.py --out build/android-ab/reuse \
      --arms on=com.example.bench.on,off=com.example.bench.off \
      --scenarios "pxButtonStretch pxSheetResize" --reps 4
    tool/bench_analyze.sh build/android-ab/reuse

Set ANDROID_SERIAL to pick a device and UNLOCK_PIN if the device has a PIN.
"""
import argparse
import json
import os
import re
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path

SERIAL = os.environ.get("ANDROID_SERIAL")
ADB = ["adb", "-s", SERIAL] if SERIAL else ["adb"]


def sh(*args, check=False, capture=True, timeout=120):
    r = subprocess.run(ADB + ["shell", *args], capture_output=capture, text=True, timeout=timeout)
    if check and r.returncode:
        raise RuntimeError(r.stderr)
    return (r.stdout or "").replace("\r", "")


def adb(*args, timeout=180):
    return subprocess.run(ADB + list(args), capture_output=True, text=True, timeout=timeout)


def keyguard():
    return "isKeyguardShowing=true" in sh("dumpsys", "window")


class NeedsHuman(Exception):
    pass


def unlock():
    sh("svc", "power", "stayon", "true")
    sh("input", "keyevent", "KEYCODE_WAKEUP")
    time.sleep(0.3)
    if not keyguard():
        return
    pin = os.environ.get("UNLOCK_PIN", "")
    sh("wm", "dismiss-keyguard")
    time.sleep(0.4)
    sh("input", "swipe", "540", "1900", "540", "600", "200")
    time.sleep(0.4)
    if pin:
        sh("input", "text", pin)
        sh("input", "keyevent", "KEYCODE_ENTER")
        time.sleep(0.6)
    if keyguard():
        raise NeedsHuman("device is locked and could not be unlocked")


def thermal():
    out = sh("dumpsys", "thermalservice")
    m = re.search(r"Thermal Status:\s*(\d+)", out)
    status = int(m.group(1)) if m else 9
    skin = None
    current = out.split("Current temperatures from HAL:", 1)[-1]
    mm = re.search(r"mValue=([\d.]+), mType=3, mName=VIRTUAL-SKIN,", current)
    if mm:
        skin = float(mm.group(1))
    return status, skin


def wait_cool(max_skin, min_wait):
    time.sleep(min_wait)
    waited = min_wait
    while True:
        status, skin = thermal()
        if status == 0 and (skin is None or max_skin is None or skin <= max_skin):
            return status, skin, waited, True
        if waited > 900:
            return status, skin, waited, False
        time.sleep(10)
        waited += 10


def pin_device():
    keys = [("system", "peak_refresh_rate"), ("system", "min_refresh_rate"),
            ("system", "screen_brightness_mode"), ("system", "screen_brightness")]
    orig = {k: sh("settings", "get", *k).strip() for k in keys}
    sh("settings", "put", "system", "peak_refresh_rate", "120")
    sh("settings", "put", "system", "min_refresh_rate", "120")
    sh("settings", "put", "system", "screen_brightness_mode", "0")
    sh("settings", "put", "system", "screen_brightness", "128")
    sh("svc", "power", "stayon", "true")
    return orig


def restore(orig):
    for (ns, key), value in orig.items():
        if value and value != "null":
            sh("settings", "put", ns, key, value)
    sh("svc", "power", "stayon", "false")


PERFETTO_CFG = """buffers: {{ size_kb: 131072 fill_policy: RING_BUFFER }}
data_sources: {{ config {{ name: "android.power" android_power_config {{
  battery_poll_ms: 250 collect_power_rails: true
  battery_counters: BATTERY_COUNTER_CURRENT }} }} }}
data_sources: {{ config {{ name: "android.gpu.memory" }} }}
data_sources: {{ config {{ name: "linux.ftrace" ftrace_config {{
  ftrace_events: "power/gpu_frequency"
  ftrace_events: "power/gpu_work_period"
  ftrace_events: "gpu_mem/gpu_mem_total"
  atrace_categories: "gfx"
  atrace_categories: "view"
  atrace_categories: "dart"
  atrace_apps: "{pkg}" }} }} }}
data_sources: {{ config {{ name: "linux.process_stats" process_stats_config {{ scan_all_processes_on_start: true }} }} }}
data_sources: {{ config {{ name: "android.surfaceflinger.frametimeline" }} }}
write_into_file: true
file_write_period_ms: 2000
duration_ms: {dur}
"""


def uid_of(pkg):
    out = sh("pm", "list", "packages", "-U", pkg)
    for line in out.splitlines():
        if line.startswith("package:" + pkg + " "):
            return line.split("uid:")[1].strip()
    return None


def uid_gpu_time(uid):
    out = subprocess.run(ADB + ["exec-out", "cat", "/sys/devices/platform/34f00000.gpu0/uid_time_in_state"],
                         capture_output=True, text=True).stdout
    return out


class Logcat:
    def __init__(self, path):
        self.path = path
        adb("logcat", "-c")
        self.fh = open(path, "w")
        self.proc = subprocess.Popen(ADB + ["logcat", "-v", "threadtime"], stdout=self.fh,
                                     stderr=subprocess.DEVNULL)

    def text(self):
        self.fh.flush()
        return Path(self.path).read_text(errors="replace")

    def wait(self, marker, timeout):
        end = time.time() + timeout
        while time.time() < end:
            if marker in self.text():
                return True
            time.sleep(0.2)
        return False

    def stop(self):
        self.proc.terminate()
        try:
            self.proc.wait(5)
        except subprocess.TimeoutExpired:
            self.proc.kill()
        self.fh.close()


def parse_chunks(text, tag):
    rows = {}
    for m in re.finditer(tag + r":(\d+):(.*)$", text, re.M):
        rows[int(m.group(1))] = [json.loads(x) for x in m.group(2).strip().split(";") if x]
    out = []
    for k in sorted(rows):
        out.extend(rows[k])
    return out


def run_once(out, arm, pkg, activity, scenario, rep, warmup, measure, extra, gate):
    run_dir = out / f"{arm}__{scenario}__r{rep}"
    done = run_dir / "run.json"
    if done.exists() and json.loads(done.read_text()).get("status") == "ok":
        return json.loads(done.read_text())
    run_dir.mkdir(parents=True, exist_ok=True)
    status, skin, waited, gate_reached = wait_cool(*gate)
    result = {"arm": arm, "pkg": pkg, "scenario": scenario, "rep": rep,
              "thermalStatus": status, "skinC": skin, "cooldownS": waited,
              "status": "ok", "startEpoch": time.time()}
    if not gate_reached:
        result["status"] = "failed:thermal"
        result["failureReason"] = "thermal gate was not reached"
        (run_dir / "run.json").write_text(json.dumps(result))
        print(f"{time.strftime('%H:%M:%S')} {arm:>6} {scenario:<18} r{rep} "
              f"{result['status']} skin={skin} cool={waited}s", flush=True)
        return result

    unlock()
    for other in ALL_PKGS:
        sh("am", "force-stop", other)
    time.sleep(0.5)
    uid = uid_of(pkg)
    log = Logcat(run_dir / "logcat.txt")
    cmd = ["am", "start", "-W", "-n", f"{pkg}/{activity}", "--ez", "trace-systrace", "true",
           "--es", "scenario", scenario, "--ei", "warmupSeconds", str(warmup),
           "--ei", "measureSeconds", str(measure), "--ei", "repetition", str(rep)] + extra
    sh(*cmd)
    result["uid"] = uid
    if not log.wait(f"LIQUID_GLASS_BENCHMARK_MEASURE_BEGIN:{scenario}", 90):
        result["status"] = "failed:begin"
    else:
        dur = max(1000, (measure - 1) * 1000)
        cfg = run_dir / "perfetto.cfg"
        cfg.write_text(PERFETTO_CFG.format(pkg=pkg, dur=dur))
        adb("push", str(cfg), "/data/misc/perfetto-configs/p10.cfg")
        remote = f"/data/misc/perfetto-traces/p10_{arm}_{scenario}_{rep}.pftrace"
        sh("rm", "-f", remote)
        pf = subprocess.Popen(ADB + ["shell", "perfetto", "-c", "/data/misc/perfetto-configs/p10.cfg",
                                     "--txt", "-o", remote],
                              stdout=open(run_dir / "perfetto.log", "w"), stderr=subprocess.STDOUT)
        (run_dir / "uid_begin.txt").write_text(uid_gpu_time(uid))
        if not log.wait(f"LIQUID_GLASS_BENCHMARK_MEASURE_END:{scenario}", measure + 60):
            result["status"] = "failed:end"
        (run_dir / "uid_end.txt").write_text(uid_gpu_time(uid))
        (run_dir / "meminfo.txt").write_text(sh("dumpsys", "meminfo", pkg))
        pf.wait(timeout=measure + 60)
        adb("pull", remote, str(run_dir / "trace.pftrace"))
        sh("rm", "-f", remote)
        if not log.wait("LIQUID_GLASS_BENCHMARK_SUMMARY:", 60):
            result["status"] = "failed:summary"
    time.sleep(0.5)
    text = log.text()
    log.stop()
    for other in ALL_PKGS:
        sh("am", "force-stop", other)
    m = re.findall(r"LIQUID_GLASS_BENCHMARK_SUMMARY:(\{.*\})", text)
    if m:
        result["summary"] = json.loads(m[-1])
    result["frames"] = parse_chunks(text, "LIQUID_GLASS_BENCHMARK_FRAMES")
    result["mem"] = parse_chunks(text, "LIQUID_GLASS_BENCHMARK_MEMORY")
    if re.search(r"EXCEPTION CAUGHT|Unhandled exception|FATAL EXCEPTION", text):
        result["status"] += "+error"
    (run_dir / "run.json").write_text(json.dumps(result))
    s = result.get("summary", {})
    print(f"{time.strftime('%H:%M:%S')} {arm:>6} {scenario:<18} r{rep} {result['status']} "
          f"skin={skin} cool={waited}s frames={s.get('frameCount')} "
          f"rasterP50={s.get('rasterP50Micros')} buildP50={s.get('buildP50Micros')} "
          f"pssPeak={s.get('pssPeakKb')}", flush=True)
    return result


ALL_PKGS = []


def resolve_scenarios(spec):
    script = Path(__file__).with_name("bench_scenes.sh")
    result = subprocess.run(
        [
            "bash",
            "-c",
            'source "$1"; bench_resolve_scenes "$2"',
            "bench-resolve-scenarios",
            str(script),
            spec,
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode:
        raise ValueError(result.stderr.strip())
    return result.stdout.split()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--arms", required=True, help="name=pkg,name=pkg")
    ap.add_argument("--activity", default="com.example.liquid_glass_renderer_example.MainActivity")
    ap.add_argument("--scenarios", required=True)
    ap.add_argument("--reps", type=int, default=5)
    ap.add_argument("--warmup", type=int, default=4)
    ap.add_argument("--measure", type=int, default=12)
    ap.add_argument("--out", required=True)
    ap.add_argument("--max-skin", type=float, default=None)
    ap.add_argument("--min-cool", type=int, default=15)
    ap.add_argument("--extra", default="")
    ap.add_argument("--start-rep", type=int, default=1)
    a = ap.parse_args()
    try:
        scenarios = resolve_scenarios(a.scenarios)
    except ValueError as error:
        ap.error(str(error))
    arms = [tuple(x.split("=")) for x in a.arms.split(",")]
    ALL_PKGS.extend(p for _, p in arms)
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    orig = pin_device()
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(1))
    try:
        unlock()
        _, skin0 = thermal()
        max_skin = a.max_skin if a.max_skin is not None else (skin0 + 1.5 if skin0 else None)
        print(f"start skin={skin0} gate={max_skin}", flush=True)
        (out / "meta.json").write_text(json.dumps({"arms": arms, "scenarios": scenarios,
                                                   "reps": a.reps, "warmup": a.warmup,
                                                   "measure": a.measure, "maxSkin": max_skin,
                                                   "fingerprint": sh("getprop", "ro.build.fingerprint").strip()}))
        extra = a.extra.split() if a.extra else []
        for rep in range(a.start_rep, a.reps + 1):
            order = arms if rep % 2 else list(reversed(arms))
            scen = scenarios
            for scenario in (scen if rep % 2 else list(reversed(scen))):
                for arm, pkg in order:
                    run_once(out, arm, pkg, a.activity, scenario, rep, a.warmup, a.measure, extra,
                             (max_skin, a.min_cool))
    except NeedsHuman as e:
        print(f"NEEDS_HUMAN: {e}", flush=True)
        sys.exit(3)
    finally:
        restore(orig)


if __name__ == "__main__":
    main()
