# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Flutter monorepo for implementing liquid glass/frosted glass effects in Flutter applications. The project uses Melos for managing multiple packages and requires Impeller (Flutter's new rendering engine) - Skia is not supported.

**Packages:**
- `liquid_glass_renderer`: Core package for rendering liquid glass effects with custom shaders
- `apple_liquid_glass`: iOS 27-style controls, bars and presentations drawn on the renderer
  (libraries foundation < motions < surfaces < liquid < raw < widgets, held by
  `test/layer_rules_test.dart`); without a `GlassScope` it draws flat glass, and the adaptive
  renderer draws fake glass where full glass is unavailable
- `kinesis`: unpublished motion and input foundation the widgets build on (springs, one clock,
  input regions, presentations); depends on neither glass package
- `apple_liquid_glass_accessibility`: unpublished plugin that feeds the iOS and macOS
  accessibility settings Flutter does not report into `apple_liquid_glass`
- `liquid_glass_adaptive_brightness`: unpublished, experimental light/dark estimate of the content behind a widget; independent of the renderer

**Platform Support:**
- Supported: macOS, iOS, Android (Impeller only)
- Not supported: Web, Windows, Linux

## Common Commands

### Package Management
```bash
# Bootstrap the workspace (run after cloning)
melos bootstrap

# Get dependencies for all packages
melos clean && melos bootstrap
```

### Development
```bash
# Run code generation for all packages
melos run generate

# Run code generation for specific package
melos run generate:select

# Analyze all packages (concurrency=1 to avoid crashes on low-end machines)
melos run analyze
```

### Testing
```bash
# Run all tests (requires --enable-impeller flag)
melos run test

# Run tests for specific packages
melos run test:select

# Run tests without golden tests (useful for PRs without golden label)
melos run test-without-goldens

# Update golden test images (on macOS 27.2.1 or 27.0.1, see Testing > Golden Tests)
melos run update-goldens

# Generate coverage for all packages
melos run coverage
```

### Versioning
```bash
# Version all packages (without git tags)
melos run version-all

# Standard melos versioning with git tags
melos version
```

### Running the Example App
```bash
cd packages/liquid_glass_renderer/example
flutter run --enable-impeller --enable-flutter-gpu
```

## Architecture

### Rendering Pipeline

`liquid_glass_renderer` has four libraries, each a folder of `lib/src/`: `painting`
(values: shapes, settings, appearance) < `plan` (the frame's plan) < `rendering` (render
objects and layers that carry the plan out, and the frame's report) < `widgets`.
`painting`, `rendering` and `widgets` each sit behind one library file that lists only
its public API; `plan` has none and serves the package alone.
`test/layer_rules_test.dart` holds the order;
`liquid_glass_renderer.dart` exports `painting` and `widgets`. The renderer animates
nothing (no tickers, no gestures): motion belongs to the widget libraries on top, which
drive glass through `LiquidGlass.live` frames.

One frame of glass:

1. **Widgets** (`lib/src/widgets/`): `LiquidGlassLayer` shares settings and one layer
   among its glass, `LiquidGlass` is a shape, `LiquidGlassBlendGroup` fuses nearby shapes
   (at most 16 per draw, `geometryMaxShapesPerDraw`), `FakeGlass` draws a cheaper look
   from backdrop filters.
2. **Composer** (`lib/src/rendering/glass_composer.dart`): a child `PipelineOwner` of the
   view's owner, flushed after the view's paint and before any scene is built. It lowers
   the view's layers into a `GlassForm` (`glass_form*.dart`; `_nodeOf` lists the layer
   types it can copy past), asks every site (`SiteFacts`) what it needs, and compiles the plan.
3. **Plan** (`lib/src/plan/`): `compilePlan` is a pure function of the sites' answers.
   It decides each read's source (`SceneRead`: the copy's layers replayed inside the
   read's filter; `ImageRead`: a held image; `BackdropRead`: the backdrop itself), which glass
   shares a read, the copy's size and frost (`read_layout.dart`), and how many passes
   that costs. `PlanPrices` (`plan_tuning.dart`) are measured on a Pixel 6a and only sign
   these trades.
