## 0.3.0-dev.1

> Note: This release has breaking changes.

- **BREAKING**: replace the old `LiquidGlassSettings` material model:
  - `glassColor` is now `tint`.
  - `blur` is now `frost` and is an absolute logical-pixel sigma.
  - `lightIntensity` is now `highlight`.
  - `refractiveIndex` is replaced by the observable `edgeRefraction` peak.
  - `lightAngle` and `ambientStrength` are removed.
  - Add refraction reach/scale, transmission, paired-highlight, contour,
    curvature-lighting, inner-shadow, and size-response controls.
- **BREAKING**: remove the experimental `Glassify` API and its arbitrary-shape
  shader path. The supported shapes are `LiquidRoundedSuperellipse`,
  `LiquidRoundedRectangle`, and `LiquidOval`.
- **BREAKING**: the full renderer now requires Flutter GPU in addition to
  Impeller. `LiquidGlassLayer` automatically uses `FakeGlass` when the full
  path is unavailable instead of failing to render.
- **BREAKING**: `FakeGlass` now follows the shared tint, frost, contour,
  highlight, inner-shadow, visibility, and exterior-shadow settings. Optical
  refraction and transmission-only controls remain full-renderer-only.
- **FEAT**: add documented `LiquidGlassSettings.ios27ToolbarLight` and
  `ios27ToolbarDark` presets fitted to toolbar-sized materials; the example
  follows platform appearance and bundles both presets. The
  `LiquidGlassSettings.ios27Toolbar` factory selects the independently fitted
  material from a Flutter `Brightness`.
- **FEAT**: add explicit `backdropKey` support and consistent
  `useBackdropGroup` behavior to real and fake layers.
- **FEAT**: paint per-shape shadows below blended glass with a material cutout.
- **PERF**: cache geometry mattes, coordinate mappings, composed native image
  filters, and static transforms; clip the final shader to material bounds.
- **PERF**: compose FakeGlass blur and color work into one backdrop-filter pass
  and render each shape with a lightweight analytic material shader, skipping
  inactive effects. In repeated matched Pixel 10 toolbar measurements this cut
  raster p95 by 20.8%, total-frame p95 by 17.0%, and PSS by 3.9% versus the
  full renderer; results remain workload-dependent.
- **FIX**: keep FakeGlass foreground ordering aligned with the full layer and
  fit its contour, highlight, frost, and bevel response to shared settings.
- **FIX**: refit dark transmission across eight guarded hues, removing blue,
  green, and cyan blowout from the earlier dark toolbar preset.
- **FIX**: use the fitted Rec.709 luminance basis for real and FakeGlass color
  transfer and retune the dark preset saturation to 2.6; isolated solid-face
  probes lower the guarded dark transmission error without adding shader work.
- **FIX**: apply a measured, one-pass chroma-aware saturation lift to RealGlass
  transmission using a linear clamp (no extra samples or passes); the matching
  frost-free light/dark corpus improves vivid blue, cyan, and green transfer
  while preserving neutral and black/white guards. FakeGlass retains its affine
  fallback because a per-pixel chroma lift is not expressible there without
  changing its cheaper filter contract.
- **TEST**: extend the Apple-match harness with dynamic, provenance-checked
  full-face solid hue probes and black/white emission guards.
- **TEST**: add normalized bounded SPSA fitting and annotated all-probe solid
  color atlases so coupled color experiments run on macOS GPU goldens instead
  of repeatedly recapturing iOS references.
- **FIX**: invalidate both host-capture and path-dependent renderer shader
  caches when an included runtime-effect source changes, preventing stale
  shader binaries from contaminating color-fit measurements.
- **FIX**: emit compact benchmark reports with unchunked stdout records so
  profile frame and memory measurements are parsed reliably.
- **FIX**: preserve the full Gaussian tail in standalone and layer-owned shadow
  paint bounds without expanding the clipped refraction pass.
- **FIX**: restore glow behavior after the renderer rewrite.
- **DOCS**: generate the README showcase from a Snaptest renderer test and
  publish it to `doc/generated` after successful test runs.

## 0.2.0-dev.4

> Note: This release has breaking changes.

 - **BREAKING** **FIX**: fake glass didn't render properly on skia and had bad specular highlights (#119).

