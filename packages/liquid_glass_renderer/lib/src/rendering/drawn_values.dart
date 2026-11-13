import 'dart:math' as math;
import 'dart:ui';

import 'package:liquid_glass_renderer/painting.dart';

/// The values of [LiquidGlassSettings] the shaders take: each setting clamped
/// to the range the renderer draws, and what the passes derive from them.
extension DrawnSettings on LiquidGlassSettings {
  /// [LiquidGlassSettings.backdropShrinkRim] clamped to `0` to `1`.
  double get effectiveBackdropShrinkRim => backdropShrinkRim.clamp(0.0, 1.0);

  /// The bevel width; never negative.
  double get effectiveRefractionHeight => math.max(0, refractionHeight);

  /// The edge displacement; never negative.
  double get effectiveRefractionAmount => math.max(0, refractionAmount);

  /// [LiquidGlassSettings.backdropShrink] clamped to `0` to `0.75`.
  double get effectiveBackdropShrink => backdropShrink.clamp(0.0, 0.75);

  /// [LiquidGlassSettings.backdropPull] where it reaches anywhere, else
  /// `0`; never negative.
  double get effectiveBackdropPull =>
      backdropPullHeight > 0 ? math.max(0, backdropPull) : 0;

  /// [LiquidGlassSettings.aberration] where it shows anywhere, else `0`;
  /// never negative.
  double get effectiveAberration =>
      aberrationDepth > 0 ? math.max(0, aberration) : 0;

  /// The slider position, clamped to `0` to `1`.
  double get effectiveTintAmount => tintAmount.clamp(0.0, 1.0);

  /// The blur sigma as set; never negative.
  double get effectiveFrost => math.max(0, frost);

  /// The displacement codec scale the geometry and final passes share.
  /// [LiquidGlassSettings.refractionAmount] is the exact peak of the profile,
  /// so the RGBA8 code range is spent only on reachable displacement.
  double get effectiveDisplacementScale =>
      math.max(1e-3, effectiveRefractionAmount);

  /// The lighting depth of the rim in logical pixels, which the geometry and
  /// final shaders take but do not read.
  double get effectiveEdgeDistanceRange => math.max(12, refractionHeight);

  /// The width of the dark border in logical pixels; `0` without a border.
  double get contourWidth => contourStrength > 0 ? GlassRim.contourWidth : 0;
}

/// A [LiquidShape] as the shaders take it.
extension DrawnShape on LiquidShape {
  /// The corner radius in logical pixels, the top corners' when a
  /// [LiquidRoundedSuperellipse] has a bottom radius of its own; `0` for an
  /// oval.
  double get cornerRadius => switch (this) {
    LiquidRoundedSuperellipse(:final borderRadius) => borderRadius,
    LiquidRoundedRectangle(:final borderRadius) => borderRadius,
    LiquidOval() => 0,
  };

  /// The radius of the two bottom corners where they differ from the top
  /// ones' ([cornerRadius]), else null: the one rule that tells a
  /// [LiquidRoundedSuperellipse] drawn as two halves from one drawn whole.
  double? get pairBottomRadius => switch (this) {
    final LiquidRoundedSuperellipse shape when !shape.isUniform =>
      shape.effectiveBottomRadius,
    _ => null,
  };
}

/// A [LiquidRoundedSuperellipse] as the shaders take it.
extension DrawnSuperellipse on LiquidRoundedSuperellipse {
  /// The radius of the two bottom corners.
  double get effectiveBottomRadius => bottomRadius ?? borderRadius;

  /// Whether every corner has the same radius.
  bool get isUniform => effectiveBottomRadius == borderRadius;
}

/// A [LiquidGlassColorModel] as fake glass draws it.
extension DrawnColorModel on LiquidGlassColorModel {
  // The direct model has no glint fit of its own: it glints as the iOS 27
  // light model, whose glint is the fitted default.
  GlassColorParameters get _glint =>
      parameters ?? GlassColorParameters.ios27Light;

