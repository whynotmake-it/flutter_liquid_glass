# Apple-match harness report

Status: active, not production-ready. This report is the current evidence
ledger for the redesign. Every comparison image linked here is a harness
capture; annotated images label the left panel `APPLE GROUND TRUTH`, the middle
panel `FLUTTER CANDIDATE`, and the right panel `DIFF / RESIDUAL`.

## 2026-08-27 lighting-process correction

The current redesign candidate is not the visual baseline. Compared with the
retained pre-redesign `split-contour-transmission2` capture, specular error rose
from `.020399` to `.044304`, black response from `.001302` to `.003952`, white
response from `.001198` to `.006528`, and RGBW rim error from `.051522` to
`.112397`. The shader redesign removed independently modeled face shading,
inner-bevel shadow, and contour transmission and replaced them with a symmetric
occlusion derived from contour strength. That simplification coupled the white
outline and lighting response and allowed the aggregate optimizer to promote a
visibly worse result.

The recovery images are [`pre-redesign baseline`](out/annotated-comparisons/recovered-pre-redesign-lighting-annotated.png)
and [`current regression`](out/annotated-comparisons/current-redesign-lighting-regression-annotated.png).
Further visual iterations use `frost=0`, publish annotated black/white evidence,
and must beat the recovered lighting floor before they can change defaults.

### Retained clear-lighting recovery

Iteration 15 is the retained toolbar candidate. It removes the contact shadow
entirely and keeps the existing linear RGBA8 displacement codec. The material
contour is widened inside the final shader and fit as the coupled vector
`strength=.22`, `width=1.5`, `transmittance=.80`.
Inner bevel shadow remains `.025/12`.
The full annotated comparison is [`iteration 15`](out/annotated-comparisons/lighting-recovery-15-annotated.png)
and the nearest-neighbor outline crops are [`iteration 15 zoom`](out/annotated-comparisons/lighting-recovery-15-outline-zoom.png).

| Clear solid metric | Recovered floor | Iteration 15 | Result |
| --- | ---: | ---: | --- |
| black response | .001302 | .000897 | pass |
| white response | .001198 | .001422 | fail |
| black specular | .003640 | .003666 | fail |
| C rim | .027245 | .027619 | fail |

The strict regional gate remains open. Removing the halo improves D rim from
`.016994` to `.014039`, but white response, black specular, C rim, C
bottom-face, and D bottom-lip remain above their recovered floors. Patterned
RGBW/specular score components remain diagnostic because the retained
historical row used `frost=7` and this lighting fit deliberately uses `frost=0`.
The contact-shadow approach was rejected: it reduced a broad exterior-band
average by adding a diffuse halo that is not present in the Apple reference.
A nonlinear edge-distance codec was also rejected after an exact A/B produced
visually indistinguishable crops and no score gain. Nearest-neighbor crops still
show real contour stepping; RGBA16F and 2×/3× DPR diagnostics remain required
before changing the SDF or its distance codec.

### Focused performance audit

The visual milestone ran a fresh three-repetition macOS profile audit for
`baselineMotion`, `grouped16Motion`, and `independent16Motion`. Median raster
p95 was `1.30 ms`, `1.61 ms`, and `4.50 ms` respectively; all ordinary
frame-time, memory, repeatability, and completeness gates passed. A second
opt-in same-build A/B compared the 16-shape workloads with the recovered
contour/face/bevel uniforms disabled and enabled. Grouped GPU time was
`3.00 → 3.01 ms/frame`; independent raster p95 was `4.38 → 4.40 ms` and GPU
time `5.39 → 5.61 ms/frame` (+4.1%). This stays inside the ≤5% performance
budget and confirms the lighting work remains uniform-coherent ALU in the
existing pass. The second run's generic grouped row had one startup outlier
and therefore failed the parser's 15% repeatability gate; the paired lit row
itself had 0.8% GPU and 8.7% raster CV. No native Metal trace was requested for
this bounded visual audit.

### macOS GPU-golden fitting calibration

