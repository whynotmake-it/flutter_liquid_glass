import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/painting/glass_color_parameters.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_color_model.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_settings.dart';
import 'package:liquid_glass_renderer/src/painting/shader_constants.dart';
import 'package:liquid_glass_renderer/src/rendering/appearance.dart';

/// The values of [LiquidGlassSettings] the shaders take: each setting clamped
/// to the range the renderer draws, and what the passes derive from them.
extension DrawnSettings on LiquidGlassSettings {
  /// The bevel width; never negative.
  double get effectiveRefractionHeight => math.max(0, refractionHeight);

  /// The edge displacement; never negative.
  double get effectiveRefractionAmount => math.max(0, refractionAmount);

  /// [LiquidGlassSettings.backdropShrink] clamped to `0` to `0.75`.
  double get effectiveBackdropShrink => backdropShrink.clamp(0.0, 0.75);

  /// [LiquidGlassSettings.backdropPull] where it reaches anywhere, else
  /// `0`; never negative.
  double get effectiveBackdropPull =>
      backdropPullDepth > 0 ? math.max(0, backdropPull) : 0;

  /// [LiquidGlassSettings.aberration] where it shows anywhere, else `0`;
  /// never negative.
  double get effectiveAberration =>
      aberrationDepth > 0 ? math.max(0, aberration) : 0;

  /// The slider position, clamped to `0` to `1`.
  double get effectiveSliderPosition => sliderPosition.clamp(0.0, 1.0);

  /// The displacement codec scale the geometry and final passes share.
  /// [LiquidGlassSettings.refractionAmount] is the exact peak of the profile,
  /// so the RGBA8 code range is spent only on reachable displacement.
  double get effectiveDisplacementScale =>
      math.max(1e-3, effectiveRefractionAmount);

  /// The width of the dark contour in logical pixels; `0` without one.
  double get contourWidth => contourStrength > 0 ? GlassRim.contourWidth : 0;
}

/// A [LiquidShape] as the shaders take it.
extension DrawnShape on LiquidShape {
  /// The corner radius in logical pixels, the top corners' of a
  /// [LiquidRoundedSuperellipse]; `0` for an oval.
  double get cornerRadius => switch (this) {
    LiquidRoundedSuperellipse(:final topRadius) => topRadius,
    LiquidRoundedRectangle(:final radius) => radius,
    LiquidOval() => 0,
  };

  /// The radius of the two bottom corners in logical pixels: [cornerRadius]
  /// except on a [LiquidRoundedSuperellipse] with bottom corners of its own.
  double get bottomCornerRadius => switch (this) {
    LiquidRoundedSuperellipse(:final bottomRadius) => bottomRadius,
    _ => cornerRadius,
  };

  /// Whether the bottom corners differ from the top ones: the one rule that
  /// tells a [LiquidRoundedSuperellipse] drawn as two halves from one drawn
  /// whole.
  bool get isPair => bottomCornerRadius != cornerRadius;

  /// The kind of shape the shaders tell this one by.
  RawShapeType get rawType => switch (this) {
    LiquidRoundedSuperellipse() =>
      isPair ? RawShapeType.squirclePair : RawShapeType.squircle,
    LiquidOval() => RawShapeType.ellipse,
    LiquidRoundedRectangle() => RawShapeType.roundedRectangle,
  };
}

/// A [WornColorModel] as fake glass draws it.
extension DrawnColorModel on WornColorModel {
  /// The luminance of the neutral glint target fake glass composites, which
  /// cannot scale with the face it does not sample. The direct model has no
  /// glint fit of its own and takes the constants real glass gives it.
  double get fakeGlintLuminance =>
      parameters?.fakeGlintLuminance ?? GlassGlint.directLuminance;

  /// How much the face contributes to the fake glass glint target, which
  /// approximates the face with its surface tint plus emission.
  double get fakeGlintFaceGain => parameters?.glintFaceGain ?? 0;

