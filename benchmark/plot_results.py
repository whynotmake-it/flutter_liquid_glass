#!/usr/bin/env python3
"""Plot native Flutter blur cost curves from blur_bench_results_v2.json.

Metrics:
- display phase: FrameTiming raster/build/span per config (vsync-capped onscreen)
- raster phase: serial Picture.toImage + toByteData wall clock per render
  (includes GPU completion; marginal over nofilter baseline = isolated blur cost)
"""
import json
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

PATH = sys.argv[1] if len(sys.argv) > 1 else "blur_bench_results_v2.json"
data = json.load(open(PATH))
meta = data["meta"]
rows = data["results"]
dpr = meta["dpr"]

disp = [r for r in rows if r["phase"] == "display"]
rast = [r for r in rows if r["phase"] == "raster"]

# Baselines ------------------------------------------------------------------
disp_base = [r["raster"]["median_us"] for r in disp if r["count"] == 0]
disp_baseline = float(np.median(disp_base))
rast_base = {r["size"]: r["serial"]["median_us"] for r in rast if r["sigma"] is None}

def lab(size):
    return "full window" if size < 0 else f"{size}×{size}"

blur_disp = {}
for r in disp:
    if r["count"] == 1:
        blur_disp.setdefault(r["size"], {})[r["sigma"]] = r

scaling = {}
for r in disp:
    if r["count"] not in (0, 1):
        scaling.setdefault(r["sigma"], {})[r["count"]] = r

blur_rast = {}
for r in rast:
    if r["sigma"] is not None:
        blur_rast.setdefault(r["size"], {})[r["sigma"]] = r

sizes = sorted(blur_rast.keys())

# --- Figure 1: serial raster cost -------------------------------------------
fig, axes = plt.subplots(1, 2, figsize=(15.5, 6.4))
ax = axes[0]
for size in sizes:
    ss = sorted(blur_rast[size])
    x = [blur_rast[size][s]["sigma"] for s in ss]
    y = [blur_rast[size][s]["serial"]["median_us"] / 1000 for s in ss]
    lo = [blur_rast[size][s]["serial"]["p10_us"] / 1000 for s in ss]
    hi = [blur_rast[size][s]["serial"]["p90_us"] / 1000 for s in ss]
    ax.plot(x, y, marker="o", ms=3.5, lw=1.4, label=lab(size))
    ax.fill_between(x, lo, hi, alpha=0.08)
ax.set_xscale("symlog", linthresh=4)
ax.set_xlabel("blur sigma (logical px)")
ax.set_ylabel("serial raster time incl. GPU sync (ms)")
ax.set_title("toImage + readback wall time vs sigma")
ax.legend(fontsize=8)
ax.grid(alpha=0.3)

ax = axes[1]
for size in sizes:
    ss = sorted(blur_rast[size])
    base = rast_base.get(size, 0)
    x = [blur_rast[size][s]["sigma"] for s in ss]
    y = [(blur_rast[size][s]["serial"]["median_us"] - base) / 1000 for s in ss]
    ax.plot(x, y, marker="o", ms=3.5, lw=1.4, label=lab(size))
ax.set_xscale("symlog", linthresh=4)
ax.set_xlabel("blur sigma (logical px)")
ax.set_ylabel("marginal blur cost (ms)")
ax.set_title("Marginal serial blur cost (over no-filter raster)")
ax.legend(fontsize=8)
ax.grid(alpha=0.3)
fig.suptitle(
    f"Impeller blur cost (serial offscreen render) — macOS VM, Flutter 3.47.1, "
    f"DPR {dpr:g}", fontsize=11)
fig.tight_layout()
fig.savefig("blur_cost_vs_sigma.png", dpi=150)

# --- Figure 2: onscreen metrics ----------------------------------------------
fig, axes = plt.subplots(1, 2, figsize=(15.5, 6.4))
ax = axes[0]
for size in sorted(blur_disp):
    ss = sorted(blur_disp[size])
    x = [blur_disp[size][s]["sigma"] for s in ss]
    y = [blur_disp[size][s]["raster"]["median_us"] / 1000 for s in ss]
    ax.plot(x, y, marker="o", ms=3.5, lw=1.4, label=lab(size))
