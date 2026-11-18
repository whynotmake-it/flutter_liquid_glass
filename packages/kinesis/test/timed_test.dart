import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';

class _Fade extends Motion {
  _Fade({this._additive = false});

  final bool _additive;
  late final value = own(TimedValue(0, additive: _additive));
}

void main() {
  test('runs a curve over its duration and rests at its end', () {
    final m = _Fade();
    m.value.animate(0, 1, duration: 0.5, curve: Curves.easeInOut);
    expect(m.value.valueAt(0.25), Curves.easeInOut.transform(0.5));
    expect(m.value.restTime(), 0.5);
    expect(m.value.restsAt(0.3), isFalse);
    m.advance(0.5);
    expect(m.isSettled, isTrue);
    expect(m.value.valueAt(0.7), 1);
  });

  test('a plain value turns from where its course has it when the next '
      'curve starts', () {
    final m = _Fade();
    m.value.animate(0, 1, duration: 1);
    m.value.animate(0.2, 0, duration: 1, delay: 0.3);
    expect(m.value.valueAt(0.4), moreOrLessEquals(0.4, epsilon: 1e-12));
    expect(m.value.valueAt(0.5), moreOrLessEquals(0.5, epsilon: 1e-12));
    expect(m.value.valueAt(1), moreOrLessEquals(0.25, epsilon: 1e-12));
    expect(m.value.target, 0);
  });

  test('additive curves sum on top of each other', () {
    final m = _Fade(additive: true);
    m.value.animate(0, 10, duration: 1);
    m.value.animate(0.5, 20, duration: 1);
    expect(m.value.target, 20);
    expect(m.value.valueAt(0.5), moreOrLessEquals(5, epsilon: 1e-12));
    expect(m.value.valueAt(1), moreOrLessEquals(15, epsilon: 1e-12));
    expect(m.value.valueAt(1.5), 20);
  });

  test('a delayed curve rests until it is due, and the motion dozes until '
      'then', () {
    final m = _Fade();
    m.value.animate(0, 1, duration: 0.2, delay: 0.5);
    expect(m.value.restsAt(0.1), isTrue);
    expect(m.isSettled, isFalse);
    expect(m.wakeTime, 0.5);
    m.advance(1);
    m.settle();
    expect(m.value.valueAt(1), 1);
  });
}
