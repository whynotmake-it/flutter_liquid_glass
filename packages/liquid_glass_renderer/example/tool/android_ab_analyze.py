#!/usr/bin/env python3
"""Analyzes android_ab_bench.py output: per-run metrics and a per-(scenario, arm)
summary (median, min, max, CV) in summary.md and summary.json.

Frames and memory come from the app's chunked logcat lines, the rest from the
Perfetto trace:
- GPU Mcycles/frame: active time from power/gpu_work_period x current GPU clock;
- GPU mJ/frame and GPU mW: the S2S_VDD_GPU rail;
- rail groups (same classification as android_gpu_bench_analyze.py): GPU-mem
  (*INFRA_MM_GPU*), CPU (*VDD_CPU*), DDR (*GMC*), display (*DISP*); SoC mW is
  GPU + GPU-mem + CPU + DDR;
- UI PAINT ms/frame and QueueSubmit per frame (needs --trace-systrace);
- UI-thread GC ms/s from the Dart GC slices;
- PSS+GPU: in-app smaps_rollup PSS every 50 ms plus the process GPU memory.
"""
import bisect
import json
import re
import statistics as st
import sys
from pathlib import Path

from perfetto.trace_processor import TraceProcessor

GC_NAMES = ("CollectNewGeneration", "CollectOldGeneration", "Scavenge", "MarkSweep",
            "MarkCompact", "StartConcurrentMark", "FinalizeMarking", "EvacuateNewGeneration",
            "Sweep", "Compact", "ConcurrentMark", "CollectAllGarbage")


def pct(values, p):
    if not values:
        return None
    s = sorted(values)
    return s[round((len(s) - 1) * p)]


def union_ms(intervals):
    total = 0
    end = -1
    for a, b in sorted(intervals):
        if a > end:
            total += b - a
            end = b
        elif b > end:
            total += b - end
            end = b
    return total / 1e6


