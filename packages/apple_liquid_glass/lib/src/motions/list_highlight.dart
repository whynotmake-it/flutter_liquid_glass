import 'package:flutter/animation.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/motion.dart';

/// The highlight of a tappable list row (UIKit `UITableViewCell` in a
/// table).
///
/// Inside a scroll view the highlight waits [touchDelay] after the touch
/// went down; a tap released sooner shows it at the release. It appears
/// at full strength, without a fade. A scroll that takes the touch removes
/// it at once. A tap's release fades it out over [fadeDuration] on
/// [fadeCurve]: UIKit keeps the tapped row selected until the app
/// deselects it, and this is `deselectRow(at:animated: true)`, the fade of
/// the standard tap handler.
///
/// As a [PointerFollower] it shows at the touch's arrival: a region inside
/// a scroll view delivers the touch once the scroll's delay has passed, or
/// at its release if that comes sooner.
///
/// Measured on the iOS 27.0 simulator (UITableView inset grouped, taps
/// and holds through XCUITest, 60 Hz): the delay is the scroll view's
/// `_touchDelayForScrollDetection`, 0.15 s, read from UIKit (notes
/// private), and the highlight showed 0.155 - 0.166 s after the touch (one
/// frame later); the fade is the CABasicAnimation UIKit adds, read from
/// the layer. Times are seconds.
final class ListRowHighlight extends Motion implements PointerFollower {
  /// The delay between a touch and the highlight inside a scroll view.
  static const double touchDelay = 0.15;

  /// The duration of the fade after a tap.
  static const double fadeDuration = 0.5;

  /// The curve of the fade after a tap: UIKit's ease-in-ease-out.
  static const Curve fadeCurve = Curves.easeInOut;

  late final _opacity = own(TimedValue(0));
  bool _shown = false;

  /// How strongly the row shows highlighted, 0 to 1.
  double get opacity => _opacity.valueAt(now);

  /// At [t] the touch that went down at [contact] becomes a tap: the
  /// highlight shows [delay] after the contact, or at once when that has
  /// passed.
  void press(double t, {required double contact, double delay = touchDelay}) {
    advance(t);
    _shown = true;
    final at = contact + delay;
    _opacity.animate(t, 1, duration: 0, delay: at > t ? at - t : 0);
  }

  /// The tap was released at [t]: a highlight not shown yet shows now, and
  /// it fades out.
  void fadeOut(double t) {
    advance(t);
    if (!_shown) return;
    _shown = false;
    _opacity.snap(t, 1);
    _opacity.animate(t, 0, duration: fadeDuration, curve: fadeCurve);
  }

  /// The touch went to a scroll at [t]: the highlight goes at once.
  void clear(double t) {
    advance(t);
    _shown = false;
    _opacity.snap(t, 0);
  }

  @override
  void down(PointerDownInput input) =>
      press(input.time, contact: input.contactTime, delay: 0);

  @override
  void move(PointerMoveInput input) {}

  @override
  void up(PointerUpInput input) => fadeOut(input.time);

  @override
  void cancel(PointerCancelInput input) => clear(input.time);

  @override
  void hover(PointerHoverInput input) {}
}
