import 'dart:ui';

/// Paints for glyphs tinted with [tint] on glass of [brightness], in the
/// order to draw them.
///
/// Each glyph is drawn twice: first multiplying the glass beneath it, then
/// adding a base color on top, so every channel ends up as a base plus a
/// share of the glass tone. Both paints draw straight into the glass's
/// content, so this needs no extra layer or pass, and the tint follows the
/// backdrop instantly and shows its detail.
///
/// Fitted to the selected item of the iOS 27 system tab bar (the
/// `references/bottom-bar-refs` branch,
/// `internal/bottom-bar-match/apple-measurements.md`), whose tint follows
/// the tone of the platter beneath it in both appearances while keeping its
/// hue:
///
/// * Light: (0, 130, 248) over the platter on white (lum 231) and
///   (0, 93, 199) over the platter on black (lum 97), about
///   `tint * (0.6 + 0.45 * glass)` per channel (multiply, then screen).
/// * Dark: (6, 151, 255) over the platter on black and a light cyan
///   (85, 230, 255) over the platter on white (lum 143), about
///   `tint + 0.585 * glass` in every channel (multiply, then plus).
///
/// Either way it stays less saturated than the hard light blend this
/// replaces, which turned it deep blue (B = 255) over dark and busy glass.
/// Apple's tint does not get lighter over darker content within one
/// appearance; it reads lighter there because the whole bar flips to its
/// dark appearance, which the example gets from the bar's adaptive
/// brightness rather than from the blend.
List<Paint> vibrantTintPaints(Color tint, Brightness brightness) {
  Color channels(double Function(double channel) f) => Color.from(
    alpha: tint.a,
    red: f(tint.r).clamp(0.0, 1.0),
    green: f(tint.g).clamp(0.0, 1.0),
    blue: f(tint.b).clamp(0.0, 1.0),
  );
  final (Color share, Color base, BlendMode add) = switch (brightness) {
    Brightness.light => (
      channels((c) => c * _lightShare / (1 - c * _lightBase)),
      channels((c) => c * _lightBase),
      BlendMode.screen,
    ),
    Brightness.dark => (
      channels((_) => _darkShare),
      tint,
      BlendMode.plus,
    ),
  };
  return [
    Paint()
      ..color = share
      ..blendMode = BlendMode.multiply,
    Paint()
      ..color = base
      ..blendMode = add,
  ];
}

/// Fraction of the tint a glyph on light glass keeps over black glass.
const _lightBase = .6;

/// Fraction of the tint a glyph on light glass gains from white glass.
const _lightShare = .45;

/// Fraction of the glass tone a glyph on dark glass adds to the tint.
const _darkShare = .585;
