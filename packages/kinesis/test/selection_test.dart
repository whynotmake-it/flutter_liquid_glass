import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/testing.dart';

void main() {
  const spring = Spring.response(0.3);
  late ManualMotionClock clock;

  setUp(() => clock = ManualMotionClock());

  test('follows what it reads and publishes once per frame', () {
    final width = MotionValue<double>(10, clock: clock);
    final height = MotionValue<double>(20, clock: clock);
    var computes = 0;
    final area = MotionSelection(() {
      computes++;
      return width.value * height.value;
    }, clock: clock);
    final heard = <double>[];
    area.addListener(() => heard.add(area.value));
    expect(area.value, 200);

    width.retarget(0, 20, spring: spring);
    height.retarget(0, 40, spring: spring);
    computes = 0;
    clock.advanceTo(0.05);
    expect(computes, 1);
    expect(heard, [width.valueAt(0.05) * height.valueAt(0.05)]);
  });

  test('a value read between publishes reaches the listeners even when the '
      'inputs come back before the publish', () {
    final x = MotionSignal<double>(5);
    final source = _Signals(x, clock);
    final read = source.select((_) => x.value);
    final heard = <double>[];
    read.addRenderListener(() => heard.add(read.value));
    clock.advanceTo(0.01);

    x.write(0.01, 0);
    expect(read.value, 0);
    x.write(0.01, 5);
    clock.advanceTo(0.02);

    expect(heard, [5]);
  });

  test('listeners hear only a changed result', () {
    final x = MotionValue<double>(0, clock: clock);
    final past = MotionSelection(() => x.value > 5, clock: clock);
    final heard = <bool>[];
    past.addListener(() => heard.add(past.value));
    x.retarget(0, 10, spring: spring);
    for (var t = 0.01; t < 2; t += 0.01) {
      clock.advanceTo(t);
    }
    expect(heard, [true]);
  });

  test('a computed of computeds recomputes in the same frame', () {
    final x = MotionValue<double>(1, clock: clock);
    final doubled = MotionSelection(() => x.value * 2, clock: clock);
    final quadrupled = MotionSelection(() => doubled.value * 2, clock: clock);
    final heard = <double>[];
    quadrupled.addListener(() => heard.add(quadrupled.value));
    x.snap(0, 3);
    clock.advanceTo(0.01);
    expect(heard, [12]);
  });

  test('without listeners it follows nothing and computes on read', () {
    final x = MotionValue<double>(1, clock: clock);
    var computes = 0;
    final doubled = MotionSelection(() {
      computes++;
      return x.value * 2;
    }, clock: clock);
    x.snap(0, 4);
    clock.advanceTo(0.01);
    expect(computes, 0);
    expect(doubled.value, 8);
    expect(computes, 1);
  });
}

final class _Signals extends Motion {
  _Signals(MotionSignal<double> signal, MotionClock clock)
    : super(clock: clock) {
    own(signal);
  }
}
