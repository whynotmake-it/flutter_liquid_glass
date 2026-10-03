# Liquid Glass Adaptive Brightness (experimental)

Estimates the brightness of the content behind a widget so glyphs and glass can
flip between light and dark, like iOS toolbars and tab bars. It is independent
from `liquid_glass_renderer` and works with any widget.

Unpublished prerelease; the API may change.

## Usage

Create one `LiquidGlassBrightnessSource` per content plane. Wrap the content
that scrolls beneath your chrome in a `LiquidGlassBrightnessBackdrop`, and
wrap each piece of chrome that should flip in a
`LiquidGlassAdaptiveBrightness`:

```dart
final source = LiquidGlassBrightnessSource();

Stack(
  children: [
    LiquidGlassBrightnessBackdrop(source: source, child: content),
    LiquidGlassAdaptiveBrightness(
      source: source,
      child: const Toolbar(),
    ),
  ],
);
```

Descendants read the estimate with `LiquidGlassAdaptiveBrightness.of(context)`
and pick their glyph and glass brightness from it. The region beneath each
`LiquidGlassAdaptiveBrightness` is rasterized at a few pixels of resolution and
read back asynchronously; nothing waits for the GPU, and an idle screen does
not sample.
