import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';

const _spring = Spring.response(0.35, dampingRatio: 0.8);
const _tall = Spring.response(0.6);

class _Frame extends Motion {
  _Frame(RectSprings springs) : _springs = springs;

  final RectSprings _springs;
  late final rect = own(MotionRect(Rect.zero, springs: _springs));
}

void main() {
  test('one spring for all moves as a MotionValue<Rect>', () {
    final m = _Frame(const RectSprings.all(_spring));
    final twin = MotionValue<Rect>(Rect.zero, spring: _spring);
    const to = Rect.fromLTWH(20, 40, 100, 60);
    m.rect.retarget(0, to);
    twin.retarget(0, to);
    for (final t in [0.05, 0.2, 0.5]) {
      final a = m.rect.valueAt(t);
      final b = twin.valueAt(t);
      expect(a.left, moreOrLessEquals(b.left, epsilon: 1e-9));
      expect(a.top, moreOrLessEquals(b.top, epsilon: 1e-9));
      expect(a.right, moreOrLessEquals(b.right, epsilon: 1e-9));
      expect(a.bottom, moreOrLessEquals(b.bottom, epsilon: 1e-9));
    }
    expect(m.rect.target, to);
  });

  test('each axis moves on its own spring', () {
    final m = _Frame(const RectSprings(center: _spring, height: _tall));
    final height = MotionValue<double>(0, spring: _tall);
    final center = MotionValue<Offset>(Offset.zero, spring: _spring);
    m.rect.retarget(0, const Rect.fromLTWH(0, 0, 80, 80));
    height.retarget(0, 80);
    center.retarget(0, const Offset(40, 40));
    final r = m.rect.valueAt(0.15);
    expect(r.height, moreOrLessEquals(height.valueAt(0.15), epsilon: 1e-9));
    expect(
      r.center.dx,
      moreOrLessEquals(center.valueAt(0.15).dx, epsilon: 1e-9),
    );
    expect(m.rect.restTime(), height.restTime(MotionRest.length));
  });

  test('a delayed retarget is due, and the rect rests after it', () {
    final m = _Frame(const RectSprings.all(_spring));
    m.rect.retarget(0, const Rect.fromLTWH(0, 0, 10, 10), delay: 0.3);
    expect(m.rect.nextDue, 0.3);
    expect(m.rect.restTime(), isNull);
    m.advance(3);
    expect(m.isSettled, isTrue);
    m.settle();
    expect(m.rect.valueAt(3), const Rect.fromLTWH(0, 0, 10, 10));
  });
}
