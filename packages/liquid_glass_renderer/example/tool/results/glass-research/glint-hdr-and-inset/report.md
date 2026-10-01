# Glint HDR on iPhone, glint 1.6 vs 2.0, inner-shadow inset, tab tint blend

Device: iPhone 15, iOS 27, Flutter 3.47.1, Impeller/Metal.
Branch: #182 `tim-lehmann/example-playground-68d6`.

## Why highlights were not HDR on the iPhone

Two stacked causes, both in the example's iOS embedding, not the shader:

1. `FLTEnableWideGamut` was never in `example/ios/Runner/Info.plist` (no
   commit ever added it). Impeller rendered into 8-bit BGRA and clipped the
   glint at SDR white. Fixed in `298258c`.
2. Even with it, Flutter 3.47.1 never requests EDR. Native probe on the
   device (Documents log): `FlutterMetalLayer pixelFormat=552 (BGRA10_XR)
   colorspace=kCGColorSpaceExtendedSRGB wantsEDR=0 currentEDRHeadroom=1.2
   potential=8.0`. The engine binary contains `BGRA10_XR` and
   `kCGColorSpaceExtendedSRGB` but no `wantsExtendedDynamicRangeContent` /
   `preferredDynamicRange`. Setting the flag raised headroom to 8.0 within
   4 s. Fixed in `531665c` (AppDelegate sets it on `UIScene.didActivate`;
   verified `wantsEDR=true currentEDR=8.0`).

Pipeline check: a `rawExtendedRgba128` snapshot of the bottom bar on the
device holds values above 1 (max 1.057, 499 px > 1.0 at the default glint),
so nothing between the shader and the surface clamps. The shader glint was
unchanged since `41005f9` (only `max(…, 0)`; target 1.6, clear 2.34).
No saveLayer/ColorFilter over the glass in the playground path.

## Glint: why 1.6 was fitted, why 2.0 looked closer

Note: "2.0" is the playground **Glint slider = `highlight`**, the mask weight
(peak m = 0.14 × highlight). 1.6 is the separate target luminance
`kGlintLuminance`.

- **How 1.6 was fitted** (`ed251dd`, notes "Glint"/"HDR"): on SDR
  tone-mapped 8-bit simulator screenshots, `mix(face, 1.6 + 2.85·chroma, m)`
  fitted jointly with m from *unclipped* channels, 0.2–0.4/255 on 13 palettes.
  The peak above white is extrapolated, never observed.
- **Mac display headroom**: not a factor. The fit is numeric on PNGs.
- **Shape/width compensating**: unlikely. The mask was fitted per row at 63/94/124 pt,
  both appearances, 3× like the iPhone 15.
- **Clipped on device (the cause for bright faces)**: model output under the
  device's former SDR clip (per 3× px, W 1.2 pt):

  | face | intended peak | visible peak lift h1 / h1 clipped / h2 clipped (levels) | integrated lift h1 / h1 clipped / h2 clipped |
  |---|---|---|---|
  | 0.70 | 0.834 | 34 / 34 / 68 | 35 / 35 / 70 |
  | 0.85 | 0.962 | 29 / 29 / 38 | 29 / 29 / 51 |
  | 0.93 | 1.030 | 25 / 18 / 18 | 26 / 24 / 33 |
  | 0.97 | 1.064 | 24 / 8 / 8 | 25 / 15 / 22 |

  Over light glass on light content (playground default: toolbar over
  photos, faces ≈ 0.9–0.97), clipping removed up to two thirds of the
  peak, and `highlight` 2 roughly restores the lost integrated lift.
  Over mid faces (≤ 0.83) nothing clipped, and 2.0 doubles the lift beyond
  the fitted Apple SDR values.
- **Open residual**: Apple's filter exposes `inputMaxHeadroom`,
  `inputSDRHoldingToneEnabled`, `MaxLuma`/`MaxLumaSDR`, so Apple's device
  glint likely depends on headroom, and SDR captures cannot show that. Device
  screenshots are SDR too (`cICP` 12/13/0/1: P3, sRGB transfer).

**Verdict**: evidence supports keeping 1.6 / highlight 1. Ours was clipped on
device, and 2.0 compensated for the clipping. Re-judge on the EDR build. If Apple
still reads brighter, the remaining gap needs an HDR measurement of Apple's glass on
the device; no value can be derived from the SDR data.

## Glint on device vs simulator (EDR build, 17:00)

