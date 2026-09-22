# Renderer cost-reduction log (2026-09-15 →)

Goal: cut the on-device cost of both real and fake glass as far as possible
with only visual changes a viewer would not notice. Every idea gets an entry:
what it targets, how it was measured, and whether it was kept or rejected and
why. Numbers are Pixel 10 (Impeller/Vulkan, 120 Hz, brightness 128, on USB)
unless stated; GPU mW is the `S2S_VDD_GPU` rail from Perfetto.

Workspace: `flutter_liquid_glass-perf` (jj workspace `perf`), based on
`850c30c3` (`codex/renderer-flutter-3.44`, the commit ClickUp pins). Fast
cycles use `example/tool/android_gpu_bench.sh scenarios`; milestones use the
ClickUp journey benchmark (`/tmp/pixel_glass/run_matrix_px.sh`).

## Baselines

### ClickUp journey (OLD/NEW × FAKE/REAL), corrected driver — `/tmp/pixel_glass/runs_v2`

The first journey pass had a broken scroll phase (orphaned `ScrollPosition`
after the first tab switch → static screen at ~11 fps), which made OLD look
cheap. With the fixed driver (re-resolve the on-screen Inbox scrollable every
cycle; scroll runs at ~65 fps from a 16 ms timer), 54 s windows, thermal gate,
first-after-install run discarded, 2 runs per cell:

| cell | GPU mW | CPU mW | DDR mW | SoC compute mW |
|---|---:|---:|---:|---:|
| OLD fake | 247–286 | 510–775 | 167–203 | 1005–1352 |
| OLD real | 227–231 | 548–552 | 164–167 | 1018–1023 |
| NEW fake | 139–145 | 383–428 | 113–119 | 696–753 |
| NEW real | 157–160 | 403–429 | 118–121 | 739–774 |

Per phase (r2 of each cell, mW GPU / CPU, fps = SurfaceFlinger display frames):

| phase | OLD fake | OLD real | NEW fake | NEW real |
|---|---:|---:|---:|---:|
| scroll (≈65 fps) | 244 / 586 | 244 / 632 | 122 / 448 | 139 / 493 |
| tabs, loupe travel (≈100 fps) | 366 / 501 | 311 / 556 | 190 / 336 | 213 / 375 |
| More menu open | 261 / 329 | 228 / 352 | 201 / 249 | **251** / 312 |
| Brain sheet (static) | 117 / 271 | 132 / 284 | 77 / 207 | 83 / 236 |

Reading: NEW real already beats OLD everywhere except the **More menu**, where
its GPU is the highest of the four (large glass panel → large filter
coverage + per-item shapes). Targets for the renderer, by weight: the
scroll-phase filter cost (readback + blur + shader), the animation phases
(matte rebuild + shadows on every repaint), and the More-menu coverage.

### Prior package-side measurements (from PERFORMANCE_AUDIT.md, 2026-09-13/14)

- Each independent `BackdropFilter` ≈115 mW for Impeller's full-screen readback.
- Plain blur σ7 ≈165 mW/element, FakeGlass ≈230, real glass ≈335 (single element, scroll scene).
- Shared `BackdropGroup` pays the readback once (two real layers 797 → 688).
- Glass shadow ≈75 mW per shape (`saveLayer` + punch).
- Blur σ≤4 disables Impeller's downsample and costs *more* than σ7; σ20 ≈3× σ7.
- Final-shader ALU is not a lever on PowerVR (mediump/pow/single-read moved nothing).
- Animated blend-group geometry: ~2 ms/frame UI-thread `PAINT`, ~1.75 ms of it is Flutter GPU encode+submit (engine-side).

## What ClickUp asks the renderer for (clickup_ui4 `Glass` wrapper)

