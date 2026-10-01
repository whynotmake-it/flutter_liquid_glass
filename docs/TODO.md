# To do

Open work from the 1.0 renderer review. Items that need a device say which.
Paths are relative to `packages/liquid_glass_renderer/`.

## Needs the Pixel 10

### Simplify `LiquidGlass.precache` and GPU renderer loading

Today `precache` waits for the first rasterized frame on Android, builds a
whole `FlutterGpuGeometryRenderer` and disposes it, only to fill the static
`_resolvedAssetResources` cache. The "reading `gpuContext` before the first
frame blocks the UI thread for 100 ms or more" claim behind
`waitUntilGpuContextAvailable` has no recorded measurement.

Proposed design:

- One `FlutterGpuGeometryRenderer.preload()` that awaits
  `ShaderLibrary.fromAsset`, creates the three pipelines and caches them in a
  single static `Future<_SharedGeometryResources>?` (replacing the two maps
  keyed by asset).
- `precache` calls `preload()`. A layer calls `tryCreateCached` and falls back
  to `preload()` post-frame.
- The dispose dance and the separate `fromAsset` path go away.

Measure first: a Perfetto trace of a cold start that reads `gpuContext`
before the first frame. If it is cheap, drop `waitUntilGpuContextAvailable`.
If it blocks, `preload()` has to run post-frame, because creating pipelines
reads `gpuContext`.

### Simpler geometry texture reuse

The current `_TextureRing` keeps up to two extra spares per output, an
app-wide pool of released textures claimed by other layers (with a 1.5x waste
rule), and a set of renderers with spares trimmed by a frame counter.

Proposed design:

- **Two slots per output** (matte, material map). Render into whichever slot
  was retired at least `reuseAfterFrames` ago. If neither has (a second render
  in one frame), allocate a fresh texture and drop the older one. That is the
  only reuse rule.
- **Grow in 1.5x steps**, capped at the view, rather than plain 64 px buckets,
  so a growing sheet does not allocate a new pair every 64 px.
- **Shrink when idle:** when the needed size has fit in less than about half
  the capacity for 120 frames, drop both textures; the next render allocates
  at the needed size.
- **No cross-layer pool:** whatever a disposed layer held is freed.

Removes `_released`, `_claimReleased`, `_renderersWithSpares`, the spare
trimming and about half of `_TextureRing`. Validate with
`test/src/geometry_texture_reuse_test.dart` and a Pixel A/B against the
#185 numbers in `VALIDATION.md` (sheet `PAINT` 1.71 ms, peak 321 MB).

## Needs macos-26

### Regenerate goldens and README snapshots

The new default settings (light toolbar border and inner shadow, 3.7 pt
frost) and the removed knobs change 27 golden files. Run
`flutter test --update-goldens` for the package on the golden job's macos-26
image, and regenerate `doc/generated/` (written by `docs_snapshot_test.dart`).
`fake_glass_real_contour_offsets.png` was deleted with its test.

## Bugs

### Border and inner shadow change under `LiquidGlassCapture` in a fade

Inside a fractional `Opacity` or `FadeTransition`, a layer with
`contourStrength` or `bevelShadowStrength` above 0 renders differently with
and without a `LiquidGlassCapture` around it. Reproduces on `72859eea1`.

Repro: remove the `contourStrength: 0` and `bevelShadowStrength: 0` lines in
`test/src/capture_scenes.dart` and run
`test/src/liquid_glass_capture_real_opacity_test.dart` and
`liquid_glass_capture_real_fade_transition_test.dart` (max channel diff 255
with the border, 63 with only the inner shadow; limit 4). Suspect: the seeded
opacity pass origin (`GlassCompositionProbe.seededPassOrigin`) or the capture
region not covering the contour outset. Check on a device too, since some fade
cases are known flutter_tester mis-renders.

## Refactors

### FakeGlass anti-aliasing in one pass on Impeller

Impeller clips backdrop filters with the stencil, so the clipped blur has a
jagged silhouette. Today a second keyed backdrop filter
(`fake_glass_backdrop_edge.frag`) redraws a ±2 px band of sharp backdrop over
it. This is FakeGlass only.

Proposed: one `BackdropFilterLayer` clipped to the pixel-snapped bounding
rect (rect clips do not alias) with
`ImageFilter.compose(inner: blur, outer: coverageShader)`. The shader returns
the blurred color times analytic coverage with alpha equal to coverage; with
`srcOver`, the sharp backdrop stays outside the shape. That removes the edge
filter, its shared key, the outset/inset/band paths, and probably the separate
passes for fading shapes. Skia and the web keep the path clip, which they
anti-alias.

### Share one base between the real and fake layers

See the subagent prompt in the review thread. Also covers the three input
snapshots plus two flags in `LiquidGlassRenderObject` (one state machine) and
the third copy of the translation poll in `consolidated_fake_glass_layer.dart`.

### Fold `GlassRim` constants into the shaders

The removed settings are now constants written into the same uniform slots,
so the shaders still carry contour offset, transmittance, bevel size response
and the other rim uniforms. Moving them into the GLSL as constants shrinks the
uniform blocks of the final pass and `fake_glass_surface.frag`. Mind the
hand-counted float indices (47, 53, 55, 59) in
`liquid_glass_render_object.dart`.

## Waiting on a decision

### Parameterize the color models

- `DirectLiquidGlassColorModel(saturation, transmissionGamma, vibrancy)`
- `Ios27LiquidGlassColorModel(brightness, tintAmount)`, moving `tintAmount` off
  `LiquidGlassSettings` (the presets still take it to derive frost)
- `LiquidGlassAppearance` shrinks to `tint`, `visibility` and `colorModel`

Needs separate slots in the material map's per-shape lookup row so a
direct-to-iOS-27 merge does not blend unrelated values.

## Tooling

See the subagent prompt in the review thread for the full audit. Known so far:

- `tool/apple_match/settings/*.json` carry keys `LiquidGlassSettings` no
  longer has, and old direct-model fits (saturation 1.65–2.6, gamma
  0.58–1.3, vibrancy 0.1–0.15) even on files that select `ios27*` models.
  The harness now parses settings with `LiquidGlassSettings.fromJson`, so
  missing keys take the new toolbar defaults.
- `capture.sh` and `evaluate.py` still pass
  `LIQUID_GLASS_DISABLE_CANVAS_CONTOUR`, which nothing reads.
