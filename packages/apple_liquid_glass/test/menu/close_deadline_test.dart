import 'package:apple_liquid_glass/src/motions/menu_event.dart';
import 'package:apple_liquid_glass/src/motions/menu_motion.dart';
import 'package:apple_liquid_glass/src/motions/menu_tuning.dart';
import 'package:apple_liquid_glass/src/motions/menu_values.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';

const _button = Rect.fromLTWH(24, 80, 44, 44);
const _outside = Offset(350, 500);

MenuMotion _motion({MenuTuning tuning = MenuTuning.standard}) => MenuMotion(
  source: MenuSource(_button),
  bounds: const Size(402, 874),
  itemCount: 3,
  tuning: tuning,
);

/// Opens [motion] by a tap at 0 and feeds the release that requests the
/// close: [input] is outside, on a row, or one of them before the menu
/// appeared. Returns the time the close comes due.
double _request(MenuMotion motion, String input) {
  if (input.startsWith('early')) {
    motion.pointerDown(0, _button.center);
    motion.pointerUp(0.01, _button.center);
    motion.pointerDown(0.02, _outside);
    motion.pointerUp(
      0.03,
      input == 'early row' ? const Offset(60, 110) : _outside,
    );
    return 0.01 + motion.tuning.tapOpenDelay + motion.tuning.earlyCloseDelay;
  }
  motion.open(0);
  motion.advance(1);
  final position = input == 'selection'
      ? motion.menuBlob.rrect.outerRect.center
      : _outside;
  motion.pointerDown(1.01, position);
  motion.pointerUp(1.02, position);
  return 1.02 + motion.tuning.dismissDelay;
}

void main() {
  for (final input in ['outside', 'selection', 'early outside', 'early row']) {
    test('$input closes at its deadline, after the action it chose', () {
      final motion = _motion();
      final due = _request(motion, input);
      motion.drainEvents();
      motion.advance(due - 1e-6);
      expect(motion.isOpen, isTrue);
      expect(motion.isClosing, isFalse);
      final progress = motion.progress;
      motion.advance(due);
      expect(motion.isClosing, isTrue);
      expect(motion.progress, closeTo(progress, 1e-4));
      expect(
        [
          for (final e in motion.drainEvents())
            if (e case MenuActivated(:final index)) index,
        ],
        switch (input) {
          'selection' => [1],
          'early row' => [0],
          _ => isEmpty,
        },
      );
      for (var t = due; t < due + 1.5; t += 1 / 60) {
        motion.advance(t);
      }
      expect(motion.isPresented, isFalse);
    });
  }

  test('the morph asks for every vsync of a fast display', () {
    expect(_motion().minFrameRate, greaterThan(FrameCadence.fullFloor));
  });

  test('explicit close is a command at its own time', () {
    final motion = _motion();
    motion.open(0);
    motion.advance(1);
    motion.close(1.1);
    expect(motion.now, 1.1);
    expect(motion.isClosing, isTrue);
    motion.advance(3);
    expect(motion.isPresented, isFalse);
  });
}
