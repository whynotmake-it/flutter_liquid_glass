import 'dart:ui';

import 'package:kinesis/motion.dart';

/// The deformation tuning of a glass surface that responds to touch.
///
/// UIKit keeps one set of these values per size class and derives the set
/// for a concrete surface from its size: [FlexSpec.forSize] for
/// controls, selection lenses and buttons, [FlexSpec.loupeForSize]
/// for magnifying loupes such as a slider thumb. Lengths are in logical
/// pixels and are absolute, not proportional to the surface.
class FlexSpec {
  /// Creates a flex spec from explicit values.
  const FlexSpec({
    required this.liftScalePoints,
    required this.scaleDistanceThreshold,
    required this.movementNormalizationFactor,
    required this.movementScalePoints,
    required this.movementMinScale,
    required this.movementMaxScale,
    required this.scaleSpring,
    required this.trackingSpring,
    this.interactionPulseNormalizationFactor = 1,
    this.interactionPulseScaleX = 0,
    this.interactionPulseScaleY = 0,
    this.interactionPulseDriftRatio = 0,
    this.littleGlowOpacity = 0,
    this.bigGlowOpacity = 0,
    this.retargetImpulse = 0,
  });

  /// The spec UIKit derives for a touch-responsive surface of [size].
  ///
  /// UIKit picks by the short and long sides, not by width and height, so
  /// a portrait surface gets the same spec as its landscape twin. When the
  /// long side is under [compactLongSideLimit] the surface uses
  /// [ultraSmall]. From there on the spec blends [small] into [large] over
  /// the 44 to 160 range along two independent axes: the sizes (lift,
  /// stretch threshold, glow) follow the short side and the springs follow
  /// the long side. The movement scale stays at the small value. Read from
  /// UIKit, notes private; the endpoints agree with the device reads.
  factory FlexSpec.forSize(Size size) {
    final short = size.shortestSide;
    final long = size.longestSide;
    if (long < compactLongSideLimit) return ultraSmall;
    final ts = _unit(short, smallDimension, largeDimension);
    final tl = _unit(long, smallDimension, largeDimension);
    return FlexSpec(
      liftScalePoints: _lerp(small.liftScalePoints, large.liftScalePoints, ts),
      scaleDistanceThreshold: _lerp(
        small.scaleDistanceThreshold,
        large.scaleDistanceThreshold,
        ts,
      ),
      movementNormalizationFactor: _lerp(
        small.movementNormalizationFactor,
        large.movementNormalizationFactor,
        ts,
      ),
      movementScalePoints: small.movementScalePoints,
      movementMinScale: small.movementMinScale,
      movementMaxScale: small.movementMaxScale,
      scaleSpring: Spring.lerp(small.scaleSpring, large.scaleSpring, tl),
      trackingSpring: Spring.lerp(
        small.trackingSpring,
        large.trackingSpring,
        tl,
      ),
      littleGlowOpacity: _lerp(
        small.littleGlowOpacity,
        large.littleGlowOpacity,
        ts,
      ),
      bigGlowOpacity: _lerp(small.bigGlowOpacity, large.bigGlowOpacity, ts),
    );
  }

  /// The spec UIKit derives for a magnifying loupe of [size].
  ///
  /// Every value blends [smallLoupe] into [loupe] by the short side over
  /// the 37 to 70 range. The lift and the stretch threshold stay at zero.
  /// Read from UIKit, notes private.
  factory FlexSpec.loupeForSize(Size size) {
    final t = _unit(size.shortestSide, smallLoupeDimension, loupeDimension);
    const a = smallLoupe;
    const b = loupe;
    return FlexSpec(
      liftScalePoints: 0,
      scaleDistanceThreshold: 0,
      movementNormalizationFactor: _lerp(
        a.movementNormalizationFactor,
        b.movementNormalizationFactor,
        t,
      ),
      movementScalePoints: _lerp(
        a.movementScalePoints,
        b.movementScalePoints,
        t,
      ),
      movementMinScale: _lerp(a.movementMinScale, b.movementMinScale, t),
      movementMaxScale: _lerp(a.movementMaxScale, b.movementMaxScale, t),
      scaleSpring: Spring.lerp(a.scaleSpring, b.scaleSpring, t),
      trackingSpring: Spring.lerp(a.trackingSpring, b.trackingSpring, t),
    );
  }

  /// How many pixels the surface's long side grows while pressed; the short
  /// side grows in proportion ([liftScaleFor]).
  final double liftScalePoints;

  /// The squared-distance scale over which a drag stretches the surface.
  final double scaleDistanceThreshold;

  /// The divisor that normalizes movement before it becomes deformation.
  final double movementNormalizationFactor;

  /// The deformation, in pixels, produced by a normalized unit of movement.
  final double movementScalePoints;

  /// The smallest scale movement may squash the surface to.
  final double movementMinScale;

  /// The largest scale movement may stretch the surface to.
  final double movementMaxScale;

  /// The spring that carries the deformation once the finger lets go.
  final Spring scaleSpring;

  /// The spring that carries the deformation while the finger is down.
  final Spring trackingSpring;

  /// The divisor that normalizes an interaction pulse.
  final double interactionPulseNormalizationFactor;

  /// The horizontal size of an interaction pulse, in pixels.
  final double interactionPulseScaleX;

  /// The vertical size of an interaction pulse, in pixels.
  final double interactionPulseScaleY;