Same-device A/B (`lib/glint_ab_main.dart`, #182 `5fcbb80`): native
`UIGlassEffect(.regular)` platform view vs our toolbar preset at the same
spot, 300×64 capsule. iPhone 15 screenshots vs the same app on an iOS 27
iPhone 17 Pro simulator (system default tint). Integrated glint lift over the
face, rows 1–7 below the top edge, center 30% (levels):

| backdrop | Apple iPhone | Apple sim | ratio | ours on iPhone at h 1.0 / 1.5 / 2.0 |
|---|---|---|---|---|
| gray 128 | 152 | 78 | 1.95 | 68 / 96 / 124 |
| black | 151 | 94 | 1.61 | 77 / 117 / 154 |
| coast | 156 | 97 | 1.61 | 85 / 115 / 139 |
| city | 134 | 69 | 1.93 | 80 / 112 / 143 |

- Per row on gray: Apple on the iPhone +55 / +39 / +16 / +13, and on the simulator +27 / +18 / +9 / +7.
  Ours at h1 gives +26 / +16 / +8 / +7, so the fit matches the simulator. Apple's device glint is
  about 2× across all rows, and row 2 is slightly wider than ours at h2 (39 vs 28).
- Not our EDR flag: Apple's device values are identical with our layer's EDR off.
- Not the tint slider: the simulator at the same default tint shows the
  simulator-level glint, and the slider sweep leaves the glint mask unchanged.
- So it's device vs simulator. This fits the filter's headroom inputs
  (`inputMaxHeadroom 9999`, `inputSDRHoldingToneEnabled`, SDR-only
  gradient/shadow terms). The simulator display is SDR, while the iPhone panel is EDR
  capable (potential headroom 8).
- Highlight that matches Apple on the iPhone: 1.85–2.5 (mean ≈ 2.15), with our face
  at tint 0 vs Apple's default. At a matched, brighter face the value would be
  slightly higher still.
- Side finding: the system default tint is not Clear. Apple's face over black is 130
  on both the simulator (key unset) and the iPhone, vs 102 in the tint-0 references.
  That matches our model at tintAmount ≈ 0.45.
- The Mac HDR capture path (ScreenCaptureKit, `hdrglass/probe.swift`) is blocked:
  the worker process lacks Screen Recording permission.
- Crops: `glint-device-vs-sim-5x.jpg`.

## Inner-shadow inset (not changed)

Host GPU-golden renders of `toolbar_capsule` (light, highlight 1) vs the
Reduce Motion off Apple capture (#175, white probe), band 1.5–25 pt:

| offset | all rms | top wall | bottom wall | sides | bias (all) |
|---|---|---|---|---|---|
| 2.5 | 2.76 | 2.22 | 4.27 | 1.52 | −1.43 |
| 3.75 | 2.76 | 2.20 | 4.28 | 1.61 | −1.41 |
| 4.5 | 2.77 | 2.17 | 4.28 | 1.67 | −1.40 |
| 6.0 | 2.78 | 2.17 | 4.28 | 1.80 | −1.39 |

Why it looks tight: below the top wall, Apple's band is darkest around 8–14 pt; ours
peaks at about 4–5 pt. On the sides, Apple darkens right at the rim; ours has a light
leading-edge gap (see `inner-shadow-inset-5x.jpg`). One isotropic offset can't
express this. The fit is flat in offset (2.76–2.78), and 2.5 is where the top and
sides balance. The larger error is a uniform bias: Apple is 1.1–2 levels darker
across the band, most at the bottom wall. The 49d9c86 note "absent at the
bottom" is not supported by this capture.

Proposal (needs sign-off, #171): make the offset follow the light axis
(larger where the normal faces the light, ~0 at the sides) in both shaders
(ALU only), and refit strength for the bias. Don't just change the default.

## Directional inner shadow (implemented, #171 `c78e956`)

Measured Apple's shadow as a share of transmitted light: `(ours_noshadow −
Apple − interior offset) / (ours_D − ours_C)`, binned by inset and light
facing, on Reduce Motion off `toolbar_capsule(_dark)` (#175).

- It's the rim band displaced along the light. Top: peak at 7–12 pt. Sides:
  peak at the rim. Bottom: none. As a share of transmitted light it's the same in
  light (2.6%) and dark (2.4%), so it absorbs transmitted backdrop, not the wash.
- Model (same 4 uniforms): `shift = offset·facing`,
  `band = smoothstep(0, 2·max(shift,0), d) · (1 − smoothstep(0, depth, d − shift))`,
  `× mix(1, wrappedFacing, directionality) × strength`, applied as
  `result −= transmitted · (1 − border) · shadow` (drops the `pow(lum, .25)`).
  FakeGlass adds back `shadow · faceEmission` (new vec3 uniform).
- Fit: strength 0.036, depth 16, offset 6, directionality 0.5.
  Analytic rms (levels): toolbar L/D 0.65/0.62 → 0.40/0.40, held-out small
  capsule 0.98/1.22 → 0.51/0.86. The old family refitted only reaches 0.63/0.58,
  so the gain is the displacement, not the tuning.
- Rendered (host GPU golden, band 1.5–25 pt): light toolbar 0.82 → 0.65
  (sides 0.99 → 0.49, bottom 0.74 → 0.52, top 0.85 → 0.79). Dark 1.41 (no
  shadow) → 0.73. FakeGlass 0.55 / 0.65. 5× crops:
  `directional-inset-light-5x.jpg`, `directional-inset-dark-5x.jpg`.
- The 1–2 level gap is not shadow. It's uniform over the face beyond any band and
  also shows on the black probe (light emission 103 vs 102), so it belongs to the
  face model and was left alone.
- Harness caveat: the small capsule, large capsule and circle scenes ignore the
  settings file, so they are validated analytically only.

## Tab tint blend (#182 `3237809`)

Apple reference (`apple-tab-bar-reference.jpg`): the selected tint is (0,130,248) over
the light platter on white and (0,83,186) on black. Fitted with a single blend
mode on encoded values, rms in levels: hardLight 18.8, srcOver 22.5, darken
50.7, multiply 53.5, colorBurn 60.6, overlay 99.8, softLight 100.4,
color 99.1, luminosity 91.4. Chosen: hardLight. The glyphs are painted with it
directly (no layer); the source is the inverse at platter tone 0.92
(light) / 0.4 (dark), from the app appearance, not the sampled estimate.
Device comparison: `tint-blend-modes-device.jpg`.
