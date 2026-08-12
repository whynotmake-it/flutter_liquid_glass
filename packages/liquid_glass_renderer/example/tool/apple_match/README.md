# Apple liquid glass matching

Deterministic scorecard for getting Flutter glass close to Apple without
LLM vibe-checks. This is not a pixel-perfect clone. The contract is a numeric
closeness score against pinned iOS 27 captures.

The harness that will live in this directory is not built yet. This document
is the plan: scene JSON, a SwiftUI capture app, a Flutter capture of the same
JSON, OpenCV/NumPy compare (flow/MTF), then `scorecard.json` plus diagnostic
PNGs.

Do not let the LLM judge closeness. The LLM only patches shaders and settings.
Success is JSON thresholds.

## Source of truth

Pinned **iOS 27** simulator. iOS 26 Clear/Tinted is obsolete. macOS
WindowServer glass is a later cross-check, not the reference.

First honesty check: one probe on the simulator versus a real iOS 27 device.
If they disagree, freeze Apple references from the device and only re-capture
Flutter overnight.

Pin device, orientation, and Reduce Motion for every capture.

## Capture protocol

Subtractive probes, one scene at a time. Compare:

| Probe | Background | Isolates |
| --- | --- | --- |
| A | Grid or photo | Combined look |
| B | Mid-gray | Subtract from A → refraction / warp |
| C | Black | Specular / highlight |
| D | White or solid color | Tint / face color |

Median of N frames. Apple specular jitters, and a physical device can shift
pose between shots.

Tell **radial flow sign** on A−B, not just magnitude:

- Convex lens: interior ~0, rim flow inward.
- Lip / switch: center minifies (flow reverses).
- Same shape after scaling = just bezel width, not a different profile.

## iOS 27 transparency slider

Settings → Appearance → Liquid Glass. Sweep
`{0, 0.25, 0.5, 0.75, 1.0}` (0 = ultra clear, 1 = most tinted). Midpoint is
the default. Reduce Transparency is a separate endpoint, not `t=1`.

Hypothesis: a tint + blur overlay fading in. Do **not** map this slider to
`LiquidGlassSettings.visibility` until the sweep plot exists. `visibility`
also scales thickness and refraction.

No public `simctl` key yet. Dump defaults or XCUITest-drag Settings.

## Per-control catalog

One lens does not describe every control. Score per profile, not one pill:

- `profile_toolbar_capsule`
- `profile_switch` (off and on; crop the thumb)
- `profile_slider_track` / `profile_slider_thumb`
- generic grid capsule + transparency sweep
- tab bar as a **holdout** (acceptance, not loss)

## What our shader does today

`packages/liquid_glass_renderer/lib/assets/shaders/render.glsl` builds a
quarter-circle convex height from the SDF:

```glsl
getHeight(sd, thickness) = sqrt(thickness^2 - (thickness+sd)^2)
```

`thickness` and `refractiveIndex` cannot become a lip profile. If Apple's
switch differs, the agent must change `getHeight` or add a per-shape profile
enum. Do not keep turning the existing knobs and hoping.

## First slice

Four static probes + transparency sweep + tab-bar holdout. Prove the
scorecard moves when `thickness`, `lightAngle`, and `blur` change. Then the
overnight loop is allowed to patch.

## Overnight loop

Better dump than LLM screenshots: per-control `_UIViewGlass` +
`glassBackground` uniforms on the iOS 27 simulator (slider vs tab pill vs
toggle).

Published reverse engineering (no `metallib` dump):

- [Lrdcq](https://lrdcq.com/me/read.php/165.htm) — `_UIViewGlass`,
  `CABackdropLayer` + `glassBackground`, `CASDFLayer`. Warp is a **1D
  SDF-distance remap**, not Snell on a 3D bezel. Modes: shrink, magnify, and
  **reflect** (most used). Knobs: `inputInnerRefractionHeight`,
  `inputInnerRefractionAmount`. Flags: `contentLensing`,
  `excludingControlLensing`, `excludingControlDisplacement`.
- CAFilterBuiltins: inner **and** outer refraction; 5-stop blur ramp
  (`blurOpacity0–4` / `blurDistance0–4`); face tint matrix; bleed; shadow;
  separate `glassForeground` with aberration.
- [ShatteredGlass](https://github.com/AlexStrNik/ShatteredGlass) — “Liquid
  Lens” for slider/toggle still in progress; dual opposite-angle
  `CASDFGlassHighlightEffect`.
- [GlassExplorer](https://github.com/ktiays/GlassExplorer)
- [sspai](https://sspai.com/post/100983)
- decant: icon CoreUI only, not chrome.
- kube.io CSS article is a reconstruction, not a leak.

## Layout (planned)

```
tool/apple_match/
  README.md          ← this plan
  scenes/*.json      ← shared scene graph
  apple/             ← SwiftUI capture app
  flutter/           ← Flutter capture of the same JSON
  compare/           ← OpenCV/NumPy flow + MTF
  out/scorecard.json
  out/*.png
```
