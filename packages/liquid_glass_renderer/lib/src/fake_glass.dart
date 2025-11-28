// ignore_for_file: require_trailing_commas

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:meta/meta.dart';

/// A widget that aims to provide a similar look to [LiquidGlass], but without
/// the expensive shader.
class FakeGlass extends StatelessWidget {
  /// Creates a new [FakeGlass] widget with the given [child], [shape], and
  /// [settings].
  const FakeGlass({
    required this.shape,
    required this.child,
    LiquidGlassSettings this.settings = const LiquidGlassSettings(),
    super.key,
  });

  /// Creates a new [FakeGlass] widget that takes settings from the nearest
  /// ancestor [LiquidGlassLayer].
  const FakeGlass.inLayer({
    required this.shape,
    required this.child,
    super.key,
  }) : settings = null;

  /// {@macro liquid_glass_renderer.LiquidGlass.shape}
  final LiquidShape shape;

  /// The settings for the glass effect.
  ///
  /// Some properties will not have any effect, such as `thickness` and
  /// `refractiveIndex`, since there is no actual refraction happening.
  final LiquidGlassSettings? settings;

  /// The child widget that will be displayed inside the glass.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final settings = this.settings ?? LiquidGlassSettings.of(context);

    // If we are in a layer, we accept that layer's backdrop key.
    final backdropKey =
        this.settings == null ? BackdropGroup.of(context)?.backdropKey : null;
    return ClipPath(
      clipper: ShapeBorderClipper(shape: shape),
      child: RawFakeGlass(
        shape: shape,
        settings: settings,
        backdropKey: backdropKey,
        child: Opacity(
          opacity: settings.visibility.clamp(0, 1),
          child: GlassGlowLayer(
            child: child,
          ),
        ),
      ),
    );
  }
}

@internal
class RawFakeGlass extends SingleChildRenderObjectWidget {
  const RawFakeGlass({
    required this.shape,
    required super.child,
    this.backdropKey,
    this.settings = const LiquidGlassSettings(),
    super.key,
  });

  final LiquidShape shape;

  final LiquidGlassSettings settings;

  final BackdropKey? backdropKey;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderFakeGlass(
      shape: shape,
      settings: settings,
      backdropKey: backdropKey,
    );
  }

  @override
  void updateRenderObject(
      BuildContext context, covariant RenderObject renderObject) {
    if (renderObject is _RenderFakeGlass) {
      renderObject
        ..shape = shape
        ..settings = settings
        .._backdropKey = backdropKey;
    }
  }
}

class _RenderFakeGlass extends RenderProxyBox {
  _RenderFakeGlass({
    required LiquidShape shape,
    required LiquidGlassSettings settings,
    required BackdropKey? backdropKey,
  })  : _shape = shape,
        _settings = settings,
        _backdropKey = backdropKey;

  LiquidShape _shape;
  LiquidShape get shape => _shape;
  set shape(LiquidShape value) {
    if (_shape == value) return;
    _shape = value;
    markNeedsPaint();
  }

  LiquidGlassSettings _settings;
  LiquidGlassSettings get settings => _settings;
  set settings(LiquidGlassSettings value) {
    if (_settings == value) return;
    _settings = value;
    markNeedsPaint();
  }

