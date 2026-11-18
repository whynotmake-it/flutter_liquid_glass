import 'package:apple_liquid_glass/src/motions/ui_frame_rate.dart';
import 'package:kinesis/motion.dart';
import 'package:meta/meta.dart';

/// The measured tuning and geometry of an iOS 27 alert
/// (UIAlertController with the alert style).
@internal
abstract final class AlertTuning {
  /// The spring of every alert animation: the dimming, the alert's opacity
  /// and its scale, presenting and dismissing. UIKit runs a
  /// CASpringAnimation of stiffness 522.35 and damping 45.71, mass 1:
  /// response 0.275 s, critically damped.
  static const spring = Spring.response(0.2749);

  /// The scale an alert presents from: it shrinks from this size to its
  /// own while it fades in (fitted 1.199 on an iPhone 16 Pro, 0.02
  /// percent rms; 1.196 on the simulator). A dismissing alert only fades.
  static const double presentScale = 1.199;
}

/// The motion of an iOS 27 alert: the dimming, the alert's opacity and its
/// scale.
///
/// Presenting, the alert fades in with the dimming while it shrinks from
/// [AlertTuning.presentScale] to its size; dismissing, it fades out
/// with the dimming at its size. Both run on [AlertTuning.spring],
/// and a dismissal in the middle of the presentation reverses from where
/// the alert stands, velocity included.
///
/// Under Reduce Motion (the motion's [Motion.traits]) the alert does not
/// shrink: it fades in at its size on the same spring. Read from UIKit, notes
/// private: UIAlertController starts the presentation at scale 1 instead
/// of 1.2 under Reduce Motion and keeps the timing.
///
/// Times are seconds on the motion's timeline.
///
/// The fade and the dimming rest within [MotionRest.opacity], the scale
/// within [MotionRest.scale] of the alert's width (NEAR, invisible).
///
/// Android's predictive back runs the dismissal under the finger: the
/// alert and the dimming fade with the gesture's progress at the alert's
/// size, a commit fades the rest on the spring from the gesture's
/// velocity, and a cancel springs back to shown. Android has no alert of
/// iOS's to measure, so this is the dismissal's own path, not a recording.
class AlertMotion extends PresentedProgress {
  /// Creates the motion of an alert that is not shown yet.
  AlertMotion()
    : super(openSpring: AlertTuning.spring, rest: MotionRest.opacity);

  /// The width of an alert in points; the scale rests within a tolerance of
  /// it.
  static const double width = 320;

  @override
  double get minFrameRate => uikitMinFrameRate;

  late final _scale = own(
    MotionValue<double>(
      AlertTuning.presentScale,
      spring: AlertTuning.spring,
    ),
    rest: () => MotionRest.scale(AlertMotion.width),
  );

  /// Starts presenting the alert at time [t]: from hidden it shrinks from
  /// [AlertTuning.presentScale] again, from a dismissal it turns where it
  /// stands.
  @override
  void open(double t) {
    advance(t);
    if (presence == PresenceStatus.hidden) {
      _scale.snap(t, AlertTuning.presentScale);
    }
    super.open(t);
    _scale.retarget(t, 1);
  }

  /// The opacity of the dimming, as a fraction of
  /// the opacity of the black dimming behind the alert.
  double get dimming => opacity;

  @override
  double get scale => traits.reduceMotion ? 1 : _scale.valueAt(now);
}
