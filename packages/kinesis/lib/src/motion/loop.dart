import 'package:flutter/foundation.dart';
import 'package:kinesis/src/motion/clock.dart';
import 'package:kinesis/src/motion/motion.dart';
import 'package:kinesis/src/motion/part.dart';

/// A per-frame filter on frames of its own: UIKit's display-link loops,
/// measured at a fixed [rate] (the lens's stretch at 120 Hz) or at the
/// rate of the display, stepped at the same times whatever the host
/// renders.
///
/// Frames are numbered from zero at `k / rate` seconds. The owning motion
/// runs the loop as it advances, every frame at its own time between its
/// reactions, so a replay at any sampling steps the same frames. A loop
/// sleeps once [step] answers false and runs again from [wake].
///
/// ```dart
/// final class StretchLoop extends MotionLoop {
///   StretchLoop() : super(rate: 120);
///
///   @override
///   bool step(double t) {
///     ...
///     return moving;
///   }
/// }
/// ```
abstract class MotionLoop extends MotionPart {
  /// Creates a loop that steps [rate] times per second of motion time, or
  /// at the frame rate of the clock that steps its motion when [rate] is
  /// null, and at most [maxFrames] frames per advance.
  MotionLoop({double? rate, this.maxFrames = 600})
    : _fixedRate = rate,
      assert(rate == null || rate > 0, 'a loop ticks forward'),
      assert(maxFrames > 0, 'a loop steps');

  final double? _fixedRate;
  double? _wokenRate;

  /// The frames per second of motion time: the rate given, or else the
  /// frame rate of the clock that steps the owning motion
  /// ([Motion.clock]), read when the loop wakes and kept until it wakes
  /// again, so the frames of one run keep their spacing.
  double get rate => _fixedRate ?? _wokenRate ?? _clockRate;

  double get _clockRate => (owner?.clock ?? MotionClock.instance).frameRate;

  /// The length of one frame, in seconds.
  double get frame => 1 / rate;

  /// The most frames one advance steps through; earlier frames of a
  /// longer gap are skipped. A loop that must reach its rest after any gap
  /// allows the frames it takes to rest.
  final int maxFrames;

  int _last = 0;
  bool _moving = false;
  double _restAt = double.negativeInfinity;

  /// Whether the loop steps as its motion advances.
  bool get isMoving => _moving;

  /// The time of the frame the loop last stepped, or of the one it woke
  /// at; the next frame it steps follows it.
  double get lastFrame => _last / rate;

  /// Steps the loop from the first frame after [t] on, if it slept.
  void wake(double t) {
    if (_moving) return;
    if (_fixedRate == null) _wokenRate = _clockRate;
    _last = _index(t);
    _moving = true;
    changed();
  }

  /// One frame at time [t]; answers whether the loop needs another.
  @protected
  bool step(double t);

  /// Steps every frame after the last one up to [t], or up to just before
  /// [t] when [before], in order.
  @internal
  void run(double t, {bool before = false}) {
    if (!_moving) return;
    final end = before ? (t * rate - 1e-6).ceil() - 1 : _index(t);
    var k = _last + 1;
    if (end - k >= maxFrames) k = end - maxFrames + 1;
    for (; k <= end; k++) {
      final s = k / rate;
      if (!step(s)) {
        _last = k;
        _moving = false;
        _restAt = s;
        return;
      }
    }
    if (end > _last) _last = end;
  }

  int _index(double t) => (t * rate + 1e-6).floor();

  /// The frame the loop last slept at, or null while it steps.
  @override
  double? restTime([double? tolerance]) => _moving ? null : _restAt;

  @override
  bool restsAt(double t, [double? tolerance]) => !_moving;

  /// Declares the loop at rest from [t]. A loop with something to put in
  /// place once it rests (a filter to re-prime, a deformation to snap off)
  /// does it here, and calls super.
  @override
  @mustCallSuper
  void restFrom(double t) {}

  @override
  double? get nextDue => null;
}
