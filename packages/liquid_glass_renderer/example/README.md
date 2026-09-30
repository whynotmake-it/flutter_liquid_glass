# Liquid Glass playground

A settings playground for `liquid_glass_renderer`. Run it from the repository
root with:

```sh
cd packages/liquid_glass_renderer/example
fvm flutter run -d macos
```

Use `fvm flutter devices` to pick an iOS or Android Impeller device instead of
`macos`.

The stage shows glass over a backdrop you can switch between photographs and
high-contrast type and grid pages. The inspector next to it (below it on
phones) controls:

- **Scene**: everyday controls, shapes that merge in a `LiquidGlassBlendGroup`,
  light, dark, clear and tinted glass blending in one layer, and large lenses
  for judging refraction.
- **Material**: the Regular, Toolbar, Clear and Loupe presets in light or dark,
  or Auto, where each control flips with the brightness of the backdrop behind
  it (`LiquidGlassAdaptiveBrightness`). The Liquid Glass slider sets
  `LiquidGlassSettings.tintAmount`.
- **Renderer**: the full renderer or `FakeGlass`.
- **Refraction**, **Lighting** and **Blending** controls. **Copy Settings as
  Dart** puts the current `LiquidGlassSettings` on the clipboard.

All glass on the stage renders in a single `LiquidGlassLayer`.

For a deterministic grid backdrop and a fixed blur (useful for screenshots):

```sh
fvm flutter run -d macos \
  --dart-define=LIQUID_GLASS_EXAMPLE_TEST_BACKGROUND=true \
  --dart-define=LIQUID_GLASS_EXAMPLE_TEST_BLUR=0
```

Other entry points:

- `lib/adaptive_brightness_main.dart`: a focused adaptive brightness demo.
- `integration_test/benchmark_test.dart`: the benchmark harness, see
  [`tool/README.md`](tool/README.md).
- `--dart-define=LIQUID_GLASS_EXAMPLE_PERFORMANCE_PROBE=true` logs frame timing
  windows, and `--dart-define=LIQUID_GLASS_DEBUG_GEOMETRY=true` paints the
  geometry textures instead of glass.

The photographic backdrops in `assets/backdrops/` are AI-generated for this
example.
