// ignore_for_file: require_trailing_commas

import 'dart:math' as math;
import 'dart:ui';

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
    this.settings = const LiquidGlassSettings(),
    super.key,
  });

  /// {@macro liquid_glass_renderer.LiquidGlass.shape}
  final LiquidShape shape;

  /// The settings for the glass effect.
  ///
  /// Some properties will not have any effect, such as `thickness` and
  /// `refractiveIndex`, since there is no actual refraction happening.
  final LiquidGlassSettings settings;

  /// The child widget that will be displayed inside the glass.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: ShapeBorderClipper(shape: shape),
      child: RawFakeGlass(
        shape: shape,
        settings: settings,
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
    final ImageFilter? saturationFilter = settings.saturation != 1.0
        ? ColorFilter.matrix(_createSaturationMatrix(settings.saturation))
        : null;

    final blurFilter = ImageFilter.blur(
      sigmaX: settings.blur,
      sigmaY: settings.blur,
    );

    // Combine blur and saturation filters
    final combinedFilter = saturationFilter != null
        ? ImageFilter.compose(
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
        _paintSpecular(context.canvas, path);
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
      ..color = settings.glassColor
      ..blendMode = blendMode
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, paint);
  }

  void _paintSpecular(Canvas canvas, Path path) {
    // Compute alignments from light angle
    final radians = settings.lightAngle;

    final x = -1 * math.cos(radians);
    final y = -1 * math.sin(radians);

    final color = Colors.white.withValues(
      alpha: settings.lightIntensity.clamp(0, 1),
    );
    final shader = LinearGradient(
      colors: [
        color,
        color.withValues(alpha: settings.ambientStrength.clamp(0, 1)),
        color.withValues(alpha: settings.ambientStrength.clamp(0, 1)),
        color,
      ],
      begin: Alignment(x, y),
      end: Alignment(-x, -y),
    ).createShader(path.getBounds());

    // Paint sharp outline

    final paint = Paint()
      ..shader = shader
      ..blendMode = BlendMode.lighten
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, .7);
    canvas.drawPath(path, paint);

    // Paint a second, slightly blurred outline
    paint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawPath(path, paint);
  }
}
