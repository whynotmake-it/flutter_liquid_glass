import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/rounded_superellipse_parameters.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_settings.dart';

/// Extra logical pixels required for the portion of the contour that lies
/// outside the shape's nominal bounds.
double fakeGlassSurfaceOutset(LiquidGlassSettings settings) {
  return math
      .max(
        settings.contourWidth + 1,
        0,
      )
      .toDouble();
}

const _noSuperellipse = <double>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

/// WORKAROUND for an Impeller/Metal coverage bug on macOS, pending an
/// upstream fix (repro project: `impeller_pixel_aligned_coverage`, kept
/// outside this repo for the Flutter issue): a
/// shader-filled draw whose quad edge lands on a half-integer device-pixel
/// boundary renders its alpha ramp quantized to whole pixels near that
/// edge — the analytic silhouette stair-steps. Integer-aligned quad edges
/// render smoothly.
///
/// The drawn rect only bounds where the shader runs — the shape is placed
/// by `FlutterFragCoord`, so growing the quad changes nothing visible.
/// Expanding each edge out to the nearest whole device pixel keeps the
/// raster phase off the bad half-pixel grid at any position.
///
/// [transform] is the draw's local-to-device transform
/// (`canvas.getTransform()`); only axis-aligned transforms are snapped —
/// anything else passes through unchanged.
///
/// The snap is computed at paint time. Compositor-only motion (a retained
/// `OffsetLayer` moving this subtree without a repaint) can land the baked
/// quad back on the bad phase; such moves are transient and the surface
/// realigns on the next repaint.
Rect fakeGlassSurfaceQuad(Rect localQuad, Float64List transform) {
  final s = transform;
  // Anything but an axis-aligned scale+translate: nothing sane to snap.
  if (s[1] != 0 ||
      s[2] != 0 ||
      s[3] != 0 ||
      s[4] != 0 ||
      s[6] != 0 ||
      s[7] != 0 ||
      s[11] != 0 ||
      s[14] != 0 ||
      s[0] == 0 ||
      s[5] == 0) {
    return localQuad;
  }
  double axis(
    double localMin,
    double localMax,
    double scale,
    double shift,
  ) {
    final a = scale * localMin + shift;
    final b = scale * localMax + shift;
    return (math.min(a, b).floor() - shift) / scale;
  }

  double axisMax(
    double localMin,
    double localMax,
    double scale,
    double shift,
  ) {
    final a = scale * localMin + shift;
    final b = scale * localMax + shift;
    return (math.max(a, b).ceil() - shift) / scale;
  }

  return Rect.fromLTRB(
    axis(localQuad.left, localQuad.right, s[0], s[12]),
    axis(localQuad.top, localQuad.bottom, s[5], s[13]),
    axisMax(localQuad.left, localQuad.right, s[0], s[12]),
    axisMax(localQuad.top, localQuad.bottom, s[5], s[13]),
  );
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
  final opticalThickness = settings.effectiveEdgeDistanceRange;
  shader.setFloatUniforms((uniforms) {
    uniforms
      ..setSize(size)
      ..setFloats([shapeType, cornerRadius])
      ..setColor(tint)
      ..setFloats([
        settings.highlight * appearanceVisibility,
        GlassRim.highlightWidth,
        opticalThickness,
        GlassRim.highlightWrap,
        GlassRim.highlightOppositeStrength * appearanceVisibility,
        settings.contourStrength *
            appearance.colorModel.contourScale(
              size.shortestSide,
              settings.effectiveTintAmount,
            ) *
            appearanceVisibility,
        settings.contourWidth,
        0, // contour transmittance
        0, // contour offset
        settings.contourDirectionality,
        settings.bevelShadowStrength * appearanceVisibility,
        GlassRim.bevelShadowDepth,
        GlassRim.bevelShadowOffset,
        GlassRim.bevelShadowDirectionality,
        0, // bevel shadow size response
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
    fakeGlassSurfaceQuad(
      (Offset.zero & size).inflate(contourOutset),
      canvas.getTransform(),
    ),
    Paint()..shader = shader,
  );
}
