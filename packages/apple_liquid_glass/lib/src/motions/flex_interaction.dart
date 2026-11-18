import 'dart:math' as math;
import 'dart:ui';

import 'package:apple_liquid_glass/src/motions/flex_spec.dart';
import 'package:kinesis/motion.dart';
import 'package:meta/meta.dart';

/// The four channels a flex deforms a surface by: the scale of its width
/// and height and the drift of its center.
typedef FlexValues = ({
  double scaleX,
  double scaleY,
  double driftX,
  double driftY,
});

/// The targets of UIKit's flex interaction, the one machine that lifts,
/// stretches and shifts every flexible glass surface under a finger
/// (`GlassPress` runs it), and the menu's variant with its pulse channel
/// ([menuTargets]). Each of the four channels moves on the spec's
/// [FlexSpec.channelSpring] ([chaseFlexChannel]).
@internal
abstract final class FlexInteraction {
  /// The share of the stretch threshold a finger travelling inside the
  /// surface counts: inside, the stretch grows by a quarter of what the
  /// same travel beyond the edge adds. Read from UIKit, notes private;
  /// replayed by the glass button's drag-off captures.
  static const double inBoundsWeight = 0.25;

  /// The slope at which a movement scale enters its soft limit
  /// ([softClamp]). Read from UIKit, notes private.
  static const double softness = 0.55;

  /// A flex at rest.
  static const FlexValues rest = (
    scaleX: 1,
    scaleY: 1,
    driftX: 0,
    driftY: 0,
  );

  /// The targets of UIKit's dynamic flex for a finger on a surface of
  /// [size] with tuning [spec].
  ///
  /// [translation] is the finger's travel since the touch-down,
  /// [inBounds] the same travel with the finger clamped into the surface.
  /// With [lift] both scales start from the lift over the long side L,
  /// `s = (L + liftScalePoints) / L`; with [stretch], along x (y likewise
  /// with H, the scales swapped):
  ///
  /// ```text
  /// kx = |it.x| / (4 T) + (|t.x| - |it.x|) / T   (0 when t.x is 0)
  /// sx = s + kx, sy = s - kx, dx = sign(t.x) kx W
  /// ```
  ///
  /// T the spec's stretch threshold. Read from UIKit, notes private.
  static FlexValues dynamicTargets({
    required FlexSpec spec,
    required Size size,
    required Offset translation,
    required Offset inBounds,
    bool lift = true,
    bool stretch = true,
  }) {
    if (size.width <= 0 || size.height <= 0) return rest;
    final s = lift ? spec.liftScaleFor(size) : 1.0;
    var sx = s;
    var sy = s;
    var dx = 0.0;
    var dy = 0.0;
    final threshold = spec.scaleDistanceThreshold;
    if (stretch && threshold > 0) {
      final kx = stretchOf(translation.dx, inBounds.dx, threshold);
      final ky = stretchOf(translation.dy, inBounds.dy, threshold);
      sx += kx - ky;
      sy += ky - kx;
      dx = _sign(translation.dx) * kx * size.width;
      dy = _sign(translation.dy) * ky * size.height;
    }
    return (scaleX: sx, scaleY: sy, driftX: dx, driftY: dy);
  }

  /// The stretch along one axis of a finger that travelled [travel] since
  /// the touch-down, [inBounds] of it inside the surface:
  /// `|it| / (4 T) + (|t| - |it|) / T`, zero without travel.
  static double stretchOf(double travel, double inBounds, double threshold) {
    if (travel == 0) return 0;
    final inside = inBounds.abs();
    return (inBoundsWeight * inside + travel.abs() - inside) / threshold;
  }

  /// The scales movement may take a surface [extent] long to along that
  /// axis: the spec's movement points either way, within its movement
  /// scale bounds. Read from UIKit, notes private.
  static ({double low, double high}) movementBounds(
    FlexSpec spec,
    double extent,
  ) {
    final points = spec.movementScalePoints;
    return (
      low: math.max(spec.movementMinScale, (extent - points) / extent),
      high: math.min(spec.movementMaxScale, (extent + points) / extent),
    );
  }

  /// [value] eased into [low] .. [high]: unchanged inside, and beyond an
  /// end it approaches a third of the range further out, entering at the
  /// slope [softness]. Read from UIKit, notes private; the easing curve is
  /// a hyperbolic tangent (inferred: the library call's name is not
  /// recoverable, its ends and slope are).
  static double softClamp(double value, double low, double high) {
    final margin = (high - low) / 3;
    if (margin <= 0) return value.clamp(low, high);
    if (value > high) {
      return high + margin * _tanh(softness * (value - high) / margin);
    }
    if (value < low) {
      return low + margin * _tanh(softness * (value - low) / margin);
    }
    return value;
  }

