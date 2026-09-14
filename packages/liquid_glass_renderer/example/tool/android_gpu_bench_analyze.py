#!/usr/bin/env python3
"""Analyze Android GPU-power benchmark runs into summary.md / summary.json."""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
from pathlib import Path
from statistics import median
from typing import Any, Iterable

try:
    from perfetto.trace_processor import TraceProcessor
except ImportError:
    sys.stderr.write(
        "error: the 'perfetto' module is missing.\n"
        "Create the venv and install it:\n"
        "  python3 -m venv packages/liquid_glass_renderer/example/tool/.venv-android-bench\n"
        "  packages/liquid_glass_renderer/example/tool/.venv-android-bench/bin/pip install perfetto\n"
    )
    sys.exit(2)


NA = "N/A"
TEMP_RE = re.compile(
    r"Temperature\{mValue=([^,]+),[^}]*mName=([^,}]+)"
)


def _num(value: Any) -> float | None:
    if value is None:
        return None
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        if isinstance(value, float) and not math.isfinite(value):
            return None
        return float(value)
    try:
        parsed = float(str(value).strip())
    except (TypeError, ValueError):
        return None
    return parsed if math.isfinite(parsed) else None


def _read_text(path: Path) -> str:
    if not path.is_file():
        return ""
    return path.read_text(encoding="utf-8", errors="replace").replace("\r", "")


def _read_json(path: Path) -> Any:
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None


def _rows(tp: Any, sql: str) -> list[Any]:
    try:
        return list(tp.query(sql))
    except Exception:
        return []


def _first_last_by_name(rows: Iterable[Any]) -> dict[str, tuple[float, float, int, int]]:
    grouped: dict[str, list[tuple[int, float]]] = {}
    for row in rows:
        name = getattr(row, "name", None)
        ts = _num(getattr(row, "ts", None))
        value = _num(getattr(row, "value", None))
        if not name or ts is None or value is None:
            continue
        grouped.setdefault(str(name), []).append((int(ts), value))
    result: dict[str, tuple[float, float, int, int]] = {}
    for name, points in grouped.items():
        points.sort(key=lambda item: item[0])
        result[name] = (points[0][1], points[-1][1], points[0][0], points[-1][0])
    return result


def _avg_mw(first: float, last: float, duration_s: float) -> float | None:
    if duration_s <= 0:
        return None
    return (last - first) / duration_s / 1000.0


def _classify_rail(name: str) -> str:
    upper = name.upper()
    if "S2S_VDD_GPU" in upper and "INFRA" not in upper:
        return "gpu"
    if "INFRA_MM_GPU" in upper or (
        "GPU" in upper and ("INFRA" in upper or "MEM" in upper) and "S2S_VDD_GPU" not in upper
    ):
        return "gpu_mem"
    if "VDD_CPU" in upper or re.search(r"CPU\d", upper):
        return "cpu"
    if "DISP" in upper:
        return "display"
    if "VBATT" in upper:
        return "vbatt"
    if (
        "DDR" in upper
        or "GMC" in upper
        or (re.search(r"(?:^|_)MEM(?:_|$)", upper) and "GPU" not in upper)
    ):
        return "ddr"
    return "other"


def _weighted_freq(points: list[tuple[int, float]]) -> dict[str, Any]:
    if len(points) < 2:
        if not points:
            return {
                "mean_mhz": None,
                "off_pct": None,
                "residency": {},
            }
        hz = points[0][1]
        return {
            "mean_mhz": hz / 1e6,
            "off_pct": 100.0 if hz <= 0 else 0.0,
            "residency": {str(int(hz)): 1.0},
        }
    points = sorted(points, key=lambda item: item[0])
    total_ns = 0
    weighted = 0.0
    off_ns = 0
    buckets: dict[int, int] = {}
    for (ts0, hz), (ts1, _) in zip(points, points[1:]):
        dt = ts1 - ts0
        if dt <= 0:
            continue
        total_ns += dt
        weighted += hz * dt
        key = int(hz)
        buckets[key] = buckets.get(key, 0) + dt
        if hz <= 0:
            off_ns += dt
    if total_ns <= 0:
        return {"mean_mhz": None, "off_pct": None, "residency": {}}
    residency = {
        str(hz): dt / total_ns for hz, dt in sorted(buckets.items())
    }
    return {
        "mean_mhz": (weighted / total_ns) / 1e6,
        "off_pct": 100.0 * off_ns / total_ns,
        "residency": residency,
    }


