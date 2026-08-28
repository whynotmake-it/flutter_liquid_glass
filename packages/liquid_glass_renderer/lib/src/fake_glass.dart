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

/// A lower-cost approximation of [LiquidGlass] without refraction geometry.
///
/// Impeller fuses tint and saturation in a small backdrop shader. Skia uses a
/// canvas tint plus color matrix, while both backends share the same
/// contour-following canvas lighting.
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
  /// [LiquidGlassSettings.edgeRefraction] and
  /// [LiquidGlassSettings.chromaticAberration] therefore have no effect.
  /// Refraction-only material controls ([LiquidGlassSettings.refractionSpread],
  /// [LiquidGlassSettings.backdropScale],
  /// [LiquidGlassSettings.transmissionGamma], and
  /// [LiquidGlassSettings.vibrancy]) are likewise ignored. Thickness only
  /// controls the width of the approximate inner light bleed.
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
    final clipped = OptimizedClip(
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
          GlassGlowLayer(child: child),
        ),
      ),
    );
    final surfaced = _FakeExternalContour(
      shape: shape,
      settings: settings,
      child: clipped,
    );
    if (shadows.isEmpty) return surfaced;
    return GlassShadow(
      shape: shape,
      shadows: shadows,
      settings: settings,
      child: surfaced,
    );
  }

  static Widget _maybeFade(double visibility, Widget child) {
    final opacity = visibility.clamp(0.0, 1.0);
    if (opacity >= 1) return child;
    return Opacity(opacity: opacity, child: child);
  }
}

class _FakeExternalContour extends SingleChildRenderObjectWidget {
  const _FakeExternalContour({
    required this.shape,
    required this.settings,
    required super.child,
  });

  final LiquidShape shape;
  final LiquidGlassSettings settings;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFakeExternalContour(shape: shape, settings: settings);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderFakeExternalContour renderObject,
  ) {
    renderObject
      ..shape = shape
      ..settings = settings;
  }
}

