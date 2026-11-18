import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/testing.dart';

void main() {
  const spring = Spring.response(0.4, dampingRatio: 0.8);
  late ManualMotionClock clock;

  setUp(() => clock = ManualMotionClock());
  tearDown(() => MotionTraits.debugPlatformOverride = null);

  MotionValue<double> value([double start = 0]) =>
      MotionValue(start, clock: clock);

  test('outside a transaction a new target jumps', () {
    final v = value();
    v.target = 10;
    expect(v.value, 10);
    clock.advanceTo(0.1);
    expect(v.value, 10);
  });

  test('withSpring moves the value from the clock time', () {
    final v = value();
    clock.advanceTo(1);
    withSpring(spring, () => v.target = 10);
    final reference = MotionValue<double>(0);
    reference.retarget(1, 10, spring: spring);
    clock.advanceTo(1.2);
    expect(v.value, reference.valueAt(1.2));
  });

  test('a second target mid-flight keeps position and velocity', () {
    final v = value();
    withSpring(spring, () => v.target = 10);
    clock.advanceTo(0.1);
    final position = v.value;
    final speed = v.velocity;
    withSpring(spring, () => v.target = 0);
    expect(v.value, position);
    expect(v.velocity, speed);
  });

  test('an enclosing withoutAnimation makes inner springs jump', () {
    final v = value();
    withoutAnimation(() => withSpring(spring, () => v.target = 10));
    expect(v.value, 10);
  });

  test('withoutAnimation inside withSpring jumps', () {
    final v = value();
    withSpring(spring, () => withoutAnimation(() => v.target = 10));
    expect(v.value, 10);
  });

  test('the innermost spring wins', () {
    final v = value();
    const inner = Spring.response(0.2);
    withSpring(spring, () => withSpring(inner, () => v.target = 10));
    expect(v.spring, inner);
  });

  test('Reduce Motion picks the reduced spring', () {
    const reduced = Spring.response(0.25);
    const preferred = Spring.response(0.5, dampingRatio: 0.7, reduced: reduced);
    MotionTraits.debugPlatformOverride = const MotionTraits(reduceMotion: true);
    final v = value();
    withSpring(preferred, () => v.target = 10);
    expect(v.spring, reduced);
  });

  test('tracking follows the tracking spring', () {
    const tracking = Spring.response(0.15, dampingRatio: 0.86);
    const settle = Spring.response(0.4, tracking: tracking);
    final v = value();
    withSpring(settle, () => v.target = 10, tracking: true);
    final reference = MotionValue<double>(0, spring: tracking);
    reference.retarget(0, 10);
    clock.advanceTo(0.05);
    expect(v.value, reference.valueAt(0.05));
  });

  test('a delayed change reads its target at once and moves later', () {
    final v = value();
    withSpring(
      spring,
      () => v.target = 10,
      delay: 0.04,
    );
    expect(v.target, 10);
    clock.advanceTo(0.03);
    expect(v.value, 0);
    clock.advanceTo(0.2);
    expect(v.value, greaterThan(0));
  });

  test('an explicit retarget keeps its own spring inside withSpring', () {
    const measured = Spring.response(0.3, dampingRatio: 0.99);
    final v = value();
    withSpring(spring, () => v.retarget(0, 10, spring: measured));
    expect(v.spring, measured);
  });

  test('writing the current target changes nothing', () {
    final v = value();
    withSpring(spring, () => v.target = 10);
    clock.advanceTo(0.1);
    withSpring(const Spring.response(0.1), () => v.target = 10);
    expect(v.spring, spring);
  });
}