  /// How strongly the fake glass glint amplifies the face chroma proxy.
  double get fakeGlintVibrancy =>
      parameters?.glintVibrancy ?? GlassGlint.directVibrancy;

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
  /// shader at slider [sliderPosition], by [ColorModelLane].
  List<double> toShaderParameters(double sliderPosition) {
    final emission = emissionAlpha.evaluate(sliderPosition);
    return laneBlock(ColorModelLane.values, {
      ColorModelLane.emission: [
        emission,
        emission,
        emission,
      ],
      ColorModelLane.transmittance: [transmittance.evaluate(sliderPosition)],
      ColorModelLane.faceTransfer: [
        luminanceLift.evaluate(sliderPosition),
        chromaGain.evaluate(sliderPosition),
      ],
      ColorModelLane.contourBoost: [contourScale(sliderPosition) - 1],
      ColorModelLane.bleedOpacity: [
        if (bleed.onBright) -bleed.opacity else bleed.opacity,
      ],
      ColorModelLane.bleed: [bleed.black, bleed.white, bleed.saturation],
      ColorModelLane.tones: [
        toneLow.base,
        toneLow.amplitude,
        toneHigh.base,
        toneHigh.amplitude,
      ],
      ColorModelLane.glint: [glintLuminance, glintFaceGain, glintVibrancy],
    });
  }
}

/// A [WornAppearance] as a layer draws it.
extension DrawnAppearance on WornAppearance {
  /// Whether glass in this appearance shows at all.
  bool get shows => visibility > 0;
}

/// A glow that draws: one with a wash or a spot.
extension type const DrawnGlow._(LiquidGlassGlow _glow)
    implements LiquidGlassGlow {
  /// [glow] where it draws, else null.
  static DrawnGlow? of(LiquidGlassGlow? glow) {
    if (glow == null) return null;
    final drawn = DrawnGlow._(glow);
    return drawn.drawsWash || drawn.drawsSpot ? drawn : null;
  }

  /// Whether the spot brightens anything: it has a gain and a radius.
  bool get drawsSpot => gain > 0 && radius > 0;

  /// Whether the wash raises the channels.
  bool get drawsWash => wash > 0;
}

/// The glow's lanes of the final shader's uEffects: glowSpot, glowBox and
/// glowWash.
typedef GlowUniforms = Map<EffectsLane, List<double>>;

/// The glow of a layer whose glass glows nowhere.
const GlowUniforms noGlowUniforms = {
  EffectsLane.glowSpot: [0, 0, 0, 0],
  EffectsLane.glowBox: [0, 0, 0, 0],
  EffectsLane.glowWash: [0],
};

/// The glow of [glow] on a shape that [toLayer] maps into a layer whose
/// matte has [devicePixelRatio] device pixels per unit.
///
/// The spot's radius goes in as its falloff `log2(e) / (2 sigma^2)` per
/// squared device pixel, so the shader's Gaussian is one exp2 with no divide.
GlowUniforms glowUniforms(
  DrawnGlow glow, {
  required Matrix4 toLayer,
  required Rect? box,
  required double devicePixelRatio,
}) {
  final dpr = devicePixelRatio;
  final m = toLayer.storage;
  final stretch = math.sqrt((m[0] * m[5] - m[1] * m[4]).abs());
  final sigma = glow.radius * stretch * dpr;
  final spot = glow.drawsSpot && sigma > 0;
  final center = MatrixUtils.transformPoint(toLayer, glow.center) * dpr;
  final lit = box == null ? null : MatrixUtils.transformRect(toLayer, box);
  return Map.unmodifiable(<EffectsLane, List<double>>{
    EffectsLane.glowSpot: [
      center.dx,
      center.dy,
      if (spot) math.log2e / (2 * sigma * sigma) else 0,
      if (spot) glow.gain else 0,
    ],
    EffectsLane.glowBox: lit == null
        ? const [0, 0, _unboxed, _unboxed]
        : [
            lit.center.dx * dpr,
            lit.center.dy * dpr,
            lit.width / 2 * dpr + _antialiasedEdgeRoom,
            lit.height / 2 * dpr + _antialiasedEdgeRoom,
          ],
    EffectsLane.glowWash: [if (glow.drawsWash) glow.wash else 0],
  });
}

const double _unboxed = 1000000;

const double _antialiasedEdgeRoom = 1;
