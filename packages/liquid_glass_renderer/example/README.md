# Liquid Glass playground

A settings playground for `liquid_glass_renderer`. Run it from the repository
root with:

```sh
cd packages/liquid_glass_renderer/example
fvm flutter run -d macos
```

Use `fvm flutter devices` to pick an iOS or Android Impeller device instead of
`macos`.

The stage shows glass over backdrops that page horizontally and scroll
vertically, so the glass moves over real content: a photo feed, a night page,
a long article and a grid. The inspector next to it (below it on phones)
controls:

- **Scene**: everyday controls, shapes that merge in a `LiquidGlassBlendGroup`,
  light, dark, clear and tinted glass blending in one layer, and
  `LiquidGlassLoupe`s magnifying the backdrop.
- **Material**: the Regular, Toolbar, Clear and Loupe presets in light or dark,
  or Auto, where the top controls and the bottom bar each flip as a group with
  the brightness of the backdrop behind them
  (`LiquidGlassAdaptiveBrightness`). The Liquid Glass slider sets
  `LiquidGlassSettings.tintAmount`.
- **FakeGlass** instead of the full renderer, plus **Refraction** and
  **Lighting** controls. **Copy as Dart** puts the current
  `LiquidGlassSettings` on the clipboard.

Interactive glass shows the package's `GlassGlow` under the pointer. All glass
on the stage renders in a single `LiquidGlassLayer`; each loupe brings its own.

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
