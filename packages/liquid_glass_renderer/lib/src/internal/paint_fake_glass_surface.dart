import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/rounded_superellipse_parameters.dart';

/// Resolves the highlight band width using the same fallback as the real
/// image-filter shader: an omitted highlight width follows the contour width.
///
/// Keep this in one place so FakeGlass does not invent a minimum one-pixel rim
/// that makes the dark toolbar preset visibly thicker than RealGlass.
@visibleForTesting
double fakeGlassHighlightBandWidth(LiquidGlassSettings settings) {
  return settings.effectiveHighlightWidth > 0
      ? settings.effectiveHighlightWidth
      : settings.effectiveContourWidth;
}

/// Extra logical pixels required for the portion of the contour that lies
/// outside the shape's nominal bounds.
double fakeGlassSurfaceOutset(LiquidGlassSettings settings) {
  return math
      .max(
        settings.effectiveContourOffset + settings.effectiveContourWidth + 1,
        0,
      )
      .toDouble();
}

const _noSuperellipse = <double>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

/// Paints one analytic FakeGlass surface with the same logical-pixel setting
/// contract used by RealGlass.
void paintFakeGlassSurface(
  Canvas canvas, {
  required ui.FragmentShader shader,
  required Size size,
  required LiquidShape shape,
  required LiquidGlassSettings settings,
  required LiquidGlassAppearance appearance,
  required double devicePixelRatio,
  bool exteriorOnly = false,
}) {
  final appearanceVisibility = appearance.visibility.clamp(0.0, 1.0);
  final surfaceTint = appearance.colorModel.approximateSurfaceTint(
    appearance.tint,
  );
  final tint = surfaceTint.withValues(
    alpha: surfaceTint.a * appearanceVisibility,
  );
  final faceEmission =
      appearance.colorModel
          .faceTransfer(
            size.shortestSide,
            tintAmount: settings.effectiveTintAmount,
          )
          ?.emission ??
      const Color(0x00000000);
  final shapeType = switch (shape) {
    LiquidOval() => 0.0,
    LiquidRoundedRectangle() => 1.0,
    LiquidRoundedSuperellipse() => 2.0,
  };
  final cornerRadius = switch (shape) {
    LiquidOval() => 0.0,
    LiquidRoundedRectangle(:final borderRadius) => borderRadius,
    LiquidRoundedSuperellipse(:final borderRadius) => borderRadius,
  };
  final configuredHighlightWidth = fakeGlassHighlightBandWidth(settings);
  final opticalThickness = settings.effectiveEdgeDistanceRange;
  shader.setFloatUniforms((uniforms) {
    uniforms
      ..setSize(size)
      ..setFloats([shapeType, cornerRadius])
      ..setColor(tint)
      ..setFloats([
        settings.effectiveHighlight * appearanceVisibility,
        configuredHighlightWidth,
        opticalThickness,
        settings.effectiveHighlightWrap,
        settings.effectiveHighlightOppositeStrength * appearanceVisibility,
        settings.effectiveContourStrength *
            appearance.colorModel.contourScale(
              size.shortestSide,
              settings.effectiveTintAmount,
            ) *
            appearanceVisibility,
        settings.effectiveContourWidth,
        settings.effectiveContourTransmittance,
        settings.effectiveContourOffset,
        settings.effectiveContourDirectionality,
        settings.effectiveBevelShadowStrength * appearanceVisibility,
        settings.effectiveBevelShadowDepth,
        settings.effectiveBevelShadowOffset,
        settings.effectiveBevelShadowDirectionality,
        settings.effectiveBevelShadowSizeResponse,
      ])
      ..setOffset(const Offset(0, 1))
      ..setFloat(1 / math.max(devicePixelRatio, 0.01))
      ..setFloat(exteriorOnly ? 1 : 0)
      ..setFloat(appearance.colorModel.fakeGlintLuminance)
      ..setFloats([
        faceEmission.r * appearanceVisibility,
        faceEmission.g * appearanceVisibility,
        faceEmission.b * appearanceVisibility,
      ])
      ..setFloats(
        shape is LiquidRoundedSuperellipse
            ? roundedSuperellipseParameters(size, cornerRadius)
            : _noSuperellipse,
      );
  });
  final contourOutset = fakeGlassSurfaceOutset(settings);
  canvas.drawRect(
    (Offset.zero & size).inflate(contourOutset),
    Paint()..shader = shader,
  );
}
