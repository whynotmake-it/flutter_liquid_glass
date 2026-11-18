import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:liquid_glass_renderer/src/painting/glass_work.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_color_model.dart';

/// What a `LiquidGlassBackdropFilterLayer` does to what lies under it.
///
/// A filter is any image filter ([LiquidGlassBackdropFilter.image]), a blur
/// and a color matrix the renderer can draw with a shader of its own
/// ([LiquidGlassBackdropFilter.frost]), or the band of a scroll edge
/// ([LiquidGlassFrostBand.hard], [LiquidGlassFrostBand.soft]): a frost
/// with a fade over it, which glass over the band draws in its own filter.
@immutable
sealed class LiquidGlassBackdropFilter {
  const LiquidGlassBackdropFilter._();

  /// Any image [filter], which blurs by at most [sigma] logical pixels: how
  /// far past its clip the filter reads what lies under it.
  const factory LiquidGlassBackdropFilter.image(
    ui.ImageFilter filter, {
    double sigma,
  }) = LiquidGlassImageBackdropFilter._;

  /// A Gaussian blur by [sigma] logical pixels along both axes, reading
  /// past the backdrop's edge as [tileMode] says, then [colorMatrix] as
  /// [ui.ColorFilter.matrix] takes it, or none.
  factory LiquidGlassBackdropFilter.frost({
    required double sigma,
    List<double>? colorMatrix,
    ui.TileMode? tileMode,
  }) = LiquidGlassBackdropFrost._;
}

/// A [LiquidGlassBackdropFilter] that is any image filter
/// ([LiquidGlassBackdropFilter.image]).
///
/// A copy of what lies under the layer is filtered as the backdrop would
/// be; the renderer draws no part of it with a shader of its own.
final class LiquidGlassImageBackdropFilter extends LiquidGlassBackdropFilter {
  const LiquidGlassImageBackdropFilter._(this.filter, {this.sigma = 0})
    : assert(sigma >= 0, 'A blur has no negative sigma.'),
      super._();

  /// The filter.
  final ui.ImageFilter filter;

  /// The widest blur of [filter], in logical pixels; zero for a filter
  /// that reads nothing beside a pixel.
  final double sigma;

  @override
  bool operator ==(Object other) =>
      other is LiquidGlassImageBackdropFilter &&
      other.filter == filter &&
      other.sigma == sigma;

  @override
  int get hashCode => Object.hash(filter, sigma);

  @override
  String toString() =>
      'LiquidGlassBackdropFilter.image($filter, sigma: $sigma)';
}

/// A Gaussian blur followed by a color matrix
/// ([LiquidGlassBackdropFilter.frost]): a backdrop filter that the renderer
/// draws from an unblurred copy at a fraction of the screen's pixels,
/// frosted by a shader as it is drawn, wherever a copy serves and the frost
/// is narrow enough for the shader; otherwise the copy is filtered.
///
/// NEAR: the shader's taps over a smaller copy are not Impeller's blur.
final class LiquidGlassBackdropFrost extends LiquidGlassBackdropFilter {
  LiquidGlassBackdropFrost._({
    required this.sigma,
    this.colorMatrix,
    this.tileMode,
  }) : assert(sigma > 0, 'A frost blurs.'),
       assert(colorMatrix == null || colorMatrix.length == 20, '5 x 4 values.'),
       super._();

  /// The blur's sigma, in logical pixels.
  final double sigma;

  /// The color matrix applied after the blur, row by row, as
  /// [ui.ColorFilter.matrix] takes it; null for none.
  final List<double>? colorMatrix;

  /// What the backdrop blur reads past the backdrop's edge, as
  /// [ui.ImageFilter.blur] takes it. A copy is frosted inside the screen,
  /// where it reads its own edge.
  final ui.TileMode? tileMode;

  /// The same filter as an image filter, for what reads the backdrop.
  late final ui.ImageFilter filter = _filter();

