import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

/// Paints one analytic FakeGlass surface with the same logical-pixel setting
/// contract used by RealGlass.
void paintFakeGlassSurface(
  Canvas canvas, {
  required ui.FragmentShader shader,
  required Size size,
  required LiquidShape shape,
  required LiquidGlassSettings settings,
}) {
  final tint = settings.effectiveTint;
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
  final configuredHighlightWidth = settings.effectiveHighlightWidth > 0
      ? settings.effectiveHighlightWidth
      : math.max(settings.effectiveContourWidth, 1).toDouble();
  final opticalThickness = math.max(settings.effectiveThickness, 1).toDouble();
  shader.setFloatUniforms((uniforms) {
    uniforms
      ..setSize(size)
      ..setFloats([shapeType, cornerRadius])
      ..setColor(tint)
      ..setFloats([
        settings.effectiveHighlight,
        configuredHighlightWidth,
        opticalThickness,
        settings.effectiveHighlightWrap,
        settings.effectiveHighlightOppositeStrength,
        settings.effectiveContourStrength,
        settings.effectiveContourWidth,
        settings.effectiveContourTransmittance,
        settings.effectiveContourOffset,
        settings.effectiveBevelShadowStrength,
        bevelDepth,
        settings.effectiveBevelShadowOffset,
        settings.effectiveBevelShadowDirectionality,
        settings.effectiveBevelShadowSizeResponse,
      ])
      ..setOffset(const Offset(0, 1));
  });
  final contourOutset = math
      .max(
        settings.effectiveContourOffset +
            settings.effectiveContourWidth * 0.5 +
            1,
        0,
      )
      .toDouble();
  canvas.drawRect(
    (Offset.zero & size).inflate(contourOutset),
    Paint()..shader = shader,
  );
}
