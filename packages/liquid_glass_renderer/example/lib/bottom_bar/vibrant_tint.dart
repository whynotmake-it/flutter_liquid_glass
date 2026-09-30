import 'dart:ui';

/// How tinted glyphs on glass composite with the glass behind them, pixel by
/// pixel.
///
/// Fitted to the selected item of the iOS 27 system tab bar
/// (`tool/apple_match/references/ios27-iphone17pro-ground-truth-v2/`
/// `slider-000/tab_bar_holdout`), whose tint keeps its hue but darkens with
/// the glass: (0, 130, 248) over the light platter on white and (0, 83, 186)
/// over the same platter on black. Of the single blend modes, hard light
/// comes closest: the tint's bright channels screen and its dark channels
/// multiply, so the hue holds while the glass's tone and detail show
/// through. Multiply, darken and color burn turn the tint black or teal
/// over dark glass; overlay, soft light and color wash it out over light
/// glass.
const vibrantTintBlendMode = BlendMode.hardLight;

/// Glass tone at which [vibrantTintSource] reproduces the tint exactly.
///
/// Light glass uses its resting selection platter. Dark glass ranges from
/// near black to light gray over bright content, so it is matched in
/// between, where the tint neither turns cyan over light glass nor navy
/// over dark glass.
double _referenceGlass(Brightness brightness) =>
    brightness == Brightness.dark ? .4 : .92;

/// The color to paint with [vibrantTintBlendMode] so that glyphs read as
/// exactly [tint] over glass of the reference tone for [brightness].
///
/// Inverts hard light per channel on the encoded values the blend runs on.
Color vibrantTintSource(Color tint, Brightness brightness) {
  final glass = _referenceGlass(brightness);
  double channel(double target) => target <= glass
      ? target / (2 * glass)
      : 1 - (1 - target) / (2 * (1 - glass));
  return Color.from(
    alpha: tint.a,
    red: channel(tint.r),
    green: channel(tint.g),
    blue: channel(tint.b),
  );
}
