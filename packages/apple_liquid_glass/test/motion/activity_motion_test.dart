import 'package:apple_liquid_glass/motions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/testing.dart';

void main() {
  test('the head steps once per eighth of a second from the start', () {
    final spin = ActivityMotion(clock: ManualMotionClock(frameRate: 60));
    spin.start(2);
    spin.advance(2);
    expect(spin.head, 0);
    for (var i = 1; i <= 10; i++) {
      spin.advance(2 + i / 8 + 0.01);
      expect(spin.head, i % ActivityMotion.spokes);
    }
  });
}