def _analyze_trace(trace_path: Path, package: str) -> dict[str, Any]:
    result: dict[str, Any] = {
        "trace": str(trace_path),
        "available": False,
        "rails_mw": {},
        "rail_groups_mw": {},
        "gpu_freq": {},
        "frames": {},
        "gpu_work_period_slices": None,
        "gpu_tracks": [],
        "raster_thread_slices": {
            "threadNames": [],
            "slices": [],
        },
        "error": None,
    }
    if not trace_path.is_file():
        result["error"] = "missing trace"
        return result
    try:
        tp = TraceProcessor(trace=str(trace_path))
    except Exception as error:  # noqa: BLE001
        result["error"] = f"TraceProcessor open failed: {error}"
        return result
    try:
        power_rows = _rows(
            tp,
            """
            SELECT ct.name AS name, c.ts AS ts, c.value AS value
            FROM counter c
            JOIN counter_track ct ON c.track_id = ct.id
            WHERE ct.name GLOB 'power.*_uws'
            ORDER BY ct.name, c.ts
            """,
        )
        series = _first_last_by_name(power_rows)
        duration_s = None
        rails_mw: dict[str, float | None] = {}
        groups: dict[str, float] = {
            "gpu": 0.0,
            "gpu_mem": 0.0,
            "cpu": 0.0,
            "display": 0.0,
            "ddr": 0.0,
            "vbatt": 0.0,
        }
        group_seen = {key: False for key in groups}
        for name, (first, last, t0, t1) in series.items():
            window = (t1 - t0) / 1e9
            if duration_s is None or window > duration_s:
                duration_s = window
            mw = _avg_mw(first, last, window)
            rails_mw[name] = mw
            kind = _classify_rail(name)
            if mw is not None and kind in groups:
                groups[kind] += mw
                group_seen[kind] = True
        result["duration_s"] = duration_s
        result["rails_mw"] = rails_mw
        result["rail_groups_mw"] = {
            key: (groups[key] if group_seen[key] else None) for key in groups
        }

        freq_rows = _rows(
            tp,
            """
            SELECT c.ts AS ts, c.value AS value
            FROM counter c
            JOIN counter_track ct ON c.track_id = ct.id
            WHERE ct.name = 'gpufreq'
            ORDER BY c.ts
            """,
        )
        points = []
        for row in freq_rows:
            ts = _num(getattr(row, "ts", None))
            value = _num(getattr(row, "value", None))
            if ts is None or value is None:
                continue
            points.append((int(ts), value))
        result["gpu_freq"] = _weighted_freq(points)

        package_sql = package.replace("'", "''")
        frame_rows = _rows(
            tp,
            f"""
            SELECT
              COUNT(*) AS frames,
              SUM(CASE WHEN jank_type != 'None' THEN 1 ELSE 0 END) AS jank
            FROM actual_frame_timeline_slice
            JOIN process USING (upid)
            WHERE process.name = '{package_sql}'
            """,
        )
        frames = None
        jank = None
        if frame_rows:
            frames = _num(getattr(frame_rows[0], "frames", None))
            jank = _num(getattr(frame_rows[0], "jank", None))
        if not frames:
            alt = _rows(
                tp,
                """
                SELECT
                  COUNT(*) AS frames,
                  SUM(CASE WHEN jank_type != 'None' THEN 1 ELSE 0 END) AS jank
                FROM actual_frame_timeline_slice
                """,
            )
            if alt:
                frames = _num(getattr(alt[0], "frames", None))
                jank = _num(getattr(alt[0], "jank", None))
        result["frames"] = {
            "count": int(frames) if frames is not None else None,
            "jank": int(jank) if jank is not None else None,
        }

        work = _rows(
            tp,
            """
            SELECT COUNT(*) AS n
            FROM slice
            WHERE name LIKE '%work_period%' OR name LIKE 'GPU Work%'
            """,
        )
        if work:
            result["gpu_work_period_slices"] = int(
                _num(getattr(work[0], "n", None)) or 0
            )
        tracks = _rows(
            tp,
            """
            SELECT name FROM track
            WHERE name LIKE '%gpu%' OR name LIKE '%GPU%'
            ORDER BY name
            """,
        )
        result["gpu_tracks"] = [
            str(getattr(row, "name", ""))
            for row in tracks
            if getattr(row, "name", None)
        ]
        result["raster_thread_slices"] = _query_raster_slices(tp, package)
        result["available"] = True
    except Exception as error:  # noqa: BLE001
        result["error"] = str(error)
    finally:
        close = getattr(tp, "close", None)
        if callable(close):
            close()
    return result