  /// The luminance of the neutral glint target fake glass composites, which
  /// cannot scale with the face it does not sample.
  double get fakeGlintLuminance => _glint.fakeGlintLuminance;

  /// How much the face contributes to the fake glass glint target, which
  /// approximates the face with its surface tint plus emission.
  double get fakeGlintFaceGain => _glint.glintFaceGain;

  /// How strongly the fake glass glint amplifies the face chroma proxy.
  double get fakeGlintVibrancy => _glint.glintVibrancy;

  /// The single surface tint fake glass paints for [tint].
  ///
  /// Fake glass cannot read the backdrop's luminance in its analytic surface
  /// shader, so an adaptive model evaluates its tonal ramp at a midtone. Its
  /// neutral face is applied by the backdrop color filter instead, so it is
  /// not part of this color.
  Color approximateSurfaceTint(Color tint) {
    final parameters = this.parameters;
    if (parameters == null) return tint;
    if (tint.a <= 0) return const Color(0x00000000);
    return parameters.tintTone(tint, 0.5).withValues(alpha: tint.a);
  }
}

/// A [GlassColorParameters] as the final render shader takes it.
extension DrawnColorParameters on GlassColorParameters {
  /// The floats of one slot of `uColorModelParams` in the final render
  /// shader at slider [tintAmount]: six vec4 slots per model, packed as
  /// liquid_glass_final_render_core.glsl reads them.
  List<double> toShaderParameters(double tintAmount) {
    final emission = emissionAlpha.evaluate(tintAmount);
    return [
      emissionColor.r * emission,
      emissionColor.g * emission,
      emissionColor.b * emission,
      transmittance.evaluate(tintAmount),
      luminanceLift.evaluate(tintAmount),
      chromaGain.evaluate(tintAmount),
      contourScale(tintAmount) - 1,
      if (bleed.onBright) -bleed.opacity else bleed.opacity,
      bleed.black,
      bleed.white,
      bleed.saturation,
      0,
      ..._tones,
    ];
  }

  List<double> get _tones => [
    toneLow.base,
    toneLow.amplitude,
    toneLow.pivot,
    toneLow.exponent,
    toneHigh.base,
    toneHigh.amplitude,
    toneHigh.pivot,
    toneHigh.exponent,
    toneGammaLuminance,
    glintLuminance,
    glintFaceGain,
    glintVibrancy,
  ];
}

/// How many floats [glowUniforms] writes: uGlowSpot, uGlowBox, uGlowShape.
const int glowUniformCount = 12;

/// The floats of uGlowSpot, uGlowBox and uGlowShape for [glow] in a layer
/// whose matte has [devicePixelRatio] device pixels per unit; all zero, which
/// draws no glow, for none.
///
/// The spot's radius goes in as its falloff `log2(e) / (2 sigma^2)` per
/// squared device pixel, so the shader's Gaussian is one exp2 with no divide.
List<double> glowUniforms(LiquidGlassGlow? glow, double devicePixelRatio) {
  if (glow == null || (glow.wash <= 0 && glow.gain <= 0)) {
    return List<double>.filled(glowUniformCount, 0);
  }
  final scale = devicePixelRatio;
  final bounds = glow.bounds;
  final spot = glow.radius > 0 && glow.gain > 0;
  final sigma = glow.radius * scale;
  final corner = glow.cornerRadius.clamp(0, bounds.shortestSide / 2);
  return [
    glow.center.dx * scale,
    glow.center.dy * scale,
    if (spot) math.log2e / (2 * sigma * sigma) else 0,
    if (spot) glow.gain else 0,
    bounds.center.dx * scale,
    bounds.center.dy * scale,
    bounds.width / 2 * scale,
    bounds.height / 2 * scale,
    corner * scale,
    if (glow.wash > 0) glow.wash else 0,
    0,
    0,
  ];
}
