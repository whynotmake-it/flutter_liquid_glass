import 'package:apple_liquid_glass/src/motions/sheet_event.dart';
import 'package:apple_liquid_glass/src/motions/sheet_motion.dart';
import 'package:apple_liquid_glass/src/motions/sheet_tuning.dart';
import 'package:flutter_test/flutter_test.dart';

SheetMotion _sheet({bool dismissible = true}) {
  final motion = SheetMotion(
    heights: const [400, 800],
    width: 402,
    initial: 0,
    dismissible: dismissible,
  );
  motion.present(0);
  motion.advance(2);
  return motion;
}

/// Drags the sheet from [from] to [to] (screen y) over 0.2 s from [t],
/// lets go at [velocity] points per second and advances past the release
/// delay, when the settle picks its detent.
void _drag(
  SheetMotion motion,
  double t,
  double from,
  double to,
  double velocity,
) {
  motion.dragStart(t, from);
  for (var i = 1; i <= 12; i++) {
    motion.dragUpdate(t + i / 60, from + (to - from) * i / 12);
  }
  motion.dragEnd(t + 0.2, velocity);
  expect(motion.drainEvents(), isEmpty);
  motion.advance(t + 0.2 + SheetTuning.releaseDelay);
}

void main() {
  test('a drag to another detent raises one change, by the user', () {
    final motion = _sheet();
    _drag(motion, 2, 500, 100, -800);
    final events = motion.drainEvents();
    expect(events, hasLength(1));
    final event = events.single as SheetDetentChanged;
    expect(event.index, 1);
    expect(event.byUser, isTrue);
    expect(motion.drainEvents(), isEmpty);
  });

  test('a detent set from code raises a change not by the user', () {
    final motion = _sheet();
    motion.animateTo(2, 1);
    final event = motion.drainEvents().single as SheetDetentChanged;
    expect(event.byUser, isFalse);
    motion.animateTo(3, 1);
    expect(motion.drainEvents(), isEmpty);
  });

  test('a grabber tap raises its change on the frame that applies it', () {
    final motion = _sheet();
    motion.tapGrabber(2);
    expect(motion.drainEvents(), isEmpty);
    motion.advance(2 + SheetTuning.grabberTapDelay);
    final event = motion.drainEvents().single as SheetDetentChanged;
    expect(event.index, 1);
    expect(event.byUser, isTrue);
  });

  test('a flick down dismisses, or is refused when not dismissible', () {
    final dismissible = _sheet();
    _drag(dismissible, 2, 500, 700, 2000);
    expect(dismissible.drainEvents(), [isA<SheetDismissed>()]);
    final kept = _sheet(dismissible: false);
    _drag(kept, 2, 500, 900, 2000);
    expect(kept.drainEvents(), [isA<SheetDismissRefused>()]);
  });
}
