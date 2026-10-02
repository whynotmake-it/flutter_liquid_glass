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

### FakeGlass silhouettes alias at rest on macOS

Some FakeGlass edges showed a fine staircase, visible only when zoomed in:
the example's tab bar and the circles in the Blend and Colors scenes. Real
glass was fine, and so were iOS and Android.

Root cause: on Impeller's Metal macOS backend, a runtime-effect
(`Paint().shader`) `drawRect` whose quad edge lands on a half-integer
device-pixel boundary renders its alpha ramp quantized to whole pixels
within a few px of that edge — the analytic silhouette in
`fake_glass_surface.frag` came out as a staircase. It reproduces with a
bare `canvas.drawRect` + `Paint().shader` on a plain `CustomPaint`, so
none of the FakeGlass layer machinery is involved. Skia renders the same
draws smoothly at every phase, and the artifact is unchanged with
`impeller-use-sdfs=false`, so it lives in the general contents/entity-pass
path, not the UberSDF pipeline — the same failure family as
flutter/engine#52973 (flutter/flutter#146967, nearest sampling straddling
a half-pixel offset).

The surface quad is `shape.inflate(1.75pt)` — at 2x that is a 3.5px
outset, so an integer-positioned shape puts the quad edge at x.5px, the
bad phase. That matches every observation: dragged elements land on
fractional positions (integer quad edges) and stay smooth after settling,
the tab bar returns to an integral rest position (half-pixel quad edge),
and moving the whole layer keeps the shapes' positions relative to it.

Fix: `fakeGlassSurfaceQuad` in `internal/paint_fake_glass_surface.dart`
expands the drawn quad outward so its edges land on whole device pixels.
The rect only bounds where the shader runs — the silhouette is placed by
`FlutterFragCoord` — so growing it is invisible and the shape stays
exact. This is a workaround for the engine bug; a self-contained minimal
repro with the issue text (`ISSUE.md`) lives outside this repo at
`~/Developer/flutter_issues/impeller_pixel_aligned_coverage`. Verified on a real macOS window with an edge-fit
metric (rms_dev 0.33px -> 0.06px on aligned superellipses; the Colors
ovals likewise).

Removed with it, because none of them were load-bearing for the artifact:
`fake_glass_backdrop_edge.frag` and the whole edge band (the shared
`BackdropKey`, the outset/inset/band clip paths, `_edgeShapes` encoding,
`backdropEdgeShader` plumbing, `_syncBackdropEdge`), and
`test/src/fake_glass_edge_test.dart`. The shared backdrop pass is clipped to
the plain shape path again; its stencil edge sits under the surface's own
analytic coverage and is not visible.

## Refactors

### FakeGlass anti-aliasing in one pass on Impeller

Done differently: the edge band turned out to be compensating for the wrong
bug. The real defect is half-pixel-aligned shader draw quads quantizing
coverage on macOS (see Bugs), now worked around by `fakeGlassRasterOffset`.
The edge pass, its shared key and the outset/inset/band paths are removed;
the shared backdrop is back to a plain path clip. If the blur's stencil
silhouette ever becomes visible, the remaining option is
`ImageFilter.compose(inner: blur, outer: coverageShader)` clipped to the
pixel-snapped bounding rect.

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
