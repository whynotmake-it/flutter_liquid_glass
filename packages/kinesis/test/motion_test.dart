import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';

const _bouncy = Spring.response(0.4, dampingRatio: 0.6);
const _glow = Spring.response(0.6);

class _Pair extends Motion {
  late final a = own(MotionValue<double>(0, spring: _bouncy));
  late final b = own(MotionValue<double>(0, spring: _glow));
  final List<(String, double)> log = [];
  bool held = false;

  @override
  bool get holds => held;

  void schedule(double t, String name, {Object? slot}) =>
      at(t, (t) => log.add((name, t)), slot: slot);

  void react(double t, void Function() action) => at(t, (_) => action());

  void drop(Object slot) => unschedule(slot);

  void dropAll() => unscheduleAll();

  bool waits(Object slot) => isScheduled(slot);

  void letGo(MotionPart part) => disown(part);

  void hold({required bool held}) {
    this.held = held;
    changed();
  }
}

class _Outer extends Motion {
  late final inner = own(_Pair());

  void later(double t, void Function() action, {Object? slot}) =>
      at(t, (_) => action(), slot: slot);
  late final fade = own(
    MotionValue<double>(0, spring: _glow),
    rest: () => MotionRest.opacity,
  );
}

void main() {
  group('Motion', () {
    testWidgets("a command that only changes state of the motion's own "
        'reaches its followed selections', (tester) async {
      final m = _Pair();
      final held = m.select((m) => m.held);
      void listener() {}
      held.addListener(listener);
      expect(held.value, isFalse);
      m.hold(held: true);
      expect(held.value, isTrue);
      held.removeListener(listener);
    });

    test('a disowned part no longer keeps the motion from resting', () {
      final m = _Pair();
      m.a.retarget(0, 1);
      expect(m.restsAt(0.01), isFalse);
      m.letGo(m.a);
      expect(m.restsAt(0.01), isTrue);
      expect(m.a.owner, isNull);
    });

    test('the cursor only moves forward', () {
      final m = _Pair();
      m.advance(0.5);
      m.advance(0.2);
      expect(m.now, 0.5);
    });

    test('reactions run at their own times, in order, however coarse the '
        'step', () {
      final m = _Pair();
      m.schedule(0.3, 'c');
      m.schedule(0.1, 'a');
      m.schedule(0.1, 'b');
      m.advance(1);
      expect(m.log, [('a', 0.1), ('b', 0.1), ('c', 0.3)]);
      expect(m.now, 1);
    });

    test('a reaction due by now runs right away at now', () {
      final m = _Pair();
      m.advance(0.4);
      m.schedule(0.2, 'late');
      expect(m.log, [('late', 0.4)]);
    });

    test('a slot keeps one reaction; cancel drops it', () {
      final m = _Pair();
      m.schedule(0.2, 'first', slot: #land);
      m.schedule(0.3, 'second', slot: #land);
      expect(m.waits(#land), isTrue);
      m.advance(1);
      expect(m.log, [('second', 0.3)]);
      m.schedule(1.2, 'gone', slot: #land);
      m.drop(#land);
      m.advance(2);
      expect(m.log, [('second', 0.3)]);
    });

    test('slots belong to their motion: dropping or refilling a slot leaves '
        'an equal slot of another motion on the timeline alone', () {
      const slot = Object();
      final outer = _Outer();
      final seen = <String>[];
      outer.later(0.25, () => seen.add('outer'), slot: slot);
      outer.inner.schedule(0.2, 'inner', slot: slot);
      outer.inner.schedule(0.3, 'inner again', slot: slot);
      outer.inner.drop(slot);
      expect(outer.inner.waits(slot), isFalse);
      outer.advance(1);
      expect(seen, ['outer']);
      expect(outer.inner.log, isEmpty);
    });

    test('unscheduleAll drops only the reactions the motion scheduled', () {
      final outer = _Outer();
      final other = _Pair();
      outer.inner.schedule(0.2, 'mine', slot: #a);
      outer.inner.schedule(0.3, 'mine too');
      outer.later(0.25, () => other.log.add(('outer', 0.25)));
      outer.inner.dropAll();
      outer.advance(1);
      expect(outer.inner.log, isEmpty);
      expect(other.log, [('outer', 0.25)]);
    });

    test('a command a reaction gives at its time leaves the reactions due '
        'with it in their order', () {
      final m = _Pair();
      m.schedule(0.1, 'first');
      m.react(0.2, () {
        m.advance(0.2);
        m.log.add(('second', m.now));
      });
      m.schedule(0.2, 'third');
      m.advance(1);
      expect(m.log, [('first', 0.1), ('second', 0.2), ('third', 0.2)]);
    });

    test('an owned motion shares the cursor and the timeline', () {
      final outer = _Outer();
      outer.inner.schedule(0.2, 'inner');
      expect(outer.isSettled, isFalse);
      outer.advance(0.5);
      expect(outer.inner.now, 0.5);
      expect(outer.inner.log, [('inner', 0.2)]);
    });

    test('settles when every part rests and nothing waits or holds', () {
      final m = _Pair();
      m.a.retarget(0, 10);
      expect(m.isSettled, isFalse);
      m.advance(5);
      expect(m.isSettled, isTrue);
      m.held = true;
      expect(m.isSettled, isFalse);
      m.held = false;
      m.schedule(6, 'later');
      expect(m.isSettled, isFalse);
      expect(m.wakeTime, 6);
    });

    test('settle declares only the parts that rest; the others keep their '
        'course exactly', () {
      final m = _Pair();
      final twin = MotionValue<double>(0, spring: _glow);
      m.a.retarget(0, 10);
      m.b.retarget(0, 100);
      twin.retarget(0, 100);
      final aRest = m.a.restTime()!;
      final bRest = m.b.restTime()!;
      expect(bRest, greaterThan(aRest));
      final t = (aRest + bRest) / 2;
      m.advance(t);
      m.settle();
      expect(m.a.valueAt(t), 10);
      expect(m.a.velocityAt(t), 0);
      for (final s in [t, t + 0.05, bRest - 0.01]) {
        expect(m.b.valueAt(s), twin.valueAt(s));
      }
    });

    test('a part rests within the tolerance given to own', () {
      final outer = _Outer();
      outer.fade.retarget(0, 1);
      final loose = outer.fade.restTime(MotionRest.opacity)!;
      final tight = outer.fade.restTime(1e-6)!;
      expect(loose, lessThan(tight));
      outer.advance(loose + 1e-6);
      expect(outer.restTime(), closeTo(loose, 1e-9));
    });
  });
}