ax.axhline(disp_baseline / 1000, color="k", ls="--", lw=1, alpha=0.6,
           label=f"no-blur baseline ({disp_baseline/1000:.1f} ms)")
ax.set_xscale("symlog", linthresh=4)
ax.set_xlabel("blur sigma (logical px)")
ax.set_ylabel("raster thread time / frame (ms)")
ax.set_title("Onscreen rasterDuration vs sigma (GPU async => mostly flat)")
ax.legend(fontsize=8)
ax.grid(alpha=0.3)

ax = axes[1]
for sigma in sorted(scaling):
    counts = sorted(scaling[sigma])
    xs = [1] + counts
    one = blur_disp.get(128, {}).get(sigma, {}).get("raster", {}).get("median_us")
    y = [one / 1000 if one else np.nan]
    y += [scaling[sigma][c]["raster"]["median_us"] / 1000 for c in counts]
    ax.plot(xs, y, marker="o", ms=4, label=f"σ={sigma:g}")
ax.axhline(16.7, color="k", ls="--", lw=1, alpha=0.6, label="60 fps")
ax.axhline(8.3, color="k", ls=":", lw=1, alpha=0.6, label="120 fps")
ax.axhline(disp_baseline / 1000, color="gray", ls="-.", lw=1, alpha=0.6,
           label=f"no-blur ({disp_baseline/1000:.1f} ms)")
ax.set_xlabel("number of 128×128 blur regions on screen")
ax.set_ylabel("raster thread time / frame (ms)")
ax.set_yscale("log")
ax.set_title("Onscreen cost vs number of overlapping blur regions")
ax.legend(fontsize=8)
ax.grid(alpha=0.3, which="both")
fig.suptitle(
    "BackdropFilter on screen (animated backdrop, profile mode) — raster thread "
    "CPU time; GPU work only shows via backpressure", fontsize=11)
fig.tight_layout()
fig.savefig("blur_cost_onscreen.png", dpi=150)

# --- Figure 3: heatmap of marginal serial cost --------------------------------
sig_all = sorted({s for sz in blur_rast.values() for s in sz})
Z = np.full((len(sizes), len(sig_all)), np.nan)
for i, sz in enumerate(sizes):
    for j, sg in enumerate(sig_all):
        if sg in blur_rast[sz]:
            Z[i, j] = (blur_rast[sz][sg]["serial"]["median_us"]
                       - rast_base.get(sz, 0)) / 1000
fig, ax = plt.subplots(figsize=(10.5, 5.8))
vmax = np.nanmax(Z)
im = ax.imshow(Z, aspect="auto", origin="lower", cmap="inferno", vmin=0)
ax.set_xticks(np.arange(len(sig_all)))
ax.set_xticklabels([f"{s:g}" for s in sig_all], fontsize=8)
ax.set_yticks(np.arange(len(sizes)))
ax.set_yticklabels([lab(s) for s in sizes], fontsize=9)
for i in range(len(sizes)):
    for j in range(len(sig_all)):
        if not np.isnan(Z[i, j]):
            ax.text(j, i, f"{Z[i, j]:.1f}", ha="center", va="center", fontsize=7,
                    color="white" if Z[i, j] < vmax * 0.55 else "black")
ax.set_xlabel("sigma (logical px)")
ax.set_ylabel("region size")
ax.set_title("Marginal blur cost, ms — serial raster + GPU sync (sigma × size)")
fig.colorbar(im, ax=ax, label="ms")
fig.tight_layout()
fig.savefig("blur_cost_heatmap.png", dpi=150)

# --- Console summary ----------------------------------------------------------
print(f"DPR={dpr}  window={meta['physical_size']}")
print(f"onscreen no-blur baseline: {disp_baseline/1000:.2f} ms raster/frame")
for size in sizes:
    base = rast_base.get(size, 0) / 1000
    ss = sorted(blur_rast[size])
    marg = {blur_rast[size][s]['sigma']: blur_rast[size][s]['serial']['median_us']/1000 - base
            for s in ss}
    peak = max(marg, key=marg.get)
    print(f"{lab(size):>12}: raster+readback base {base:5.2f} ms | "
          f"marginal blur {min(marg.values()):5.2f}..{max(marg.values()):5.2f} ms "
          f"| peak at sigma={peak:g}")
