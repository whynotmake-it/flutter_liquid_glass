import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:liquid_glass_renderer/src/painting/ios27_measures.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_appearance.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_shape.dart';

/// A shadow a glass shape casts.
///
/// A shadow is either one of numbers the caller names, cast as given at
/// every size ([LiquidGlassShadow.new]), or the one fitted to iOS 27
/// regular glass ([LiquidGlassShadow.ios27Regular]), which widens and
/// deepens with the shorter side of the shape that casts it.
///
/// Glass casts its shadows by one law
/// ([LiquidGlassSilhouette.paintShadows]): they keep off the body that
/// casts them and fade with it, so a shadow has a color, an offset, a blur
/// and a spread, and no blur style.
@immutable
sealed class LiquidGlassShadow {
  /// A shadow of [color] moved by [offset], blurred by [blurRadius] and
  /// grown by [spreadRadius], with the meanings they have in a [BoxShadow],
  /// cast as given by glass of every size.
  const factory LiquidGlassShadow({
    Color color,
    Offset offset,
    double blurRadius,
    double spreadRadius,
  }) = LiquidGlassFixedShadow._;

  const LiquidGlassShadow._();

  /// The shadow iOS 27 casts under regular glass in [brightness].
  ///
  /// Glass up to 64 points on its shorter side casts a faint contact shadow:
  /// black at 1.2 % under a blur of 4 points. From 160 points it casts the
  /// full one: black at 12 % in light mode and 18 % in dark mode under a
  /// blur of 24 points. Between the two every part grows linearly. All of
  /// them fall 8 points below the glass. Clear glass casts no shadow on iOS.
  ///
  /// The numbers are read from UIKit on iOS 27 and agree with captures of
  /// native glass over white within half a level out of 255.
  ///
  /// Near, not identical: iOS shades by the distance to the outline, Flutter
  /// blurs the shape. The two agree along straight edges and differ by a
  /// fraction of a level around a corner.
  const factory LiquidGlassShadow.ios27Regular({
    required Brightness brightness,
  }) = LiquidGlassIos27RegularShadow._;
}

/// A [LiquidGlassShadow] of numbers, cast as given ([LiquidGlassShadow.new]).
final class LiquidGlassFixedShadow extends LiquidGlassShadow {
  const LiquidGlassFixedShadow._({
    this.color = const Color(0xFF000000),
    this.offset = Offset.zero,
    this.blurRadius = 0,
    this.spreadRadius = 0,
  }) : super._();

  /// The color of the shadow.
  final Color color;

  /// How far the shadow lies from the body that casts it.
  final Offset offset;

  /// The blur of the shadow, a radius as [BoxShadow.blurRadius] is.
  final double blurRadius;

  /// How far the shadow grows past the body before it is blurred. A body
  /// given as a path casts without it.
  final double spreadRadius;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiquidGlassFixedShadow &&
          other.color == color &&
          other.offset == offset &&
          other.blurRadius == blurRadius &&
          other.spreadRadius == spreadRadius;

  @override
  int get hashCode => Object.hash(color, offset, blurRadius, spreadRadius);

  @override
  String toString() =>
      'LiquidGlassShadow(color: $color, offset: $offset, '
      'blurRadius: $blurRadius, spreadRadius: $spreadRadius)';
}

/// The [LiquidGlassShadow] of iOS 27 regular glass
/// ([LiquidGlassShadow.ios27Regular]).
final class LiquidGlassIos27RegularShadow extends LiquidGlassShadow {
  const LiquidGlassIos27RegularShadow._({required this.brightness}) : super._();

  /// The colour scheme of the glass, which sets how dark its shadow gets.
  final Brightness brightness;

  @override
  bool operator ==(Object other) =>
      other is LiquidGlassIos27RegularShadow && other.brightness == brightness;

  @override
  int get hashCode => Object.hash(LiquidGlassIos27RegularShadow, brightness);

  @override
  String toString() =>
      'LiquidGlassShadow.ios27Regular(brightness: $brightness)';
}