def analyze_run(run_dir: Path):
    run = json.loads((run_dir / "run.json").read_text())
    res = {k: run.get(k) for k in ("arm", "scenario", "rep", "status", "skinC", "cooldownS")}
    s = run.get("summary") or {}
    frames = run.get("frames") or []
    measure = 12
    meta = run_dir.parent / "meta.json"
    if meta.exists():
        measure = json.loads(meta.read_text())["measure"]
    res["fps"] = (s.get("frameCount") or 0) / measure
    b = [f[0] / 1000 for f in frames]
    r = [f[1] / 1000 for f in frames]
    res.update(buildP50=pct(b, .5), buildP95=pct(b, .95), rasterP50=pct(r, .5),
               rasterP95=pct(r, .95), rasterP99=pct(r, .99),
               jank=sum(1 for x, y in zip(b, r) if max(x, y) > 8.33) / max(1, len(frames)))
    if not frames:
        for key, src in (("buildP95", "buildP95Micros"), ("rasterP50", "rasterP50Micros"),
                         ("rasterP95", "rasterP95Micros"), ("rasterP99", "rasterP99Micros")):
            res[key] = s[src] / 1000 if s.get(src) is not None else None
        res["jank"] = None
    trace = run_dir / "trace.pftrace"
    mem = run.get("mem") or []
    if not trace.exists():
        return res
    tp = TraceProcessor(trace=str(trace))
    q = lambda sql: list(tp.query(sql))
    pid_rows = q(f"select upid, pid from process where name = '{run['pkg']}' order by upid desc limit 1")
    if not pid_rows:
        tp.close()
        return res
    upid, pid = pid_rows[0].upid, pid_rows[0].pid
    t0, t1 = [(x.a, x.b) for x in q("select trace_start() a, trace_end() b")][0]
    # Frames in window from the app's raster slices.
    nframes = q(f"""select count(*) n from slice s join thread_track tt on s.track_id=tt.id
        join thread using(utid) where upid={upid} and s.name='GPURasterizer::Draw'""")[0].n
    res["traceFrames"] = nframes
    win_s = (t1 - t0) / 1e9
    # GPU work period (slice name is active percent) for the app UID.
    uid = run.get("uid")
    wp = []
    if uid:
        wp = q(f"""select s.ts, s.dur, s.name from slice s join track t on s.track_id=t.id
            join args a on a.arg_set_id=t.dimension_arg_set_id
            where t.type='android_gpu_work_period' and a.key='uid' and a.int_value={uid}""")
    freq = q("""select c.ts, c.value from counter c join counter_track t on c.track_id=t.id
        where t.name='gpufreq' order by c.ts""")
    fts = [x.ts for x in freq]
    active_ns = 0.0
    cycles = 0.0
    for x in wp:
        m = re.search(r"([\d.]+)", x.name or "100")
        frac = float(m.group(1)) / 100 if m else 1.0
        dur = x.dur * frac
        active_ns += dur
        i = bisect.bisect_right(fts, x.ts) - 1
        f = freq[i].value if i >= 0 else (freq[0].value if freq else 0)
        cycles += dur / 1e9 * f
    res["gpuBusyPct"] = active_ns / (t1 - t0) * 100
    res["gpuMsPerFrame"] = active_ns / 1e6 / nframes if nframes else None
    res["gpuMcyclesPerFrame"] = cycles / 1e6 / nframes if nframes else None
    if freq:
        # time-weighted mean frequency in window
        tot = 0.0
        for i, x in enumerate(freq):
            a = max(x.ts, t0)
            e = freq[i + 1].ts if i + 1 < len(freq) else t1
            e = min(e, t1)
            if e > a:
                tot += (e - a) * x.value
        res["gpuMHz"] = tot / (t1 - t0) / 1e6
    rail = q("""select c.ts, c.value from counter c join counter_track t on c.track_id=t.id
        where t.name='power.S2S_VDD_GPU_uws' order by c.ts""")
    if len(rail) >= 2:
        mw = (rail[-1].value - rail[0].value) / ((rail[-1].ts - rail[0].ts) / 1e9) / 1000
        res["gpuRailMw"] = mw
        res["gpuMjPerFrame"] = mw * win_s / nframes if nframes else None
    # Rail groups as in example/tool/android_gpu_bench_analyze.py.
    groups = {"gpuMemMw": 0.0, "cpuMw": 0.0, "ddrMw": 0.0, "displayMw": 0.0}
    for r in q("""select t.name, max(c.value) - min(c.value) e, max(c.ts) - min(c.ts) d
            from counter c join counter_track t on c.track_id=t.id
            where t.name glob 'power.*_uws' group by t.name"""):
        if not r.d:
            continue
        u, mw_r = r.name.upper(), r.e / (r.d / 1e9) / 1000
        key = ("gpuMemMw" if "INFRA_MM_GPU" in u else "cpuMw" if "VDD_CPU" in u
               else "ddrMw" if "GMC" in u else "displayMw" if "DISP" in u else None)
        if key:
            groups[key] += mw_r
    if res.get("gpuRailMw") is not None:
        res.update(groups)
        res["socMw"] = res["gpuRailMw"] + groups["gpuMemMw"] + groups["cpuMw"] + groups["ddrMw"]
    # GPU memory for the process.
    gm = q(f"""select c.ts, c.value from counter c join process_counter_track t on c.track_id=t.id
        where t.name='GPU Memory' and t.upid={upid} order by c.ts""")
    if gm:
        vals = [x.value / 1048576 for x in gm]
        res["gpuMemPeakMB"] = max(vals)
        res["gpuMemMinMB"] = min(vals)
        res["gpuMemP50MB"] = pct(vals, .5)
    # UI-thread GC.
    names = ",".join(f"'{n}'" for n in GC_NAMES)
    gc = q(f"""select s.ts, s.dur, s.name, s.depth from slice s join thread_track tt on s.track_id=tt.id
        join thread th using(utid) where th.tid={pid} and s.name in ({names})""")
    gc_all = q(f"""select s.ts, s.dur from slice s join thread_track tt on s.track_id=tt.id
        join thread th using(utid) where th.upid={upid} and s.name in ({names})""")
    ui_ms = union_ms([(x.ts, x.ts + x.dur) for x in gc])
    res["uiGcMsPerS"] = ui_ms / win_s
    res["uiGcMsPerFrame"] = ui_ms / nframes if nframes else None
    tops = [x for x in gc if x.name in ("CollectNewGeneration", "CollectOldGeneration")]
    res["uiGcCount"] = len(tops)
    res["uiGcMaxMs"] = max((x.dur / 1e6 for x in gc), default=0)
    res["allGcMsPerS"] = union_ms([(x.ts, x.ts + x.dur) for x in gc_all]) / win_s
    paint = q(f"""select s.dur from slice s join thread_track tt on s.track_id=tt.id
        join thread th using(utid) where th.tid={pid} and s.name='PAINT (root)'""")
    subs = q(f"""select count(*) n from slice s join thread_track tt on s.track_id=tt.id
        join thread th using(utid) where th.tid={pid} and s.name='QueueSubmit'""")[0].n
    res["uiQueueSubmitPerFrame"] = subs / nframes if nframes else None
    if paint:
        pd = [x.dur / 1e6 for x in paint]
        res["paintMsPerFrame"] = sum(pd) / nframes if nframes else None
        res["paintP50"] = pct(pd, .5)
        res["paintP95"] = pct(pd, .95)
    # Continuous PSS: smaps rollup (in-app, 50 ms) + process GPU memory.
    if mem:
        gts = [x.ts for x in gm]
        combined = []
        for row in mem:
            t_ns = row[0] * 1000
            pss_mb = row[1] / 1048576
            i = bisect.bisect_right(gts, t_ns) - 1
            g = gm[i].value / 1048576 if i >= 0 and gm else (gm[0].value / 1048576 if gm else 0)
            if gm and (t_ns < t0 or t_ns > t1):
                continue
            combined.append((t_ns, pss_mb, pss_mb + g))
        if combined:
            res["smapsPssPeakMB"] = max(c[1] for c in combined)
            res["pssTotalPeakMB"] = max(c[2] for c in combined)
            res["pssTotalP50MB"] = pct([c[2] for c in combined], .5)
            res["pssTotalMinMB"] = min(c[2] for c in combined)
            steps = [b2[2] - a2[2] for a2, b2 in zip(combined, combined[1:])]
            res["pssMaxRise50msMB"] = max(steps, default=0)
    mi = (run_dir / "meminfo.txt").read_text() if (run_dir / "meminfo.txt").exists() else ""
    m = re.search(r"TOTAL PSS:\s+(\d+)", mi)
    g = re.search(r"Graphics:\s+(\d+)", mi)
    if m:
        res["dumpsysPssMB"] = int(m.group(1)) / 1024
    if g:
        res["dumpsysGraphicsMB"] = int(g.group(1)) / 1024
    tp.close()
    return res


