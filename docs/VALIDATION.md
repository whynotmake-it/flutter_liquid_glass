# What we validated

One entry per decision that was settled by a measurement or a test, so a
switch or knob can be removed without losing why it was safe. Each entry says
what was decided, the numbers, and where the full data lives.

Paths are relative to `packages/liquid_glass_renderer/`. Benchmark sections
refer to `example/tool/results/pixel10-2026-09-30.md` unless noted.

## Renderer switches removed in the 1.0 cleanup

### Geometry texture reuse (`LIQUID_GLASS_REUSE_GEOMETRY_TEXTURES`)

- **Decision:** always reuse; the switch is gone.
- **Pixel 10, #178 vs reuse off** (section 6.1, medians of 4 runs, ±1–2%):
  - button stretch 103.7 → 120.1 fps, `PAINT` 3.74 → 0.94 ms;
  - three layers 67.4 → 116.1 fps, `PAINT` 9.43 → 2.18 ms;
  - peak PSS + GPU: sheet 816 → 629 MB, `resizeAnimated` 591 → 425 MB;
  - UI GC about 19 → 5 ms/s; GPU Mcycles/frame within ±2%.
- **Final design, #185 grow-only sub-rect textures** (section 6.14, n = 4):
  - Pixel sheet `PAINT` 1.71 vs 3.67 ms (#178) / 5.32 ms (reuse off), peak
    321 vs 562 / 647 MB, 108.4 vs 99.0 fps;
  - Metal (M4 Max) `largeResize` peak 610 MB vs 2408 MB (#178) / 2119 MB
    (off); every Metal scene at or below reuse off.

### Rewriting a texture one frame after it was replaced (`reuseAfterFrames = 1`)

- **Decision:** one frame is enough; the matte-order validator
  (`LIQUID_GLASS_VALIDATE_MATTE_ORDER`, stamp shader, `uMatteSerial`) is gone.
- **Evidence:** 0 magenta frames and 0 magenta pixels in all 20 scene runs
  (section 6.14, step 1). Metal captured 480–860 frames per scene, Pixel
  93–296. Scenes: `resizeAnimated`, sheet, `largeResize`, 5 pills,
  `dynamicBlend16`, Colors motion, three layers, `independent16Motion`, button
  stretch, pill stretch.
- **Reasoning** (engine frame pipeline and queue ordering): doc comment on
  `FlutterGpuGeometryRenderer.reuseAfterFrames`.

### Deferred geometry submission (`LIQUID_GLASS_BATCH_GEOMETRY_SUBMISSIONS`)

- **Decision:** always defer to scene build; the switch and
  `debugSubmitImmediately` are gone.
- **Pixel 10, #179 deferred vs immediate** (section 6.1): `PAINT` 0.92 → 0.52
  ms on single-pass scenes and 2.19 → 1.17 ms on three layers; build p50 2.13
  vs 2.38 ms only on the multi-pass scene; fps, GPU, power and memory within
  noise. Verdict at the time: marginal but not harmful.
- **One command buffer per pass:** sharing a command buffer crashes on Vulkan
  (Pixel 10 PowerVR, SwiftShader) and asserts on Metal in Flutter 3.47.1.
  Stack traces are in the comment above
  `FlutterGpuGeometryRenderer._pendingCommandBuffers`.
- **Kept test:** `test/src/geometry_submit_batching_test.dart`, passes are
  submitted while the scene is built (4 passes, 4 submits per frame, no
  post-frame fallback).

### Geometry anti-aliasing half-width (`LIQUID_GLASS_GEOMETRY_AA_HALF_WIDTH`)

- **Decision:** constant 0.5 px, Flutter's own centered coverage.
- **Evidence:** none recorded. It was a tuning knob for the Apple-match harness
  and no fitted setting changed it.

### Test-only `GeometryTestFragment` in the shipped bundle

- **Decision:** removed from the bundle with its two smoke tests.
  `test/src/flutter_gpu_shader_test.dart` still builds a pipeline from the
  real `GeometryFragment` and checks its uniform reflection.

## `LiquidGlassSettings` fields removed in the 1.0 cleanup

- **Decision:** 24 fields down to 11. The removed ones are constants in
  `GlassRim` (`lib/src/liquid_glass_settings.dart`).
- **Evidence:** every preset and every example use set them to the same value
  (audit in the review thread):
  - `highlightWidth` 1.2, `highlightWrap` 0.5, `highlightOppositeStrength` 1;
  - `contourWidth` 0.75 (only the loupe tab bar used 1), `contourOffset` 0,
    `contourTransmittance` 0;
  - `bevelShadowDepth` 16, `bevelShadowOffset` 6,
    `bevelShadowDirectionality` 0.5 (clear glass had other values but strength
    0), `bevelShadowSizeResponse` 0;
  - `curvatureLighting`: never read by the renderer;
  - `exteriorShadowSizeResponse`: 1 in toolbar light, 0 in dark; now always 0
    (caller shadows are drawn exactly as given).
- **`smoothRefraction`** (always bilinear now), section 6.3, 5 runs:
  `realClearSmooth` 1.51 vs `realClearNearest` 1.50 GPU Mcycles/frame, toolbar
  2.08 vs 2.08, power and raster times unchanged.
- **Default constructor** is now the light iOS 27 toolbar (border 0.43,
  directionality 0.77, inner shadow 0.036, frost 3.7).

## Refactors checked against rendering

One poll of shape transforms per frame, the shader-input change flag that
replaced `_ShaderInputSnapshot`, and the removal of the identity
`matteTransform`:

- Full package suite with the old defaults temporarily restored: every
  nested, capture, scroll and transform test passes. The only differences were
  the ≤0.03% golden diffs that the unchanged branch also shows on this machine
  (macOS 27; references come from macos-26), plus tests whose settings changed
  on purpose.
- With the new defaults: 0 non-golden failures, 27 golden files differ (the
  ≤0.03% ones above plus the intended look change). Regenerating them on
  macos-26 is in `TODO.md`.

## Found while validating

- **Capture plus fractional fade with a border or inner shadow.** With
  `contourStrength` or `bevelShadowStrength` above 0, `real_opacity` and
  `real_fade_transition` render differently with and without a
  `LiquidGlassCapture` (max channel diff 255 for the border, 63 for the inner
  shadow; limit 4). It reproduces on the committed branch (`72859eea1`), so it
  predates the cleanup; the old defaults had both off. Tracked in `TODO.md`.

## Shadow defaults audit (2026-10-14)

- **Decision:** retain the material's `bevelShadowStrength = 0.036` and the
  caller-owned exterior-shadow API. Do not promote a universal exterior-shadow
  replacement from this host-only audit.
- **Inputs:** retained
  `example/tool/apple_match/references/ios27-iphone17pro-reduce-motion-off/slider-000/`
  references, validated with the existing provenance tool; Flutter 3.47.1,
  macOS 27, Impeller and Flutter GPU, 3x SDR captures. The existing host capture
  harness enables real MaskFilter shadows. No alignment or color adjustment
  was applied to the images.
- **The blog toolbar is not a shadow-default comparison:** its material-only
  settings omit exterior shadows. Its scene renders a roughly 225x101 pt
  capsule, whereas the Apple black-probe support measures 224x94 pt. Holding
  the renderer at 224x94 pt reproduces Apple's support bounds exactly
  (`267,1170` to `939,1452`, exclusive right/bottom, physical pixels).
- **Inner shadow:** with geometry corrected and appearance held fixed,
  the white-probe mean absolute error of face-relative darkening in the
  12-48 physical-pixel inner band is 1.790 at strength 0, 0.513 at 0.030,
  0.253 at the current 0.036, 0.282 at 0.040, and 0.558 at 0.050.
  Face-relative darkening removes the uniform core-color residual from the
  measurement, not from the images. This supports the current strength,
  not a claim that all rim/profile residuals are solved.
- **Exterior shadow:** measured white-probe RGB MAE in the annulus 6-60
  physical pixels outside the Apple black-probe silhouette (2-20 pt).
  The toolbar search held all material controls fixed; the small and large
  capsules are holdouts with their unmodified scene geometry.

  | Shape | No exterior shadow | Example shadow | Toolbar host fit |
  | --- | ---: | ---: | ---: |
  | Small capsule | 0.330 | 6.944 | 1.711 |
  | Toolbar, corrected geometry | 1.805 | 5.887 | 0.357 |
  | Large capsule | 3.763 | 4.028 | 1.578 |

  Values are 8-bit channel levels, not perceptual or whole-render scores.
  The example shadow is black alpha `31/255`, blur radius 24 pt, offset
  `(0,8)` pt, spread 0. The toolbar host fit is black alpha 0.06, blur
  radius 12 pt, offset `(0,6)` pt, spread 0. Its regression on the small
  holdout is why it must not become a universal default.
- **Evidence:** 23 toolbar candidate vectors plus six holdout vectors and
  their frozen C/D frames, manifests, logs, measurement scripts/JSON and
  `toolbar-shadow-audit.png` under
  `example/tool/apple_match/out/shadow-audit/` (ignored local output).
  The audit preserved the original blog inputs and retained Apple captures. The blog toolbar figure was subsequently updated, at the user’s request, to show the scene-specific host fit; its original raw inputs remain archived alongside the fitted ones.
- **Regression checks:** `liquid_glass_settings_test.dart` and
  `fake_glass_bevel_shadow_test.dart` passed, 11 tests total, with Impeller
  and Flutter GPU enabled.
- **Promotion blocker:** the fitting tool's pinned iPhone 17 Pro/iOS 27
  simulator (`DB4F41F3-1C36-476D-B775-AFDC3686C75B`) is absent on this
  machine. A matching pinned iOS capture must confirm any replacement before
  changing shipped shadow values; this audit did not recreate a simulator or
  change its pin. The user chose a clearly labeled host-only blog illustration rather than simulator setup or a shipped-default change.

## Implementation summaries

<!-- Summaries from the agents that implemented each piece go here. -->