Ordinary fitting no longer requires a simulator capture per candidate. The
new `flutter/host_capture.sh` path runs the shared scene through macOS Impeller
and Flutter GPU at DPR 3 and emits the same A/B/C/D PNG contract. It touches no
simulator. Four isolated golden processes complete in 14–20 seconds; isolation
works around a Flutter 3.47 teardown hang after repeated large GPU readbacks in
one `flutter_tester` process.

With iteration 15 settings, the macOS candidate scores `99.4155` against its
iOS-simulator counterpart and `61.9584` against Apple, versus iOS `61.9966`.
The adjacent `.80`/`.90` contour-transmittance ranking is preserved: macOS
prefers `.80` by `.00394`, while iOS prefers it by `.00471`. The annotated
same-settings comparison is [`host versus iOS`](out/annotated-comparisons/host-vs-ios-lighting-recovery-15-annotated.png).
The remaining platform residual is visibly concentrated at the contour and
cast shadow, so macOS is the default search backend but every promoted winner
still requires the pinned three-frame iOS validation before changing defaults.

## What “frost” means on the Apple side

Apple does not expose a numeric frost setting in the reference. For the clear
lighting probe used in the current comparison, however, the visual target has
no observable frost and the Flutter candidate must therefore use `frost=0`.
Other Apple material/slider endpoints may include background softening and must
be attributed separately.

The previous image incorrectly used the shared candidate vector with `frost=7`. The
small-control compositor normalizes that to approximately `7 × 63 / 94 = 4.69`
logical pixels. It is visibly softer than the Apple target and is rejected as
evidence for this clear lighting probe.

## Probe contract

| Probe | Background | What it measures |
| --- | --- | --- |
| A | primary RGBW grid | transmission, blur, refraction, tint, chroma, shape |
| B | holdout RGBW grid | generalization and spatial/refraction flow |
| C | black | highlight, contour, dark response, specular behavior |
| D | white | tint, outline, internal shadow/lighting response |

The score uses the current metric weights: shape (25%), combined transmission
(15%), paired A/B radial flow (15%), blur-MTF (10%), tint/channel (15%),
highlight/specular (10%), and holdout (10%). `combined` and `flow` are kept
beside the headline score because a score-only improvement can hide a
refraction or blur regression.

## Current shared vector

| Setting | Value |
| --- | ---: |
| thickness | 8 px (small/large), 12 px (toolbar/tab) |
| edgeRefraction | 18.3 px |
| refractionSpread | 0 |
| frost | 0 for the clear-lighting fit; 7 only for legacy patterned rows |
| tint alpha | .53 |
| saturation | .9 |
| transmissionGamma | .9 |
| vibrancy | .15 |
| chromaticAberration | .005 |
| highlight | .5 |
| contourStrength / width / transmittance | .22 / 1.5 px / .90 |
| bevel shadow strength / depth | .025 / 12 px |

The current cross-scene table treats `thickness` as a recovered
geometry-specific scalar (12 px for the toolbar, 8 px for the capsules), while
the remaining material vector is shared. This is why the table is useful for
looks attribution but does not prove the strict “fully frozen parameters”
generalization gate; that gate remains open until a rerun freezes thickness as
well or explicitly records an approved geometry exemption.

The source vector is retained in
`out/generalization-toolbar-vector/*/final/settings.json`.

Important provenance boundary: this harness vector is not automatically the
demo's initial material. The shipped named `ios27ToolbarLight` preset remains
on the last user-accepted optical values while the strict frozen-vector and
visual gates are open. The example starts with the private
`exampleDefaultGlassSettings` override (`frost=0`) so lighting and silhouette
can be judged without a demo-only backdrop blur; loading or editing a preset
can still opt into frost explicitly.

The latest provenance correction is shown in this annotated composite:
[`demo path correction`](out/annotated-comparisons/demo-provenance-correction-annotated.png).
Its pixels are the retained harness lighting capture (not a fresh simulator
render); the subtitle makes the harness `frost=7` versus demo `frost=0`
distinction explicit.

## Scene scorecards

