## 0.1.0-dev.1

- Initial prerelease, moved out of `liquid_glass_renderer`:
  `LiquidGlassAdaptiveBrightness` and `LiquidGlassBrightnessBackdrop` estimate
  the brightness of the content behind a widget so glyphs and glass can flip
  between light and dark. Descendants read the estimate with
  `LiquidGlassAdaptiveBrightness.of`.
