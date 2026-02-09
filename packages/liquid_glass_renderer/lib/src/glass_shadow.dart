import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:meta/meta.dart';

/// Paints [BoxShadow]s for a [LiquidShape] using canvas primitives
/// (drawRRect, drawCircle, drawRSuperellipse, etc.) instead of drawPath.
///
/// This avoids the cost of rasterizing an arbitrary [Path] with a blur
/// [MaskFilter], which is significantly slower than the dedicated GPU-
/// accelerated primitives that Impeller/Skia provide for simple shapes.
@internal
class GlassShadow extends SingleChildRenderObjectWidget {
  /// Creates a new [GlassShadow] widget with the given [shape], [shadows], and
  /// optional [child].
  const GlassShadow({
    required this.shape,
    required this.shadows,
    required this.settings,
    super.child,
    super.key,
  });

  /// The shape to paint shadows for.
  final LiquidShape shape;

  final LiquidGlassSettings settings;

  /// The list of shadows to paint.
  final List<BoxShadow> shadows;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderGlassShadow(
      shape: shape,
      shadows: shadows,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    // ignore: library_private_types_in_public_api
    _RenderGlassShadow renderObject,
  ) {
    renderObject
      ..shape = shape
      ..shadows = shadows;
  }
}

class _RenderGlassShadow extends RenderProxyBox {
  _RenderGlassShadow({
    required LiquidShape shape,
    required List<BoxShadow> shadows,
  })  : _shape = shape,
        _shadows = shadows;

  LiquidShape get shape => _shape;
  LiquidShape _shape;
  set shape(LiquidShape value) {
    if (_shape == value) return;
    _shape = value;
    markNeedsPaint();
  }

  List<BoxShadow> get shadows => _shadows;
  List<BoxShadow> _shadows;
  set shadows(List<BoxShadow> value) {
    if (_shadows == value) return;
    _shadows = value;
    markNeedsPaint();
  }

  double get visibility => _visibility;
  double _visibility = 1;
  set visibility(double value) {
    if (_visibility == value) return;
    _visibility = value.clamp(0, 1);
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (shadows.isNotEmpty) {
      final rect = offset & size;
      final canvas = context.canvas;

      for (final shadow in shadows) {
        final shadowRect =
            rect.shift(shadow.offset).inflate(shadow.spreadRadius);
        final paint = shadow
            .copyWith(
              blurRadius: shadow.blurRadius * visibility,
              color: shadow.color.withValues(
                alpha: shadow.color.a * visibility,
              ),
            )
            .toPaint();

        switch (shape) {
          case LiquidRoundedSuperellipse(:final borderRadius):
            canvas.drawRRect(
              RRect.fromRectAndRadius(rect, Radius.circular(borderRadius)),
              paint,
            );

          case LiquidOval():
            canvas.drawOval(shadowRect, paint);
          case LiquidRoundedRectangle(:final borderRadius):
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                shadowRect,
                Radius.circular(borderRadius),
              ),
              paint,
            );
        }
      }
    }

    super.paint(context, offset);
  }
}
