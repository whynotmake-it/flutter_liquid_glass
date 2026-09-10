import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

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
        settings.effectiveContourOffset +
            settings.effectiveContourWidth * 0.5 +
            1,
        0,
      )
      .toDouble();
}

/// Paints one analytic FakeGlass surface with the same logical-pixel setting
/// contract used by RealGlass.
void paintFakeGlassSurface(
  Canvas canvas, {
  required ui.FragmentShader shader,
  required Size size,
  required LiquidShape shape,
  required LiquidGlassSettings settings,
  required LiquidGlassAppearance appearance,
}) {
  final visibility = appearance.visibility;
  final surfaceTint = appearance.colorModel.approximateSurfaceTint(
    appearance.tint,
  );
  final tint = surfaceTint.withValues(
    alpha: surfaceTint.a * visibility,
  );
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
  final configuredDepth = settings.effectiveBevelShadowDepth;
  final bevelDepth = configuredDepth > 0
      ? configuredDepth
      : math.min(size.shortestSide * 0.12, 12).toDouble();
  final configuredHighlightWidth = fakeGlassHighlightBandWidth(settings);
  final opticalThickness = math.max(settings.effectiveThickness, 1).toDouble();
  final appearanceVisibility = appearance.visibility.clamp(0.0, 1.0);
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
        settings.effectiveContourStrength * appearanceVisibility,
        settings.effectiveContourWidth,
        settings.effectiveContourTransmittance,
        settings.effectiveContourOffset,
        settings.effectiveBevelShadowStrength * appearanceVisibility,
        bevelDepth,
        settings.effectiveBevelShadowOffset,
        settings.effectiveBevelShadowDirectionality,
        settings.effectiveBevelShadowSizeResponse,
      ])
      ..setOffset(const Offset(0, 1));
  });
  final contourOutset = fakeGlassSurfaceOutset(settings);
  canvas.drawRect(
    (Offset.zero & size).inflate(contourOutset),
    Paint()..shader = shader,
  );
}
