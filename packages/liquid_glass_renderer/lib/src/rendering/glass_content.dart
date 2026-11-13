import 'package:flutter/rendering.dart';

/// The content of one glass shape: the child of a `LiquidGlass` or a
/// `FakeGlass`, faded with the shape's visibility, over the light a touch
/// raises on it.
///
/// Every glass has one, so a glass without a touch light costs nothing for
/// it: the light is three fields this render object paints only while its
/// color is visible. `GlassGlow` finds the nearest one above it and drives
/// [glowOffset], [glowRadius] and [glowColor] as a finger moves.
///
/// The light is a radial gradient added to what lies under the child
/// ([BlendMode.plus]), inside the shape's clip and under its fade.
class RenderLiquidGlassContent extends RenderOpacity {
  /// Creates the content of a glass shown at [opacity].
  RenderLiquidGlassContent({super.opacity, super.child});

  /// The radius of the light, relative to the shorter side of this box; 0
  /// draws none.
  double get glowRadius => _glowRadius;
  double _glowRadius = 0;
  set glowRadius(double value) {
    if (_glowRadius == value) return;
    _glowRadius = value;
    markNeedsPaint();
  }

  /// The color at the center of the light, fading to transparent at its
  /// rim; a transparent color draws none.
  Color get glowColor => _glowColor;
  Color _glowColor = const Color(0x00000000);
  set glowColor(Color value) {
    if (_glowColor == value) return;
    _glowColor = value;
    markNeedsPaint();
  }

  /// The center of the light, in this box's coordinates.
  Offset get glowOffset => _glowOffset;
  Offset _glowOffset = Offset.zero;
  set glowOffset(Offset value) {
    if (_glowOffset == value) return;
    _glowOffset = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child case final child?
        when paintsChild(child) && _glowColor.a > 0 && _glowRadius > 0) {
      final center = offset + _glowOffset;
      final radius = _glowRadius * size.shortestSide;
      final gradient = RadialGradient(
        colors: [_glowColor, _glowColor.withValues(alpha: 0)],
      );
      context.canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = gradient.createShader(
            Rect.fromCircle(center: center, radius: radius),
          )
          ..blendMode = BlendMode.plus,
      );
    }
    super.paint(context, offset);
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DoubleProperty('glowRadius', glowRadius))
      ..add(ColorProperty('glowColor', glowColor))
      ..add(DiagnosticsProperty<Offset>('glowOffset', glowOffset));
  }
}
