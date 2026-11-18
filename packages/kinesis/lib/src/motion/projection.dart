import 'package:flutter/foundation.dart';
import 'package:kinesis/src/motion/spring.dart';

/// Where a release lands and what it picks: the position plus the velocity
/// times [rate], the nearest of a set of stops, or an exit it passes (a
/// sheet's dismiss, a page's pop).
///
/// ```dart
/// final choice = Projection.of(SheetTuning.spring).choose(
///   offset,
///   velocity,
///   stops: detents,
///   exits: [ProjectionExit(threshold: hidden / 2, flickVelocity: 1000)],
/// );
/// ```
@immutable
final class Projection {
  /// Creates a projection [rate] seconds ahead; a projected travel shorter
  /// than [minDistance] is dropped, so a slow release lands where it is.
  const Projection({required this.rate, this.minDistance = 0});

  /// The projection of [spring] ([Spring.projection]).
  Projection.of(Spring spring, {this.minDistance = 0})
    : rate = spring.projection;

  /// How many seconds of the release velocity the landing adds.
  final double rate;

  /// The shortest projected travel that counts.
  final double minDistance;

  /// Where a release at [position] moving at [velocity] lands.
  double landing(double position, double velocity) {
    final ahead = velocity * rate;
    return ahead.abs() < minDistance ? position : position + ahead;
  }

  /// What a release at [position] moving at [velocity] picks: the first of
  /// [exits] it passes, in order, or else the stop nearest its [landing]
  /// (the lower index on a tie).
  ProjectionChoice choose(
    double position,
    double velocity, {
    List<double> stops = const [],
    List<ProjectionExit> exits = const [],
  }) {
    final lands = landing(position, velocity);
    for (final exit in exits) {
      if (exit.passes(lands, velocity)) return ProjectionExited(exit);
    }
    assert(stops.isNotEmpty, 'a release that exits nowhere needs a stop');
    var best = 0;
    for (var i = 1; i < stops.length; i++) {
      if ((stops[i] - lands).abs() < (stops[best] - lands).abs()) best = i;
    }
    return ProjectionStop(best, stops[best]);
  }

  @override
  bool operator ==(Object other) =>
      other is Projection &&
      other.rate == rate &&
      other.minDistance == minDistance;

  @override
  int get hashCode => Object.hash(rate, minDistance);
}

/// A way out of a release: a landing past [threshold] in the direction of
/// [sign], or a flick that way faster than [flickVelocity].
@immutable
final class ProjectionExit {
  /// Creates an exit past [threshold] toward [sign] (1 for growing, -1 for
  /// shrinking positions).
  const ProjectionExit({
    required this.threshold,
    this.sign = 1,
    this.flickVelocity,
  }) : assert(sign == 1 || sign == -1, 'an exit lies one way');

  /// The landing past which the release exits.
  final double threshold;

  /// The direction of the exit: 1 or -1.
  final int sign;

  /// The speed toward [sign] that exits wherever the release lands; none
  /// when null.
  final double? flickVelocity;

  /// Whether a release that lands at [landing], moving at [velocity],
  /// takes this exit.
  bool passes(double landing, double velocity) {
    if (sign * (landing - threshold) > 0) return true;
    final flick = flickVelocity;
    return flick != null && sign * velocity > flick;
  }

  @override
  bool operator ==(Object other) =>
      other is ProjectionExit &&
      other.threshold == threshold &&
      other.sign == sign &&
      other.flickVelocity == flickVelocity;

  @override
  int get hashCode => Object.hash(threshold, sign, flickVelocity);
}

/// What [Projection.choose] picks.
sealed class ProjectionChoice {
  const ProjectionChoice();
}

/// The release settles on stop [index], at [value].
final class ProjectionStop extends ProjectionChoice {
  /// Creates the choice of stop [index].
  const ProjectionStop(this.index, this.value);

  /// The index of the stop in the list given to [Projection.choose].
  final int index;

  /// The stop itself.
  final double value;
}

/// The release takes [exit].
final class ProjectionExited extends ProjectionChoice {
  /// Creates the choice of [exit].
  const ProjectionExited(this.exit);

  /// The exit taken.
  final ProjectionExit exit;
}
