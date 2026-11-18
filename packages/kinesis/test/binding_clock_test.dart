import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/src/motion/clock.dart';

class _Stepped implements MotionFollowed {
  _Stepped({this.frames = 1 << 30});

  int frames;
  double? wake;
  final List<double> steps = [];

  @override
  bool stepTo(double time) {
    steps.add(time);
    frames--;
    return frames > 0;
  }

  @override
  double? get wakeTime {
    final at = wake;
    if (at == null || steps.isEmpty || steps.last >= at) return null;
    return at;
  }

  @override
  void publish({required bool widgets}) {}

  @override
  bool get hasWidgetFollowers => false;
}

Future<void> _dilated(double dilation, Future<void> Function() body) async {
  final original = timeDilation;
  timeDilation = dilation;
  try {
    await body();
  } finally {
    timeDilation = original;
  }
}

void main() {
  setUp(MotionClock.debugReset);
  tearDown(MotionClock.debugReset);

  testWidgets('a value at rest asks for no frames', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final value = MotionValue<double>(0);
    var heard = 0;
    value.addListener(() => heard++);
    withSpring(const Spring.response(0.2), () => value.target = 100);
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();
    expect(heard, greaterThan(1));
    expect(value.value, 100);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
  });

  for (final rate in [60, 120]) {
    for (final dilation in [1.0, 5.0]) {
      for (final tickerFirst in [true, false]) {
        testWidgets('a ticker reads the time its frame steps at, $rate Hz, '
            '${dilation}x, ${tickerFirst ? 'ticker' : 'clock'} first', (
          tester,
        ) async {
          await tester.pumpWidget(const SizedBox());
          await _dilated(dilation, () async {
            final clock = MotionClock.instance;
            final driver = _Stepped();
            final read = <double>[];
            final ticker = const TestVSync().createTicker((_) {
              read.add(clock.now);
            });
            addTearDown(ticker.dispose);
            if (tickerFirst) {
              unawaited(ticker.start());
              clock.follow(driver);
            } else {
              clock.follow(driver);
              unawaited(ticker.start());
            }
            final frame = Duration(
              microseconds: (1e6 / rate * dilation).round(),
            );
            for (var i = 0; i < 12; i++) {
              await tester.pump(frame);
            }
            ticker.stop();
            clock.unfollow(driver);
            final steps = driver.steps;
            for (var i = 2; i < steps.length; i++) {
              expect(read[i], steps[i]);
              expect(steps[i] - steps[i - 1], closeTo(1 / rate, 1e-6));
            }
            await tester.pump(frame);
            expect(tester.binding.hasScheduledFrame, isFalse);
          });
        });
      }
    }
  }

  testWidgets('a value that waits dozes on a timer, and the doze counts', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    const frame = Duration(microseconds: 16667);
    final clock = MotionClock.instance;
    final driver = _Stepped();
    clock.follow(driver);
    await tester.pump(frame);
    final start = driver.steps.single;
    driver.wake = start + 0.5;
    await tester.pump(frame);
    expect(driver.steps, hasLength(2));
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pump(const Duration(milliseconds: 200));
    expect(driver.steps, hasLength(2));
    for (var i = 0; i < 40; i++) {
      await tester.pump(frame);
    }
    expect(driver.steps.length, greaterThan(3));
    final woken = driver.steps[2];
    expect(woken, greaterThan(start + 0.5 - 1 / 60));
    expect(woken, lessThan(start + 0.5 + 2 / 60));
    clock.unfollow(driver);
    await tester.pump(frame);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('phases still queued when the frame draws, as on the web, '
      'run before it', (tester) async {
    await tester.pumpWidget(const SizedBox());
    const frame = Duration(microseconds: 16667);
    final clock = MotionClock.instance;
    final driver = _Stepped();
    clock.follow(driver);
    await tester.pump(frame);
    driver.wake = driver.steps.single + 0.5;
    // The test binding pumps its frames itself; the engine's callbacks are
    // set only for this one frame, delivered as the web engine does.
    final binding = tester.binding;
    final dispatcher = binding.platformDispatcher;
    dispatcher.onBeginFrame = binding.handleBeginFrame;
    dispatcher.onDrawFrame = binding.handleDrawFrame;
    dispatcher.onBeginFrame!(binding.currentSystemFrameTimeStamp + frame);
    expect(driver.steps, hasLength(1));
    dispatcher.onDrawFrame!();
    dispatcher.onBeginFrame = null;
    dispatcher.onDrawFrame = null;
    expect(driver.steps, hasLength(2));
    await tester.idle();
    expect(driver.steps, hasLength(2));
    expect(binding.hasScheduledFrame, isFalse);
    for (var i = 0; i < 40; i++) {
      await tester.pump(frame);
    }
    expect(driver.steps.length, greaterThan(2));
    clock.unfollow(driver);
    await tester.pump(frame);
  });

  testWidgets('a change ends a doze', (tester) async {
    await tester.pumpWidget(const SizedBox());
    const frame = Duration(microseconds: 16667);
    final clock = MotionClock.instance;
    final driver = _Stepped();
    clock.follow(driver);
    await tester.pump(frame);
    driver.wake = driver.steps.single + 1;
    await tester.pump(frame);
    expect(tester.binding.hasScheduledFrame, isFalse);
    final value = MotionValue<double>(0);
    value.addListener(() {});
    withSpring(const Spring.response(0.2), () => value.target = 1);
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump(frame);
    await tester.pump(frame);
    expect(value.value, greaterThan(0));
    clock.unfollow(driver);
    await tester.pumpAndSettle();
  });

  testWidgets('a wake in a frame of the last frame time starts counting '
      'from it', (tester) async {
    await tester.pumpWidget(const SizedBox());
    const frame = Duration(milliseconds: 100);
    final clock = MotionClock.instance;
    final first = _Stepped(frames: 2);
    clock.follow(first);
    await tester.pump(frame);
    await tester.pump(frame);
    final slept = clock.now;
    final second = _Stepped(frames: 3);
    clock.follow(second);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(second.steps, [slept, closeTo(slept + 0.06, 1e-9)]);
    clock.unfollow(first);
    clock.unfollow(second);
  });

  testWidgets('under a fake frame clock, time asleep does not count', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    const frame = Duration(microseconds: 16667);
    final clock = MotionClock.instance;
    final first = _Stepped(frames: 3);
    clock.follow(first);
    for (var i = 0; i < 5; i++) {
      await tester.pump(frame);
    }
    final slept = clock.now;
    await tester.pump(const Duration(seconds: 3));
    expect(clock.now, slept);
    final second = _Stepped(frames: 2);
    clock.follow(second);
    await tester.pump(frame);
    expect(second.steps.single, closeTo(slept, 0.02));
    clock.unfollow(first);
    clock.unfollow(second);
  });

  testWidgets('where frame stamps follow the engine clock, time asleep '
      'counts, a touch held still included', (tester) async {
    Duration engine() => Duration(
      microseconds: tester.binding.clock.now().microsecondsSinceEpoch,
    );
    MotionClock.debugEngineNow = engine;
    MotionClock.debugPointerClockOffset = () => Duration.zero;
    addTearDown(() {
      MotionClock.debugEngineNow = null;
      MotionClock.debugPointerClockOffset = null;
    });
    await tester.pumpWidget(const SizedBox());
    const frame = Duration(microseconds: 16667);
    final clock = MotionClock.instance;
    final first = _Stepped(frames: 3);
    clock.follow(first);
    for (var i = 0; i < 5; i++) {
      await tester.pump(frame);
    }
    expect(tester.binding.hasScheduledFrame, isFalse);
    final slept = clock.now;
    await tester.pump(const Duration(seconds: 3));
    expect(clock.now, closeTo(slept + 3, 0.001));
    expect(clock.stamp(engine()), closeTo(slept + 3, 0.02));
    final second = _Stepped(frames: 2);
    clock.follow(second);
    await tester.pump(frame);
    expect(second.steps.first, closeTo(slept + 3 + 1 / 60, 0.02));
    clock.unfollow(first);
    clock.unfollow(second);
  });

  testWidgets('touches while asleep keep their spacing, slowed by '
      'timeDilation', (tester) async {
    await tester.pumpWidget(const SizedBox());
    await _dilated(2, () async {
      final clock = MotionClock.instance;
      final down = clock.stamp(const Duration(seconds: 100));
      final up = clock.stamp(const Duration(seconds: 100, milliseconds: 80));
      expect(up - down, closeTo(0.04, 1e-9));
      await tester.pump(const Duration(milliseconds: 16));
      expect(clock.now, greaterThanOrEqualTo(up));
      await tester.pumpAndSettle();
    });
  });

  testWidgets('timeDilation slows a spring', (tester) async {
    await tester.pumpWidget(const SizedBox());
    await _dilated(5, () async {
      final value = MotionValue<double>(0);
      value.addListener(() {});
      withSpring(const Spring.response(0.2), () => value.target = 1);
      final start = value.clock.now;
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 500));
      expect(value.clock.now - start, closeTo(0.1, 0.01));
      await tester.pumpAndSettle();
    });
  });

  testWidgets('scheduled actions run at their own time', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final clock = MotionClock.instance;
    final ran = <double>[];
    final due = clock.now + 0.05;
    clock.schedule(due, ran.add);
    await tester.pump(const Duration(milliseconds: 16));
    expect(ran, isEmpty);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(ran, [due]);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