def _query_raster_slices(tp: Any, package: str) -> dict[str, Any]:
    """Top Impeller/Flutter slices on the app raster thread.

    Pixel traces often omit thread names (no proc comm). Identify the
    raster thread by ``Rasterizer::DoDraw`` / ``GPURasterizer::Draw``
    when the name does not contain ``raster``.
    """
    empty: dict[str, Any] = {"threadNames": [], "slices": []}
    _ = package
    raster_where = """
      (
        thread.name GLOB '*raster*'
        OR thread.name GLOB '*Raster*'
        OR thread.name GLOB '*io.flutter.raster*'
        OR thread.utid IN (
          SELECT thread.utid
          FROM slice
          JOIN thread_track ON slice.track_id = thread_track.id
          JOIN thread ON thread_track.utid = thread.utid
          WHERE slice.name IN (
            'Rasterizer::DoDraw',
            'GPURasterizer::Draw'
          )
        )
      )
    """
    thread_rows = _rows(
        tp,
        f"""
        SELECT DISTINCT
          COALESCE(thread.name, '') AS name,
          thread.tid AS tid
        FROM thread
        WHERE {raster_where}
        ORDER BY thread.tid
        """,
    )
    thread_names = []
    for row in thread_rows:
        name = str(getattr(row, "name", "") or "")
        tid = getattr(row, "tid", None)
        if name:
            thread_names.append(name)
        elif tid is not None:
            thread_names.append(f"tid:{int(tid)} (Rasterizer::DoDraw)")
    if not thread_names:
        return empty

    rows = _rows(
        tp,
        f"""
        SELECT
          slice.name AS name,
          COUNT(*) AS cnt,
          SUM(slice.dur) AS total_dur_ns,
          AVG(slice.dur) AS mean_dur_ns
        FROM slice
        JOIN thread_track ON slice.track_id = thread_track.id
        JOIN thread ON thread_track.utid = thread.utid
        WHERE {raster_where}
          AND slice.dur > 0
          AND slice.name IS NOT NULL
        GROUP BY slice.name
        ORDER BY total_dur_ns DESC
        LIMIT 25
        """,
    )
    slices = []
    for row in rows:
        name = getattr(row, "name", None)
        count = _num(getattr(row, "cnt", None))
        total_ns = _num(getattr(row, "total_dur_ns", None))
        mean_ns = _num(getattr(row, "mean_dur_ns", None))
        if not name or count is None or total_ns is None:
            continue
        slices.append(
            {
                "name": str(name),
                "count": int(count),
                "totalUs": total_ns / 1e3,
                "meanUs": (mean_ns / 1e3) if mean_ns is not None else None,
            }
        )
    return {"threadNames": thread_names, "slices": slices}


