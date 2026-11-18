import 'package:apple_liquid_glass/src/motions/menu_context_hold.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a resting finger commits and opens at its hold times exactly, '
      'however coarse the steps', () {
    final commits = <double>[];
    final opens = <(double, double)>[];
    late final ContextHold hold;
    hold = ContextHold(
      onCommit: () => commits.add(hold.now),
      onOpen: (t, growth) => opens.add((t, growth)),
    );
    hold.down(1);
    hold.advance(1.3);
    expect(hold.growth, closeTo(32 * (0.3 - 0.184), 1e-9));
    hold.advance(2);
    expect(commits, [closeTo(1.42, 1e-9)]);
    expect(opens, hasLength(1));
    expect(opens.single.$1, closeTo(1.78, 1e-9));
    expect(opens.single.$2, closeTo(8 + 20 * (0.78 - 0.434), 1e-9));
    expect(hold.isHeld, isFalse);
    expect(hold.growth, 0);
    expect(hold.isSettled, isTrue);
  });

  test('a release drops the view back at once and opens nothing', () {
    var opened = false;
    final hold = ContextHold(onCommit: () {}, onOpen: (_, _) => opened = true);
    hold.down(0);
    hold.advance(0.3);
    expect(hold.isCommitted, isFalse);
    expect(hold.release(0.35), closeTo(32 * (0.35 - 0.184), 1e-9));
    expect(hold.growth, 0);
    hold.advance(2);
    expect(opened, isFalse);
    expect(hold.isSettled, isTrue);
  });

  test('a hold past the commit is committed until it ends', () {
    final hold = ContextHold(onCommit: () {}, onOpen: (_, _) {});
    hold.down(0);
    hold.advance(0.5);
    expect(hold.isCommitted, isTrue);
    hold.release(0.5);
    expect(hold.isCommitted, isFalse);
  });

  test('the growth law matches the measured knee and cap', () {
    expect(ContextHold.growthAfter(0.184), 0);
    expect(ContextHold.growthAfter(0.434), closeTo(8, 1e-9));
    expect(ContextHold.growthAfter(5), 15);
  });
}
