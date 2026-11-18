import 'package:meta/meta.dart';

/// What a frame did beyond its plan, counted where it happens.
///
/// A renderer adds one to a count each time it does that work, in debug and
/// profile builds; a frame's report reads the counts and starts them again
/// from zero. The counts run from the end of the last reported frame to the
/// end of this one, so they hold what paint recorded and what the scene
/// added too.
@internal
abstract final class GlassWork {
  /// Image filters made.
  static int filters = 0;

  /// Pictures recorded for glass.
  static int pictures = 0;

  /// Images drawn for reads.
  static int images = 0;

  /// Layers a read added again to the scene.
  static int replayed = 0;

  /// Repaints the composer asked for.
  static int marks = 0;

  /// Those of [marks] asked after paint, which land a frame late: the glass
  /// shows its content where it is now and its silhouette, shadows and clip
  /// where they were for one frame.
  static int lateMarks = 0;

  /// Starts every count again from zero.
  static void clear() {
    filters = 0;
    pictures = 0;
    images = 0;
    replayed = 0;
    marks = 0;
    lateMarks = 0;
  }
}
