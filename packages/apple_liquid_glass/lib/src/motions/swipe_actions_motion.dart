import 'package:kinesis/motion.dart';

/// How far a swiped row is moved toward its trailing edge (negative), and
/// the extents it settles between.
///
/// Not measured: the spring and [fullSwipeShare] are chosen by eye, as
/// UIKit's swipe actions were not captured on iOS 27.
final class SwipeActionsMotion extends Motion {
  /// Creates the motion of a row at rest.
  SwipeActionsMotion({super.clock});

  static const _spring = Spring.smooth;

  /// The share of the row's width a release must pass to perform the
  /// first action.
  static const double fullSwipeShare = 0.6;

  /// How far the row is moved.
  late final offset = own(MotionValue<double>(0));

  /// The width of the row at the last layout.
  double rowWidth = 0;

  /// The width of the row's actions at the last layout.
  double actionsWidth = 0;

  /// Whether the finger can pull the row across its whole width, so that a
  /// release past [fullSwipeShare] can perform the first action; otherwise
  /// the row stretches past its actions only on the band.
  bool fullSwipe = true;

  double _grab = 0;

  RubberBand get _band => RubberBand(
    fullSwipe ? -rowWidth : -actionsWidth,
    0,
    dimension: rowWidth,
  );

  /// Where a released row lands: the projection of the spring it settles
  /// on.
  Projection get projection => Projection.of(_spring);

  /// A finger takes the row where it is shown at time [t].
  void grab(double t) {
    _grab = _band.unshow(offset.valueAt(t));
  }

  /// The finger that took the row has moved [translation] along it by time
  /// [t]; past its extents the row follows on a rubber band.
  void drag(double t, double translation) {
    advance(t);
    offset.snap(t, _band.show(_grab + translation));
  }

  /// The finger lets go at time [t] with [velocity], and says where the
  /// row goes: it settles open or closed where the release projects, or,
  /// with [fullSwipe] and when [canPerform], sweeps off the row's whole
  /// width ([ProjectionExited]) when the release projects past
  /// [fullSwipeShare] of it.
  ProjectionChoice release(
    double t,
    double velocity, {
    required bool canPerform,
  }) {
    final choice = projection.choose(
      offset.valueAt(t),
      velocity,
      stops: [0, -actionsWidth],
      exits: [
        if (fullSwipe && canPerform)
          ProjectionExit(threshold: -fullSwipeShare * rowWidth, sign: -1),
      ],
    );
    switch (choice) {
      case ProjectionExited():
        moveTo(t, -rowWidth, velocity: velocity);
      case ProjectionStop(:final value):
        moveTo(t, value, velocity: velocity);
    }
    return choice;
  }

  /// The row settles at [value] from time [t], carrying [velocity].
  void moveTo(double t, double value, {double velocity = 0}) {
    advance(t);
    if (velocity != 0) offset.setVelocity(t, velocity);
    offset.retarget(t, value, spring: _spring);
  }
}
