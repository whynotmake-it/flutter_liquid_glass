import 'package:kinesis/src/motion/motion.dart';
import 'package:kinesis/src/motion/rest.dart';
import 'package:kinesis/src/motion/spring.dart';
import 'package:kinesis/src/motion/value.dart';

/// Where a [Presence] stands.
enum PresenceStatus {
  /// At rest at 0.
  hidden,

  /// Heading to 1.
  opening,

  /// At rest at 1.
  shown,

  /// Heading to 0.
  leaving,
}

/// A progress from 0 (hidden) to 1 (shown) on an open spring and a close
/// spring, turning from where it stands, velocity included.
///
/// The [status] follows from the target and rest alone, so a motion keeps
/// no flag of its own for "dismissing".
///
/// ```dart
/// late final lift = own(Presence(openSpring: .bouncy));
/// lift.open(t);
/// final scale = 1 + 0.06 * lift.progress;
/// ```
final class Presence extends Motion {
  /// Creates a hidden presence that opens on [openSpring], hides on
  /// [closeSpring] ([openSpring] when null) and rests within [rest].
  Presence({
    required this.openSpring,
    Spring? closeSpring,
    this.rest = MotionRest.opacity,
  }) : closeSpring = closeSpring ?? openSpring;

  /// The spring toward 1.
  final Spring openSpring;

  /// The spring toward 0.
  final Spring closeSpring;

  /// How close to 0 or 1 the progress rests.
  final double rest;

  late final MotionValue<double> _progress = own(
    MotionValue<double>(0, spring: openSpring),
    rest: () => rest,
  );

  /// Opens at [t], or [delay] seconds later.
  void open(double t, {double delay = 0}) =>
      _progress.retarget(t, 1, spring: openSpring, delay: delay);

  /// Hides at [t], or [delay] seconds later.
  void hide(double t, {double delay = 0}) =>
      _progress.retarget(t, 0, spring: closeSpring, delay: delay);

  /// Jumps to [progress] at [t], at rest.
  void snap(double t, double progress) => _progress.snap(t, progress);

  /// The progress at [now], 0 to 1 and past it on a bouncy spring.
  double get progress => _progress.valueAt(now);

  /// The progress at [t].
  double progressAt(double t) => _progress.valueAt(t);

  /// The progress at [now] as an opacity, 0 to 1.
  double get opacity => progress.clamp(0.0, 1.0);

  /// Where the presence stands at [now].
  PresenceStatus get status {
    final shown = _progress.target > 0.5;
    final rests = _progress.restsAt(now, rest) && _progress.nextDue == null;
    if (shown) return rests ? PresenceStatus.shown : PresenceStatus.opening;
    return rests ? PresenceStatus.hidden : PresenceStatus.leaving;
  }

  /// Whether the presence is hidden and at rest.
  bool get isHidden => status == PresenceStatus.hidden;
}