def _with_slice_rates(
    profile: dict[str, Any], frame_count: float | None
) -> dict[str, Any]:
    frames = frame_count if frame_count and frame_count > 0 else None
    slices = []
    for item in profile.get("slices") or []:
        count = _num(item.get("count"))
        enriched = dict(item)
        enriched["countPerFrame"] = (
            count / frames if frames is not None and count is not None else None
        )
        slices.append(enriched)
    return {
        "threadNames": list(profile.get("threadNames") or []),
        "frameCount": int(frames) if frames is not None else None,
        "slices": slices,
    }


def _parse_uid_time(path: Path, uid: str | None) -> dict[str, float]:
    text = _read_text(path)
    if not text or not uid:
        return {}
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    if not lines:
        return {}
    header = lines[0]
    freqs: list[str] = []
    if header.lower().startswith("uid:"):
        freqs = header.split(":", 1)[1].split()
    values: list[float] = []
    for line in lines[1:]:
        if not line.startswith(f"{uid}:") and not line.startswith(f"{uid} "):
            continue
        _, _, rest = line.partition(":")
        if not rest:
            parts = line.split()
            rest = " ".join(parts[1:])
        values = [_num(part) or 0.0 for part in rest.split()]
        break
    if not values:
        return {}
    if freqs and len(freqs) == len(values):
        return {freq: values[i] for i, freq in enumerate(freqs)}
    return {str(i): value for i, value in enumerate(values)}


def _parse_power_state(path: Path) -> dict[str, float]:
    text = _read_text(path).strip()
    if not text:
        return {}
    numbers = [_num(part) for part in text.replace(",", " ").split()]
    numbers = [value for value in numbers if value is not None]
    if len(numbers) >= 3:
        return {"off": numbers[0], "pg": numbers[1], "on": numbers[2]}
    return {}


def _parse_trans_stat(path: Path) -> dict[str, float]:
    text = _read_text(path)
    residency: dict[str, float] = {}
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.lower().startswith("from") or stripped.lower().startswith("total"):
            continue
        if stripped.startswith(":"):
            continue
        match = re.match(r"\*?[\s]*(\d+)\s*:\s*(.+)$", stripped)
        if not match:
            continue
        freq = match.group(1)
        cols = match.group(2).split()
        if not cols:
            continue
        last = _num(cols[-1])
        if last is not None:
            residency[freq] = last
    return residency


def _parse_thermals(path: Path) -> dict[str, float]:
    text = _read_text(path)
    section = text
    marker = "Current temperatures"
    if marker in text:
        section = text.split(marker, 1)[1]
    found: dict[str, float] = {}
    for match in TEMP_RE.finditer(section):
        name = match.group(2).strip()
        value = _num(match.group(1))
        if value is None:
            continue
        if name in {"VIRTUAL-SKIN", "soc_therm"}:
            found[name] = value
    return found


def _delta_map(begin: dict[str, float], end: dict[str, float]) -> dict[str, float]:
    keys = set(begin) | set(end)
    return {key: end.get(key, 0.0) - begin.get(key, 0.0) for key in sorted(keys)}


