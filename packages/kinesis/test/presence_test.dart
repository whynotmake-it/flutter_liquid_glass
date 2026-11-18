import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';

const _open = Spring.response(0.4, dampingRatio: 0.7);
const _close = Spring.response(0.25);

class _Card extends Motion {
  late final lift = own(Presence(openSpring: _open, closeSpring: _close));
}

void main() {
  test('opens and hides on its springs; status follows target and rest', () {
    final card = _Card();
    final twin = MotionValue<double>(0, spring: _open);
    expect(card.lift.status, PresenceStatus.hidden);
    card.lift.open(0);
    twin.retarget(0, 1);
    expect(card.lift.status, PresenceStatus.opening);
    card.advance(0.1);
    expect(card.lift.progress, twin.valueAt(0.1));
    card.advance(3);
    expect(card.lift.status, PresenceStatus.shown);
    card.lift.hide(3);
    expect(card.lift.status, PresenceStatus.leaving);
    card.advance(6);
    expect(card.lift.isHidden, isTrue);
  });

  test('turns from where it stands, velocity included', () {
    final card = _Card();
    final twin = MotionValue<double>(0, spring: _open);
    card.lift.open(0);
    twin.retarget(0, 1);
    card.advance(0.05);
    card.lift.hide(0.05);
    twin.retarget(0.05, 0, spring: _close);
    for (final t in [0.08, 0.15, 0.3]) {
      expect(card.lift.progressAt(t), twin.valueAt(t));
    }
  });

  test('a delayed open keeps it hidden until it starts', () {
    final card = _Card();
    card.lift.open(0, delay: 0.2);
    expect(card.lift.status, PresenceStatus.opening);
    expect(card.isSettled, isFalse);
    card.advance(0.1);
    expect(card.lift.progress, 0);
    card.advance(0.3);
    expect(card.lift.progress, greaterThan(0));
  });

  test('opacity clamps an overshoot', () {
    final card = _Card();
    card.lift.snap(0, 1.08);
    expect(card.lift.opacity, 1);
  });
}
