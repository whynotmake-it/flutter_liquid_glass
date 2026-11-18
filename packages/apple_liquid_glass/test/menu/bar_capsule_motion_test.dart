import 'package:apple_liquid_glass/src/motions/menu_motion.dart';
import 'package:apple_liquid_glass/src/motions/menu_values.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

const _shared = Rect.fromLTWH(232, 62, 154, 44);
const _alone = Rect.fromLTWH(342, 62, 44, 44);

MenuMotion _motion(Rect capsule, Offset origin, {bool alone = false}) =>
    MenuMotion(
      source: MenuCapsuleSource(
        capsule: capsule,
        item: Rect.fromCenter(center: origin, width: 44, height: 44),
        height: 36,
        alone: alone,
      ),
      bounds: const Size(402, 874),
      padding: const EdgeInsets.only(top: 62, bottom: 34),
      itemCount: 4,
    );

void _tap(MenuMotion motion, Offset at) {
  motion.pointerDown(0, at);
  motion.pointerUp(0.05, at);
}

void main() {
  group('a menu growing out of a bar capsule (iPhone 16 Pro)', () {
    test('lands in the same place whichever item opens it', () {
      for (final x in [255.0, 309.0, 364.0]) {
        final at = Offset(x, 84);
        final motion = _motion(_shared, at);
        _tap(motion, at);
        motion.advance(3);
        expect(motion.menuRect.left, closeTo(139.33, 0.01));
        expect(motion.menuRect.top, 62);
        expect(motion.menuRect.width, 250);
      }
    });

    test('lands 2 pt past a capsule of one item', () {
      const at = Offset(364, 84);
      final motion = _motion(_alone, at, alone: true);
      _tap(motion, at);
      motion.advance(3);
      expect(motion.menuRect.right, 388);
      expect(motion.menuRect.top, 62);
    });

    test('lands 8 pt from the screen after a hold', () {
      const at = Offset(255, 84);
      final motion = _motion(_shared, at);
      motion.pointerDown(0, at);
      motion.advance(3);
      expect(motion.menuRect.right, 394);
      expect(motion.menuRect.top, 62);
    });

    test('ends its close once the capsule is back, before the springs stop '
        'ringing', () {
      const at = Offset(255, 84);
      final motion = _motion(_shared, at);
      _tap(motion, at);
      motion.advance(3);
      motion.pointerDown(3, const Offset(40, 500));
      motion.pointerUp(3.05, const Offset(40, 500));
      var t = 3.05;
      while (!motion.isClosing && t < 4) {
        t += 1 / 120;
        motion.advance(t);
      }
      final start = t;
      Rect? last;
      while (motion.isClosing && t < 6) {
        last = motion.buttonBlob.rect;
        t += 1 / 120;
        motion.advance(t);
      }
      expect(t - start, inInclusiveRange(0.45, 0.72));
      expect(last!.left - _shared.left, closeTo(0, 0.35));
      expect(last.bottom - _shared.bottom, closeTo(0, 0.35));
      expect(motion.fusionRadius, 0);
      expect(motion.progress, 0);
      expect(motion.isPresented, isFalse);
      expect(motion.presence, PresenceStatus.hidden);

      motion.pointerDown(t, at);
      motion.pointerUp(t + 0.05, at);
      motion.advance(t + 3);
      expect(motion.isOpen, isTrue);
      expect(motion.progress, closeTo(1, 0.001));
      expect(motion.menuRect.left, closeTo(139.33, 0.01));
      expect(motion.menuRect.top, 62);
    });

    test('takes a touch on the item only, not on the rest of the capsule', () {
      const at = Offset(255, 84);
      final motion = _motion(_shared, at);
      motion.pointerDown(0, const Offset(364, 84));
      motion.pointerUp(0.05, const Offset(364, 84));
      motion.advance(3);
      expect(motion.isOpen, isFalse);
    });

    test('grows the menu from the tapped item as an 18 pt square', () {
      const at = Offset(255, 84);
      final motion = _motion(_shared, at);
      _tap(motion, at);
      var t = 0.05;
      while (motion.progress <= 0 && t < 1) {
        t += 1 / 120;
        motion.advance(t);
      }
      final blob = motion.menuBlob.rect;
      expect(blob.width, closeTo(18, 3));
      expect(blob.height, closeTo(18, 3));
      expect((blob.center - at).distance, lessThan(3));
    });

    test('starts the source as the whole capsule, then shrinks it to an 11 pt '
        'square a quarter of the way from the item to the menu', () {
      const at = Offset(255, 84);
      final motion = _motion(_shared, at);
      _tap(motion, at);
      var t = 0.05;
      while (motion.progress <= 0 && t < 1) {
        t += 1 / 120;
        motion.advance(t);
      }
      final first = motion.buttonBlob.rect;
      expect(first.width, greaterThan(_shared.width));
      expect((first.center - _shared.center).distance, lessThan(3));

      motion.advance(3);
      final last = motion.buttonBlob.rect;
      expect(last.width, closeTo(11, 0.01));
      expect(last.height, closeTo(11, 0.01));
      final menu = motion.menuRect.center;
      expect(last.center.dx, closeTo(at.dx + 0.25 * (menu.dx - at.dx), 0.01));
      expect(last.center.dy, closeTo(at.dy + 0.25 * (menu.dy - at.dy), 0.01));
    });
  });
}