def _snapshot_metrics(run_dir: Path, uid: str | None, wall_s: float | None) -> dict[str, Any]:
    begin = run_dir / "begin"
    end = run_dir / "end"
    uid_delta = _delta_map(
        _parse_uid_time(begin / "uid_time_in_state.txt", uid),
        _parse_uid_time(end / "uid_time_in_state.txt", uid),
    )
    gpu_active_ms = sum(uid_delta.values()) if uid_delta else None
    busy_pct = None
    if gpu_active_ms is not None and wall_s and wall_s > 0:
        busy_pct = 100.0 * (gpu_active_ms / 1000.0) / wall_s
    therm_begin = _parse_thermals(begin / "thermalservice.txt")
    therm_end = _parse_thermals(end / "thermalservice.txt")
    return {
        "uid": uid,
        "gpu_active_ms": gpu_active_ms,
        "gpu_busy_pct_app": busy_pct,
        "power_state_delta_ms": _delta_map(
            _parse_power_state(begin / "power_state_time_in_state_ms.txt"),
            _parse_power_state(end / "power_state_time_in_state_ms.txt"),
        ),
        "trans_stat_delta_ms": _delta_map(
            _parse_trans_stat(begin / "trans_stat.txt"),
            _parse_trans_stat(end / "trans_stat.txt"),
        ),
        "battery_current_now_ua": {
            "begin": _num(_read_text(begin / "battery_current_now.txt").strip()),
            "end": _num(_read_text(end / "battery_current_now.txt").strip()),
            "note": "informational; USB charging pollutes this node",
        },
        "thermal": {
            "skin_begin": therm_begin.get("VIRTUAL-SKIN"),
            "skin_end": therm_end.get("VIRTUAL-SKIN"),
            "soc_begin": therm_begin.get("soc_therm"),
            "soc_end": therm_end.get("soc_therm"),
        },
    }


def _discover_runs(out_dir: Path) -> list[Path]:
    runs: list[Path] = []
    for child in sorted(out_dir.iterdir() if out_dir.is_dir() else []):
        if not child.is_dir() or child.name.startswith("."):
            continue
        if (child / "run.json").is_file() or (child / "trace.pftrace").is_file():
            runs.append(child)
    return runs


def _analyze_run(run_dir: Path) -> dict[str, Any]:
    meta = _read_json(run_dir / "run.json") or {}
    flutter = _read_json(run_dir / "flutter_summary.json") or meta.get("flutterSummary")
    package = str(meta.get("package") or "com.example.liquid_glass_renderer_example")
    uid = meta.get("uid") or _read_text(run_dir / "begin" / "uid.txt").strip() or None
    measure_s = _num(meta.get("measureSeconds"))
    wall_s = _num(meta.get("wallSeconds")) or measure_s
    skip_analysis = bool(meta.get("skipAnalysis"))
    if skip_analysis:
        trace = {
            "trace": str(run_dir / "trace.pftrace"),
            "available": False,
            "rails_mw": {},
            "rail_groups_mw": {},
            "gpu_freq": {},
            "frames": {},
            "gpu_work_period_slices": None,
            "gpu_tracks": [],
            "raster_thread_slices": {"threadNames": [], "slices": []},
            "error": f"skipped: {meta.get('failureReason') or 'no-frames'}",
        }
    else:
        trace = _analyze_trace(run_dir / "trace.pftrace", package)
    if wall_s is None:
        wall_s = _num(trace.get("duration_s"))
    sysfs = _snapshot_metrics(run_dir, uid, wall_s)
    frame_count = None
    raster_p50 = None
    raster_p95 = None
    raster_p99 = None
    total_p95 = None
    fps = None
    if isinstance(flutter, dict):
        frame_count = _num(flutter.get("frameCount"))
        raster_p50 = _num(flutter.get("rasterP50Micros"))
        raster_p95 = _num(flutter.get("rasterP95Micros"))
        raster_p99 = _num(flutter.get("rasterP99Micros"))
        total_p95 = _num(flutter.get("totalP95Micros"))
        if frame_count is not None and measure_s and measure_s > 0:
            fps = frame_count / measure_s
    rails = trace.get("rail_groups_mw") or {}
    gpu_freq = trace.get("gpu_freq") or {}
    thermal = sysfs.get("thermal") or {}
    skin_begin = _num(thermal.get("skin_begin"))
    skin_end = _num(thermal.get("skin_end"))
    return {
        "dir": run_dir.name,
        "scenario": meta.get("scenario") or meta.get("label") or run_dir.name,
        "repetition": meta.get("repetition"),
        "status": meta.get("status") or "ok",
        "failureReason": meta.get("failureReason"),
        "package": package,
        "measureSeconds": measure_s,
        "flutter": flutter,
        "fps": fps,
        "frameCount": frame_count,
        "rasterP50Micros": raster_p50,
        "rasterP95Micros": raster_p95,
        "rasterP99Micros": raster_p99,
        "totalP95Micros": total_p95,
        "gpu_mw": rails.get("gpu"),
        "gpu_mem_mw": rails.get("gpu_mem"),
        "ddr_mw": rails.get("ddr"),
        "cpu_mw": rails.get("cpu"),
        "display_mw": rails.get("display"),
        "vbatt_mw": rails.get("vbatt"),
        "gpu_mhz_mean": gpu_freq.get("mean_mhz"),
        "gpu_off_pct": gpu_freq.get("off_pct"),
        "gpu_busy_pct_app": sysfs.get("gpu_busy_pct_app"),
        "skin_delta_c": (
            skin_end - skin_begin
            if skin_begin is not None and skin_end is not None
            else None
        ),
        "soc_delta_c": (
            (_num(thermal.get("soc_end")) - _num(thermal.get("soc_begin")))
            if _num(thermal.get("soc_begin")) is not None
            and _num(thermal.get("soc_end")) is not None
            else None
        ),
        "trace": trace,
        "sysfs": sysfs,
        "skipAnalysis": skip_analysis,
        "rasterThreadSliceProfile": _with_slice_rates(
            trace.get("raster_thread_slices") or {},
            frame_count,
        ),
    }