- `GlassLayer`: `LiquidGlassLayer(useBackdropGroup: true)` wrapping a `LiquidGlassBlendGroup(blend: 10)`; one `BackdropGroup` per layer.
- Settings: `LiquidGlassSettings.ios27Toolbar(frost: fake ? 8 : 5)`, `edgeRefraction ×1.15`, `bevelShadowStrength 0.03`, `contourWidth 0.5`.
- Appearance: `ios27Toolbar` tint grey100 @ 0.6, `LiquidGlassColorModel.direct()`.
- Every `Glass` gets `GlassGlow` + `LiquidStretch`, shadows default `BoxShadow(outer, α0.1, blur 30)`.
- Bottom bar: bar pill (grouped), indicator/loupe with its own capture (`useBackdropGroup: false`), Create button and Brain pill as separate `Glass`.

## Steady-state GPU graph of the ClickUp bar (per frame, real glass)

1. Shared `BackdropGroup` readback (bar pill + Create + Brain pill in one blend group): ~115 mW fixed.
2. `ImageFilter.compose(blur σ=frost, glass shader)` inside `ClipRect(shape-union bounds, 64 px buckets)`. The shader only ever sees the blurred backdrop; there is no sharp branch. Blur runs at Impeller's downsampled scale; the shader runs at full resolution over the whole clip (including empty space between shapes).
3. Loupe/indicator: a **second independent readback** (`useBackdropGroup: false`, frost 0) + shader over the loupe bounds.
4. Shadow pass per layer: `saveLayer(paintBounds)` → per shape a `MaskFilter.blur` superellipse (an offscreen Gaussian blur each) → per shape `dstOut` punch → composite. Two layers (bar, loupe), four shapes.
5. Foreground children (icons/text), `GlassGlow` (only while pressed), `LiquidStretch` (transform only).
6. Independent-opacity / composition-probe machinery adds native passes only when a fractional `Opacity` ancestor exists; otherwise CPU-only and only on repaint (the layer does not repaint during list scroll; the compositor filter is retained).

## Ideas

Format: **Idea** — target — measurement — verdict.

### C. Loupe/indicator on the shared backdrop capture — ClickUp-side proposal, measured in the example (pending)

Target: the tab indicator's own `BackdropFilter` (`useBackdropGroup: false`,
frost 0) is a second full-screen readback every frame the bar is visible.
Variant: the loupe joins the layer's `BackdropGroup` and takes the bar's tint
and frost, so it refracts the (blurred) list instead of the painted bar.
Visual: over white content the two are hard to tell apart
(`/tmp/pixel_glass/shots/loupe_compare.png`: slightly lighter lens, same
refractive rim); over colourful content the loupe would show the list's
colours more directly and lose the bar's specular under it. This is a look
decision for the product, not something the renderer can hide.

