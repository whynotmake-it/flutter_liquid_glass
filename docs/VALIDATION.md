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

## Implementation summaries

<!-- Summaries from the agents that implemented each piece go here. -->