/// A [LiquidGlassShadow] as glass of a size casts it.
@internal
extension CastGlassShadow on LiquidGlassShadow {
  static const _offset = Offset(0, 8);

  // The iOS 27 shadow's own colour is black at 30 %; the opacity that grows
  // with the size multiplies it.
  static const _alpha = 0.3;

  /// The shadow of a shape of [size].
  BoxShadow castAt(Size size) {
    switch (this) {
      case LiquidGlassFixedShadow(
        :final color,
        :final offset,
        :final blurRadius,
        :final spreadRadius,
      ):
        return BoxShadow(
          color: color,
          offset: offset,
          blurRadius: blurRadius,
          spreadRadius: spreadRadius,
        );
      case LiquidGlassIos27RegularShadow(:final brightness):
        final grown = ios27PanelProgress(size.shortestSide);
        final opacity =
            0.04 + (brightness == Brightness.dark ? 0.56 : 0.36) * grown;
        // iOS fades the shadow as erfc(distance / radius), a Gaussian edge
        // whose sigma is the radius over sqrt 2; Flutter derives sigma from
        // blurRadius as 0.57735 r + 0.5.
        final sigma = (4 + 20 * grown) / math.sqrt2;
        return BoxShadow(
          color: Color.from(
            alpha: _alpha * opacity,
            red: 0,
            green: 0,
            blue: 0,
          ),
          offset: _offset,
          blurRadius: (sigma - 0.5) / 0.57735,
        );
    }
  }
}

/// [shadows] as a shape of [size] casts them ([CastGlassShadow.castAt]).
@internal
List<BoxShadow> castGlassShadows(List<LiquidGlassShadow> shadows, Size size) =>
    shadows.isEmpty
    ? const []
    : [for (final shadow in shadows) shadow.castAt(size)];

/// The outline a glass body casts its shadows by: a [LiquidShape] filling a
/// rect ([LiquidGlassSilhouette.shape]), or a path
/// ([LiquidGlassSilhouette.path]), such as a field's edge
/// (`LiquidGlassField.edge`).
@immutable
sealed class LiquidGlassSilhouette {
  const LiquidGlassSilhouette._();

  /// The silhouette of [shape] filling [bounds].
  const factory LiquidGlassSilhouette.shape(LiquidShape shape, Rect bounds) =
      LiquidGlassShapeSilhouette._;

  /// The silhouette [path] fills.
  factory LiquidGlassSilhouette.path(Path path) = LiquidGlassPathSilhouette._;

  /// The bounds of the silhouette.
  Rect get bounds;

  /// Fills the silhouette with [paint], a shape with the canvas primitive
  /// that draws and blurs faster than its path ([LiquidShape.paintInterior]).
  void fill(Canvas canvas, Paint paint) => _fill(canvas, paint, Offset.zero, 0);

  void _fill(Canvas canvas, Paint paint, Offset offset, double spread) {
    switch (this) {
      case LiquidGlassShapeSilhouette(:final shape, :final bounds):
        shape.paintInterior(
          canvas,
          bounds.shift(offset).inflate(spread),
          paint,
        );
      case LiquidGlassPathSilhouette(:final path):
        canvas.drawPath(
          offset == Offset.zero ? path : path.shift(offset),
          paint,
        );
    }
  }

  /// Paints [shadows] cast by a glass body of this silhouette at
  /// [visibility], as a glass layer casts the shadows of a shape alone on
  /// it.
  ///
  /// The shadows keep off the body: they are cut outside it half a pixel
  /// into its edge, so no seam shows between them, and shadows with neither
  /// offset nor spread are blurred outside it alone ([BlurStyle.outer]).
  /// While the body fades their opacity and blur scale with its
  /// [visibility], and they show through it by the part it has yet to fade
  /// in. A [LiquidGlassShadow.ios27Regular] among them is cast at the size
  /// of [bounds], and a path casts without spread.
  void paintShadows(
    Canvas canvas,
    List<LiquidGlassShadow> shadows, {
    double visibility = 1,
  }) => paintLoneGlassShadows(
    canvas,
    this,
    castGlassShadows(shadows, bounds.size),
    visibility: visibility,
  );
}