  /// How far an interaction pulse drifts toward the touch, as a ratio.
  final double interactionPulseDriftRatio;

  /// The opacity of the small touch glow.
  final double littleGlowOpacity;

  /// The opacity of the large touch glow.
  final double bigGlowOpacity;

  /// The push, in seconds, a changed target gives a channel on these
  /// springs ([Spring.impulse]): its velocity grows by the spring's
  /// stiffness times this times the change.
  ///
  /// Read from UIKit, notes private: 0.016 for [menu], 0.032 for
  /// [smallLoupe], zero for the others. [FlexSpec.loupeForSize] keeps zero: a
  /// slider thumb's recorded drift replays best without it (0.136 pt rms,
  /// 0.229 with 0.032).
  final double retargetImpulse;

  /// The spring of a channel the flex drives: [scaleSpring], on
  /// [trackingSpring] while a finger tracks, every changed target pushed by
  /// [retargetImpulse].
  Spring get channelSpring =>
      scaleSpring.copyWith(tracking: trackingSpring, impulse: retargetImpulse);

  /// The class for surfaces whose long side is under [compactLongSideLimit].
  static const ultraSmall = FlexSpec(
    liftScalePoints: 16,
    scaleDistanceThreshold: 2000,
    movementNormalizationFactor: 10000,
    movementScalePoints: 10,
    movementMinScale: 0.9,
    movementMaxScale: 1.1,
    scaleSpring: Spring.response(0.4, dampingRatio: 0.375),
    trackingSpring: Spring.response(0.262, dampingRatio: 0.625),
    littleGlowOpacity: 1,
    bigGlowOpacity: 1,
  );

  /// The small end of the interpolated range, anchored at 44 pixels.
  static const small = FlexSpec(
    liftScalePoints: 16,
    scaleDistanceThreshold: 6000,
    movementNormalizationFactor: 10000,
    movementScalePoints: 10,
    movementMinScale: 0.9,
    movementMaxScale: 1.1,
    scaleSpring: Spring.response(0.4, dampingRatio: 0.375),
    trackingSpring: Spring.response(0.262, dampingRatio: 0.625),
    littleGlowOpacity: 0.3,
    bigGlowOpacity: 1,
  );

  /// The large end of the interpolated range, anchored at 160 pixels.
  static const large = FlexSpec(
    liftScalePoints: 4,
    scaleDistanceThreshold: 24000,
    movementNormalizationFactor: 10000,
    movementScalePoints: 5,
    movementMinScale: 0.9,
    movementMaxScale: 1.1,
    scaleSpring: Spring.response(0.36, dampingRatio: 0.6),
    trackingSpring: Spring.response(0.314, dampingRatio: 0.625),
    littleGlowOpacity: 0.2,
  );

  /// The spec of a button that opens a menu.
  static const menu = FlexSpec(
    liftScalePoints: 0,
    scaleDistanceThreshold: 6000,
    movementNormalizationFactor: 10000,
    movementScalePoints: 5,
    movementMinScale: 0.9,
    movementMaxScale: 1.1,
    scaleSpring: Spring.response(0.6, dampingRatio: 0.5),
    trackingSpring: Spring.response(0.15, dampingRatio: 0.5),
    interactionPulseNormalizationFactor: 8000,
    interactionPulseScaleX: 50,
    interactionPulseScaleY: 32,
    interactionPulseDriftRatio: 0.7,
    littleGlowOpacity: 0.5,
    retargetImpulse: 0.016,
  );

  /// The large end of the loupe range, anchored at 70 pixels.
  static const loupe = FlexSpec(
    liftScalePoints: 0,
    scaleDistanceThreshold: 0,
    movementNormalizationFactor: 2500,
    movementScalePoints: 100,
    movementMinScale: 0.75,
    movementMaxScale: 1.15,
    scaleSpring: Spring.response(0.5),
    trackingSpring: Spring.response(0.5, dampingRatio: 0.9),
  );

  /// The small end of the loupe range, anchored at 37 pixels.
  static const smallLoupe = FlexSpec(
    liftScalePoints: 0,
    scaleDistanceThreshold: 6000,
    movementNormalizationFactor: 2000,
    movementScalePoints: 10,
    movementMinScale: 0.9,
    movementMaxScale: 1.1,
    scaleSpring: Spring.response(0.444, dampingRatio: 0.56),
    trackingSpring: Spring.response(0.444, dampingRatio: 0.56),
    retargetImpulse: 0.032,
  );

  /// Surfaces whose longer side is under this use [ultraSmall].
  static const double compactLongSideLimit = 120;

  /// The dimension [small] is anchored at.
  static const double smallDimension = 44;

  /// The dimension [large] is anchored at.
  static const double largeDimension = 160;

  /// The dimension [smallLoupe] is anchored at.
  static const double smallLoupeDimension = 37;

  /// The dimension [loupe] is anchored at.
  static const double loupeDimension = 70;

  /// The uniform scale of a fully lifted surface of [size]:
  /// `(L + liftScalePoints) / L` on both axes, L its long side, so the
  /// long side grows by [liftScalePoints] and the short side keeps the
  /// proportion. Read from UIKit, notes private.
  double liftScaleFor(Size size) {
    final long = size.longestSide;
    return long > 0 ? (long + liftScalePoints) / long : 1;
  }

  static double _unit(double value, double from, double to) =>
      ((value - from) / (to - from)).clamp(0.0, 1.0);

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}