| Scene | Score | combined | flow | black response | white response | image |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Toolbar | 91.7814 | .033417 | .004618 | .003952 | .006528 | [`annotated`](out/annotated-comparisons/toolbar-current-annotated.png) |
| Small capsule | 85.2647 | .063668 | .036286 | .000301 | .001861 | [`annotated`](out/annotated-comparisons/small-current-annotated.png) |
| Large capsule | 89.4927 | .027357 | .008524 | .005355 | .009951 | [`annotated`](out/annotated-comparisons/large-current-annotated.png) |
| Tab-bar holdout | 43.0289 | .155696 | .144294 | .018058 | .015558 | [`annotated`](out/annotated-comparisons/tab-holdout-current-annotated.png) |
| Loupe composition | 13.5557 | .419829 | 1.777910 | .045744 | .007749 | [`annotated`](out/annotated-comparisons/loupe-current-annotated.png) |

The loupe score is a composition score: `RawMagnifier` paints the backdrop at
1.55× before the ordinary glass shader. It is not evidence that shader-level
zoom is correct.

For the current `frost=7` vector, the harness decomposes the headline score as
follows. `black ΔL*` and `white ΔL*` are signed candidate-minus-Apple values in
8-bit luminance (negative means the Flutter candidate is darker); `boundary px`
is the mean transmission-boundary position error.

| Scene | Direct MAE8 | Refraction stage | Blur-MTF stage | Tint stage | Highlight stage | Holdout stage | black ΔL* | white ΔL* | RGBW rim | boundary px |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Toolbar | 2.5985 | 99.5382 | 89.1218 | 91.1542 | 82.2786 | 85.4963 | -1.0079 | -1.6647 | .112397 | .1813 |
| Small capsule | 3.6009 | 96.3714 | 86.9773 | 84.1423 | 80.8473 | 74.5688 | -.0767 | -.4745 | .108544 | .8289 |
| Large capsule | 2.9393 | 99.1476 | 69.8280 | 92.0227 | 84.7179 | 85.1619 | -1.3656 | -2.5374 | .094195 | .9234 |

## Parameter iterations and retained images

Each scan held all other material fields fixed and retained A–D captures. The
complete annotated image index is
[`out/annotated-comparisons/iterations/INDEX.md`](out/annotated-comparisons/iterations/INDEX.md)
([machine-readable JSON](out/annotated-comparisons/iterations/INDEX.json)).
Representative annotated images are linked below; the index contains one
annotated image for every retained candidate row.

The complete numeric ledger is generated from those same retained captures by
running `compare/.venv/bin/python3 write_metric_ledger.py` from this directory:
[`METRIC_LEDGER.md`](out/annotated-comparisons/iterations/METRIC_LEDGER.md)
([JSON](out/annotated-comparisons/iterations/METRIC_LEDGER.json)). It includes
the historical score and direct MAE plus shape, combined transmission,
refraction flow, blur-MTF, tint/channel, highlight/specular, holdout,
black/white signed luminance, RGBW rim, and transmission-boundary curvature
measurements for every retained A/B/C/D row. Its JSON preserves the scanner's
stored score/errors and the current-code rescore, with an explicit metric
revision and reference-set identifier. The ledger does not rerun Flutter or
alter simulator state.

