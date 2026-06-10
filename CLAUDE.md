# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Flutter monorepo for implementing liquid glass/frosted glass effects in Flutter applications. The project uses Melos for managing multiple packages and requires Impeller (Flutter's new rendering engine) - Skia is not supported.

**Packages:**
- `liquid_glass_renderer`: Core package for rendering liquid glass effects with custom shaders
- `apple_liquid_glass`: WIP wrapper that currently just re-exports `liquid_glass_renderer`

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
   - `liquid_glass_geometry_blended.frag`: Renders blended glass geometry
   - `liquid_glass_filter.frag`: Applies glass effects (refraction, blur)
   - `liquid_glass_final_render.frag`: Final composition

### Key Components

- **Shapes** (`lib/src/liquid_shape.dart`): Defines glass shape types (RoundedSuperellipse, Oval, RoundedRectangle)
- **Settings** (`lib/src/liquid_glass_settings.dart`): Configures glass appearance (thickness, blur, color, lighting)
- **FakeGlass** (`lib/src/fake_glass.dart`): Lightweight alternative using backdrop filters instead of shaders
- **GlassGlow** (`lib/src/glass_glow.dart`): Touch-responsive glow effects
- **LiquidStretch** (`lib/src/stretch.dart`): Squash and stretch animations

### Performance Considerations

The package aggressively caches geometry in textures to minimize GPU work. However, due to [Flutter issue #138627](https://github.com/flutter/flutter/issues/138627), textures cannot be disposed immediately, causing memory spikes during animations.

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
- On macOS-15 runners (see `.github/workflows/main.yaml`)

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
- Shared utilities: `*.glsl` (sdf.glsl, shared.glsl, displacement_encoding.glsl, render.glsl)

Shaders are compiled by Flutter and loaded via `flutter_shaders` package. Edit `.frag` files and run `flutter run` to hot reload changes (though shaders typically require full restart).
