# Apple-match harness report

Status: active, not production-ready. This report is the current evidence
ledger for the redesign. Every comparison image linked here is a harness
capture; annotated images label the left panel `APPLE GROUND TRUTH`, the middle
panel `FLUTTER CANDIDATE`, and the right panel `DIFF / RESIDUAL`.

## What “frost” means on the Apple side

Apple does not expose a frost number in the reference. The Apple panel is a
rendered A/B probe (RGBW grid), not an Apple candidate with settings. `frost`
is only our compositor blur radius. The Apple image therefore cannot be read as
“frost=0”; it is the target response that our candidate settings must fit.

The previous image used the shared candidate vector with `frost=7`. The
small-control compositor normalizes that to approximately `7 × 70 / 94 = 5.2`
logical pixels. It is visibly softer than the Apple target, so the clear
endpoint is now included in the next scan. It has not been measured yet because
CoreSimulatorService is currently unavailable.

## Probe contract

| Probe | Background | What it measures |
| --- | --- | --- |
| A | primary RGBW grid | transmission, blur, refraction, tint, chroma, shape |
| B | holdout RGBW grid | generalization and spatial/refraction flow |
| C | black | highlight, contour, dark response, specular behavior |
| D | white | tint, outline, internal shadow/lighting response |

The score combines appearance (30%), paired A/B radial flow (25%), edge (15%),
black specular (15%), and white tint response (15%). `combined` and `flow` are
kept beside the headline score because a score-only improvement can hide a
refraction or blur regression.

## Current shared vector

| Setting | Value |
| --- | ---: |
| thickness | 8 px (small/large), 12 px (toolbar/tab) |
| edgeRefraction | 18.3 px |
| refractionSpread | 0 |
| frost | 7 |
| tint alpha | .53 |
| saturation | .9 |
| transmissionGamma | .9 |
| vibrancy | .15 |
| chromaticAberration | .005 |
| highlight | .4 |
| contourStrength / width | .65 / 1 px |

The source vector is retained in
`out/generalization-toolbar-vector/*/final/settings.json`.

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

## Parameter iterations and retained images

Each scan held all other material fields fixed and retained A–D captures. The
complete annotated image index is
[`out/annotated-comparisons/iterations/INDEX.md`](out/annotated-comparisons/iterations/INDEX.md)
([machine-readable JSON](out/annotated-comparisons/iterations/INDEX.json)).
Representative annotated images are linked below; the index contains one
annotated image for every retained candidate row.

| Iteration | Values measured | Result | Representative image |
| --- | --- | --- | --- |
| Frost | 3, 4, 5, 6, 7, 8, 9; 0–2 pending | Small headline score peaks at 5 (86.4094), but shared 7 has lower combined/flow and preserves toolbar/large. No default change. | [`small-frost-3-vs-5-vs-7`](out/annotated-comparisons/small-frost-3-vs-5-vs-7-annotated.png) |
| Transmission gamma | .80, .85, .875, .90, .925, .95, 1 | Small combined moves only .4%; no flow/generalization gain. Keep .90. | [`gamma candidate`](out/annotated-comparisons/iterations/material-attribution-gamma/small_capsule/transmissionGamma-0p85-rep1.png) |
| Edge refraction | 0, 8, 12, 18.3, 24, 32 | Best small row is 8 but movement is within noise; larger values regress. Keep 18.3. | [`edge candidate`](out/annotated-comparisons/iterations/material-attribution-edge/small_capsule/edgeRefraction-8-rep1.png) |
| Vibrancy | 0, .075, .15, .225, .30 | Small best combined improves only .8%; no two-scene attribution. Keep .15. | [`vibrancy candidate`](out/annotated-comparisons/iterations/material-attribution-vibrancy/small_capsule/vibrancy-0p3-rep1.png) |
| Tint alpha | .48, .505, .53, .555, .58 | Small combined improves .6% at .555 but toolbar/large regress and transparency contract is disturbed. Keep .53. | [`tint candidate`](out/annotated-comparisons/iterations/material-attribution-tint/small_capsule/tintAlpha-0p555-rep1.png) |
| Chromatic aberration | 0, .001, .0025, .005, .01, .025, .05, .1 | 0–.01 are byte-identical in A across toolbar/small/large; larger values change a few pixels without score gain. One-read fast path is visually safe. | [`CA candidate`](out/annotated-comparisons/iterations/material-attribution-chromaticAberration-cutoff/small_capsule/chromaticAberration-0-rep1.png) |
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
  unreliable due Instruments event loss/finalization. No final native gate is
  claimed.
- Final same-runner performance ratio and small/toolbar ≤1.25× gate remain
  open.

Do not call this production-ready until the pinned visual endpoint scan,
reliable independent16 native evidence, and the final performance audit pass.