ClickUp measurement attempt (`OPTLOUPE_REAL_r1/r2`, `runs_v2`) is **not
usable**: r1 straddled a host outage (skin +3.4 °C, CPU 1.1 W), r2 ran in a
different device state (scroll at 79 fps vs 60–63 in every other run). The
e2e Inbox also grew from ~750 px to ~2600 px of content during the day, which
raised scroll-phase CPU for every later run (`OPT_*` CPU 487–540 vs the
morning's 383–429 for the same renderer paths). Per Tim: when the workspace
drifts, trust the example benchmarks and keep scrolling in them.

Example measurement (`/tmp/pixel_glass/fast/loupe_pair`, `loupe_static`;
120 fps, medians of 3, thermal-gated). `appScrollRealTabs*` = bar pill with a
loupe; "blended" = loupe in the bar's blend group and capture; "own" = loupe
as its own `LiquidGlassLayer(useBackdropGroup: false)` with ClickUp's
indicator settings:

| | GPU mW | CPU mW | DDR mW | GPU-mem mW |
|---|---:|---:|---:|---:|
| static bar, loupe blended | 751–783 | 381–385 | 263–269 | 162–165 |
| static bar, loupe **own capture** | **895** | 387 | **322** | **183** |
| loupe moving, blended | 829 | 498 | 301 | 162 |
| loupe moving, own capture | 902 | 439 | 325 | 188 |

Verdict: the indicator's own capture costs **≈ +120…145 mW GPU and ≈ +60 mW
DDR on every frame the bar is visible**, with no CPU benefit while static.
While the loupe is *moving*, the own capture saves ~60 mW CPU (no full-bar
matte rebuild) but still costs +73 mW GPU / +24 DDR / +26 GPU-mem. A readback
is full-screen regardless of shape size, so this transfers to ClickUp nearly
1:1 — it is the single largest glass cost found today. **Product decision
(Tim, 2026-09-16): the loupe must refract the painted bar; sharing the bar's
capture is not acceptable.** Treat the loupe's own capture as a requirement;
the open question is whether that second capture can come from something
cheaper than a full-screen pass break (ideas being collected). The
`GLASS_LOUPE_SHARED` dart-define in the scratch ClickUp workspace remains only
as the measurement variant.

### D. ClickUp milestone with the analytic shadows (OPT_* vs NEW_*) — path later rejected, see A

GPU: real 150–155 vs 157–160 mW, fake 138–141 vs 139–145 (per phase, real r2:
scroll 125 vs 139, tabs 194 vs 213, More 241 vs 251, Brain 87 vs 83). CPU is
confounded by the Inbox growth above. The paired NEW re-run (`NEW2_*`, after
the phone had been offline and cooled) drove the scroll at 76–77 fps instead of
60–63, so raw mW are not comparable either; per displayed frame (GPU mJ):
real scroll 2.12 vs 2.08, real tabs 2.07 vs 2.11, fake scroll 1.86 vs 1.92 →
**neutral in ClickUp**, as the fast harness predicted (the shadow is a small
share of the bar's frame; the fake-path gain is 25 % of that share).

### E. Hard-coding intensities in the final shader — not pursued (2026-09-16)

Suggested as a per-pixel saving. Assessment: the final pass is bound by
memory traffic (blurred-backdrop read, matte read, full-resolution write over
the clip coverage, plus Impeller's full-res blur intermediate), not by ALU;
the 2026-09-14 ALU reductions in the same shader (mediump colour path, no
`pow`, one backdrop read) stayed within run noise, and uniform loads /
coherent uniform branches are close to free on PowerVR. Folding the toolbar
preset into constants would remove exactly those. A compile-time
`BAKE_CONSTANTS` variant was prepared to measure it; Tim chose to skip the
run. Expected effect: below measurement noise. Re-open only with new evidence
that the pass is ALU-bound.

### F. Idea generation (2026-09-16, independent graphics-engineer review)

An unbiased review of the pipeline produced a ranked list, saved in
`RENDERER_IDEAS_2026-09-16.md`. Highlights: (1) a bounded "seed" subpass
around bar + loupe (passthrough BackdropFilter over the bar region) so the
loupe's own capture flips a ~0.3 Mpx subpass instead of the 2.6 Mpx screen
while still refracting the painted bar; (2) a matte-less analytic path for
layers with ≤4 shapes (kills the matte rebuild during loupe travel / menu
growth); (3) a designated-source backdrop via `toImageSync` (highest ceiling,
highest risk); (4) an engine fix anchoring the runtime-effect intermediate at
the filter coverage; (5) retained layer tree / stable filter objects for the
CPU rail. Each comes with the cheapest experiment to validate Impeller's
behaviour. None implemented yet.

### G. E1 — runtime-effect intermediate anchored at the pass origin — CONFIRMED (2026-09-16 20:05)

Test: shader-stage increment (real − plain blur, same element, same position)
for a top element vs a bottom element (`/tmp/pixel_glass/fast/e1`, 3 reps,
thermal-gated, 120 fps):

| element | plain blur | real | increment |
|---|---:|---:|---:|
| top bar 1000×104 @ y=0 | 334 GPU / 147 DDR | 425 / 164 | +92 GPU, +16 DDR, +4 GPU-mem |
| bottom pill 340×64 | 211 / 99 | 389 / 157 | **+178 GPU, +58 DDR, +25 GPU-mem** |

A 5× smaller element at the bottom costs ~2× more in the shader stage: ≈ +85
GPU / +40 DDR of position penalty, matching Impeller's
`RuntimeEffectFilterContents` re-rasterising the downsampled blur snapshot
into an intermediate spanning from the subpass origin to the filter coverage
(~screen height × bar width for a bottom bar). Look-neutral to remove.
Options: engine fix (rasterise only the coverage rect and rebase the quad's
`position`; file upstream) or package-side idea #1 (bar-sized seeded subpass
moves the pass origin next to the bar and also makes the loupe's readback
bar-sized). New scenario `appScrollPlainBlurPillOnly` added for this test.

### H. E3 — `LiquidGlassSeed`: bar-sized seeded subpass — KEPT as experimental (2026-09-16 21:30)

Idea #1 of the review. `lib/src/liquid_glass_seed.dart`: a pixel-snapped
`ClipRect` + passthrough `BackdropFilterLayer` (identity `ColorFilter`)
around glass layers; `RenderLiquidGlassLayer.shaderCoordinateTransform` maps
filter fragment coordinates to the nearest enclosing seed instead of the root
(inside a subpass `FlutterFragCoord` is subpass-local — with the old
root-relative mapping the matte lookup missed and real glass rendered
transparent; fake glass and plain blur were unaffected, which is how the
cause was isolated). `ImageFilter.matrix` identity does not seed the subpass
(black); the ColorFilter identity does.

macOS probe: seeded vs unseeded real glass pixel-identical (max 4/255).
Pixel 10 (`/tmp/pixel_glass/fast/e3b`, 3 reps, thermal-gated, 120 fps):

| static bar, list scrolling | GPU | DDR | GPU-mem | CPU |
|---|---:|---:|---:|---:|
| bottom pill | 383 | 162 | 104 | 334 |
| bottom pill in seed | **329** | 153 | 94 | 353 |
| bar + own-capture loupe | 910 | 322 | 191 | 408 |
| bar + own-capture loupe in seed | **736** | **266** | **158** | 417 |

−19 % GPU, −17 % DDR with the loupe still refracting the painted bar; the
seeded own-capture configuration (736) beats the shared-capture one measured
earlier (751–783). Open before shipping: goldens for seed × fade/opacity
scopes; seed sizing rule (≥ 3σ + max displacement + shadow support; 64 px
used here); documentation that refracted content must paint below the seed;
ClickUp integration + journey measurement. Earlier E3 attempt with a hand-
rolled seed measured −230 GPU but had silently dropped the glass — always
check the screenshot.

### I. `LiquidGlassSeed` in ClickUp (2026-09-18)

Integration: `LiquidGlassSeed(reach: EdgeInsets.all(64))` around the bar's
`GlassLayer` (bar pill, Create, Brain pill, loupe all inside). Two seed bugs
found on device and fixed: (1) coordinates mapped to the seed's layout box
instead of the reach-inflated clip origin (glass drawn 64 px up/left);
(2) the reach pushed the clip past the screen edge, Impeller clamps the
subpass to the screen, so the origin must be derived from clip ∩ screen
(missing left cap). `flutter_tester` on macOS hangs natively with the
reach-inflated seed (device is fine); host goldens for this variant need a
different approach.

Paired journey runs (seeded build, then unmodified NEW right after; 2 each):

| cell | GPU | GPU-mem | DDR | CPU | SoC |
|---|---:|---:|---:|---:|---:|
| NEW real | 164 | 63 | 119 | 415 | 760 |
| seeded real | **156** | 60 | 117 | 424 | 757 |
| NEW fake | 145 | 61 | 111 | 381 | 698 |
| seeded fake | 147 | 61 | 117 | **423** | 748 |

Per phase (real): scroll 143/139 → 132/138, tabs 205/213 → 195/199, More
and Brain unchanged. **The −19 % GPU of the example scene did not
transfer**: −5 % GPU on real, SoC neutral, fake +40 mW CPU. Leading
hypothesis: ClickUp's `GlassLayer` uses `useBackdropGroup: true`
(`BackdropKey`), the example scenarios did not; keyed backdrop filters take a
different Impeller path that may still read back at the root inside the seed.
`GLASS_NO_BACKDROP_GROUP` build (seed, no key): real GPU 162 (161–162), CPU
402, SoC 741 — **hypothesis rejected**, the key is not the reason. The Pixel
10's GPU driver exposes no `gpu.renderstages` to Perfetto, so the pass list
cannot be read from the existing traces; the remaining routes are a RenderDoc
frame capture of the (debuggable) profile APK or bisecting ClickUp's structure
into the example scene (RepaintBoundary, LiquidStretch, seed size ≈ 0.75 Mpx
vs 0.15, 68 fps timer scroll vs 120). Decision pending.

### J. `LiquidGlassSeed` shipped as `LiquidGlassCapture` (2026-09-22)

Renamed; `reach` became a nullable `bleed` and the capture now sizes itself
from the glass inside it (`LiquidGlassLayerRenderObject.effectBounds`: filter
clip + blur/refraction sampling reach + shadow paint reach). Two fixes found
while locking it down with pixel tests: (1) the independent-opacity passes
computed their pass origin from the ancestor clip chain and did not see the
capture, so real glass under `Opacity`/`FadeTransition` inside a capture drew
its refraction shifted; the capture now reports its region through
`describeApproximatePaintClip` and both paths share `clipOfAncestor`.
(2) `flutter_tester` renders only the first subpass containing a
`BackdropFilter` per process (later ones black; Metal and Vulkan are fine),
so the host pixel tests run one scene per file and the full matrix runs as a
macOS integration test. Capture vs no capture: max 4/255 on the host,
max 24/255 on Metal (MSAA edge resolve through the subpass, glass identical).

Pixel 10 re-measurement with the auto-sized capture (Flutter 3.47 build,
3 reps, thermal-gated, 120 fps, `/tmp/pixel_glass/fast/cap_pair*`):

| static bar, list scrolling | GPU | GPU-mem | DDR | CPU |
|---|---:|---:|---:|---:|
| bottom pill (`appScrollRealPillOnly`) | 374 | 106 | 154 | 307 |
| bottom pill in capture | **309** | 93 | 141 | 323 |
| bar + own-capture loupe (`appScrollRealTabsOwnLoupeStatic`) | 863 | 182 | 303 | 376 |
| bar + own-capture loupe in capture | **706** | **154** | **254** | 386 |

−17 % / −18 % GPU, −16 % DDR, CPU +10…16 mW (within noise): the automatic
region reproduces the hand-sized seed's result (383 → 329, 910 → 736).

## Summary (2026-09-16 00:50)

Kept at the time, rejected 2026-09-22 (see A): **A** analytic shadows (fake −26 mW GPU / −8 CPU per two shadowed
layers in the example; real GPU-neutral / −12 CPU; ClickUp neutral per frame;
no per-frame offscreen). Rejected: **B** half-res matte (visible corner
artifacts). Measured, ClickUp-side: **C** the indicator's own capture is
≈ +140 mW GPU + 60 mW DDR while the bar is on screen — the largest lever, a
product decision. Not levers (measured before or today): shader ALU, frost
sigma tier at Pixel DPR, per-shape SDF culling (already in the geometry
shader), nested blur→shader passes, texture pooling (frame ownership).

What is left is engine-bound: one full-screen readback per capture, the
downsampled blur, and the shader fill over the clip coverage (the More menu's
large panel is the one place NEW real costs more GPU than OLD). Opacity
support adds no steady-state GPU cost and was kept.

Benchmark hygiene fixed today, all documented above: constant status-bar inset
in the example scene; thermal gate in both harnesses; first-after-install
throwaway run; scroll driver re-resolving the on-screen list every cycle.

### B. Half-resolution geometry matte — REJECTED (2026-09-15 18:01)

Target: the per-rebuild Flutter GPU matte pass and texture allocation during
animation (tabs/loupe travel, stretch, More-menu resize). Rendering the
SDF/normal/displacement texture at 0.5× device resolution (bounded to ≥1
texel per logical px) with all matte-space quantities scaled consistently and
the material map's device scale corrected.

Goldens looked acceptable (DPR-2 goldens: ≤0.9 % of pixels > 40/255, no
silhouette shift, mean diff < 1/255), but a visual check of the macOS example
by Tim showed **clearly visible artifacts at rounded corners**. The
sqrt-encoded edge distance and the displacement field are not linear across a
texel, so bilinear interpolation at half resolution bends the refraction and
edge exactly where curvature is highest. Not a "small visual tweak"; reverted
to `matteResolutionScale = 1.0` (constant kept as documentation). Lesson: the
golden diff statistics under-weighted concentrated corner errors; visual
review on a real display is required for anything touching the matte.

### A. Analytic SDF shadow instead of saveLayer + mask blur + punch — REJECTED (2026-09-22)

**Rejected after visual review.** The analytic pass computed one smooth-union
SDF per layer, but Flutter's shadows are per shape: each shape's path blurred
and punched separately. In a blend group the analytic shadow therefore drew
one blob with wide fillets between shapes that fake glass never merges and
that real glass merges by the group's own blend, not by the shader's constant.
`RSuperellipse` is a specific bezier construction that an SDF only
approximates, which shows at small blur radii, and the iOS 27 presets are all
superellipses. Exact silhouette match is the requirement for shadows; the
raster path (`saveLayer` + mask blur + cutout) is the only one that has it.
The earlier "0.46 % of pixels, max 7/255" golden delta was measured on a scene
without a blend group and was wrongly generalized. Measurements below are kept
for the record; the shader and `LGR_RASTER_SHADOWS` are removed from the
stack.


Target: item 4 above (~75 mW/shape measured 2026-09-13; ClickUp has 4 shapes across 2 layers).

Change: `glass_shadow.frag` + `internal/analytic_glass_shadow.dart`. One `drawRect` with a fragment shader per shadow index per layer: the shadow is the normal-CDF falloff of the signed distance to the smooth-union of the layer's shapes (logistic approximation, ≤1 % error), offset/spread applied to the SDF, interior punched with an anti-aliased mask of the same union. No offscreen, no blur pass, no punch. Superellipse corners use rounded-rect corners (invisible under the blur). Falls back to the old pass for rotated/skewed shapes, >16 shapes, or mixed shadow colors within one draw. `--dart-define=LGR_RASTER_SHADOWS=true` restores the old pass for A/B.

Visual: `layer_owned_cutout_blend_shadows` golden differs by 0.46 % of pixels, max 7/255 per channel, mean 0.09 — not perceptible (see `/tmp/pixel_glass/shots/shadow_zoom.png`). Fake goldens `fake_glass_lighting_matrix`, `fake_glass_real_contour_offsets`, `fake_glass_real_comparison` already fail on this host/Flutter before the change (pre-existing drift); the change moves only the last one, by ~1.5 pp of pixels.

Device numbers, example app-like scene (two chrome layers, 120 Hz scroll, GPU mW; `/tmp/pixel_glass/fast/*`):

| scenario | rasterized (base) | analytic v1 | note |
|---|---:|---:|---|
| appScrollFakeShadow | 745 | 687 | −58 |
| appScrollRealShadow | 906, 967 (2 reps: 937) | 981; 975, 995 (985) | **+48**, reproducible |
| appScrollReal (control) | 811 | 820 | noise |

v2 shader (dynamic loop bound, one SDF per shape when unshifted):
appScrollRealShadow 928 (886–970) ≈ baseline 937; appScrollFakeShadow 694 vs
745. A "null" shader variant (returns transparent) measured 980 in the same
scenario, which is physically impossible if the fill were the cost, so the
run-to-run noise of this scene is at least ±40 mW and single scenarios cannot
resolve a 50 mW shadow increment.

**Confound found 17:14 (Tim, watching the device):** the benchmark scene's
top bar read `MediaQuery.paddingOf(context).top` for its status-bar inset,
which is 0 on some launches (first build before insets / harness screen
pinning), so the top bar's filter area differed by ~40 logical px between
otherwise identical runs. Fixed by a constant 48 px inset in
`integration_test/benchmark_test.dart`. All fast numbers above are therefore
suspect and were re-measured (below) with paired shadow/no-shadow scenarios
in the same run, 3 reps.

Renderer ruled out for the inset issue: in every affected screenshot the
title/icons also sit inside the status bar, i.e. the whole widget was laid out
with a 0 inset and the glass silhouette matches the content; Android delivered
`statusBars:[0,173,0,0]` on every launch (logcat), so ~25 % of fresh-process
launches simply never propagated the metrics to `MediaQuery` in this harness.
ClickUp runs are bottom-anchored and unaffected.

**Second confound (17:40):** the fast harness had no thermal gate; after ~40
minutes of back-to-back scenarios the Pixel sat at thermal status 2 and the
scene dropped to 105–115 fps with GPU spreads of 534–809 mW within one cell.
`android_gpu_bench.sh run_scenario` now waits for thermal status ≤ 1 before
every scenario (`THERMAL_GATE`). Both confounds mean the first day's fast
numbers (16:48–17:40) are only indicative; the paired rerun below is the
reference.

**Reference measurement (fixed inset, thermal gate, paired, 3 reps, medians;
`/tmp/pixel_glass/fast/base3_pair`, `v3b_pair`):**

| increment = shadow scenario − same scene without shadows | rasterized | analytic v2 |
|---|---|---|
| fake (two layers) | +104 GPU / +14 CPU / +24 DDR mW | +78 / +6 / +10 |
| real (two layers) | +110 / +23 / +31 | +109 / +11 / +33 |

v3 (2026-09-18, the shipped shader): the loop bound had to become the
constant `MAX_SHAPES` with `if (i >= count) break;` because the web build
compiles every declared shader to SkSL, which rejects dynamic bounds. Paired
re-measurement, same method, 3 reps, medians (`/tmp/pixel_glass/fast/v3_pair`;
absolute levels shifted — the shadow-less scenes ran at 602/796 mW today vs
548/731 in the reference — so only increments are comparable):

| increment | analytic v3 |
|---|---|
| fake (two layers) | +71 GPU / −18 CPU / +1 DDR mW |
| real (two layers) | +128 / +22 / +39 |

Same picture: fake keeps ~30 % of the shadow's GPU cost off the rail, real
stays inside the ±40 mW noise of this scene.

Verdict: **kept**. −25 % of the shadow's GPU cost on fake, GPU-neutral on real,
−8…−12 mW CPU on both, no per-frame offscreen or mask blur. Why the real path
does not gain on GPU is not understood (same draw, same bounds); the legacy
saveLayer in the real path is evidently cheaper than the same construct in the
fake path on this GPU. Not worth more cycles: the shadow is ~15 % of the
real-glass frame here.

Earlier, confounded observation kept for the record: "the fake path wins, the real path loses with the identical draw." Legacy shadow
increment on real = 937 − 811 ≈ 126 mW for two layers; analytic ≈ 165 mW.
Hypotheses under test (v2 = dynamic loop bound + single SDF when unshifted;
`null` = shader returns transparent immediately, isolating the fill cost of
the shadow quad): (a) per-fragment cost of the 16-iteration predicated loop /
uniform-array reads; (b) the quad's blended fill over the whole 3σ support
(~1.9 Mpx at device resolution per frame) is itself the cost, in which case
the legacy path's offscreen must be cheaper than assumed on this GPU and the
analytic draw needs a smaller footprint (ring / 2.5σ support) or a lower
resolution intermediate.
