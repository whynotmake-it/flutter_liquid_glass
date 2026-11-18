import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/src/motion/clock.dart';

class _Stepped implements MotionFollowed {
  final List<double> steps = [];

  @override
  bool stepTo(double time) {
    steps.add(time);
    return true;
  }

  @override
  double? get wakeTime => null;

  @override
  void publish({required bool widgets}) {}

  @override
  bool get hasWidgetFollowers => false;
}

void main() {
  setUp(MotionClock.debugReset);
  tearDown(MotionClock.debugReset);

  test('a publish callback runs once, after the values stepped', () {
    final clock = ManualMotionClock();
    final driver = _Stepped();
    clock.follow(driver);
    final seen = <List<double>>[];
    clock.schedulePublish(() => seen.add(List.of(driver.steps)));
    clock.advanceTo(0.1);
    clock.advanceTo(0.2);
    expect(seen, [
      [0.1],
    ]);
  });

  test('a publish callback scheduled while publishing runs in that phase', () {
    final clock = ManualMotionClock();
    final heard = <String>[];
    void second() => heard.add('second');
    clock.schedulePublish(() {
      heard.add('first');
      clock.schedulePublish(second);
    });
    clock.advanceTo(0.1);
    expect(heard, ['first', 'second']);
  });

  test('a value commanded while publishing is drawn in that frame', () {
    final clock = ManualMotionClock();
    final title = MotionValue<double>(0, clock: clock);
    final heard = <double>[];
    void listener() => heard.add(title.value);
    title.addListener(listener);
    addTearDown(() => title.removeListener(listener));
    clock.schedulePublish(() => title.snap(clock.now, 1));
    clock.advanceTo(0.1);
    expect(heard, [1]);
  });

  test('a cancelled publish callback never runs', () {
    final clock = ManualMotionClock();
    var runs = 0;
    final cancel = clock.schedulePublish(() => runs++);
    cancel();
    clock.advanceTo(0.1);
    expect(runs, 0);
  });

  testWidgets('a publish callback a ticker asks for runs in its frame', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    var runs = 0;
    var ticks = 0;
    final ticker = const TestVSync().createTicker((_) {
      ticks++;
      MotionClock.instance.schedulePublish(() => runs++);
    });
    addTearDown(ticker.dispose);
    unawaited(ticker.start());
    for (var i = 1; i <= 3; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(runs, ticks);
    }
    ticker.stop();
  });

  testWidgets('a publish callback asked for after the phases of a frame '
      'ran still runs in that frame', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final driver = _Stepped();
    MotionClock.instance.follow(driver);
    await tester.pump(const Duration(milliseconds: 16));
    final stepsBefore = driver.steps.length;
    var runs = 0;
    tester.binding.scheduleFrameCallback((_) {
      scheduleMicrotask(
        () => MotionClock.instance.schedulePublish(() => runs++),
      );
    });
    await tester.pump(const Duration(milliseconds: 16));
    expect(runs, 1);
    expect(driver.steps.length, stepsBefore + 2);
    expect(driver.steps.last, driver.steps[driver.steps.length - 2]);
    MotionClock.instance.unfollow(driver);
  });

  testWidgets('a publish callback outside a frame asks for one frame', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    expect(tester.binding.hasScheduledFrame, isFalse);
    var runs = 0;
    MotionClock.instance.schedulePublish(() => runs++);
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump();
    expect(runs, 1);
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
