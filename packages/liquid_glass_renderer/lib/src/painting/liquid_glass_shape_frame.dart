import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_appearance.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_shape.dart';

/// One frame of a live `LiquidGlass`: its geometry, material and shadows.
///
/// [rect], [scaleX] and [scaleY] apply at paint: the glass moves, resizes
/// and scales without a layout, so a frame written after layout still draws
/// in that frame. The `LiquidGlass.child` keeps the size it was laid out at,
/// moves and scales with the glass and is clipped to its shape.
@immutable
class LiquidGlassShapeFrame {
  /// Describes one frame of a shape.
  const LiquidGlassShapeFrame({
    required this.shape,
    this.appearance,
    this.shadows = const [],
    this.rect,
    this.scaleX = 1,
    this.scaleY = 1,
  });

  /// Where the shape is drawn in the box the `LiquidGlass` was laid out
  /// in, or null to fill that box.
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
  final List<BoxShadow> shadows;
}
