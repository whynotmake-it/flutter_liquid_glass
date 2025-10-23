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
    return ClipPath(
      clipper: ShapeBorderClipper(shape: shape),
      child: RawFakeGlass(
        shape: shape,
        settings: settings ?? LiquidGlassSettings.of(context),
        child: GlassGlowLayer(
          child: child,
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
    this.settings = const LiquidGlassSettings(),
    super.key,
  });

  final LiquidShape shape;

  final LiquidGlassSettings settings;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderFakeGlass(
      shape: shape,
      settings: settings,
    );
  }

  @override
  void updateRenderObject(
      BuildContext context, covariant RenderObject renderObject) {
    if (renderObject is _RenderFakeGlass) {
      renderObject
        ..shape = shape
        ..settings = settings;
    }
  }
}

class _RenderFakeGlass extends RenderProxyBox {
  _RenderFakeGlass({
    required LiquidShape shape,
    required LiquidGlassSettings settings,
  })  : _shape = shape,
        _settings = settings;

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

  @override
  bool get alwaysNeedsCompositing => child != null;

  @override
  BackdropFilterLayer? get layer => super.layer as BackdropFilterLayer?;

  @override
  void paint(PaintingContext context, Offset offset) {
    // Create saturation filter if needed
    final ui.ImageFilter? saturationFilter = settings.saturation != 1.0
        ? ui.ColorFilter.matrix(_createSaturationMatrix(settings.saturation))
        : null;

    final blurFilter = ui.ImageFilter.blur(
      sigmaX: settings.blur,
      sigmaY: settings.blur,
      tileMode: TileMode.mirror,
    );

    // Combine blur and saturation filters
    final combinedFilter = saturationFilter != null
        ? ui.ImageFilter.compose(
            inner: saturationFilter,
            outer: blurFilter,
          )
        : blurFilter;

    final blurLayer = (layer ??= BackdropFilterLayer())
      ..filter = combinedFilter;

    context.pushLayer(
      blurLayer,
      (context, offset) {
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
    final luminance = settings.glassColor.computeLuminance();

    final blendMode = luminance < 0.5 ? BlendMode.multiply : BlendMode.screen;

    final paint = Paint()
      ..color =
          settings.glassColor.withValues(alpha: settings.glassColor.a * .5)
      ..blendMode = blendMode
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, paint);

    // Paint a blurred stroke to simulate the glass edge
    paint
      ..maskFilter = MaskFilter.blur(
          BlurStyle.normal, (settings.thickness * 2).clamp(2, 100))
      ..style = PaintingStyle.stroke
      ..color = settings.glassColor
      ..strokeWidth = settings.thickness;

    canvas.drawPath(path, paint);
  }

  /// Paints an approximation for specular highlights by using a linear
  /// gradient that is aligned with the light angle and painting a strokw with
  /// that gradient.
  void _paintSpecular(Canvas canvas, Path path, Rect bounds) {
    // Expand bounds to a square to make sure the gradient angle will match the
    // light angle correctly. A squashed gradient would change the angle.
    final squareBounds = Rect.fromCircle(
      center: bounds.center,
      radius: bounds.size.longestSide / 2,
    );

    final thicknessFactor = (settings.thickness / 5).clamp(0.0, 1.0);

    final color = Colors.white.withValues(
      alpha: settings.lightIntensity.clamp(0, 1) * thicknessFactor,
    );
    final rad = settings.lightAngle;

    final x = math.cos(rad);
    final y = math.sin(rad);

    // How far the light covers the glass, used to adjust the gradient stops
    final lightCoverage = ui.lerpDouble(
      .3,
      .5,
      settings.lightIntensity.clamp(0, 1),
    )!;

    // How perpendicular we are to the shortest side of the box, 1 means the
    // light is hitting the shortest side directly, 0 means it's hitting the
    // longest side directly.
    final alignmentWithShortestSide = (size.aspectRatio < 1 ? y : x).abs();

    // How far we are from a square aspect ratio, used to adjust the gradient
    final aspectAdjustment = 1 - 1 / size.aspectRatio;

    // We scale the gradient when we are at a non-square aspect ratio, and the
    // light is aligned with the longest side.
    final gradientScale = aspectAdjustment * (1 - alignmentWithShortestSide);

    // How far the outer stops are inset
    final inset = ui.lerpDouble(0, .5, gradientScale.clamp(0, 1))!;

    // How far the second stops are inset
    final secondInset =
        ui.lerpDouble(lightCoverage, .5, gradientScale.clamp(0, 1))!;

    final shader = LinearGradient(
      colors: [
        color,
        color.withValues(alpha: settings.ambientStrength.clamp(0, 1)),
        color.withValues(alpha: settings.ambientStrength.clamp(0, 1)),
        color,
      ],
      stops: [
        inset,
        secondInset,
        1 - secondInset,
        1 - inset,
      ],
      begin: Alignment(x, y),
      end: Alignment(-x, -y),
    ).createShader(squareBounds);

    final paint = Paint()
      ..shader = shader
      ..blendMode = BlendMode.softLight
      ..style = PaintingStyle.stroke
      ..maskFilter = MaskFilter.blur(
          BlurStyle.normal, (settings.thickness / 20).clamp(1, 50))
      ..strokeWidth = 2 * (settings.thickness / 20) * thicknessFactor;

    canvas.drawPath(path, paint);

    paint
      ..strokeWidth =
          ui.lerpDouble(.5, 1.5, settings.lightIntensity.clamp(0, 1))!
      ..color = color.withValues(alpha: color.a * 0.3)
      ..maskFilter = null
      ..blendMode = BlendMode.hardLight;
    canvas.drawPath(path, paint);
  }
}