  /// [base] with the movement of a surface of [size] added: [acceleration]
  /// is the filtered rate of change of its speed along each axis and
  /// [velocity] its filtered velocity, as the flex integrator reports
  /// them.
  ///
  /// Along x (y likewise, the axes swapped), with m = a.x / N (N the
  /// spec's movement normalization) and the bounds of [movementBounds]:
  ///
  /// ```text
  /// Lx = soft(1 + m (hiX - 1)), sx += Lx - 1, sy += soft(1 + m (loY - 1)) - 1
  /// dx += (1 - Lx) W / 2 sign(v.x)
  /// ```
  ///
  /// so a surface speeding up grows along its motion, narrows across it
  /// and its trailing edge lags. Read from UIKit, notes private; the
  /// lens deformation measured on UISegmentedControl and UITabBar follows
  /// the same law with [FlexSpec.loupeForSize].
  static FlexValues withMovement(
    FlexValues base, {
    required FlexSpec spec,
    required Size size,
    required Offset acceleration,
    required Offset velocity,
  }) {
    final n = spec.movementNormalizationFactor;
    final x = movementBounds(spec, size.width);
    final y = movementBounds(spec, size.height);
    var (:scaleX, :scaleY, :driftX, :driftY) = base;
    final mx = acceleration.dx / n;
    if (mx != 0 && !mx.isNaN) {
      final along = softClamp(1 + mx * (x.high - 1), x.low, x.high);
      scaleX += along - 1;
      driftX += (1 - along) * 0.5 * size.width * _sign(velocity.dx);
      scaleY += softClamp(1 + mx * (y.low - 1), y.low, y.high) - 1;
    }
    final my = acceleration.dy / n;
    if (my != 0 && !my.isNaN) {
      final along = softClamp(1 + my * (y.high - 1), y.low, y.high);
      scaleY += along - 1;
      driftY += (1 - along) * 0.5 * size.height * _sign(velocity.dy);
      scaleX += softClamp(1 + my * (x.low - 1), x.low, x.high) - 1;
    }
    return (scaleX: scaleX, scaleY: scaleY, driftX: driftX, driftY: driftY);
  }

  /// The targets of UIKit's menu flex: the stretch an open menu of [size]
  /// takes under a finger and its pulse.
  ///
  /// [translation] is the finger's travel from its touch-down, [inBounds]
  /// its travel clamped into the menu, [velocity] the pulse channel's
  /// velocity (its stepped pulse channel) and [side] +1 for a menu below its
  /// button, -1 above it. Along x (y likewise with H):
  ///
  /// ```text
  /// kx = (|t.x| - |it.x| + P |it.x| / W) / T   (0 when t.x is 0)
  /// sx = 1 + kx - ky, sy = 1 - kx + ky
  /// dx = sign(t.x) kx W, dy = sign(t.y) ky H
  /// p = velocity side / pulse normalization
  /// sx *= 1 - pulseX p / W, sy *= 1 + pulseY p / H,
  /// dy += side driftRatio pulseY p
  /// sx, sy clamped to the spec's movement min and max scales
  /// ```
  ///
  /// T the spec's stretch threshold and P [inBoundsPoints]. Read from
  /// UIKit, notes private.
  static FlexValues menuTargets({
    required FlexSpec spec,
    required double inBoundsPoints,
    required Offset translation,
    required Offset inBounds,
    required Size size,
    required double velocity,
    required double side,
  }) {
    double k(double t, double it, double extent) => t == 0
        ? 0
        : (t.abs() - it.abs() + inBoundsPoints * it.abs() / extent) /
              spec.scaleDistanceThreshold;
    final w = size.width;
    final h = size.height;
    final kx = k(translation.dx, inBounds.dx, w);
    final ky = k(translation.dy, inBounds.dy, h);
    final p = velocity * side / spec.interactionPulseNormalizationFactor;
    final sx = (1 + kx - ky) * (1 - p * spec.interactionPulseScaleX / w);
    final sy = (1 - kx + ky) * (1 + p * spec.interactionPulseScaleY / h);
    return (
      scaleX: sx.clamp(spec.movementMinScale, spec.movementMaxScale),
      scaleY: sy.clamp(spec.movementMinScale, spec.movementMaxScale),
      driftX: translation.dx.sign * kx * w,
      driftY:
          translation.dy.sign * ky * h +
          side *
              spec.interactionPulseDriftRatio *
              spec.interactionPulseScaleY *
              p,
    );
  }

  static double _sign(double x) => x.isNegative ? -1 : 1;

  static double _tanh(double x) {
    final e = math.exp(-2 * x.abs());
    final y = (1 - e) / (1 + e);
    return x.isNegative ? -y : y;
  }
}

/// Sends a flex [channel] toward [target] at time [t] on [spring], on its
/// tracking spring when [tracking].
///
/// A target equal to the channel's current one changes nothing, not even
/// the spring, so a finger that holds still never re-anchors the spring or
/// pushes it with [Spring.impulse]. Read from UIKit, notes private; the
/// impulse replays the open menu's channels to the recorded velocity on
/// every retarget (iPhone 16 Pro, iOS 27.0.1).
@internal
void chaseFlexChannel(
  MotionValue<double> channel,
  double t,
  double target,
  Spring spring, {
  bool tracking = false,
}) {
  if (target == channel.target) return;
  channel.retarget(t, target, spring: spring, tracking: tracking);
}
