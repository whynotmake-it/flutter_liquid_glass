import 'package:apple_liquid_glass/src/motions/search_motion.dart';
import 'package:kinesis/motion.dart';

/// The presentation of a search field stacked under a navigation bar: the
/// page and its field move up until the field sits under the status bar,
/// the field narrows and turns to glass, the close button arrives, and the
/// bar's title and items fade out in time, not by how far the page has
/// risen.
///
/// Times are seconds on the clock's timeline.
final class StackedSearchMotion {
  /// Creates the motion of a resting field that fades the bar through
  /// [barFade], 1 there to 0 gone.
  StackedSearchMotion({required this.barFade, MotionClock? clock})
    : shown = MotionValue<double>(
        0,
        spring: SearchTuning.stackedSpring,
        clock: clock,
      ),
      glass = MotionValue<double>(
        0,
        spring: SearchTuning.stackedGlassSpring,
        clock: clock,
      );

  /// How far the field is presented: 0 at rest under the bar, 1 under the
  /// status bar.
  final MotionValue<double> shown;

  /// How far the field's plain fill has turned to glass, 0 to 1.
  final MotionValue<double> glass;

  /// The opacity of the navigation bar's large title and items.
  final MotionValue<double> barFade;

  /// Presents the field at time [t].
  void present(double t) {
    shown.retarget(t, 1);
    glass.retarget(t, 1);
    barFade.retarget(t, 0, spring: SearchTuning.stackedFadeOutSpring);
  }

  /// Sends the field back at time [t].
  void dismiss(double t) {
    shown.retarget(t, 0);
    glass.retarget(t, 0);
    barFade.retarget(
      t,
      1,
      spring: SearchTuning.stackedFadeInSpring,
      delay: SearchTuning.stackedFadeInDelay,
    );
  }
}
