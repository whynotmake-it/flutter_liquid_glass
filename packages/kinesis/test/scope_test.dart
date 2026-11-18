import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';
import 'package:kinesis/testing.dart';

const _spring = Spring.response(0.4, dampingRatio: 0.6);

class _Card extends Motion {
  _Card({super.clock});

  late final x = own(MotionValue<double>(0, spring: _spring));
  late final fade = own(
    MotionValue<double>(0, spring: const Spring.response(0.3)),
    rest: () => MotionRest.opacity,
  );

  void show(double t) {
    x.retarget(t, 100);
    at(t + 0.1, (t) => fade.retarget(t, 1), slot: #fade);
  }
}

void main() {
  group('MotionClock.input', () {
    test('the ambient time inside is the stamp; inputs commit in arrival '
        'order', () {
      final clock = ManualMotionClock(start: 1);
      final seen = <double>[];
      clock.input(0.98, () => seen.add(clock.now));
      clock.input(0.97, () => seen.add(clock.now));
      seen.add(clock.now);
      expect(seen, [0.98, 0.98, 1]);
    });

    test('withSpring inside an input starts at the stamp', () {
      final clock = ManualMotionClock(start: 1);
      final value = MotionValue<double>(0, clock: clock);
      final reference = MotionValue<double>(0);
      clock.input(0.98, () => withSpring(_spring, () => value.target = 10));
      reference.retarget(0.98, 10, spring: _spring);
      expect(value.valueAt(1.2), reference.valueAt(1.2));
    });
  });

  group('Motion on the clock', () {
    test('a selection steps the root while it moves and drops it at rest', () {
      final clock = ManualMotionClock();
      final card = _Card(clock: clock);
      final x = card.select((m) => m.x.valueAt(m.now));
      final heard = <double>[];
      x.addListener(() => heard.add(x.value));
      card.show(0);
      clock.advanceTo(clock.frameTime + 1 / 120);
      expect(heard.single, card.x.valueAt(1 / 120));
      for (var i = 0; i < 400; i++) {
        clock.advanceTo(clock.frameTime + 1 / 120);
      }
      expect(card.isSettled, isTrue);
      expect(heard.last, 100);
      final frames = heard.length;
      clock.advanceTo(clock.frameTime + 1);
      expect(heard.length, frames);
      expect(card.fade.valueAt(card.now), 1);
    });

    test('a selection is heard only when its value changes', () {
      final clock = ManualMotionClock();
      final card = _Card(clock: clock);
      final moving = card.select((m) => m.x.valueAt(m.now) > 50);
      var heard = 0;
      moving.addListener(() => heard++);
      card.show(0);
      for (var i = 0; i < 200; i++) {
        clock.advanceTo(clock.frameTime + 1 / 120);
      }
      expect(heard, 1);
      expect(moving.value, isTrue);
    });

    test('a read right after a command answers it before the frame '
        'publishes it', () {
      final clock = ManualMotionClock();
      final card = _Card(clock: clock);
      final x = card.select((m) => m.x.target);
      final heard = <double>[];
      x.addListener(() => heard.add(x.value));
      card.show(0);
      expect(x.value, 100);
      expect(heard, isEmpty);
      clock.advanceTo(clock.frameTime + 1 / 120);
      expect(heard, [100]);
    });

    test('reads are the same whatever frames ran (E1)', () {
      final random = Random(3);
      final reads = <List<double>>[];
      for (final rate in [60.0, 120.0, 47.0]) {
        final clock = ManualMotionClock(frameRate: rate);
        final card = _Card(clock: clock);
        final selection = card.select((m) => m.x.valueAt(m.now));
        selection.addListener(() {});
        card.show(0);
        while (clock.now < 2) {
          clock.advanceTo(
            clock.frameTime + 1 / rate * (0.5 + random.nextDouble()),
          );
        }
        reads.add([
          for (final t in [0.0, 0.05, 0.13, 0.4, 0.9, 1.5]) card.x.valueAt(t),
          for (final t in [0.1, 0.2, 0.5]) card.fade.valueAt(t),
        ]);
      }
      expect(reads[1], reads[0]);
      expect(reads[2], reads[0]);
    });
  });

  group('MotionScope', () {
    testWidgets('holds the motion on the clock and resumes exactly after a '
        'muted TickerMode', (tester) async {
      MotionClock.debugReset();
      final card = _Card();
      final twin = _Card();
      Widget scope({required bool enabled}) => TickerMode(
        enabled: enabled,
        child: MotionScope(motion: card, child: const SizedBox()),
      );
      await tester.pumpWidget(scope(enabled: true));
      final start = MotionClock.instance.now;
      card.show(start);
      twin.show(start);
      await tester.pump(const Duration(milliseconds: 50));
      expect(card.now, greaterThan(start));
      await tester.pumpWidget(scope(enabled: false));
      final muted = card.now;
      await tester.pump(const Duration(milliseconds: 200));
      expect(card.now, muted);
      await tester.pumpWidget(scope(enabled: true));
      await tester.pump(const Duration(milliseconds: 16));
      final t = card.now;
      expect(t, greaterThan(muted));
      twin.advance(t);
      expect(card.x.valueAt(t), twin.x.valueAt(t));
      expect(card.fade.valueAt(t), twin.fade.valueAt(t));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('gives the motion the traits of its place', (tester) async {
      final card = _Card();
      await tester.pumpWidget(
        MotionTraitsOverride(
          traits: const MotionTraits(reduceMotion: true),
          child: MotionScope(motion: card, child: const SizedBox()),
        ),
      );
      expect(card.traits.reduceMotion, isTrue);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('MotionClockScope', () {
    testWidgets('gives its clock to the states below, from initState on, '
        'and the binding clock without a scope', (tester) async {
      final clock = ManualMotionClock(start: 3);
      final read = <MotionClock>[];
      await tester.pumpWidget(
        MotionClockScope(
          clock: clock,
          child: _ClockReader(read.add),
        ),
      );
      expect(read, [clock]);
      expect(read.single.now, 3);
      read.clear();
      await tester.pumpWidget(_ClockReader(read.add));
      expect(read, [MotionClock.instance]);
    });
  });
}

class _ClockReader extends StatefulWidget {
  const _ClockReader(this.onClock);

  final ValueChanged<MotionClock> onClock;

  @override
  State<_ClockReader> createState() => _ClockReaderState();
}

class _ClockReaderState extends State<_ClockReader> {
  @override
  void initState() {
    super.initState();
    widget.onClock(MotionClockScope.of(context));
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
