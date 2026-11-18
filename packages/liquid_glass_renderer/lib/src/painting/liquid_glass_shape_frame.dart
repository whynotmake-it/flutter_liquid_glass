import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_appearance.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_body.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_glow.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_shadow.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_shape.dart';

/// One frame of a live `LiquidGlass`: its geometry, appearance, shadows and
/// glow.
///
/// [rect], [scaleX] and [scaleY] apply at paint: the glass moves, resizes
/// and scales without a layout, so a frame written after layout still draws
/// in that frame. The `LiquidGlass.child` keeps the size it was laid out at,
/// moves and scales with the glass and is clipped to its shape.
@immutable
final class LiquidGlassShapeFrame {
  /// Describes one frame of a shape.
  const LiquidGlassShapeFrame({
    required this.shape,
    this.appearance,
    this.shadows = const [],
    this.rect,
    this.scaleX = 1,
    this.scaleY = 1,
    this.glow,
  });

  /// Where the shape is drawn in the box the `LiquidGlass` was laid out
  /// in, or null to fill that box. The child keeps the box's size and is
  /// drawn centered on this rect.
  final Rect? rect;

  /// The horizontal scale of the shape and its child about the center of
  /// [rect].
  final double scaleX;

  /// The vertical scale of the shape and its child about the center of
  /// [rect].
  final double scaleY;

  /// See `LiquidGlass.shape`.
  final LiquidShape shape;

  /// See `LiquidGlass.appearance`.
  final LiquidGlassAppearance? appearance;

  /// See `LiquidGlass.shadows`.
  final List<LiquidGlassShadow> shadows;

  /// The glow a finger raises on the glass, or null for none.
  ///
  /// A new glow changes only what the layer's final pass is given: no
  /// geometry is drawn again, and a layer whose retained filter reads the
  /// backdrop does not repaint.
  final LiquidGlassGlow? glow;

  /// Where this frame draws the body in a box of [boxSize].
  LiquidGlassBody bodyIn(Size boxSize) =>
      LiquidGlassBody(boxSize, rect: rect, scaleX: scaleX, scaleY: scaleY);

  @override
  bool operator ==(Object other) =>
      other is LiquidGlassShapeFrame &&
      other.shape == shape &&
      other.appearance == appearance &&
      listEquals(other.shadows, shadows) &&
      other.rect == rect &&
      other.scaleX == scaleX &&
      other.scaleY == scaleY &&
      other.glow == glow;

  @override
  int get hashCode => Object.hash(
    shape,
    appearance,
    Object.hashAll(shadows),
    rect,
    scaleX,
    scaleY,
    glow,
  );

  @override
  String toString() =>
      'LiquidGlassShapeFrame($shape'
      '${appearance == null ? '' : ', appearance: $appearance'}'
      '${shadows.isEmpty ? '' : ', shadows: $shadows'}'
      '${rect == null ? '' : ', rect: $rect'}'
      '${scaleX == 1 && scaleY == 1 ? '' : ', scale: $scaleX x $scaleY'}'
      '${glow == null ? '' : ', glow: $glow'})';
}