def _fmt(value: Any, digits: int = 1, scale: float = 1.0, suffix: str = "") -> str:
    number = _num(value)
    if number is None:
        return NA
    number *= scale
    rendered = f"{number:.{digits}f}"
    return f"{rendered}{suffix}"


def _fmt_group(values: list[Any], digits: int = 1, scale: float = 1.0) -> str:
    numbers = [_num(value) for value in values]
    numbers = [value for value in numbers if value is not None]
    if not numbers:
        return NA
    mid = median(numbers)
    lo = min(numbers)
    hi = max(numbers)
    if len(numbers) == 1 or lo == hi:
        return _fmt(mid, digits=digits, scale=scale)
    return (
        f"{_fmt(mid, digits=digits, scale=scale)} "
        f"({_fmt(lo, digits=digits, scale=scale)}–{_fmt(hi, digits=digits, scale=scale)})"
    )


def _md_escape(value: Any) -> str:
    return str(value).replace("|", "\\|")


def _write_table(lines: list[str], headers: list[str], rows: list[list[str]]) -> None:
    lines.append("| " + " | ".join(headers) + " |")
    lines.append("| " + " | ".join("---" for _ in headers) + " |")
    for row in rows:
        lines.append("| " + " | ".join(_md_escape(cell) for cell in row) + " |")
    lines.append("")


