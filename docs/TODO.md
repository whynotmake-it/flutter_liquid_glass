# To do

Open work from the 1.0 renderer review. Items that need a device say which.
Paths are relative to `packages/liquid_glass_renderer/`.

## Needs the Pixel 10

### Preload GPU resources directly

Let `precache` load and cache shared GPU resources without constructing and
disposing a temporary `FlutterGpuGeometryRenderer`.

### Shrink idle geometry textures

`_TextureRing` grows in 1.5x steps but never shrinks while a layer lives. A
shrink after sustained smaller use landed in #228 and was reverted in #229;
revisit with a Pixel A/B against the numbers in `VALIDATION.md`.

## Refactors

### Let the active frame state own the matte

`LiquidGlassRenderObject` tracks the frame as a `GlassFrameState` enum
(`empty` / `idle` / `active`) next to its input snapshot and bounds.
The matte itself (`_geometryImage`, `_materialImage`, `_geometryMatteBounds`,
`_geometryTextureSize`, `_materialTextureSize`, `_matteSerial`,
`_materialCenterInMatte`, `_ownsGeometryImages`) stays in separate fields.
Turning the state into classes that carry the matte makes the active state
its single owner, so an idle frame keeps the images alive by construction and
releasing a frame releases its images.

### Fold `GlassRim` constants into the shaders

The removed settings are now constants written into the same uniform slots,
so the shaders still carry contour offset, transmittance, bevel size response
and the other rim uniforms. Moving them into the GLSL as constants shrinks the
uniform blocks of the final pass and `fake_glass_surface.frag`. Mind the
hand-counted float indices (47, 53) in `rendering/liquid_glass_layer.dart`.

## Tooling

See the subagent prompt in the review thread for the full audit. Known so far:

- `tool/apple_match/settings/*.json` carry keys `LiquidGlassSettings` no
  longer has, and old direct-model fits (saturation 1.65–2.6, gamma
  0.58–1.3, vibrancy 0.1–0.15) even on files that select `ios27*` models.
  The harness now parses settings with `LiquidGlassSettings.fromJson`, so
  missing keys take the new regular defaults.
- `capture.sh` and `evaluate.py` still pass
  `LIQUID_GLASS_DISABLE_CANVAS_CONTOUR`, which nothing reads.
