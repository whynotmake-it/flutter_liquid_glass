import 'dart:ui';

import 'package:apple_liquid_glass/src/motions/bar_frames.dart';
import 'package:apple_liquid_glass/src/motions/bar_motion.dart';
import 'package:flutter_test/flutter_test.dart';

GlassBarCapsuleLayout _capsule(List<String> items) {
  const rect = Rect.fromLTWH(300, 62, 88, 44);
  final step = rect.width / items.length;
  return GlassBarCapsuleLayout(
    'trailing',
    rect,
    [
      for (var k = 0; k < items.length; k++)
        GlassBarItemLayout(
          items[k],
          Rect.fromLTWH(rect.left + k * step, rect.top, step, rect.height),
        ),
    ],
    segment: 'trailing',
  );
}

void main() {
  test('an item that takes the place of another beside one that stays '
      'changes with it in place', () {
    final motion = GlassBarMotion()
      ..setLayout(0, [
        _capsule(['drop', 'gear']),
      ])
      ..setLayout(1, [
        _capsule(['square', 'gear']),
      ]);
    for (var t = 1.0; t < 2; t += 1 / 60) {
      motion.advance(t);
      final frames = {for (final f in motion.items) f.id: f};
      expect(frames['square']!.center.dx, closeTo(322, 0.01), reason: 't=$t');
      expect(frames['gear']!.center.dx, closeTo(366, 0.01), reason: 't=$t');
      if (frames['drop'] case final drop?) {
        expect(drop.center.dx, closeTo(322, 0.01), reason: 't=$t');
      }
    }
  });

  test('the old and the new item blur and fade through each other', () {
    final motion = GlassBarMotion()
      ..setLayout(0, [
        _capsule(['drop', 'gear']),
      ])
      ..setLayout(1, [
        _capsule(['square', 'gear']),
      ])
      ..advance(1.15);
    final frames = {for (final f in motion.items) f.id: f};
    expect(frames['drop']!.leaving, isTrue);
    expect(frames['drop']!.blur, greaterThan(0));
    expect(frames['drop']!.presence, lessThan(1));
    expect(frames['square']!.blur, greaterThan(0));
    expect(frames['square']!.presence, lessThan(1));
    expect(frames['gear']!.blur, 0);
    expect(frames['gear']!.presence, 1);
  });

  test('when every item of a capsule changes, the ones that leave still '
      'meet at its center', () {
    final motion = GlassBarMotion()
      ..setLayout(0, [
        _capsule(['drop', 'gear']),
      ])
      ..setLayout(1, [
        _capsule(['square', 'bell']),
      ])
      ..advance(1.2);
    final frames = {for (final f in motion.items) f.id: f};
    expect(frames['drop']!.center.dx, greaterThan(323));
    expect(frames['gear']!.center.dx, lessThan(365));
  });
}
