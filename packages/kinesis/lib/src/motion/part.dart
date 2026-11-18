import 'package:kinesis/src/motion/motion.dart';
import 'package:meta/meta.dart';

/// Something a `Motion` owns and moves on its time cursor: a spring value,
/// a timed value, a rect, a loop or a smaller motion.
///
/// Rest is a property of the part's course, not a change: [restTime] says
/// from when nothing visible moves, and [restFrom] declares it, so a
/// command stamped before that time still starts from the course at its own
/// time.
abstract class MotionPart {
  /// The motion that owns this part ([Motion.own]), told of every change
  /// the part makes so its root wakes on the clock.
  @internal
  Motion? owner;

  /// Tells the owning motion that the part changed, so its root wakes on
  /// the clock; a part calls it after every command that moves it.
  @protected
  void changed() => owner?.partChanged();

  /// The earliest time from which every component stays within [tolerance]
  /// of where it comes to rest, or null while a change of the part's own
  /// is pending ([nextDue]). A null [tolerance] is the part's own rest.
  double? restTime([double? tolerance]);

  /// Whether nothing visible moves at [t] until [nextDue]: the part is
  /// within [tolerance] now, though a pending change of its own may move it
  /// later.
  bool restsAt(double t, [double? tolerance]);

  /// Declares the part at rest from [t], which is no earlier than
  /// [restTime]: reads at or after [t] answer where it comes to rest, with
  /// no velocity. The course is kept, so a later command stamped before [t]
  /// starts from the course at its own time; the declaration only rounds
  /// what is drawn, by less than the part's rest.
  void restFrom(double t);

  /// The time of the part's next change of its own (a delayed retarget, a
  /// timed value's end), or null.
  double? get nextDue;
}