| Iteration | Values measured | Result | Representative image |
| --- | --- | --- | --- |
| Frost | 3, 4, 5, 6, 7, 8, 9; 0–2 pending | Small headline score peaks at 5 (86.4094), but shared 7 has lower combined/flow and preserves toolbar/large. No default change. | [`small-frost-3-vs-5-vs-7`](out/annotated-comparisons/small-frost-3-vs-5-vs-7-annotated.png) |
| Transmission gamma | .80, .85, .875, .90, .925, .95, 1 | Small combined moves only .4%; no flow/generalization gain. Keep .90. | [`gamma candidate`](out/annotated-comparisons/iterations/material-attribution-gamma/small_capsule/0p85-rep1.png) |
| Edge refraction | 0, 8, 12, 18.3, 24, 32 | Best small row is 8 but movement is within noise; larger values regress. Keep 18.3. | [`edge candidate`](out/annotated-comparisons/iterations/material-attribution-edge/small_capsule/8p0-rep1.png) |
| Vibrancy | 0, .075, .15, .225, .30 | Small best combined improves only .8%; no two-scene attribution. Keep .15. | [`vibrancy candidate`](out/annotated-comparisons/iterations/material-attribution-vibrancy/small_capsule/0p3-rep1.png) |
| Tint alpha | .48, .505, .53, .555, .58 | Small combined improves .6% at .555 but toolbar/large regress and transparency contract is disturbed. Keep .53. | [`tint candidate`](out/annotated-comparisons/iterations/material-attribution-tint/small_capsule/0p555-rep1.png) |
| Chromatic aberration | 0, .001, .0025, .005, .01, .025, .05, .1 | 0–.01 are byte-identical in A across toolbar/small/large; larger values change a few pixels without score gain. One-read fast path is visually safe. | [`CA candidate`](out/annotated-comparisons/iterations/material-attribution-chromaticAberration-cutoff/small_capsule/0p0-rep1.png) |
| Profile spread | 0, .0625, .125, .25, .5 | Best small combined .063511 at .25, only .25% better and still 1.90× toolbar; reject as generalization fix. | [`spread-grid retained capture`](out/annotated-comparisons/small-spread-grid-last-retained-annotated.png) |
| Coupled spread/thickness | spread 0–1 × thickness 2–16 | Best small combined .063221, still ≈2.01× toolbar and below historical capsule gate. Reject. | [`coupled candidate`](out/annotated-comparisons/small-coupled-best-annotated.png) |
| Small geometry registration | width 148.0–150.0 | 148.667 matches Apple’s detected 446 px width and improves shape/flow, but combined worsens 2.6%; retain 150 default. | [`width registration`](out/annotated-comparisons/small-width-148667-annotated.png) |

## Lighting and luminance audit

The harness measures black and white separately; these are not inferred from
the RGBW A image. The current toolbar and capsule scorecards carry
`blackResponseError`, `whiteResponseError`, `blackSpecularError`, and
`rgbwRimError`. The current dark contour is SDF-derived, with paired
directional highlights; legacy independent rim/inner-shadow weights are not
shipped. Retained black/white iteration images are under each candidate's
`solid_lighting_comparison.png` and are included in the annotated iteration
index where a full comparison composite exists.

Current black/white probe composites (Apple ground truth is the left panel in
each row) are [`small capsule lighting`](out/annotated-comparisons/small-lighting-current-annotated.png)
and [`toolbar lighting`](out/annotated-comparisons/toolbar-lighting-current-annotated.png).

The clear visual residual is the small capsule's transmission/refraction
response, not proof that Apple has a zero-valued frost parameter. The next
valid blur decision requires the pinned `frost=0…9` scan, repeated baseline and
best rows, and inspection of A, B, C, and D together.

## Verification state

- Analyzer: passed through the pinned Flutter/Dart 3.47.1 SDK (informational
  lint debt remains).
- Non-golden Flutter tests: passed.
- Comparator tests: 42 passed, one expected simulator smoke skip.
- Android debug and macOS Profile builds: passed.
- Native Metal: grouped16 has partial valid repeats; independent16 remains
  unreliable due Instruments event loss/finalization. This remains requested
  attribution evidence, not a production gate.
- Final same-runner performance ratio and small/toolbar ≤1.25× gate remain
  open.

The settings evidence contract is now executable. The machine-readable
[`evidence manifest`](settings/evidence_manifest.json) covers every public
`LiquidGlassSettings` field and records its status as `qualified`, `pending`,
`rejected`, or API-utility `exempt`, with artifact-backed scene rows where
available. Run `python3 validate_evidence_manifest.py` for the structural audit;
`--strict` intentionally exits nonzero until every material knob has qualifying
two-scene evidence. This prevents the documentation table from being mistaken
for proof that the gate is closed.

The generalization runner is likewise explicit about its policy: thickness is
frozen to the toolbar card by default, while `--fit-thickness` is diagnostic
only. Its `generalizationGate` reports the actual small-capsule combined-error
ratio against the toolbar; the existing retained per-geometry captures are not
treated as proof of the frozen-parameter gate.

Do not call this production-ready until the pinned visual endpoint scan,
the small/toolbar generalization gate, and the final same-runner performance
audit pass. Native traces cannot substitute for that audit.