## 0.2.0-dev.3

 - **FIX**: improve logging readability and names.
 - **FIX**: don't create intermediate images for geometry until it's settled.

    This should decrease memory consumption somewhat, as a layer with one animating geometry would create 2 images per frame before

 - **FEAT**: export `debugPaintLiquidGlassGeometry` (#111).

## 0.2.0-dev.2

 - **FIX**: glass was always grouped no matter which constructor was used.
 - **FIX**: one frame delay in geometry mattes.
 - **FIX**: link doesn't need to notify listeners, we can mark it dirty.

## 0.2.0-dev.1

> Note: This release has breaking changes.

 - **FIX**: adjust `LiquidGlassSettings` defaults to match the look more closely.
 - **FEAT**: cache geometry images as well to make sure we only run the geometry shader when absolutely necessary.
 - **DOCS**: mention Impeller requirement earlier in README.
 - **DOCS**: update README with newest changes and performance tips.
 - **BREAKING** **REFACTOR**: remove the unsupported experimental widget API.
 - **BREAKING** **REFACTOR**: renamed many constructors and default `LiquidGlass` to not creating its own layer.

    Please read the README to understand how to use this package.

 - **BREAKING** **REFACTOR**: `LiquidGlassShape`s now take a simple double as radius.
 - **BREAKING** **REFACTOR**: move `blend` setting from `LiquidGlassSettings` to `LiquidGlassBlendGroup`.
 - **BREAKING** **FEAT**: adjust fake glass light intensity.
 - **BREAKING** **FEAT**: rewrote rendering pass to use two passes.

    We now cache all geometry into textures first, then render liquid glass in a second pass.
    This allows us to save a lot of cycles while glass shapes are static.


## 0.1.1-dev.26

> Note: This release has breaking changes.

 - **FIX**: only run shader on bounding box pixels.
 - **FIX**: set alwaysNeedsCompositing correctly on `FakeGlass`.
 - **BREAKING** **REFACTOR**: change default blend value to 0 in `LiquidGlassSettings`.
 - **BREAKING** **REFACTOR**: move `fake` parameter to `LiquidGlassLayer` and make entire layer fall back to fake glass on Skia.
 - **BREAKING** **FEAT**: visibility parameter in `LiquidGlassSettings`.

    This can be used to scale all relevant properties of the liquid glass effect
    at once.
    
    If you have made glass appear and disappear manually before, you can now
    simply animate the visibility between 0 and 1.


## 0.1.1-dev.25

 - **FEAT**: add `fake` parameter to `LiquidGlass` to enable it to turn into `FakeGlass` dynamically (#103).

## 0.1.1-dev.24

 - **FIX**: import `@internal` from meta again (#102).
 - **FIX**: scrolling elements work again.
 - **FEAT**: add `FakeGlass.inLayer` which adopts settings from the nearest ancestor layer.

## 0.1.1-dev.23

> Note: This release has breaking changes.

 - **BREAKING** **FEAT**: re-use generated geometry more aggressively (#98).

## 0.1.1-dev.22

> Note: This release has breaking changes.

 - **FIX**: reduce texture samples (#94).
 - **FEAT**: small performance wins in shader (#91).
 - **BREAKING** **REFACTOR**: remove `restrictThickness`.
 - **BREAKING** **FEAT**: rewrote the rendering process to use two passes.

    This significantly improves performance while glass elements
    are static on screen. Moving glass elements will still induce the same
    performance cost as before.

## 0.1.1-dev.20

 - **FIX**: `resistance` parameter didn't actually get used.

## 0.1.1-dev.19

> Note: This release has breaking changes.

 - **FIX**: revert matrix methods to support older Flutter versions again.
 - **FIX**: `TileMode.mirror` in `FakeGlass` blur.
 - **FEAT**: allow customizing `resistance` in `LiquidStretch`.
 - **FEAT**: expose `RawLiquidStretch` for custom pixel-based stretching.
 - **FEAT**: expose `Offset.withResistance` extension method.
 - **BREAKING** **FEAT**: `LiquidStretch` now bases its stretch on the child's size.

## 0.1.1-dev.18

 - **FIX**: removed unused transform from shader (#88).
 - **FIX**: render liquid glass correctly on all Android devices (#82 by @teociaps).

## 0.1.1-dev.17

 - **FEAT**: tried to improve the fidelity of fake light once more.

## 0.1.1-dev.16

 - **FIX**: import annotations from `package:meta` again.

## 0.1.1-dev.15

> Note: This release has breaking changes.

 - **FIX**: settling springs.
 - **FIX**: optimize some painting and transformations with early return.
 - **FEAT**: better specular on all platforms for `FakeGlass` (#83).
 - **BREAKING** **REFACTOR**: rename `StretchGlass` to `LiquidStretch`.

## 0.1.1-dev.14

 - **FIX**: `LiquidGlassLayer` breaks when no child glass widgets are found.

## 0.1.1-dev.13

 - **DOCS**: update README and add better disclaimer (#80).

## 0.1.1-dev.12

> Note: This release has breaking changes.

 - **FIX**: regression in how `LiquidGlass` applies transform to children.
 - **FEAT**: add `GlassGlowLayer` and `GlassGlow` widget for glow effects.
 - **FEAT**: add `StretchGlass` widget that can stretch its child with user gestures.
 - **FEAT**: add `FakeGlass` widget that aims to match `LiquidGlass` appearance while being much more performant.
 - **BREAKING** **REFACTOR**: remove useless `lightness` parameter from shader and `LiquidGlassSettings`.
 - **BREAKING** **REFACTOR**: change default value of `glassContainsChild` to false.

## 0.1.1-dev.11

> Note: This release has breaking changes.

 - **BREAKING** **FEAT**: performance gains and too many changes to cover one by one (#72).

## 0.1.1-dev.10

> Note: This release has breaking changes.

 - **REFACTOR**: move shader to uniform arrays for better shape support.
 - **FIX**: transform children of liquid glass correctly.
 - **FEAT**: add saturation and brightness controls (#47).
 - **FEAT**: better light dispersion.
 - **FEAT**: support up to 64 shapes per layer.
 - **FEAT**: specular highlights now take the background color into account (#43).
 - **DOCS**: updated README with new parameters (#56).
 - **DOCS**: updated example gif (#55).
 - **BREAKING** **FEAT**: cheat lighting that is independent from thickness.

## 0.1.1-dev.9

 - **DOCS**: fix errors in README (#31).

## 0.1.1-dev.8

 - **FIX**: glass now also renders when blend is set to 0.
 - **FIX**: sharper glass edges whithout background shining through.
 - **FEAT**: added refractive index to settings and show values in example.
 - **FEAT**: nicer specular highlights.
 - **DOCS**: update README.md and add better examples (#28)

## 0.1.1-dev.7

 - **FIX**: throw `AssertionError` when used without Impeller.
 - **DOCS**: update pubspec.yaml to reflect minimum SDK and supported platforms.

## 0.1.1-dev.6

 - **FIX**: liquid glass not repainting in route transitions (#16).

## 0.1.1-dev.5

> Note: This release has breaking changes.

 - **FEAT**: decrease precision in shader to mediump, which should increase performance.
 - **BREAKING** **FIX**: shader compilation and removed unused outline strength parameter.

## 0.1.1-dev.4

 - **FIX**: fix shader on flutter stable.
 - **DOCS**: new shape names.

## 0.1.1-dev.3

 - **DOCS**: new shape names.

## 0.1.1-dev.2

> Note: This release has breaking changes.

 - **REFACTOR**: cleaned up shaders.
 - **FIX**: squircle can handle zero radius.
 - **FEAT**: add `clipBehavior` to `LiquidGlass`.
 - **FEAT**: flutter-approved SDF for squircles.
 - **FEAT**: support three shapes per layer.
 - **FEAT**: support all shapes.
 - **FEAT**: better chromatic abberation.
 - **DOCS**: added pub badge to README.
 - **BREAKING** **FEAT**: renamed liquid glass shapes to match their OutlinedBorder counterparts.

## 0.1.1-dev.1

 - **DOCS**: update pubspec and readme.

## 0.1.1-dev.0

 - **FEAT**: initial release.

## 0.1.0

- feat: initial commit 🎉
