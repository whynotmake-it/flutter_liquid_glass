import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';

/// The glow a finger raises on the glass of one shape of a layer, in the
/// layer's coordinates, for `LiquidGlassLayer.glow`.
///
/// Inside [bounds], a wash adds [wash] to every color channel and a spot
/// multiplies the channels by `1 + gain * exp(-0.5 * (r / radius)^2)` at
/// distance `r` from [center], clamped at white. Both act on everything the
/// glass shows and stay under the content painted after the layer, as iOS
/// lights a pressed glass surface: color matrices over the backdrop, the
/// spot equal to a color dodge whose white level is `1 - 1 / m` for its
/// multiplier `m`. The widget that owns the glass decides where and how
/// strongly it glows, frame by frame; `GlassGlow` instead follows the
/// pointer itself.
///
/// A layer whose shapes differ in color model or visibility draws no glow;
/// shapes that differ only in tint still glow.
@immutable
class LiquidGlassGlow {
  /// Creates a glow.
  const LiquidGlassGlow({
    required this.bounds,
    required this.cornerRadius,
    required this.center,
    required this.radius,
    required this.gain,
    required this.wash,
  });

  /// The lit shape's box: the glow stays inside it.
  final Rect bounds;

  /// The radius of every corner of [bounds], at most half its shorter side.
  final double cornerRadius;

  /// The center of the spot.
  final Offset center;

  /// The standard deviation of the spot's falloff.
  final double radius;

  /// How much the spot brightens its center: there the channels are
  /// multiplied by `1 + gain`.
  final double gain;

  /// How much every color channel rises inside [bounds], in `[0, 1]` units.
  final double wash;

  /// How many floats [uniformsOf] writes: uGlowSpot, uGlowBox, uGlowShape.
  @internal
  static const int floatCount = 12;

  /// The floats of uGlowSpot, uGlowBox and uGlowShape for [glow] in a
  /// layer whose matte has [devicePixelRatio] device pixels per unit; all
  /// zero, which draws no glow, for none.
  ///
  /// The spot's radius goes in as its falloff `log2(e) / (2 sigma^2)` per
  /// squared device pixel, so the shader's Gaussian is one exp2 with no
  /// divide.
  @internal
  static List<double> uniformsOf(
    LiquidGlassGlow? glow,
    double devicePixelRatio,
  ) {
    if (glow == null || (glow.wash <= 0 && glow.gain <= 0)) {
      return List<double>.filled(floatCount, 0);
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

  /// The color the final pass gives the glass color [rgb] at [point], in
  /// matte device pixels, under the glow [uniforms] (from [uniformsOf]):
  /// the CPU reference of shaders/glass_glow.glsl and of the branch that
  /// skips it.
  @visibleForTesting
  static (double, double, double) shade(
    List<double> uniforms,
    Offset point,
    (double, double, double) rgb,
  ) {
    final gain = uniforms[3];
    final wash = uniforms[9];
    if (gain <= 0 && wash <= 0) return rgb;
    final qx = (point.dx - uniforms[4]).abs() - uniforms[6] + uniforms[8];
    final qy = (point.dy - uniforms[5]).abs() - uniforms[7] + uniforms[8];
    final ox = qx > 0 ? qx : 0.0;
    final oy = qy > 0 ? qy : 0.0;
    final deeper = qx > qy ? qx : qy;
    final inside = deeper < 0 ? deeper : 0.0;
    final d = math.sqrt(ox * ox + oy * oy) + inside - uniforms[8];
    final cover = (0.5 - d).clamp(0.0, 1.0);
    final rx = point.dx - uniforms[0];
    final ry = point.dy - uniforms[1];
    final factor =
        1 + gain * math.exp(-uniforms[2] * (rx * rx + ry * ry) * math.ln2);
    double channel(double c) {
      final raised = (c + wash) * factor;
      final lit = raised < 1 ? raised : 1.0;
      return c + (lit - c) * cover;
    }

    return (channel(rgb.$1), channel(rgb.$2), channel(rgb.$3));
  }

  @override
  bool operator ==(Object other) =>
      other is LiquidGlassGlow &&
      other.bounds == bounds &&
      other.cornerRadius == cornerRadius &&
      other.center == center &&
      other.radius == radius &&
      other.gain == gain &&
      other.wash == wash;

  @override
  int get hashCode =>
      Object.hash(bounds, cornerRadius, center, radius, gain, wash);
}
