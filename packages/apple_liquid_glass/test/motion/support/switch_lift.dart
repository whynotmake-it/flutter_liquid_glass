import 'package:apple_liquid_glass/src/motions/small_lens.dart';
import 'package:apple_liquid_glass/src/motions/switch_motion.dart';

/// Seconds a switch knob's lens lift needs to reach [progress].
double timeToLift(double progress) {
  final lens = SmallLens(
    restSize: SwitchMotion.knobSize,
    liftedSize: SwitchMotion.liftedKnobSize,
    frameRate: 60,
  );
  lens.lift(0);
  var lo = 0.0;
  var hi = 0.2;
  for (var i = 0; i < 50; i++) {
    final mid = (lo + hi) / 2;
    if (lens.progress(mid) < progress) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return lo;
}
