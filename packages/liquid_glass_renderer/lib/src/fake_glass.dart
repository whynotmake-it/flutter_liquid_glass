// ignore_for_file: require_trailing_commas

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/glass_shadow.dart';
import 'package:liquid_glass_renderer/src/internal/optimized_clip.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_render_scope.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';
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
    this.shadows = const [],
    this.backdropKey,
    this.useBackdropGroup = false,
    super.key,
  });

  /// Creates a new [FakeGlass] widget that takes settings from the nearest
  /// ancestor [LiquidGlassLayer].
  const FakeGlass.inLayer({
    required this.shape,
    required this.child,
    this.shadows = const [],
    super.key,
  }) : settings = null,
       backdropKey = null,
       useBackdropGroup = false;

  /// {@macro liquid_glass_renderer.LiquidGlass.shape}
  final LiquidShape shape;

  /// The settings for the glass effect.
  ///
  /// This path approximates lighting and blur without refraction.
  /// [LiquidGlassSettings.refractiveIndex] and
  /// [LiquidGlassSettings.chromaticAberration] therefore have no effect;
  /// thickness only controls the width of the approximate inner light bleed.
  final LiquidGlassSettings? settings;

  /// The list of shadows to paint around the glass shape.
  ///
  /// Only outer-equivalent shadows are supported; [BoxShadow.blurStyle] is
  /// ignored. When any shadow has a non-zero [BoxShadow.offset], the glass
  /// shape is cut out of the composed shadow stack so the shadow does not
  /// bleed through the translucent glass body.
  final List<BoxShadow> shadows;

  /// An explicit key used to share backdrop capture work with other effects.
  final BackdropKey? backdropKey;

  /// Whether to use the nearest ancestor [BackdropGroup].
  ///
  /// [backdropKey] takes precedence. This is ignored by [FakeGlass.inLayer],
  /// which inherits the containing [LiquidGlassLayer]'s backdrop policy.
  final bool useBackdropGroup;

  /// The child widget that will be displayed inside the glass.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final settings = this.settings ?? LiquidGlassSettings.of(context);

    final backdropKey = this.settings == null
        ? LiquidGlassRenderScope.of(context).backdropKey
        : this.backdropKey ??
              (useBackdropGroup
                  ? BackdropGroup.of(context)?.backdropKey
                  : null);
    Widget clipped = OptimizedClip(
      shape: shape,
      child: ShaderBuilder(
        assetKey: ShaderKeys.fakeGlassColor,
        (context, shader, child) => RawFakeGlass(
          shape: shape,
          settings: settings,
          backdropKey: backdropKey,
          colorShader: shader,
          child: child,
        ),
        child: _maybeFade(
          settings.visibility,
          GlassGlowLayer(
            child: child,
          ),
        ),
      ),
    );
    if (shadows.isEmpty) {
      return clipped;
    }
    return GlassShadow(
      shape: shape,
      shadows: shadows,
      settings: settings,
      child: clipped,
    );
  }

  static Widget _maybeFade(double visibility, Widget child) {
    final opacity = visibility.clamp(0.0, 1.0);
    if (opacity >= 1) return child;
    return Opacity(opacity: opacity, child: child);
  }
}

@internal
class RawFakeGlass extends SingleChildRenderObjectWidget {
  const RawFakeGlass({
    required this.shape,
    required super.child,
    required this.colorShader,
    this.backdropKey,
    this.settings = const LiquidGlassSettings(),
    super.key,
  });

  final LiquidShape shape;

  final LiquidGlassSettings settings;

  final BackdropKey? backdropKey;

  final ui.FragmentShader colorShader;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderFakeGlass(
      shape: shape,
      settings: settings,
      backdropKey: backdropKey,
      colorShader: colorShader,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    if (renderObject is _RenderFakeGlass) {
      renderObject
        ..shape = shape
        ..settings = settings
        ..backdropKey = backdropKey
        ..colorShader = colorShader;
    }
  }
}

class _RenderFakeGlass extends RenderProxyBox {
  _RenderFakeGlass({
    required this._shape,
    required this._settings,
    required this._backdropKey,
    required this._colorShader,
  });

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

  ui.FragmentShader _colorShader;
  ui.FragmentShader get colorShader => _colorShader;
  set colorShader(ui.FragmentShader value) {
    if (_colorShader == value) return;
    _colorShader = value;
    markNeedsPaint();
  }

  bool get _hasBlur => settings.effectiveBlur != 0;

  bool get _hasSaturationChange => settings.effectiveSaturation != 1;

  bool get _hasBackdropEffect => _hasBlur || _hasSaturationChange;

  @override
  bool get alwaysNeedsCompositing => _hasBackdropEffect;

