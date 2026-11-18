import 'package:kinesis/motion.dart';

/// The content offset of whichever scroll view a bar follows, held as a
/// signal so values derived from it (a title that scrolls away) follow it
/// on the clock without a rebuild.
///
/// The host writes the offset ([offset]) when the scroll view moves; a
/// plain signal has no listeners, which is why the offset sits in a motion
/// that `Motion.select` can derive from.
final class ContentOffsetMotion extends Motion {
  /// Creates the motion, stepped by [clock] or the ambient one.
  ContentOffsetMotion({super.clock});

  /// The latest offset of the content, in logical pixels past its start.
  late final MotionSignal<double> offset = own(MotionSignal(0));
}
