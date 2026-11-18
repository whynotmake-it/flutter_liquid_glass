import 'package:kinesis/motion.dart';

/// The spokes of an activity indicator, stepping round from [start].
///
/// The brightest spoke ([head]) advances once per eighth of a second, a
/// turn a second, as UIKit's medium activity indicator does.
final class ActivityMotion extends Motion {
  /// Creates the motion, stepped by [clock] or the ambient one.
  ActivityMotion({super.clock});

  /// The number of spokes the indicator draws.
  static const spokes = 8;

  late final _loop = own(_ActivityLoop());

  /// The brightest spoke now.
  int get head => _loop.head;

  /// Starts the turn at [t].
  void start(double t) {
    _loop.start = t;
    _loop.wake(t);
  }
}

final class _ActivityLoop extends MotionLoop {
  double start = 0;
  int head = 0;

  @override
  bool step(double t) {
    head =
        ((t - start) * ActivityMotion.spokes).floor() % ActivityMotion.spokes;
    return true;
  }
}
