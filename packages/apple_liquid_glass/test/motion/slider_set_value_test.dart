import 'package:apple_liquid_glass/src/motions/slider_motion.dart';
import 'package:flutter_test/flutter_test.dart';

// The fill end of a 300 pt glass UISlider after setValue(0.9, animated:
// true) from 0.1, per display-link tick (seconds after the call, points),
// iOS 27.0 simulator, 60 Hz. The motion starts 0.010 s after the call.
const _native = <(double, double)>[
  (0.0303, 53.53),
  (0.0470, 70.33),
  (0.0637, 91.66),
  (0.0803, 114.81),
  (0.0970, 137.85),
  (0.1137, 159.53),
  (0.1303, 179.13),
  (0.1470, 196.25),
  (0.1637, 210.80),
  (0.1803, 222.84),
  (0.1970, 232.56),
  (0.2137, 240.21),
  (0.2470, 250.45),
  (0.2803, 255.74),
  (0.3137, 257.93),
  (0.3470, 258.39),
  (0.3970, 257.68),
  (0.4470, 256.65),
  (0.4970, 255.87),
  (0.5970, 255.20),
];

const double _start = 0.010;

void main() {
  test('an animated setValue replays the native spring', () {
    final motion = SliderMotion(width: 300, value: 0.1, frameRate: 60);
    motion.advance(0);
    motion.setValue(_start, 0.9, animated: true);
    expect(motion.reportedValue, 0.9);
    var worst = 0.0;
    for (final (t, fill) in _native) {
      motion.advance(t);
      final error = (motion.fillEnd - fill).abs();
      if (error > worst) worst = error;
    }
    expect(worst, lessThan(1.0));
    motion.advance(3);
    expect(motion.position, closeTo(0.9, 1e-6));
    expect(motion.isAnimatingValueChange, isFalse);
  });

  test('the duration does not depend on the distance', () {
    double halfway(double from, double to) {
      final motion = SliderMotion(width: 300, value: from);
      motion.advance(0);
      motion.setValue(0, to, animated: true);
      var t = 0.0;
      while ((motion.position - from).abs() < (to - from).abs() / 2) {
        t += 0.001;
        motion.advance(t);
      }
      return t;
    }

    expect(halfway(0.3, 0.31), closeTo(halfway(0.1, 0.9), 0.002));
  });

  test('a plain setValue jumps and a stepped slider always jumps', () {
    final motion = SliderMotion(width: 300, value: 0.1);
    motion.advance(0);
    motion.setValue(0, 0.9);
    expect(motion.position, 0.9);
    final stepped = SliderMotion(width: 300, value: 0, ticks: 5);
    stepped.advance(0);
    stepped.setValue(0, 0.5, animated: true);
    expect(stepped.position, 0.5);
  });

  test('a press on the moving thumb takes over from where it shows', () {
    final motion = SliderMotion(width: 300, value: 0.1);
    motion.advance(0);
    motion.setValue(0, 0.9, animated: true);
    motion.advance(0.1);
    final shown = motion.position;
    motion.pointerDown(0.1, motion.thumbCenter);
    motion.advance(0.5);
    expect(motion.position, closeTo(shown, 1e-9));
  });
}