def _scenario_groups(runs: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    grouped: dict[str, list[dict[str, Any]]] = {}
    for run in runs:
        grouped.setdefault(str(run["scenario"]), []).append(run)
    return dict(sorted(grouped.items()))


def _build_markdown(out_dir: Path, runs: list[dict[str, Any]]) -> str:
    lines = [
        "# Android GPU power benchmark",
        "",
        f"Output: `{out_dir}`",
        "",
        "Values are the median across repetitions, with min–max in parentheses "
        "when they differ. Frame time alone can hide a GPU that is pinned just "
        "inside the vsync budget; GPU rail milliwatts are the ground-truth load.",
        "",
        "## Headline",
        "",
    ]
    grouped = _scenario_groups(runs)
    headline_rows = []
    for scenario, items in grouped.items():
        headline_rows.append(
            [
                scenario,
                _fmt_group([item.get("fps") for item in items], digits=1),
                _fmt_group(
                    [item.get("rasterP50Micros") for item in items],
                    digits=2,
                    scale=1e-3,
                ),
                _fmt_group(
                    [item.get("rasterP95Micros") for item in items],
                    digits=2,
                    scale=1e-3,
                ),
                _fmt_group([item.get("gpu_mw") for item in items], digits=0),
                _fmt_group([item.get("gpu_mem_mw") for item in items], digits=0),
                _fmt_group([item.get("ddr_mw") for item in items], digits=0),
                _fmt_group([item.get("cpu_mw") for item in items], digits=0),
                _fmt_group([item.get("display_mw") for item in items], digits=0),
                _fmt_group([item.get("vbatt_mw") for item in items], digits=0),
                _fmt_group([item.get("gpu_mhz_mean") for item in items], digits=0),
                _fmt_group(
                    [item.get("gpu_busy_pct_app") for item in items],
                    digits=1,
                ),
                _fmt_group([item.get("skin_delta_c") for item in items], digits=2),
            ]
        )
    _write_table(
        lines,
        [
            "scenario",
            "fps",
            "raster p50",
            "raster p95",
            "GPU mW",
            "GPU-mem mW",
            "DDR mW",
            "CPU mW",
            "Display mW",
            "VBATT mW",
            "GPU MHz mean",
            "GPU busy % (app)",
            "ΔSkin °C",
        ],
        headline_rows,
    )

    def metric_table(title: str, cells: list[tuple[str, Any]]) -> None:
        lines.append(f"## {title}")
        lines.append("")
        rows = []
        for scenario, items in grouped.items():
            row = [scenario]
            for key, digits_scale in cells:
                digits, scale = digits_scale
                row.append(
                    _fmt_group(
                        [item.get(key) for item in items],
                        digits=digits,
                        scale=scale,
                    )
                )
            rows.append(row)
        _write_table(
            lines,
            ["scenario"] + [key for key, _ in cells],
            rows,
        )

    metric_table(
        "Flutter frames",
        [
            ("fps", (1, 1.0)),
            ("frameCount", (0, 1.0)),
            ("rasterP50Micros", (2, 1e-3)),
            ("rasterP95Micros", (2, 1e-3)),
            ("rasterP99Micros", (2, 1e-3)),
            ("totalP95Micros", (2, 1e-3)),
        ],
    )
    metric_table(
        "Power rails (mW)",
        [
            ("gpu_mw", (0, 1.0)),
            ("gpu_mem_mw", (0, 1.0)),
            ("ddr_mw", (0, 1.0)),
            ("cpu_mw", (0, 1.0)),
            ("display_mw", (0, 1.0)),
            ("vbatt_mw", (0, 1.0)),
        ],
    )
    metric_table(
        "GPU frequency and busy",
        [
            ("gpu_mhz_mean", (0, 1.0)),
            ("gpu_off_pct", (1, 1.0)),
            ("gpu_busy_pct_app", (1, 1.0)),
        ],
    )
    metric_table(
        "Thermal",
        [
            ("skin_delta_c", (2, 1.0)),
            ("soc_delta_c", (2, 1.0)),
        ],
    )

    failed = [run for run in runs if run.get("status") != "ok"]
    if failed:
        lines.append("## Failures")
        lines.append("")
        _write_table(
            lines,
            ["scenario", "repetition", "reason"],
            [
                [
                    str(run.get("scenario")),
                    str(run.get("repetition") or ""),
                    str(run.get("failureReason") or "failed"),
                ]
                for run in failed
            ],
        )

    lines.append("## Appendix: per-run rows")
    lines.append("")
    appendix = []
    for run in runs:
        appendix.append(
            [
                str(run.get("dir")),
                str(run.get("scenario")),
                str(run.get("repetition") or ""),
                str(run.get("status")),
                _fmt(run.get("fps"), digits=1),
                _fmt(run.get("rasterP50Micros"), digits=2, scale=1e-3),
                _fmt(run.get("rasterP95Micros"), digits=2, scale=1e-3),
                _fmt(run.get("gpu_mw"), digits=0),
                _fmt(run.get("gpu_mem_mw"), digits=0),
                _fmt(run.get("ddr_mw"), digits=0),
                _fmt(run.get("cpu_mw"), digits=0),
                _fmt(run.get("display_mw"), digits=0),
                _fmt(run.get("vbatt_mw"), digits=0),
                _fmt(run.get("gpu_mhz_mean"), digits=0),
                _fmt(run.get("gpu_busy_pct_app"), digits=1),
                _fmt(run.get("skin_delta_c"), digits=2),
            ]
        )
    _write_table(
        lines,
        [
            "run",
            "scenario",
            "rep",
            "status",
            "fps",
            "raster p50",
            "raster p95",
            "GPU mW",
            "GPU-mem mW",
            "DDR mW",
            "CPU mW",
            "Display mW",
            "VBATT mW",
            "GPU MHz",
            "GPU busy %",
            "ΔSkin °C",
        ],
        appendix,
    )

    lines.append("## Appendix: raster-thread slice profile (repetition 1)")
    lines.append("")
    lines.append(
        "Impeller/Flutter slices on the app raster thread "
        "(thread name contains `raster` or `io.flutter.raster`). "
        "Count/frame uses the Flutter SUMMARY `frameCount`. "
        "This is the pass-structure X-ray: how many "
        "`FlipBackdrop` / `SaveLayer` / blur / runtime-effect "
        "passes each scenario issues per frame."
    )
    lines.append("")
    for scenario, items in grouped.items():
        rep1 = next(
            (
                item
                for item in items
                if item.get("repetition") == 1
            ),
            items[0] if items else None,
        )
        if rep1 is None:
            continue
        profile = rep1.get("rasterThreadSliceProfile") or {}
        threads = ", ".join(
            f"`{name}`" for name in (profile.get("threadNames") or [])
        ) or "none"
        lines.append(f"### {scenario}")
        lines.append("")
        lines.append(
            f"Thread(s): {threads}. "
            f"frameCount: {profile.get('frameCount') if profile.get('frameCount') is not None else NA}."
        )
        lines.append("")
        slice_rows = []
        for item in profile.get("slices") or []:
            slice_rows.append(
                [
                    str(item.get("name") or ""),
                    _fmt(item.get("count"), digits=0),
                    _fmt(item.get("countPerFrame"), digits=2),
                    _fmt(item.get("meanUs"), digits=1),
                    _fmt(item.get("totalUs"), digits=0, scale=1e-3),
                ]
            )
        if not slice_rows:
            lines.append("_No raster-thread slices in this trace._")
            lines.append("")
            continue
        _write_table(
            lines,
            ["slice", "count", "count/frame", "mean µs", "total ms"],
            slice_rows,
        )
    return "\n".join(lines).rstrip() + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", required=True, help="Harness output directory")
    args = parser.parse_args()
    out_dir = Path(args.out).resolve()
    run_dirs = _discover_runs(out_dir)
    if not run_dirs:
        sys.stderr.write(f"error: no run directories in {out_dir}\n")
        sys.exit(1)
    runs = [_analyze_run(run_dir) for run_dir in run_dirs]
    payload = {
        "schemaVersion": 2,
        "outDir": str(out_dir),
        "runs": runs,
    }
    (out_dir / "summary.json").write_text(
        json.dumps(payload, indent=2, default=str) + "\n",
        encoding="utf-8",
    )
    markdown = _build_markdown(out_dir, runs)
    (out_dir / "summary.md").write_text(markdown, encoding="utf-8")
    print(markdown)
    return 0


if __name__ == "__main__":
    sys.exit(main())
