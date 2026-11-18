import 'package:apple_liquid_glass/src/motions/sheet_detent.dart';
import 'package:apple_liquid_glass/src/motions/sheet_layout.dart';
import 'package:apple_liquid_glass/src/motions/sheet_motion.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';

const _layout = SheetLayout(
  size: Size(402, 874),
  padding: EdgeInsets.only(top: 62, bottom: 34),
  detents: [GlassSheetDetent.large, GlassSheetDetent.medium],
  selected: GlassSheetDetent.medium,
);

SheetMotion _shown() {
  final motion = SheetMotion.presented();
  motion.open(0);
  motion.layout(0, _layout);
  motion.advance(3);
  return motion;
}

void main() {
  group('before its first layout', () {
    test('an opened sheet is opening, an unopened one hidden', () {
      final motion = SheetMotion.presented();
      expect(motion.isLaidOut, isFalse);
      expect(motion.presence, PresenceStatus.hidden);
      motion.open(0);
      expect(motion.presence, PresenceStatus.opening);
    });

    test('a leave ends the presentation and the sheet never shows', () {
      final motion = SheetMotion.presented();
      motion.open(0);
      expect(motion.leave(0.1, DismissTrigger.programmatic), isFalse);
      expect(motion.presence, PresenceStatus.hidden);
      motion.layout(0.2, _layout);
      motion.advance(3);
      expect(motion.offset, motion.hiddenOffset);
    });

    test('the first layout presents an opened sheet', () {
      final motion = SheetMotion.presented();
      motion.open(0);
      motion.layout(0, _layout);
      expect(motion.presence, PresenceStatus.opening);
      motion.advance(3);
      expect(motion.presence, PresenceStatus.shown);
      expect(motion.offset, closeTo(0, 1e-9));
      // Medium is the smaller of the two: the layout sorts them.
      expect(motion.index, 0);
      expect(motion.detentAt(0), 1);
      expect(motion.dockedIndex, 1);
    });
  });

  group('a keyboard', () {
    test('raises every detent by its height, up to the maximum', () {
      final motion = _shown();
      const maximum = 874.0 - 62 - 34;
      final medium = motion.heights[0];
      motion.layout(3, _layout.copyWith(keyboard: 300));
      expect(motion.heights, [medium + 300, maximum + 34]);
    });

    test('takes the sheet to its largest detent, unreported', () {
      final motion = _shown();
      motion.layout(3, _layout.copyWith(keyboard: 300));
      expect(motion.index, 1);
      motion.advance(5);
      expect(motion.drainEvents(), isEmpty);
      expect(motion.height, closeTo(motion.heights[1], 1e-9));
    });

    test('hiding returns the sheet to the selected detent, unreported', () {
      final motion = _shown();
      motion.layout(3, _layout.copyWith(keyboard: 300));
      motion.advance(5);
      motion.layout(5, _layout);
      expect(motion.index, 0);
      motion.advance(7);
      expect(motion.drainEvents(), isEmpty);
      expect(motion.height, closeTo(motion.heights[0], 1e-9));
    });

    test('a layout that changes only the selected detent does nothing', () {
      final motion = _shown();
      motion.layout(3, _layout.copyWith(selected: GlassSheetDetent.large));
      expect(motion.index, 0);
      expect(motion.isSettled, isTrue);
    });
  });
}
