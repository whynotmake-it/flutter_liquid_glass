import 'package:apple_liquid_glass/src/motions/tab_minimize.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drags [away] over [steps] equal moves through the interaction, from 0.
void _drag(ScrollAway away, double distance, {int steps = 10}) {
  away.last = 0;
  away.beginDrag();
  for (var i = 1; i <= steps; i++) {
    away.scroll(distance * i / steps, min: 0, max: 2000, tracking: true);
  }
}

extension on TabBarMinimizeMotion {
  TabBarMinimizeMotion seenAt(double t) {
    advance(t);
    return this;
  }
}

void main() {
  group('ScrollAway (UIKit scroll-away interaction)', () {
    test('64 points of scroll minimize; the hint grows on the way', () {
      final away = ScrollAway();
      final reported = <double>[];
      away.onProgress = (double p, {required bool tracking}) => reported.add(p);
      _drag(away, 32, steps: 4);
      expect(away.progress, closeTo(0.5, 1e-9));
      away.scroll(64, min: 0, max: 2000, tracking: true);
      expect(away.progress, 1);
      expect(reported.last, 1);
      away.scroll(200, min: 0, max: 2000, tracking: true);
      expect(away.progress, 1);
    });

    test('a scroll that stops short returns to 0 (floor)', () {
      final away = ScrollAway();
      _drag(away, 40);
      expect(away.progress, closeTo(40 / 64, 1e-9));
      away.endDrag(decelerates: true);
      expect(away.progress, closeTo(40 / 64, 1e-9));
      away.endDeceleration();
      expect(away.progress, 0);
    });

    test('a content shorter than 96 points of range never minimizes', () {
      final away = ScrollAway();
      away.last = 0;
      away.beginDrag();
      away.scroll(90, min: 0, max: 95, tracking: true);
      expect(away.progress, 0);
      away.scroll(10, min: 0, max: 96, tracking: true);
      away.scroll(90, min: 0, max: 96, tracking: true);
      expect(away.progress, greaterThan(0));
    });

    test('a programmatic scroll is only recorded', () {
      final away = ScrollAway();
      away.last = 0;
      away.last = 500;
      expect(away.progress, 0);
      away.beginDrag();
      away.scroll(510, min: 0, max: 2000, tracking: true);
      expect(away.progress, closeTo(10 / 64, 1e-9));
    });

    test('onScrollUp minimizes on the way back', () {
      final away = ScrollAway(minimizesOnScrollUp: true);
      away.last = 1000;
      away.beginDrag();
      away.scroll(1100, min: 0, max: 2000, tracking: true);
      expect(away.progress, 0);
      away.scroll(1000, min: 0, max: 2000, tracking: true);
      expect(away.progress, 1);
    });

    test('the expanding scroll is held at 0.01 while it runs', () {
      final away = ScrollAway();
      _drag(away, 32);
      away.scroll(-100, min: -200, max: 2000, tracking: true);
      expect(away.progress, TabBarMinimizeTuning.minimumProgress);
    });

    test('pushing past the far end expands a minimized bar', () {
      final away = ScrollAway();
      _drag(away, 100);
      expect(away.progress, 1);
      away.endDrag(decelerates: false);
      away.last = 2000;
      away.beginDrag();
      away.scroll(2010, min: 0, max: 2000, tracking: true);
      expect(away.progress, 0);
    });

    test('a drag back in the middle of the content stays minimized', () {
      final away = ScrollAway();
      _drag(away, 400);
      away.endDrag(decelerates: false);
      away.last = 400;
      away.beginDrag();
      for (var y = 400.0; y >= 250; y -= 10) {
        away.scroll(y, min: 0, max: 2000, tracking: true);
      }
      away.endDrag(decelerates: false);
      expect(away.progress, 1);
    });

    test('a scroll to the top expands', () {
      final away = ScrollAway();
      _drag(away, 100);
      away.scrollToTop();
      expect(away.progress, 0);
    });
  });

  group('TabBarMinimizeMotion', () {
    test('the hint scales by 0.05 x progress, then resets', () {
      final motion = TabBarMinimizeMotion();
      motion.advance(0);
      final away = motion.scrollAway;
      _drag(away, 32);
      motion.advance(1);
      expect(motion.seenAt(1).hint, closeTo(1 - 0.5 * 0.05, 1e-6));
      away.endDrag(decelerates: false);
      motion.advance(3);
      expect(motion.seenAt(3).hint, closeTo(1, 1e-6));
      expect(motion.minimized, isFalse);
    });

    test('the bar morphs on one spring; the accessory moves along first '
        'and up 0.05 s later, and back up first', () {
      final motion = TabBarMinimizeMotion();
      motion.advance(0);
      _drag(motion.scrollAway, 100);
      expect(motion.minimized, isTrue);
      motion.advance(0.04);
      expect(motion.seenAt(0.04).morph, greaterThan(0));
      expect(motion.seenAt(0.04).accessoryX, greaterThan(0));
      expect(motion.seenAt(0.04).accessoryY, 0);
      motion.advance(0.1);
      expect(motion.seenAt(0.1).accessoryY, greaterThan(0));
      motion.advance(3);
      expect(motion.seenAt(3).isSettled, isTrue);
      motion.settle();
      expect(motion.seenAt(3).morph, 1);
      motion.setMinimized(3, minimized: false);
      motion.advance(3.04);
      expect(motion.seenAt(3.04).accessoryY, lessThan(1));
      expect(motion.seenAt(3.04).accessoryX, 1);
      expect(motion.seenAt(3.04).morph, lessThan(1));
      motion.advance(6);
      motion.settle();
      expect(motion.seenAt(6).morph, 0);
    });

    TabBarMinimizeMotion minimized() {
      final motion = TabBarMinimizeMotion();
      motion.advance(0);
      _drag(motion.scrollAway, 100);
      motion.advance(3);
      motion.settle();
      expect(motion.minimized, isTrue);
      return motion;
    }

    test('a finger on the circle lifts it after 32 ms and nothing expands '
        'until it lifts, however late', () {
      final motion = minimized();
      motion.pressDown(3, 50);
      motion.advance(3.03);
      expect(motion.seenAt(3.03).press, 0);
      motion.advance(3.2);
      expect(motion.seenAt(3.2).press, greaterThan(0.5));
      motion.advance(4.6);
      expect(motion.minimized, isTrue);
      motion.pressUp(4.6);
      expect(motion.minimized, isFalse);
      expect(motion.pressed, isFalse);
      motion.advance(8);
      motion.settle();
      expect(motion.seenAt(8).press, 0);
      expect(motion.minimized, isFalse);
    });

    test(
      '4 points along the bar expand it at once and hand the finger over',
      () {
        final motion = minimized();
        motion.pressDown(3, 50);
        expect(motion.pressMove(3.05, 53.9), isFalse);
        expect(motion.minimized, isTrue);
        expect(motion.pressMove(3.06, 46), isTrue);
        expect(motion.minimized, isFalse);
        expect(motion.pressMove(3.1, 200), isFalse);
        motion.advance(3.5);
        motion.pressUp(3.5);
        expect(motion.minimized, isFalse);
      },
    );

    test('a cancelled press settles back, minimized', () {
      final motion = minimized();
      motion.pressDown(3, 50);
      motion.advance(3.3);
      motion.pressCancel(3.3);
      expect(motion.minimized, isTrue);
      motion.advance(6);
      motion.settle();
      expect(motion.seenAt(6).press, 0);
    });

    test('a press on an expanded bar does nothing', () {
      final motion = TabBarMinimizeMotion();
      motion.pressDown(0, 50);
      expect(motion.pressed, isFalse);
      expect(motion.pressMove(0.1, 90), isFalse);
    });

    test('a behavior that stops minimizing expands the bar', () {
      final motion = TabBarMinimizeMotion();
      motion.advance(0);
      _drag(motion.scrollAway, 100);
      expect(motion.minimized, isTrue);
      motion.setBehavior(0.5, GlassTabBarMinimizeBehavior.never);
      expect(motion.minimized, isFalse);
    });
  });
}