class _RenderFakeExternalContour extends RenderProxyBox {
  _RenderFakeExternalContour({
    required this._shape,
    required this._settings,
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

  double get _outsideReach => math
      .max(
        _settings.effectiveContourWidth * 0.5 +
            _settings.effectiveContourOffset,
        0,
      )
      .toDouble();

  @override
  Rect get paintBounds => super.paintBounds.inflate(_outsideReach + 1);

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final strength = _settings.effectiveContourStrength.clamp(0.0, 1.0);
    final width = _settings.effectiveContourWidth;
    if (strength <= 0 || width <= 0 || _outsideReach <= 0) return;

    final bounds = offset & size;
    final path = _shape.getOuterPath(bounds);
    final canvas = context.canvas;
    final clipBounds = Path()..addRect(bounds.inflate(_outsideReach + 1));
    final outside = Path.combine(PathOperation.difference, clipBounds, path);
    canvas
      ..save()
      ..clipPath(outside)
      ..drawPath(
        path,
        Paint()
          // Canvas stroke coverage is slightly denser at its center than the
          // shader's one-pixel smoothstep feather. The gain and sub-pixel
          // width compensate that sampling difference while preserving a
          // linear response to contourStrength.
          ..color = Colors.black.withValues(alpha: strength * 0.92)
          ..style = PaintingStyle.stroke
          ..strokeWidth =
              width + math.max(_settings.effectiveContourOffset, 0) * 2 + 0.2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      )
      ..restore();
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

  bool get _hasBlur => settings.effectiveFrost != 0;

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
            sigmaX: settings.effectiveFrost,
            sigmaY: settings.effectiveFrost,
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
    final tintColor = settings.effectiveTint;
    if (settings.effectiveSaturation == 1 && tintColor.a == 0) {
      return null;
    }
    // Saturation alone is exactly representable as a native color matrix.
    // Avoid paying for a custom shader filter unless tint blending actually
    // needs the sampled backdrop color. Impeller can lower this native filter
    // more efficiently when it is composed with blur, and Skia already uses
    // the same matrix as its fallback path.
    if (tintColor.a == 0) {
      return ui.ColorFilter.matrix(
        _createSaturationMatrix(settings.effectiveSaturation),
      );
    }
    if (ui.ImageFilter.isShaderFilterSupported) {
      colorShader.setFloatUniforms((uniforms) {
        uniforms
          ..setSize(size)
          ..setColor(tintColor)
          ..setFloat(settings.effectiveSaturation);
      });
      return ui.ImageFilter.shader(colorShader);
    }
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
    final color = settings.effectiveTint;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // We can actually fill the canvas, since we are clipping.
    canvas.drawPaint(paint);
  }

  /// Paints fake-glass lighting in at most seven small canvas draws.
  ///
  /// The real renderer derives three independently sized bands from its SDF.
  /// Keeping the bevel, contour, and highlight independent here avoids making
  /// a wide optical highlight also turn into a wide dark outline. These are
  /// still cheap canvas work and require no geometry texture or refraction
  /// pass. The highlight uses four nested strokes to approximate an analytic
  /// falloff without another blur filter.
  void _paintSpecular(Canvas canvas, Path path, Rect bounds) {
    final lightIntensity = settings.effectiveHighlight.clamp(0.0, 1.0);
    final contourStrength = settings.effectiveContourStrength.clamp(0.0, 1.0);
    final bevelStrength = settings.effectiveBevelShadowStrength.clamp(0.0, 1.0);
    if (lightIntensity <= 0 && contourStrength <= 0 && bevelStrength <= 0) {
      return;
    }

    // Keep the low-energy ambient component contour-following and blurred.
    // The directional component uses a face gradient whose stops map directly
    // to the configured offset and depth; unlike a blurred outline, its band
    // reaches the same measured inward distance as the real SDF bevel.
    if (bevelStrength > 0) {
      final configuredDepth = settings.effectiveBevelShadowDepth;
      final depth = configuredDepth > 0
          ? configuredDepth
          : math.min(bounds.shortestSide * 0.12, 12).toDouble();
      final sizeProgress = Curves.easeInOut.transform(
        ((bounds.shortestSide * 0.5 - depth * 3.5) /
                math.max(depth * 1.5, 0.001))
            .clamp(0.0, 1.0),
      );
      final sizeEnergy = ui.lerpDouble(
        1.0,
        1.875,
        sizeProgress * settings.effectiveBevelShadowSizeResponse.clamp(0, 1),
      )!;
      final directionality = settings.effectiveBevelShadowDirectionality.clamp(
        0.0,
        1.0,
      );
      final bevelEnergy = bevelStrength * sizeEnergy;
      final ambient = bevelEnergy * (1 - directionality);
      final directional = bevelEnergy * directionality;
      final shadowOffset = settings.effectiveBevelShadowOffset.clamp(
        0.0,
        depth,
      );
      final falloff = math.max(depth - shadowOffset, 0).toDouble();
      if (ambient > 0) {
        canvas.drawPath(
          path,
          Paint()
            ..color = Colors.black.withValues(alpha: ambient.clamp(0.0, 1.0))
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1, shadowOffset * 2)
            ..maskFilter = falloff > 0.5
                ? MaskFilter.blur(BlurStyle.normal, falloff / 3)
                : null
            ..strokeJoin = StrokeJoin.round
            ..strokeCap = StrokeCap.round,
        );
      }
      if (directional > 0) {
        final leadingMidStop = depth > 0
            ? (shadowOffset * 0.5 / depth).clamp(0.0005, 0.998)
            : 0.0005;
        final peakStop = depth > 0
            ? (shadowOffset / depth).clamp(0.001, 0.999)
            : 0.001;
        final plateauEnd = depth > 0
            ? ((shadowOffset + math.min(2.0, falloff * 0.15)) / depth).clamp(
                peakStop,
                0.9995,
              )
            : 0.9995;
        final peakEnergy = (directional * 1.25).clamp(0.0, 1.0);
        canvas.drawPath(
          path,
          Paint()
            ..shader = ui.Gradient.linear(
              bounds.topCenter,
              Offset(bounds.center.dx, bounds.top + depth),
              [
                Colors.transparent,
                Colors.black.withValues(
                  alpha: (directional * 0.5).clamp(0.0, 1.0),
                ),
                Colors.black.withValues(alpha: peakEnergy),
                Colors.black.withValues(alpha: peakEnergy),
                Colors.transparent,
              ],
              [0.0, leadingMidStop, peakStop, plateauEnd, 1.0],
            )
            ..style = PaintingStyle.fill,
        );
      }
    }

    if (lightIntensity <= 0 && contourStrength <= 0) return;
    final contourWidth = settings.effectiveContourWidth > 0
        ? settings.effectiveContourWidth
        : 1.0;
    final highlightWidth = settings.effectiveHighlightWidth > 0
        ? settings.effectiveHighlightWidth
        : contourWidth;
    final wrap = settings.effectiveHighlightWrap.clamp(0.0, 1.0);
    // The real rim is much wider than highlightWidth: that setting controls
    // the initial inset, while thickness controls the optical falloff across
    // the wall. Canvas strokes are composited after the backdrop filter rather
    // than added in the material shader, so use a perceptual response to make
    // the same public setting produce comparable displayed energy.
    final highlightAlpha = Curves.easeOut.transform(lightIntensity) * 0.78;
    final coverage = ui.lerpDouble(0.12, 0.5, wrap)!;
    final contourOpacity =
        contourStrength *
        (1 - settings.effectiveContourTransmittance.clamp(0.0, 1.0));
    final contour = Colors.black.withValues(alpha: contourOpacity);
    if (contourOpacity > 0) {
      final innerContourWidth = math
          .max(
            contourWidth - settings.effectiveContourOffset * 2,
            0,
          )
          .toDouble();
      canvas.drawPath(
        path,
        Paint()
          ..color = contour
          ..style = PaintingStyle.stroke
          // The ancestor clip retains the inner half of the centered stroke.
          // RealGlass centers contourWidth on the SDF boundary, then shifts
          // it outward by contourOffset. A zero-width canvas stroke is a
          // device-pixel hairline, matching the shader's remaining feather
          // when the fitted offset consumes the full inside half-band.
          ..strokeWidth = innerContourWidth
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }
    if (lightIntensity > 0) {
      final opticalThickness = math
          .max(
            settings.effectiveThickness,
            1,
          )
          .toDouble();
      final thicknessScale = (40 / opticalThickness).clamp(1.0, 4.0);
      final edgeThreshold = ui.lerpDouble(0.8, 0.5, 1 / thicknessScale)!;
      final opticalReach =
          opticalThickness *
          (1 - math.sqrt(math.max(0, 1 - edgeThreshold * edgeThreshold)));
      final highlightReach = math.max(
        highlightWidth,
        opticalReach,
      );
      final oppositeStrength = settings.effectiveHighlightOppositeStrength
          .clamp(0.0, 1.0);
      // Four translucent nested strokes approximate the real shader's smooth
      // edgeFactor. Drawing broad-to-narrow avoids both a flat wide band and
      // an extra image-filter blur; the total peak energy remains the same.
      // Keep the crisp inner rim, but pull the low-energy outer lobes inward.
      // The previous 1.0/0.72 reaches made the approximation read thicker
      // than the analytic RealGlass highlight despite comparable peak energy.
      const reachFractions = [0.84, 0.64, 0.43, 0.18];
      const energyFractions = [0.10, 0.20, 0.28, 0.42];
      for (var index = 0; index < reachFractions.length; index++) {
        final bandAlpha = highlightAlpha * energyFractions[index];
        final primary = Colors.white.withValues(alpha: bandAlpha);
        final opposite = Colors.white.withValues(
          alpha: bandAlpha * oppositeStrength,
        );
        final bandReach = math.max(
          highlightWidth,
          highlightReach * reachFractions[index],
        );
        canvas.drawPath(
          path,
          Paint()
            ..shader = ui.Gradient.linear(
              bounds.topCenter,
              bounds.bottomCenter,
              [primary, Colors.transparent, Colors.transparent, opposite],
              [0, coverage, 1 - coverage, 1],
            )
            ..style = PaintingStyle.stroke
            ..blendMode = BlendMode.plus
            ..strokeWidth = bandReach * 2
            ..strokeJoin = StrokeJoin.round
            ..strokeCap = StrokeCap.round,
        );
      }
    }
  }
}
