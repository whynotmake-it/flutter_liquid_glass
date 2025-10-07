import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

class FakeGlass extends SingleChildRenderObjectWidget {
  const FakeGlass({
    required this.shape,
    required this.child,
    this.settings = const LiquidGlassSettings(),
    super.key,
  });

  final LiquidShape shape;

  final Widget child;

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

class _RenderFakeGlass extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
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
  void performLayout() {
    if (child != null) {
      child!.layout(constraints, parentUsesSize: true);
      size = child!.size;
    } else {
      size = constraints.smallest;
    }
  }

  final LayerHandle<BackdropFilterLayer> _blurHandle =
      LayerHandle<BackdropFilterLayer>();

  final LayerHandle<ClipPathLayer> _clipHandle = LayerHandle<ClipPathLayer>();

  @override
  void detach() {
    _blurHandle.layer = null;
    _clipHandle.layer = null;
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final clipPath = shape.getOuterPath(offset & size);

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

    final blurLayer = (_blurHandle.layer ??= BackdropFilterLayer())
      ..filter = combinedFilter;

    final clipLayer = (_clipHandle.layer ??= ClipPathLayer())
      ..clipPath = clipPath;

    context.pushLayer(
      clipLayer,
      (context, offset) {
        context.pushLayer(
          blurLayer,
          (context, offset) {
            if (child != null) {
              _paintColor(context.canvas, clipPath);
              context.paintChild(child!, offset);
              _paintSpecular(context.canvas, clipPath);
            }
          },
          offset,
        );
      },
      offset,
    );

    super.paint(context, offset);
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
