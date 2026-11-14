import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/rendering/drawn_values.dart';
import 'package:liquid_glass_renderer/src/rendering/live_paint_size.dart';
import 'package:liquid_glass_renderer/src/rendering/snap_rect_to_pixels.dart';

/// Conservative pixel support of Flutter's Gaussian shadow mask.
///
/// [BoxShadow.blurRadius] is converted to sigma before rasterization. Reserving
/// only the radius clips the low-energy tail, especially when the shadow is
/// painted into a bounded saveLayer before translucent glass.
@internal
double glassShadowBlurSupport(double blurRadius) =>
    Shadow.convertRadiusToSigma(blurRadius) * 3;

/// The part of the plane [shadow] of a shape over [shape] can paint, with
/// its blur scaled by [visibility].
@internal
Rect glassShadowRect(Rect shape, BoxShadow shadow, double visibility) => shape
    .shift(shadow.offset)
    .inflate(
      math.max(
        shadow.spreadRadius +
            glassShadowBlurSupport(shadow.blurRadius * visibility),
        0,
      ),
    );

/// Paints a `GlassShadow`.
class RenderGlassShadow extends RenderProxyBox with LivePaintSize {
  /// Creates the render object of a `GlassShadow`.
  RenderGlassShadow({
    required this._shape,
    required this._shadows,
    required double visibility,
    required this._devicePixelRatio,
  }) : _visibility = visibility.clamp(0, 1);

  /// The shape whose shadows it paints.
  LiquidShape get shape => _shape;
  LiquidShape _shape;
  set shape(LiquidShape value) {
    if (_shape == value) return;
    _shape = value;
    markNeedsPaint();
  }

  /// The shadows it paints around [shape].
  List<BoxShadow> get shadows => _shadows;
  List<BoxShadow> _shadows;
  set shadows(List<BoxShadow> value) {
    if (_shadows == value) return;
    _shadows = value;
    markNeedsPaint();
  }

  /// The pixel ratio its shadow layer's bounds are kept on stable buckets for.
  double get devicePixelRatio => _devicePixelRatio;
  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  /// How far the shape has materialized, which fades the shadows.
  double get visibility => _visibility;
  double _visibility;
  set visibility(double value) {
    if (_visibility == value) return;
    _visibility = value.clamp(0, 1);
    markNeedsPaint();
  }

  @override
  Rect get paintBounds {
    var bounds = super.paintBounds;
    if (visibility <= 0 || shadows.isEmpty) return bounds;

    final shapeBounds = Offset.zero & paintSize;
    for (final shadow in LiquidGlassShadow.resolve(shadows, paintSize)) {
      // Report the same conservative Gaussian support used by paint()'s
      // saveLayer. Without this, Flutter culls the blurred pixels outside the
      // render box and different blur radii collapse to the same hard ring.
      bounds = bounds.expandToInclude(
        glassShadowRect(shapeBounds, shadow, visibility),
      );
    }
    return bounds;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final shadows = LiquidGlassShadow.resolve(this.shadows, paintSize);
    if (shadows.isNotEmpty) {
      final rect = offset & paintSize;
      final canvas = context.canvas;

      final needsCutout = shadows.any((s) => s.offset != Offset.zero);

      if (needsCutout) {
        var layerBounds = rect;
        for (final shadow in shadows) {
          layerBounds = layerBounds.expandToInclude(
            glassShadowRect(rect, shadow, visibility),
          );
        }
        // Bounds only, so growing them to pixel buckets changes no pixel,
        // and an animated shape keeps its render target size across frames.
        canvas.saveLayer(
          layerBounds.expandToPixelBuckets(devicePixelRatio),
          Paint(),
        );
      }

      for (final shadow in shadows) {
        final shadowRect = rect
            .shift(shadow.offset)
            .inflate(shadow.spreadRadius);
        final paint = shadow
            .copyWith(
              blurRadius: shadow.blurRadius * visibility,
              blurStyle: needsCutout ? BlurStyle.normal : BlurStyle.outer,
              color: shadow.color.withValues(
                alpha: shadow.color.a * visibility,
              ),
            )
            .toPaint();

        drawGlassShape(canvas, shape, shadowRect, paint);
      }

      if (needsCutout) {
        drawGlassShape(
          canvas,
          shape,
          rect.deflate(.5),
          Paint()..blendMode = BlendMode.dstOut,
        );
        canvas.restore();
      }
    }

    super.paint(context, offset);
  }
}

@internal
void drawGlassShape(Canvas canvas, LiquidShape shape, Rect rect, Paint paint) {
  final radius = Radius.circular(shape.cornerRadius);
  switch (shape) {
    case LiquidRoundedSuperellipse(:final radii):
      canvas.drawRSuperellipse(radii.toRSuperellipse(rect), paint);
    case LiquidOval():
      canvas.drawOval(rect, paint);
    case LiquidRoundedRectangle():
      canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), paint);
  }
}
