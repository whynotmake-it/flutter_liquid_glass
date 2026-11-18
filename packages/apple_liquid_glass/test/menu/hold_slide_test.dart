import 'package:apple_liquid_glass/src/motions/menu_motion.dart';
import 'package:apple_liquid_glass/src/motions/menu_values.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'menu_events.dart';

const _button = Rect.fromLTWH(160, 200, 80, 44);

void main() {
  test('a finger held on the source opens the menu at the hold, slides '
      'into the rows and chooses the one it lifts from', () {
    final motion = MenuMotion(
      source: MenuSource(_button),
      bounds: const Size(402, 874),
      itemCount: 4,
    );
    const frame = 1 / 120;
    final hold = motion.tuning.holdDuration;
    motion.pointerDown(0, _button.center);
    var t = 0.0;
    while (t + frame < hold) {
      t += frame;
      motion.advance(t);
      expect(motion.isOpen, isFalse);
    }
    motion.advance(hold);
    expect(motion.isOpen, isTrue);
    for (t = hold; t < hold + 0.6; t += frame) {
      motion.advance(t);
    }
    final menu = motion.menuBlob.rrect.outerRect;
    var at = _button.center;
    while (motion.highlighted != 2 && at.dy < menu.bottom) {
      t += frame;
      at = Offset(menu.center.dx, at.dy + 2);
      motion.pointerMove(t, at);
    }
    expect(motion.highlighted, 2);
    expect(menuSelections(motion), isEmpty);
    motion.pointerUp(t + frame, at);
    final selections = <int>[];
    for (var s = t + frame; s < t + 1.5; s += frame) {
      motion.advance(s);
      selections.addAll(menuSelections(motion));
    }
    expect(selections, [2]);
    expect(motion.isPresented, isFalse);
  });
}
