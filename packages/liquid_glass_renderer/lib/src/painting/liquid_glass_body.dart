import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4;

/// Where glass draws its body in the box it was laid out in: [rect] scaled
/// by [scaleX] and [scaleY] about its center.
///
/// The glass and what is drawn on it are drawn in the body's own
/// coordinates under [toBox], so corners and glow scale with the body, as a
/// layer's transform scales a view in UIKit. The child keeps the box's size
/// and is drawn centered on the body.
///
/// `LiquidGlassShapeFrame.bodyIn` gives the body a live `LiquidGlass` draws;
/// a widget library that draws over glass, or draws a body without it, lays
/// it out the same way.
@immutable
base class LiquidGlassBody {
  /// The body of [rect], or of the whole box without one, scaled by
  /// [scaleX] and [scaleY] about its center, in a box of [boxSize].
  const LiquidGlassBody(
    this.boxSize, {
    this._rect,
    this.scaleX = 1,
    this.scaleY = 1,
  });

  /// The size of the box the glass was laid out in.
  final Size boxSize;

  /// The body before its scale, in the box's coordinates.
  Rect get rect => _rect ?? Offset.zero & boxSize;
  final Rect? _rect;

  /// The body's horizontal scale about its center.
  final double scaleX;

  /// The body's vertical scale about its center.
  final double scaleY;

  /// The body's size in its own coordinates.
  Size get size => rect.size;

  /// The body in its own coordinates.
  Rect get bounds => Offset.zero & size;

  /// Where the body is seen in the box: [rect] scaled about its center.
  Rect get drawnRect => scaleX == 1 && scaleY == 1
      ? rect
      : Rect.fromCenter(
          center: rect.center,
          width: rect.width * scaleX,
          height: rect.height * scaleY,
        );

  /// From the body's coordinates to the box's, or null where they are the
  /// same, so that a body drawn in place pushes no transform.
  Matrix4? get toBox {
    if (rect.topLeft == Offset.zero && scaleX == 1 && scaleY == 1) {
      return null;
    }
    final center = rect.center;
    return Matrix4.translationValues(center.dx, center.dy, 0)
      ..scaleByDouble(scaleX, scaleY, 1, 1)
      ..translateByDouble(
        rect.left - center.dx,
        rect.top - center.dy,
        0,
        1,
      );
  }

  /// Where the child, laid out at the box's size, lies in the body's
  /// coordinates: centered on the body.
  Offset get childOffset => Offset(
    (rect.width - boxSize.width) / 2,
    (rect.height - boxSize.height) / 2,
  );

  /// From the coordinates the child was laid out in to the box's, or null
  /// where the child is drawn in place.
  Matrix4? get childToBox {
    final toBox = this.toBox;
    final shift = childOffset;
    if (toBox == null) {
      return shift == Offset.zero
          ? null
          : Matrix4.translationValues(shift.dx, shift.dy, 0);
    }
    return toBox..translateByDouble(shift.dx, shift.dy, 0, 1);
  }

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is LiquidGlassBody &&
      other.boxSize == boxSize &&
      other.rect == rect &&
      other.scaleX == scaleX &&
      other.scaleY == scaleY;

  @override
  int get hashCode => Object.hash(boxSize, rect, scaleX, scaleY);

  @override
  String toString() =>
      '${objectRuntimeType(this, 'LiquidGlassBody')}($rect in $boxSize'
      '${scaleX == 1 && scaleY == 1 ? '' : ', scale: $scaleX x $scaleY'})';
}
