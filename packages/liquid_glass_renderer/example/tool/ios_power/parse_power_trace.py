#!/usr/bin/env python3
"""Summarise an xctrace Power Profiler trace.

Exports two tables and prints duration-weighted means of Apple's per-process
"power impact" indexes (unitless, coarse, ~1 Hz) for CPU / GPU / display /
networking, plus system frame rate, thermal state and charging state.

usage: parse_power.py <trace.trace> [--skip-s 3] [--json]
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

IMPACT_TABLE = "ProcessSubsystemPowerImpact"
SIGNPOST_XPATH = (
    '/trace-toc/run[@number="1"]/data/table'
    '[@schema="os-signpost" and @category="PowerMetrics"]'
)


def export(trace: Path, xpath: str, out: Path) -> str:
    if not out.exists():
        subprocess.run(
            ["xcrun", "xctrace", "export", "--input", str(trace),
             "--xpath", xpath, "--output", str(out)],
            check=True, capture_output=True,
        )
    return out.read_text(errors="replace")


def resolve_rows(root: ET.Element):
    """Yield rows as lists of (tag, text) with id/ref indirection resolved."""
    by_id: dict[str, tuple[str, str]] = {}
    for row in root.iter("row"):
        cells = []
        for cell in row:
            if cell.tag == "sentinel":
                cells.append((cell.tag, None))
                continue
            ref = cell.get("ref")
            if ref is not None:
                cells.append(by_id.get(ref, (cell.tag, None)))
                continue
            text = cell.text.strip() if cell.text and cell.text.strip() else cell.get("fmt")
            val = (cell.tag, text)
            cid = cell.get("id")
            if cid is not None:
                by_id[cid] = val
            # nested ids (e.g. <process><pid id=..>) may be referenced later
            for sub in cell.iter():
                if sub is cell:
                    continue
                sid = sub.get("id")
                if sid is not None:
                    by_id[sid] = (sub.tag, sub.text.strip() if sub.text else sub.get("fmt"))
            cells.append(val)
        yield cells


def impact_summary(xml: str, skip_ns: int) -> dict:
    root = ET.fromstring(xml)
    cols = [c.findtext("mnemonic") for c in root.iter("col")]
    acc: dict[str, list[tuple[float, float]]] = {
        "cpu-impact": [], "gpu-impact": [], "display-impact": [], "networking-impact": [],
    }
    instr = []
    for cells in resolve_rows(root):
        if len(cells) != len(cols):
            continue
        row = dict(zip(cols, cells))
        start = int(row["start"][1])
        dur = int(row["duration"][1])
        if start < skip_ns:
            continue
        for k in acc:
            v = row[k][1]
            if v is not None:
                acc[k].append((float(v), dur))
        v = row["cpu-instructions"][1]
        if v is not None and int(v) > 0:
            instr.append((int(v), dur))
    out = {}
    for k, samples in acc.items():
        tot = sum(d for _, d in samples)
        out[k] = {
            "mean": round(sum(v * d for v, d in samples) / tot, 3) if tot else None,
            "max": max((v for v, _ in samples), default=None),
            "samples": len(samples),
            "seconds": round(tot / 1e9, 1),
        }
    tot = sum(d for _, d in instr)
    out["cpu-instructions-per-s"] = round(sum(instr_n for instr_n, _ in instr) / (tot / 1e9)) if tot else None
    return out


def system_summary(xml: str) -> dict:
    # The resolved message lives in the fmt attribute (locale decimal commas).
    fps, thermal, charging, drain = [], [], [], []
    for m in re.finditer(r'<os-log-metadata id="\d+" fmt="([^"]*)"', xml):
        txt = m.group(1).replace(",", ".")
        if "System Power Usage" not in txt:
            continue
        f = re.search(r"Frame Rate =\s+([\d.]+)", txt)
        t = re.search(r"Thermal State =\s+(\d+)", txt)
        c = re.search(r"Charging Status =\s+(\d+)", txt)
        d = re.search(r"System Power Usage \(sampled power\) =\s+([\d.]+)", txt)
        if f: fps.append(float(f.group(1)))
        if t: thermal.append(int(t.group(1)))
        if c: charging.append(int(c.group(1)))
        if d: drain.append(float(d.group(1)))
    return {
        "fps_mean": round(sum(fps) / len(fps), 1) if fps else None,
        "fps_min": min(fps) if fps else None,
        "thermal_state_max": max(thermal) if thermal else None,
        "charging": charging[0] if charging else None,
        "battery_drain_pct_per_hr": round(sum(drain) / len(drain), 2) if drain else None,
        "system_metric_samples": len(fps),
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("trace")
    ap.add_argument("--skip-s", type=float, default=3.0,
                    help="ignore rows starting before this offset (attach settle)")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    trace = Path(a.trace)
    exp = trace.parent / "exports"; exp.mkdir(exist_ok=True)
    name = trace.stem
    impact_xml = export(
        trace, f'/trace-toc/run[@number="1"]/data/table[@schema="{IMPACT_TABLE}"]',
        exp / f"{name}_{IMPACT_TABLE}.xml")
    sign_xml = export(trace, SIGNPOST_XPATH, exp / f"{name}_PowerMetrics.xml")
    res = {"trace": name,
           **impact_summary(impact_xml, int(a.skip_s * 1e9)),
           **system_summary(sign_xml)}
    if a.json:
        print(json.dumps(res, indent=2))
    else:
        i = res
        print(f"{name:26s} cpu={i['cpu-impact']['mean']} gpu={i['gpu-impact']['mean']} "
              f"disp={i['display-impact']['mean']} net={i['networking-impact']['mean']} "
              f"instr/s={i['cpu-instructions-per-s']} fps={i['fps_mean']} "
              f"thermal={i['thermal_state_max']} charging={i['charging']} drain%/h={i['battery_drain_pct_per_hr']}")


if __name__ == "__main__":
    main()