  BackdropKey? _backdropKey;
  BackdropKey? get backdropKey => _backdropKey;
  set backdropKey(BackdropKey? value) {
    if (_backdropKey == value) return;
    _backdropKey = value;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  BackdropFilterLayer? get layer => super.layer as BackdropFilterLayer?;

  @override
  void paint(PaintingContext context, Offset offset) {
    // Create saturation filter if needed
    final ui.ImageFilter? saturationFilter = settings.effectiveSaturation != 1.0
        ? ui.ColorFilter.matrix(
            _createSaturationMatrix(settings.effectiveSaturation),
          )
        : null;

    final blurFilter = ui.ImageFilter.blur(
      sigmaX: settings.effectiveBlur,
      sigmaY: settings.effectiveBlur,
      tileMode: TileMode.mirror,
    );

    // Combine blur and saturation filters
    final combinedFilter = saturationFilter != null
        ? ui.ImageFilter.compose(
            inner: saturationFilter,
            outer: blurFilter,
          )
        : blurFilter;

    final layer = (this.layer ??= BackdropFilterLayer())
      ..filter = combinedFilter
      ..blendMode = BlendMode.srcATop
      ..backdropKey = backdropKey;

    context.pushLayer(
      layer,
      (context, offset) {
        // If we are on Skia, we need to avoid the raster cache.
        if (!ui.ImageFilter.isShaderFilterSupported) {
          context.setWillChangeHint();
        }
        final path = shape.getOuterPath(offset & size);
        _paintColor(context.canvas, path);
        _paintSpecular(context.canvas, path, offset & size);
        super.paint(context, offset);
      },
      offset,
    );
  }

  /// Creates a saturation adjustment matrix
  /// saturation = 0 -> grayscale (using Rec. 709 luma coefficients)
  /// saturation = 1 -> original color (no change)
  /// saturation > 1 -> over-saturated
  List<double> _createSaturationMatrix(double saturation) {
    // Rec. 709 luma coefficients for RGB to grayscale conversion
    const lumR = 0.299;
    const lumG = 0.587;
    const lumB = 0.114;

    // Saturation matrix that interpolates between grayscale and original color
    // Based on: result = luminance + (color - luminance) * saturation
    final s = saturation;
    final invSat = 1.0 - s;

    return [
      lumR * invSat + s, lumG * invSat, lumB * invSat, 0, 0, // R
      lumR * invSat, lumG * invSat + s, lumB * invSat, 0, 0, // G
      lumR * invSat, lumG * invSat, lumB * invSat + s, 0, 0, // B
      0, 0, 0, 1, 0, // A
    ];
  }

  void _paintColor(Canvas canvas, Path path) {
    final color = settings.effectiveGlassColor;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, paint);
  }

  void _paintSpecular(Canvas canvas, Path path, Rect bounds) {
    final lightIntensity = settings.effectiveLightIntensity.clamp(0.0, 1.0);

    final thicknessFactor = (settings.effectiveThickness / 5).clamp(0.0, 1.0);
    final alpha = Curves.easeOut.transform(lightIntensity);
    final color = Colors.white.withValues(
      alpha: alpha * thicknessFactor,
    );

    final thickness = settings.effectiveThickness / 40;

    void drawHighlight(
      Canvas canvas,
      Path path,
      Rect bounds,
      Paint paint,
      // ignore: avoid_positional_boolean_parameters
      bool invert,
    ) {
      canvas.saveLayer(bounds, paint);
      {
        // Calculate gradient points relative to the bounds to ensure coverage
        // regardless of aspect ratio.
        final center = bounds.center;
        final diagonal = bounds.size.longestSide; // Safe over-estimate
        final lightDir = Offset(
          math.cos(settings.lightAngle),
          math.sin(settings.lightAngle),
        );
        final offset = invert ? -lightDir : lightDir;

        final start = center - offset * (diagonal / 2);

        final shader = ui.Gradient.linear(
          start,
          center,
          [
            color,
            color.withValues(alpha: .2), // Fade out
          ],
        );

        canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xFFFFFFFF)
            ..shader = shader,
        );

        final eraser = Paint()
          ..blendMode = BlendMode.dstOut
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1);
        canvas
          ..save()
          ..translate(
            offset.dx * thickness,
            offset.dy * thickness,
          )
          ..drawPath(path, eraser)
          ..restore();
      }
      canvas.restore();
    }

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ui.lerpDouble(1, 2, lightIntensity)!
      ..color = color.withValues(alpha: color.a * 0.3)
      ..blendMode = BlendMode.hardLight;

    final overlay = Paint()
      ..color = color.withValues(alpha: color.a * 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (settings.effectiveThickness / 10)
      ..blendMode = BlendMode.overlay;

    drawHighlight(canvas, path, bounds, paint, false);
    drawHighlight(canvas, path, bounds, overlay, false);

    // Ambient highlight (inverted)
    drawHighlight(canvas, path, bounds, paint, true);
    drawHighlight(canvas, path, bounds, overlay, true);
  }
}