  ui.ImageFilter _filter() {
    if (!kReleaseMode) GlassWork.filters++;
    final blur = ui.ImageFilter.blur(
      sigmaX: sigma,
      sigmaY: sigma,
      tileMode: tileMode,
    );
    final matrix = colorMatrix;
    if (matrix == null) return blur;
    return ui.ImageFilter.compose(
      outer: ui.ColorFilter.matrix(matrix),
      inner: blur,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LiquidGlassBackdropFrost &&
      other.sigma == sigma &&
      other.tileMode == tileMode &&
      listEquals(other.colorMatrix, colorMatrix);

  @override
  int get hashCode => Object.hash(
    sigma,
    tileMode,
    colorMatrix == null ? null : Object.hashAll(colorMatrix!),
  );

  @override
  String toString() =>
      'LiquidGlassBackdropFilter.frost(sigma: $sigma'
      '${colorMatrix == null ? '' : ', colorMatrix: $colorMatrix'}'
      '${tileMode == null ? '' : ', tileMode: $tileMode'})';
}

/// A frost by [sigma] logical pixels and [colorMatrix], as
/// [LiquidGlassBackdropFilter.frost] builds it, under its own type.
@internal
LiquidGlassBackdropFrost backdropFrost({
  required double sigma,
  List<double>? colorMatrix,
  ui.TileMode? tileMode,
}) => LiquidGlassBackdropFrost._(
  sigma: sigma,
  colorMatrix: colorMatrix,
  tileMode: tileMode,
);

/// The band of a scroll edge: what lies under it frosted, and a fade over
/// the frost, along the top or the bottom edge of the screen.
///
/// The layer's children lie over the frost. Whoever holds the layer paints
/// the band's fade as its child ([paintOver]), faded by [presence]; where
/// glass lies over the band the glass draws the frost and the fade in its
/// own filter and the children are left out.
sealed class LiquidGlassFrostBand extends LiquidGlassBackdropFilter {
  const LiquidGlassFrostBand._({
    required this.sigma,
    required this.edge,
    required this.fade,
    required this.presence,
  }) : assert(
         edge == AxisDirection.up || edge == AxisDirection.down,
         'A band lies along the top or the bottom edge.',
       ),
       super._();

  /// A hard band, a navigation bar's, along the [edge] of the screen
  /// ([AxisDirection.up] or [AxisDirection.down]): what lies under it
  /// blurred by [sigma] logical pixels, saturated by [saturation] and
  /// brightened by [brightness], all of it faded toward [fade], and a
  /// hairline of [line], one device pixel wide, along its side away from
  /// [edge]. [presence] is how much of the band shows.
  const factory LiquidGlassFrostBand.hard({
    required double sigma,
    required AxisDirection edge,
    required Color fade,
    required Color line,
    required double saturation,
    required double brightness,
    double presence,
  }) = LiquidGlassHardFrostBand._;

  /// A soft band along the [edge] of the screen ([AxisDirection.up] or
  /// [AxisDirection.down]): what lies under it blurred by [sigma] logical
  /// pixels and faded toward [fade], whole from [edge] to [fadeStart] of
  /// the way across the band and gone at its far side, its frost dissolving
  /// with the fade. [presence] is how much of the band shows.
  const factory LiquidGlassFrostBand.soft({
    required double sigma,
    required AxisDirection edge,
    required Color fade,
    required double fadeStart,
    double presence,
  }) = LiquidGlassSoftFrostBand._;

  /// The blur of what lies under the band, in logical pixels.
  ///
  /// NEAR: drawn up to 12 % wider where that lets Impeller blur at half
  /// resolution.
  final double sigma;

  /// The edge of the screen the band lies along: [AxisDirection.up] or
  /// [AxisDirection.down].
  final AxisDirection edge;

  /// The color the band fades what lies under it toward, straight.
  final Color fade;

  /// How much of the band shows, 0 to 1.
  final double presence;

  /// Paints what the band lays over its frost in [rect], the layer's clip:
  /// the fade, and a hard band's hairline, one pixel of [devicePixelRatio]
  /// wide.
  ///
  /// It paints the band whole, whatever its [presence]: the draws do not
  /// overlap, so an opacity layer of the presence fades them as one.
  void paintOver(
    Canvas canvas,
    Rect rect, {
    required double devicePixelRatio,
  });

  bool get _top => edge == AxisDirection.up;
}

/// The hard [LiquidGlassFrostBand], a navigation bar's
/// ([LiquidGlassFrostBand.hard]).
final class LiquidGlassHardFrostBand extends LiquidGlassFrostBand {
  const LiquidGlassHardFrostBand._({
    required super.sigma,
    required super.edge,
    required super.fade,
    required this.line,
    required this.saturation,
    required this.brightness,
    super.presence = 1,
  }) : super._();

  /// The hairline along the band's side away from [edge], straight.
  final Color line;

  /// The saturation of what lies under the band.
  final double saturation;

  /// The brightness added to what lies under the band, as a fraction of
  /// full intensity.
  final double brightness;

  @override
  void paintOver(
    Canvas canvas,
    Rect rect, {
    required double devicePixelRatio,
  }) {
    // The hairline takes its own strip, already blended over the fade, so
    // the two draws do not overlap: an opacity layer above them then hands
    // its alpha to each draw instead of drawing them in a layer of its own.
    final (start, end) = lineRows(rect, devicePixelRatio);
    final strip = Rect.fromLTRB(rect.left, start, rect.right, end);
    final band = _top
        ? Rect.fromLTRB(rect.left, rect.top, rect.right, start)
        : Rect.fromLTRB(rect.left, end, rect.right, rect.bottom);
    final paint = Paint()..color = fade;
    canvas.drawRect(band, paint);
    paint.color = Color.alphaBlend(line, fade);
    canvas.drawRect(strip, paint);
  }

  @override
  bool operator ==(Object other) =>
      other is LiquidGlassHardFrostBand &&
      other.sigma == sigma &&
      other.edge == edge &&
      other.fade == fade &&
      other.line == line &&
      other.saturation == saturation &&
      other.brightness == brightness &&
      other.presence == presence;

  @override
  int get hashCode =>
      Object.hash(sigma, edge, fade, line, saturation, brightness, presence);

  @override
  String toString() =>
      'LiquidGlassFrostBand.hard(sigma: $sigma, edge: $edge, '
      'fade: $fade, line: $line, saturation: $saturation, '
      'brightness: $brightness, presence: $presence)';
}

/// The soft [LiquidGlassFrostBand], which dissolves into what lies under it
/// ([LiquidGlassFrostBand.soft]).
final class LiquidGlassSoftFrostBand extends LiquidGlassFrostBand {
  const LiquidGlassSoftFrostBand._({
    required super.sigma,
    required super.edge,
    required super.fade,
    required this.fadeStart,
    super.presence = 1,
  }) : super._();

  /// Where the fade starts to dissolve, as a fraction of the way across the
  /// band from [edge]: the fade and the frost are whole up to it and gone
  /// at the band's far side.
  final double fadeStart;

  @override
  void paintOver(
    Canvas canvas,
    Rect rect, {
    required double devicePixelRatio,
  }) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: _top ? Alignment.topCenter : Alignment.bottomCenter,
        end: _top ? Alignment.bottomCenter : Alignment.topCenter,
        colors: [fade, fade, fade.withValues(alpha: 0)],
        stops: [0, fadeStart, 1],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool operator ==(Object other) =>
      other is LiquidGlassSoftFrostBand &&
      other.sigma == sigma &&
      other.edge == edge &&
      other.fade == fade &&
      other.fadeStart == fadeStart &&
      other.presence == presence;

  @override
  int get hashCode => Object.hash(sigma, edge, fade, fadeStart, presence);

  @override
  String toString() =>
      'LiquidGlassFrostBand.soft(sigma: $sigma, edge: $edge, '
      'fade: $fade, fadeStart: $fadeStart, presence: $presence)';
}

/// What the renderer draws of a band.
@internal
extension DrawnFrostBand on LiquidGlassFrostBand {
  /// The saturation of what lies under the band.
  double get drawnSaturation => switch (this) {
    LiquidGlassHardFrostBand(:final saturation) => saturation,
    LiquidGlassSoftFrostBand() => 1,
  };

  /// The brightness added, as a fraction of full intensity.
  double get drawnBrightness => switch (this) {
    LiquidGlassHardFrostBand(:final brightness) => brightness,
    LiquidGlassSoftFrostBand() => 0,
  };

  /// The hairline, straight; transparent where the band has none.
  Color get drawnLine => switch (this) {
    LiquidGlassHardFrostBand(:final line) => line,
    LiquidGlassSoftFrostBand() => const Color(0x00000000),
  };

  /// The color matrix of the band's frost, as [ui.ColorFilter.matrix] takes
  /// it; null where it changes nothing.
  List<double>? get colorMatrix {
    final saturation = drawnSaturation;
    final brightness = drawnBrightness;
    if (saturation == 1 && brightness == 0 && presence == 1) return null;
    return saturationMatrix(saturation, bias: brightness, alpha: presence);
  }

  /// The rows, in the coordinates of [clip], where the fade and the frost
  /// of a band over [clip] are whole and gone; null for a band that is
  /// whole all over.
  ({double whole, double gone})? fadeRows(Rect clip) {
    final band = this;
    if (band is! LiquidGlassSoftFrostBand) return null;
    final start = clip.height * band.fadeStart;
    return _top
        ? (whole: clip.top + start, gone: clip.bottom)
        : (whole: clip.bottom - start, gone: clip.top);
  }

  /// The rows, in the coordinates of [clip], of the hairline of a band over
  /// [clip] at [devicePixelRatio]; both the same row where there is none.
  (double, double) lineRows(Rect clip, double devicePixelRatio) {
    if (this is! LiquidGlassHardFrostBand) return (0, 0);
    final pixel = 1 / devicePixelRatio;
    return _top
        ? (clip.bottom - pixel, clip.bottom)
        : (clip.top, clip.top + pixel);
  }
}