  @override
  BackdropFilterLayer? get layer => super.layer as BackdropFilterLayer?;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_hasBackdropEffect) {
      // No blur or saturation change — skip the BackdropFilterLayer entirely
      // and just paint the specular highlights and child directly.
      this.layer = null;
      final path = shape.getOuterPath(offset & size);
      _paintColor(context.canvas, path);
      _paintSpecular(context.canvas, path, offset & size);
      super.paint(context, offset);
      return;
    }

    final blurFilter = _hasBlur
        ? ui.ImageFilter.blur(
            sigmaX: settings.effectiveBlur,
            sigmaY: settings.effectiveBlur,
            tileMode: TileMode.mirror,
          )
        : null;
    final colorFilter = _getColorFilter(settings);
    final backdropFilter = switch ((blurFilter, colorFilter)) {
      (final blur?, final color?) => ui.ImageFilter.compose(
        inner: blur,
        outer: color,
      ),
      (final blur?, null) => blur,
      (null, final color?) => color,
      (null, null) => throw StateError('No backdrop effect to paint.'),
    };

    final layer = (this.layer ??= BackdropFilterLayer())
      ..filter = backdropFilter
      ..blendMode = BlendMode.srcATop
      ..backdropKey = backdropKey;

    context.pushLayer(
      layer,
      (context, offset) {
        // If we are on Skia, we need to avoid the raster cache.
        if (!ui.ImageFilter.isShaderFilterSupported) {
          context.setWillChangeHint();
        }

        _paintInnerContent(
          context,
          offset,
          paintColor:
              colorFilter == null || !ui.ImageFilter.isShaderFilterSupported,
        );
      },
      offset,
    );
  }

  /// Paints content inside the single composed backdrop-filter pass.
  void _paintInnerContent(
    PaintingContext context,
    Offset offset, {
    required bool paintColor,
  }) {
    final path = shape.getOuterPath(offset & size);
    if (paintColor) {
      _paintColor(context.canvas, path);
    }
    _paintSpecular(context.canvas, path, offset & size);
    super.paint(context, offset);
  }

  ui.ImageFilter? _getColorFilter(LiquidGlassSettings settings) {
    final glassColor = settings.effectiveGlassColor;
    if (settings.effectiveSaturation == 1 && glassColor.a == 0) {
      return null;
    }
    if (ui.ImageFilter.isShaderFilterSupported) {
      // Apply saturation and tint in the same filter.
      _colorShader.setFloatUniforms((value) {
        // uSize (vec2)
        value
          ..setSize(size)
          ..setColor(glassColor)
          ..setFloat(settings.effectiveSaturation);
      });
      return ui.ImageFilter.shader(_colorShader);
    }
    // Skia fallback: use a color matrix for saturation only.
    return ui.ColorFilter.matrix(
      _createSaturationMatrix(settings.effectiveSaturation),
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

    // We can actually fill the canvas, since we are clipping.
    canvas.drawPaint(paint);
  }

  /// Paints an approximation for specular highlights by using a linear
  /// gradient that is aligned with the light angle and painting a stroke with
  /// that gradient.
  void _paintSpecular(Canvas canvas, Path path, Rect bounds) {
    // Expand bounds to a square to make sure the gradient angle will match the
    // light angle correctly. A squashed gradient would change the angle.
    final squareBounds = Rect.fromCircle(
      center: bounds.center,
      radius: bounds.size.longestSide / 2,
    );

    final lightIntensity = settings.effectiveLightIntensity.clamp(0.0, 1.0);
    final ambientStrength = settings.effectiveAmbientStrength.clamp(0.0, 1.0);
    final specularWrap = settings.specularWrap.clamp(0.0, 1.0);

    final highlightAlpha = Curves.easeOut.transform(lightIntensity) * 0.78;
    final highlightColor = settings.effectiveHighlightColor.withValues(
      // effectiveLightIntensity already includes highlight alpha and
      // visibility; multiplying by effectiveHighlightColor.a again would
      // unintentionally square both controls on the fake path.
      alpha: highlightAlpha,
    );
    final edgeColor = settings.effectiveEdgeColor.withValues(
      alpha:
          settings.effectiveEdgeColor.a *
          0.95 *
          Curves.easeOut.transform(
            ui.lerpDouble(0.35, 1.0, specularWrap)!,
          ),
    );

    final softEdgeColor = edgeColor.withValues(
      alpha: edgeColor.a * ui.lerpDouble(0.9, 1.0, ambientStrength)!,
    );

    final rad = settings.lightAngle;
    final x = math.cos(rad);
    final y = math.sin(rad);

    // How far the light covers the glass, used to adjust the gradient stops
    final lightCoverage = ui.lerpDouble(.12, .5, specularWrap)!;

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
    final secondInset = ui.lerpDouble(
      lightCoverage,
      .5,
      gradientScale.clamp(0, 1),
    )!;
    final edgeStart = ui.lerpDouble(
      secondInset,
      .5,
      settings.edgeInset.clamp(0.0, 1.0),
    )!;
    final edgeEnd = 1 - edgeStart;

    final shader = LinearGradient(
      colors: [
        highlightColor,
        softEdgeColor,
        softEdgeColor,
        highlightColor,
      ],
      stops: [
        inset,
        edgeStart,
        edgeEnd,
        1 - inset,
      ],
      begin: Alignment(x, y),
      end: Alignment(-x, -y),
    ).createShader(squareBounds);

    final paint = Paint()
      ..shader = shader
      ..color = highlightColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = settings.effectiveEdgeWidth > 0
          ? settings.effectiveEdgeWidth
          : ui.lerpDouble(1, 2, lightIntensity)!
      ..blendMode = BlendMode.hardLight;
    canvas.drawPath(path, paint);

    final overlay = Paint()
      ..shader = shader
      ..color = highlightColor.withValues(
        alpha:
            highlightColor.a *
            0.45 *
            settings.effectiveBleedStrength.clamp(0.0, 1.0),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = (settings.effectiveThickness / 24)
      ..blendMode = BlendMode.overlay;
    canvas.drawPath(path, overlay);
  }
}
