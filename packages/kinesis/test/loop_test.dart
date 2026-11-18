import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/testing.dart';

final class _Filter extends MotionLoop {
  _Filter(this.input, {super.rate = 120});

  final MotionValue<double> input;
  double value = 0;
  final List<double> frames = [];
  int primed = 0;

  @override
  bool step(double t) {
    frames.add(t);
    value += (input.valueAt(t) - value) * 0.3;
    return (input.valueAt(t) - value).abs() > 1e-3 || !input.restsAt(t);
  }

  @override
  void restFrom(double t) {
    super.restFrom(t);
    primed++;
  }
}

class _Lens extends Motion {
  _Lens({super.clock, this.rate = 120});

  final double? rate;
  late final knob = own(MotionValue<double>(0, spring: Spring.snappy));
  late final filter = own(_Filter(knob, rate: rate));
  final List<(double, double)> seen = [];

  void move(double t, double to) {
    knob.retarget(t, to);
    filter.wake(t);
    at(t + 0.05, (t) => seen.add((t, filter.value)), slot: #probe);
  }
}

void main() {
  test('steps every frame at its own time whatever the host samples', () {
    final runs = <List<double>>[];
    final random = Random(5);
    for (final rate in [60.0, 120.0, 47.0, 1.0]) {
      final lens = _Lens();
      lens.move(0.003, 100);
      var t = 0.0;
      while (t < 2) {
        t += 1 / rate * (0.5 + random.nextDouble());
        lens.advance(t);
      }
      lens.advance(2);
      runs.add([...lens.filter.frames.take(40), lens.seen.single.$2]);
    }
    for (final run in runs.skip(1)) {
      expect(run, runs.first);
    }
    expect(runs.first.first, 1 / 120);
  });

  test('a reaction sees the frames before it, not the one at its time', () {
    final lens = _Lens();
    lens.move(0, 10);
    lens.advance(1);
    final (t, seen) = lens.seen.single;
    expect(t, 0.05);
    expect(lens.filter.frames.where((f) => f < t - 1e-9).length, 5);
    expect(seen, isNot(lens.filter.value));
  });

  test('sleeps once a step answers false; the motion settles and the rest '
      'side effect runs once', () {
    final lens = _Lens();
    lens.move(0, 10);
    lens.advance(5);
    expect(lens.filter.isMoving, isFalse);
    final frames = lens.filter.frames.length;
    lens.advance(6);
    expect(lens.filter.frames.length, frames);
    expect(lens.isSettled, isTrue);
    lens.settle();
    expect(lens.filter.primed, 1);
  });

  test('a long gap steps only the last frames the loop allows', () {
    final lens = _Lens();
    lens.move(0, 10);
    lens.advance(0.1);
    lens.filter.frames.clear();
    lens.advance(100);
    expect(lens.filter.frames.first, moreOrLessEquals(11401 / 120));
  });

  test('wakes from the first frame after the command', () {
    final lens = _Lens();
    lens.move(0, 10);
    lens.advance(5);
    lens.move(7.001, 20);
    expect(lens.filter.lastFrame, moreOrLessEquals(840 / 120, epsilon: 1e-12));
    lens.advance(7.1);
    expect(
      lens.filter.frames.firstWhere((f) => f > 5),
      moreOrLessEquals(841 / 120, epsilon: 1e-12),
    );
    expect(lens.filter.lastFrame, lens.filter.frames.last);
  });

  test('a loop with no rate steps at the rate of the clock that steps its '
      'motion, read when it wakes', () {
    final clock = ManualMotionClock(frameRate: 60);
    final lens = _Lens(clock: clock, rate: null);
    expect(lens.filter.rate, 60);
    lens.move(0, 10);
    lens.advance(0.1);
    expect(lens.filter.frames.take(3), [1 / 60, 2 / 60, 3 / 60]);
  });
}