METRICS = ["fps", "buildP50", "buildP95", "rasterP50", "rasterP95", "rasterP99", "jank",
           "gpuMsPerFrame", "gpuMcyclesPerFrame", "gpuMHz", "gpuBusyPct", "gpuRailMw",
           "gpuMjPerFrame", "gpuMemMw", "cpuMw", "ddrMw", "socMw", "displayMw", "paintMsPerFrame",
           "uiQueueSubmitPerFrame", "uiGcMsPerS", "uiGcCount", "uiGcMaxMs", "allGcMsPerS",
           "gpuMemPeakMB", "gpuMemP50MB", "smapsPssPeakMB", "pssTotalPeakMB", "pssTotalP50MB",
           "pssMaxRise50msMB", "dumpsysPssMB", "dumpsysGraphicsMB", "skinC"]


def main():
    out = Path(sys.argv[1])
    cache = out / "analysis.json"
    rows = json.loads(cache.read_text()) if cache.exists() else {}
    for d in sorted(out.iterdir()):
        if d.is_dir() and (d / "run.json").exists() and d.name not in rows:
            try:
                rows[d.name] = analyze_run(d)
            except Exception as e:  # noqa: BLE001
                print("fail", d.name, e)
    cache.write_text(json.dumps(rows, indent=1))
    groups = {}
    for name, r in rows.items():
        if not str(r.get("status", "")).startswith("ok") or "error" in str(r.get("status")):
            continue
        groups.setdefault((r["scenario"], r["arm"]), []).append(r)
    lines = []
    for metric in METRICS:
        lines.append(f"\n### {metric}\n\n| scenario | arm | n | median | min | max | CV% |\n|---|---|---:|---:|---:|---:|---:|")
        for (scen, arm), rs in sorted(groups.items()):
            vals = [x[metric] for x in rs if x.get(metric) is not None]
            if not vals:
                continue
            med = st.median(vals)
            cv = (st.pstdev(vals) / st.mean(vals) * 100) if len(vals) > 1 and st.mean(vals) else 0
            lines.append(f"| {scen} | {arm} | {len(vals)} | {med:.3f} | {min(vals):.3f} | {max(vals):.3f} | {cv:.1f} |")
    (out / "summary.md").write_text("\n".join(lines))
    summary = {f"{scen}|{arm}": {m: st.median([x[m] for x in rs if x.get(m) is not None])
                                 for m in METRICS if any(x.get(m) is not None for x in rs)}
               for (scen, arm), rs in groups.items()}
    (out / "summary.json").write_text(json.dumps(summary, indent=1))


if __name__ == "__main__":
    main()
