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

### Share one base between the real and fake layers

See the subagent prompt in the review thread. Also covers the three input
snapshots plus two flags in `LiquidGlassRenderObject` (one state machine) and
the third copy of the translation poll in `consolidated_fake_glass_layer.dart`.

### Let the active frame state own the matte

Follow-up to the shared base. In the planned `GlassFrame` state
(`GlassFrameNoMatte` / `GlassFrameIdle` / `GlassFrameActive`, `null` for no
contributors), `GlassFrameActive` holds only the input snapshot and bounds.
The matte itself (`_geometryImage`, `_materialImage`, `_geometryMatteBounds`,
`_geometryTextureSize`, `_materialTextureSize`, `_matteSerial`,
`_materialCenterInMatte`, `_ownsGeometryImages`) stays in separate fields.
Moving it into `GlassFrameActive` makes the state the single owner of the
matte, so `GlassFrameIdle.matte` keeps the images alive by construction and
releasing a frame releases its images.

### Fold `GlassRim` constants into the shaders

The removed settings are now constants written into the same uniform slots,
so the shaders still carry contour offset, transmittance, bevel size response
and the other rim uniforms. Moving them into the GLSL as constants shrinks the
uniform blocks of the final pass and `fake_glass_surface.frag`. Mind the
hand-counted float indices (47, 53, 55, 59) in
`liquid_glass_render_object.dart`.

## Waiting on a decision

### Parameterize the color models

How the model reaches the shader today: `colorModel.shaderValue` is a
selector (0 direct, 1 iOS 27 light, 2 dark, 3 clear), sent as
`uAppearanceConfig.x` or packed into the response row's w as
`(visibility + code * 2) / 7`. `colorModelSharesOf` decomposes it into
(direct, dark, clear) shares so merges lerp shares rather than codes.
Every model constant is baked into `liquid_glass_final_render_core.glsl`
(`sliderKeyframes`, `ios27DarkTransmittance`, `ios27NeutralTint`,
`ios27FaceTransfer`, `ios27TintTone`, the clear-glass glint overrides) and
mirrored a second time in `liquid_glass_color_model.dart` for FakeGlass
(`faceTransfer`, `tintTone`, `contourScale`, `fakeGlintLuminance`). The
shader's per-pixel model inputs are only backdrop luminance, `uTintAmount`
and `uAppearanceConfig.w` (shortSide).

`saturation`/`transmissionGamma`/`vibrancy` are not dead: both shader
branches consume them — for iOS 27 as relative adjustments where 1 is the
platform face — but no preset sets them, so they are API weight that also
invites the stale direct-model fits in `tool/apple_match/settings/*.json`.

Parameterization looks feasible, which would let the sealed class become a
plain class of resolved parameters with `direct`/`ios27*` as const presets:

- Direct is a degenerate case of the iOS 27 math: emission alpha 0, lift 0,
  chromaGain 1, identity tintTone (one difference: the direct branch applies
  saturation to the blended base *including* tint; the iOS 27 branch applies
  it to backdrop chroma only, before the tint mix).
- Everything except the tint-tone ramp is resolvable on Dart per shape —
  `faceTransfer(shortSide, tintAmount)` already mirrors the GLSL for
  FakeGlass, which consumes the model as resolved data today. Passing
  emission/alpha, lift, chromaGain, contourScale and the glint triple
  (~11 floats) deletes `sliderKeyframes`, `ios27DarkTransmittance`,
  `ios27NeutralTint`, `ios27FaceTransfer` and `colorModelSharesOf` from the
  shader, and merging shapes lerps the parameters directly — better than
  the shares hack it replaces.
- `tintAmount` moves onto the model (per shape), which the resolved-params
  form needs anyway; `uTintAmount` leaves the uniform block with them.
- Per-shape cost: the material map grows from 2 lookup rows per frame to
  about 5 (the extra ~11 floats over 16 texels).
- The blocker is `ios27TintTone`, the only per-pixel piece: the light ramp
  is `scale(Y) * tint^g(Y)` (4 coefficients), the dark ramp is
  `floor(Y) + (ceil(Y) - floor(Y)) * tint` (6). Either fit both into one
  generic monotone form (~12 coefficients) or keep the two ramps with a
  selector/weight — which keeps a vestigial model axis.

Fallback if the ramp does not parameterize cleanly: keep the codes and do
the smaller version — `DirectLiquidGlassColorModel(saturation,
transmissionGamma, vibrancy)`, `Ios27LiquidGlassColorModel(brightness,
tintAmount)`, `LiquidGlassAppearance` shrinks to `tint`, `visibility` and
`colorModel`. That drops the iOS 27 relative adjustments, so stale
saturation/gamma/vibrancy on `ios27*` settings files get ignored instead
of silently applied. Needs separate slots in the material map's per-shape
lookup row so a direct-to-iOS-27 merge does not blend unrelated values.

## Tooling

See the subagent prompt in the review thread for the full audit. Known so far:

- `tool/apple_match/settings/*.json` carry keys `LiquidGlassSettings` no
  longer has, and old direct-model fits (saturation 1.65–2.6, gamma
  0.58–1.3, vibrancy 0.1–0.15) even on files that select `ios27*` models.
  The harness now parses settings with `LiquidGlassSettings.fromJson`, so
  missing keys take the new toolbar defaults.
- `capture.sh` and `evaluate.py` still pass
  `LIQUID_GLASS_DISABLE_CANVAS_CONTOUR`, which nothing reads.