/// The [LiquidGlassSilhouette] of a shape filling a rect
/// ([LiquidGlassSilhouette.shape]).
final class LiquidGlassShapeSilhouette extends LiquidGlassSilhouette {
  const LiquidGlassShapeSilhouette._(this.shape, this.bounds) : super._();

  /// The shape.
  final LiquidShape shape;

  /// The rect the shape fills.
  @override
  final Rect bounds;

  @override
  bool operator ==(Object other) =>
      other is LiquidGlassShapeSilhouette &&
      other.shape == shape &&
      other.bounds == bounds;

  @override
  int get hashCode => Object.hash(shape, bounds);

  @override
  String toString() => 'LiquidGlassSilhouette.shape($shape, $bounds)';
}

/// The [LiquidGlassSilhouette] a path fills ([LiquidGlassSilhouette.path]).
final class LiquidGlassPathSilhouette extends LiquidGlassSilhouette {
  LiquidGlassPathSilhouette._(this.path) : bounds = path.getBounds(), super._();

  /// The path.
  final Path path;

  /// The bounds of the path when the silhouette was made.
  @override
  final Rect bounds;

  /// Path silhouettes are equal when they are of the same path.
  @override
  bool operator ==(Object other) =>
      other is LiquidGlassPathSilhouette && identical(other.path, path);

  @override
  int get hashCode => identityHashCode(path);

  @override
  String toString() => 'LiquidGlassSilhouette.path($bounds)';
}

/// How the shadows of glass keep off the glass that casts them.
@internal
enum GlassShadowCut {
  /// Blurred outside the body alone ([BlurStyle.outer]), which is exact
  /// only for a lone whole body and shadows with neither offset nor spread.
  outer,

  /// Drawn in a layer of their own and cut by each body by its visibility.
  fraction,

  /// Clipped outside the whole bodies.
  clip,

  /// Drawn whole, for glass that covers them inside its bodies.
  none;

  /// The cut of [shadows] cast by one body ([lone]) or by several, while
  /// one of them is [fading] or none, drawn [under] glass that covers them
  /// or over it.
  static GlassShadowCut of({
    required bool lone,
    required Iterable<BoxShadow> shadows,
    required bool fading,
    bool under = false,
  }) {
    if (fading) return fraction;
    if (lone &&
        shadows.every(
          (shadow) => shadow.offset == Offset.zero && shadow.spreadRadius == 0,
        )) {
      return outer;
    }
    return under ? none : clip;
  }
}

/// A [LiquidGlassSilhouette] as glass casts its shadows by it.
@internal
extension CastSilhouette on LiquidGlassSilhouette {
  /// Fills [shadows] of the silhouette at [visibility].
  void cast(
    Canvas canvas,
    List<BoxShadow> shadows,
    double visibility, {
    required bool outer,
  }) {
    for (final shadow in shadows) {
      final paint = shadow
          .copyWith(
            color: shadow.color.withValues(alpha: shadow.color.a * visibility),
            blurRadius: shadow.blurRadius * visibility,
            blurStyle: outer ? BlurStyle.outer : BlurStyle.normal,
          )
          .toPaint();
      _fill(canvas, paint, shadow.offset, shadow.spreadRadius);
    }
  }

  /// The rect a shape's [cut] fills up to each side, so also its bounds.
  Rect get cutRect => bounds.deflate(_antialiasedEdgeOverlap);

  static const _antialiasedEdgeOverlap = .5;

  /// The edge the silhouette cuts its shadows at: a shape's at [cutRect], a
  /// path's its own.
  Path get cut => switch (this) {
    LiquidGlassShapeSilhouette(:final shape) => shape.getOuterPath(cutRect),
    LiquidGlassPathSilhouette(:final path) => path,
  };

