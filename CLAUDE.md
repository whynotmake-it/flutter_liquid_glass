# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Flutter monorepo for implementing liquid glass/frosted glass effects in Flutter applications. The project uses Melos for managing multiple packages and requires Impeller (Flutter's new rendering engine) - Skia is not supported.

**Packages:**
- `liquid_glass_renderer`: Core package for rendering liquid glass effects with custom shaders
- `apple_liquid_glass`: WIP wrapper that currently just re-exports `liquid_glass_renderer`
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

# Update golden test images
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
flutter run --enable-impeller
```

## Architecture

### Rendering Pipeline

The liquid glass effect works by capturing and distorting background pixels through a multi-stage rendering pipeline:

1. **LiquidGlassLayer** (`lib/src/rendering/liquid_glass_layer.dart`): Container widget that manages rendering context for all glass effects within it. Creates textures covering its entire area.

2. **LiquidGlass** (`lib/src/liquid_glass.dart`): Individual glass shapes that must be inside a LiquidGlassLayer. Can be standalone or grouped for blending.

3. **LiquidGlassBlendGroup** (`lib/src/liquid_glass_blend_group.dart`): Groups multiple `LiquidGlass.grouped()` shapes to blend them together seamlessly (max 16 shapes).

4. **Geometry Rendering** (`lib/src/internal/render_liquid_glass_geometry.dart`): Renders glass shape geometry into textures for shader processing. Caches geometry to avoid re-rendering on every frame.

5. **Shader Pipeline** (`lib/src/shaders.dart` and `lib/assets/shaders/`):
   - `gpu/geometry_fragment.glsl` (Flutter GPU): renders every shape of a layer into the matte
   - `gpu/material_gradient_fragment.glsl` (Flutter GPU): low-resolution per-shape appearance map
   - `liquid_glass_final_render{,_material,_tint}.frag`: the backdrop pass (refraction, frost, lighting, color). NOT listed in `pubspec.yaml`'s `flutter.shaders` (they can't compile to SkSL, which fails Skia/web builds) — `hook/build.dart` compiles them to `build/shaderbundles/*.iplr` via impellerc instead
   - `fake_glass_surface.frag`, `fake_glass_backdrop_edge.frag`: FakeGlass

### Key Components

- **Shapes** (`lib/src/liquid_shape.dart`): Defines glass shape types (RoundedSuperellipse, Oval, RoundedRectangle)
- **Settings** (`lib/src/liquid_glass_settings.dart`): Configures glass appearance (refraction, frost, lighting)
- **FakeGlass** (`lib/src/fake_glass.dart`): Lightweight alternative using backdrop filters instead of shaders
- **GlassGlow** (`lib/src/glass_glow.dart`): Touch-responsive glow effects
- **LiquidStretch** (`lib/src/stretch.dart`): Squash and stretch animations

### Performance Considerations

The package caches geometry in textures to minimize GPU work. `gpu.Texture` cannot be disposed ([Flutter issue #138627](https://github.com/flutter/flutter/issues/138627)), so each output reuses a ring of geometry textures instead of allocating one per change.

**When working on performance:**
- Minimize LiquidGlassLayer and LiquidGlassBlendGroup pixel coverage
- Limit number of blended shapes (each adds computational load)
- Cache static geometry - re-rendering on every frame is expensive
- Moving any shape in a LiquidGlassBlendGroup forces all shapes to re-render

## Code Generation

The project uses `build_runner` for code generation. Always run `melos run generate` after modifying files that require codegen (annotated classes, JSON serialization, etc.).

**Pre-commit hook**: The melos version command automatically runs `melos run generate` before committing.

## Testing

### Golden Tests
Golden tests verify visual output and are tagged with `golden` in `dart_test.yaml`. They only run:
- On main branch
- On PRs labeled with "goldens"
- On macOS only, against references rendered by `flutter test --update-goldens` on the golden job's `macos-26` runner (see `.github/workflows/main.yaml`); regenerate them on that macOS version

All tests must use the `--enable-impeller` flag since Skia is not supported.

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

Set `debugPaintLiquidGlassGeometry = true` (exported from `liquid_glass_renderer.dart`) to visualize geometry textures instead of the glass effect. Only works in debug mode.

## Shader Development

Shader source files are in `packages/liquid_glass_renderer/lib/assets/shaders/`:
- Main shader files: `*.frag`
- Shared utilities: `*.glsl` (`render.glsl`, `liquid_glass_final_render_core.glsl`, `fake_glass_shape.glsl`; Flutter GPU includes in `gpu/`: `sdf.glsl`, `material_sdf.glsl`, `displacement_encoding.glsl`)
- Flutter GPU shaders are listed in `liquid_glass_renderer.shaderbundle.json` and built by `hook/build.dart`

`fake_glass_surface.frag` is a pubspec shader compiled by the Flutter tool (it supports SkSL for Skia/web). The `liquid_glass_final_render*` shaders are compiled by `hook/build.dart` into `build/shaderbundles/*.iplr` for all Impeller runtime stages and loaded via `FragmentProgram.fromAsset`. Edit `.frag` files and run `flutter run` to hot reload changes (though shaders typically require full restart).