4. **Reads** (`lib/src/rendering/read.dart`, `copy_*.dart`, `scene_out.dart`): carry the
   plan out. The pixels of a read are `ScenePixels`, `ImagePixels` or `BackdropPixels`, one per
   plan source. The backdrop glass shows is never a frame late.
5. **Geometry** (`lib/src/rendering/geometry_tiling*.dart`,
   `flutter_gpu_geometry_renderer*.dart`, `gpu/tile_*_fragment.glsl`): a Flutter GPU atlas.
   `Tiling` cuts a layer's buffer into 16 x 16 tiles and draws only the tiles near an
   edge, one RGBA16F texel per buffer pixel (R: distance to the edge, positive inside; GB:
   the direction the surface faces; A: half the shape's shorter side). Outside and deep
   tiles point at shared constant blocks through a table. Where fused shapes differ in
   look, the same pass writes their looks beside the atlas. Glass of one shape with no look
   of its own that does not lean (`geometryKindOf`) skips the atlas and works its shape
   out in the final shader (`shape_geometry.glsl`).
6. **Final shader** (`liquid_glass_final_render_core.glsl`): refraction, frost, lighting
   and color, compiled into the variants `FinalShaderVariant.all` lists (one
   `liquid_glass_final_render*.frag` stub of defines each). They are not in `pubspec.yaml`'s
   `flutter.shaders` (they can't compile to SkSL, which fails Skia/web builds):
   `hook/build.dart` compiles them to `build/shaderbundles/*.iplr` via impellerc.
   `test/shader_registers.txt` holds their Mali register counts.

### Key Components

- **Shapes** (`lib/src/painting/liquid_shape.dart`): RoundedSuperellipse, Oval, RoundedRectangle
- **Settings** (`lib/src/painting/liquid_glass_settings.dart`): refraction, frost, lighting
- **FakeGlass** (`lib/src/widgets/fake_glass.dart`, `lib/src/rendering/fake_glass.dart`): backdrop filters instead of the glass shader
- **LiquidGlassGlow** (`lib/src/painting/liquid_glass_glow.dart`): the touch glow a widget sets on its glass frame by frame
- **Color models** (`lib/src/painting/liquid_glass_color_model.dart`): the iOS 27 models follow the size of the glass that wears them: inside the package an appearance is worn at a shape's size (`WearAppearance.wear`, `lib/src/rendering/appearance.dart`), which gives the model of the shape's shorter side, a control's up to 64 pt, a panel's from 160 pt. Each shape resolves its own look in real glass and in FakeGlass, so a shape's look never depends on the other shapes of its layer and does not jump when a FakeGlass shape fades into a filter of its own (`appearance_size_independence_test.dart`). Keep it that way: no layer-wide size response. The frost is the one exception: a layer reads one copy, frosted by its smallest shape (`wornShortSide`).

### Performance Considerations

`gpu.Texture` cannot be disposed ([Flutter issue #138627](https://github.com/flutter/flutter/issues/138627)), so atlases placed between two flushes share a page, and a page is drawn over again only `FlutterGpuGeometryRenderer.reuseAfterFrames` frames after its last atlas was released.

**When working on performance:**
- Minimize LiquidGlassLayer and LiquidGlassBlendGroup pixel coverage
- Limit number of blended shapes (each adds computational load)
- Moving a shape of a LiquidGlassBlendGroup against the others redraws the group's atlas; the group moving as one only moves its mapping
- `GlassFrameReport` (`GlassFrameReports.addListener`, `debugPrintGlassFrameReports`, both from `rendering.dart`) shows what a frame's glass took

## Code Generation

The project uses `build_runner` for code generation. Always run `melos run generate` after modifying files that require codegen (annotated classes, JSON serialization, etc.).

**Pre-commit hook**: The melos version command automatically runs `melos run generate` before committing.

## Testing

### Golden Tests
Golden tests verify visual output and are tagged with `golden` in `dart_test.yaml`. They only run:
- On main branch
- On PRs labeled with "goldens"
- On macOS 27 only, against references rendered by `flutter test --update-goldens` on macOS 27.2.1 (26B131, arm64); the golden job's `xcode-27` image is macOS 27.0.1 (26A434), which draws the same pixels (see `.github/workflows/main.yaml`)

**Regenerating goldens:** GPU output differs between hosts, so regenerate references only on macOS 27.2.1 or 27.0.1. On such a machine run:

```bash
melos run update-goldens
```

On another macOS version, first capture the goldens with `--dart-define=GOLDEN_CAPTURE=<dir>` and compare their pixels with the references: if they differ, references rendered there fail on the `xcode-27` golden job.

All tests must use the `--enable-impeller` flag since Skia is not supported.

### Device Tests

`example/integration_test/*_test.dart` (all but `benchmark_test.dart`) run shared tests
on a Mac (Metal), where glass reads copies of what lies under it (`glassReadsCopies`)
while flutter_tester reads backdrop filters, and check what flutter_tester cannot render
faithfully. `device_tests.dart` starts them as `test/flutter_test_config.dart` starts the
host's. Run them after changing how glass reads or composites its backdrop, one target at
a time:

```bash
cd packages/liquid_glass_renderer/example
flutter drive --driver=test_driver/backdrop_seed_driver.dart \
  --target=integration_test/visibility_frame_device_test.dart -d macos \
  --enable-impeller --enable-flutter-gpu
```

### Test Structure
- Tests are in `packages/*/test/` directories
- Test config: `dart_test.yaml` at root and package level
- Uses `alchemist` for golden testing
- Coverage reports generated with `whynotmake-it/dart-coverage-assistant`

## CI/CD Workflows

- **main.yaml**: Runs analysis, tests, and golden tests
- **version.yaml**: Automated versioning with melos
- **tag-release.yaml**: Creates GitHub releases from tags
- **benchmark.yaml**: Performance benchmarking

## Debugging

Set `debugPaintLiquidGlassGeometry = true` (exported from `rendering.dart`) to visualize the geometry instead of the glass effect. Only works in debug mode.

## Shader Development

Shader source files are in `packages/liquid_glass_renderer/lib/assets/shaders/`:
- Main shader files: `*.frag`
- Shared utilities: `*.glsl` (`render.glsl`, `liquid_glass_final_render_core.glsl`, `shape_sdf.glsl`, the shapes' distances for real glass and FakeGlass alike; Flutter GPU includes in `gpu/`: `sdf.glsl`, `geometry_encoding.glsl`)
- `shader_constants.glsl`, the `*_lanes.glsl` files, the `liquid_glass_final_render*.frag` stubs, the `gpu/tile_*_fragment.glsl` stubs and `liquid_glass_renderer.shaderbundle.json` are generated from `lib/src/painting/shader_constants.dart`, `FinalShaderVariant` and `AtlasShader`, where the numbers, uniform layouts and variants Dart and the shaders share live. Don't edit them: change the table and run `flutter test --enable-impeller --enable-flutter-gpu --dart-define=UPDATE_SHADER_CONSTANTS=true test/shader_constants_test.dart test/src/final_shader_variant_test.dart test/src/atlas_shaders_test.dart`
- Flutter GPU shaders are built by `hook/build.dart` from the shaderbundle json

The shaders `pubspec.yaml` lists (`fake_glass_surface.frag`, `fake_glass_field_surface.frag`, `bent_content.frag`) are compiled by the Flutter tool (they support SkSL for Skia/web). The `liquid_glass_final_render*` shaders are compiled by `hook/build.dart` into `build/shaderbundles/*.iplr` for all Impeller runtime stages and loaded via `FragmentProgram.fromAsset`. Edit `.frag` files and run `flutter run` to hot reload changes (though shaders typically require full restart).