  /// Whether [cut] added to a box under the even-odd rule leaves the box
  /// less the silhouette ([pathOutside]).
  bool get cutsUnderEvenOdd => switch (this) {
    LiquidGlassShapeSilhouette() => true,
    LiquidGlassPathSilhouette(:final path) =>
      path.fillType == PathFillType.evenOdd,
  };

  /// What lies in [bounds] and outside the silhouette, to clip a shadow to.
  Path outside(Rect bounds) =>
      pathOutside(cut, bounds, cutsUnderEvenOdd: cutsUnderEvenOdd);

  /// Takes [visibility] of what lies under the silhouette's [cut] out of
  /// what is drawn.
  void cutOut(Canvas canvas, double visibility) {
    final paint = Paint()
      ..color = Color.fromRGBO(0, 0, 0, visibility)
      ..blendMode = BlendMode.dstOut;
    switch (this) {
      case LiquidGlassShapeSilhouette(:final shape):
        shape.paintInterior(canvas, cutRect, paint);
      case LiquidGlassPathSilhouette(:final path):
        canvas.drawPath(path, paint);
    }
  }
}

/// What lies in [bounds] and outside [cut] (a silhouette's
/// [CastSilhouette.cut], placed by [transform]), to clip a shadow to.
@internal
Path pathOutside(
  Path cut,
  Rect bounds, {
  required bool cutsUnderEvenOdd,
  Float64List? transform,
}) {
  final whole = Path()..addRect(bounds);
  if (!cutsUnderEvenOdd) {
    return Path.combine(
      PathOperation.difference,
      whole,
      transform == null ? cut : cut.transform(transform),
    );
  }
  return whole
    ..fillType = PathFillType.evenOdd
    ..addPath(cut, Offset.zero, matrix4: transform);
}

double _blurSupport(double blurRadius) =>
    Shadow.convertRadiusToSigma(blurRadius) * 3;

Rect _shadowRect(Rect body, BoxShadow shadow, double visibility) => body
    .shift(shadow.offset)
    .inflate(
      math.max(
        shadow.spreadRadius + _blurSupport(shadow.blurRadius * visibility),
        0,
      ),
    );

/// [body] grown to hold what each of [shadows] of it paints at
/// [visibility].
@internal
Rect glassShadowBounds(
  Rect body,
  List<BoxShadow> shadows,
  double visibility,
) => shadows.fold(
  body,
  (bounds, shadow) =>
      bounds.expandToInclude(_shadowRect(body, shadow, visibility)),
);

/// Paints [shadows], cast at the body's size ([castGlassShadows]), of a
/// lone body of [silhouette] at [visibility], as
/// [LiquidGlassSilhouette.paintShadows] does.
@internal
void paintLoneGlassShadows(
  Canvas canvas,
  LiquidGlassSilhouette silhouette,
  List<BoxShadow> shadows, {
  required double visibility,
  Rect Function(Rect bounds)? layerBounds,
}) {
  final shown = drawnVisibility(visibility);
  if (shown <= 0 || shadows.isEmpty) return;
  final bounds = glassShadowBounds(silhouette.bounds, shadows, shown);
  switch (GlassShadowCut.of(lone: true, shadows: shadows, fading: shown < 1)) {
    case GlassShadowCut.outer:
      silhouette.cast(canvas, shadows, shown, outer: true);
    case GlassShadowCut.none:
      silhouette.cast(canvas, shadows, shown, outer: false);
    case GlassShadowCut.clip:
      canvas
        ..save()
        ..clipPath(silhouette.outside(bounds));
      silhouette.cast(canvas, shadows, shown, outer: false);
      canvas.restore();
    case GlassShadowCut.fraction:
      canvas.saveLayer(layerBounds?.call(bounds) ?? bounds, Paint());
      silhouette
        ..cast(canvas, shadows, shown, outer: false)
        ..cutOut(canvas, shown);
      canvas.restore();
  }
}
