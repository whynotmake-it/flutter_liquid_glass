import 'dart:math' as math;

import 'package:apple_liquid_glass/src/motions/flex_spec.dart';
import 'package:apple_liquid_glass/src/motions/menu_metrics.dart';
import 'package:apple_liquid_glass/src/motions/menu_motion.dart';
import 'package:apple_liquid_glass/src/motions/menu_tuning.dart';
import 'package:apple_liquid_glass/src/motions/menu_values.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';

const _tuning = MenuTuning.standard;
const _metrics = MenuMetrics(topInset: 41);
const _d = 0.023;
const _period = 1 / 30;

/// The exact step of the spring (response, damping) from (x, v) toward
/// [target] over [h] seconds of its own time, written out from the
/// passport (menu-button.md) rather than taken from the library.
(double, double) _step(
  double x,
  double v,
  double target,
  double h, {
  double response = 0.574,
  double damping = 0.548,
}) {
  final w = 2 * math.pi / response;
  final wd = w * math.sqrt(1 - damping * damping);
  final a = x - target;
  final b = (v + damping * w * a) / wd;
  final e = math.exp(-damping * w * h);
  final c = math.cos(wd * h);
  final s = math.sin(wd * h);
  return (
    target + e * (a * c + b * s),
    e * ((-damping * w * a + wd * b) * c + (-damping * w * b - wd * a) * s),
  );
}

MenuMotion _open({bool down = true}) {
  final motion = MenuMotion(
    source: MenuSource(Rect.fromLTWH(179, down ? 300 : 760, 44, 44)),
    itemCount: 4,
    bounds: const Size(402, 874),
    padding: const EdgeInsets.only(top: 62, bottom: 34),
    metrics: _metrics,
  );
  motion.advance(-4);
  motion.open(-3);
  motion.advance(-1);
  expect(motion.opensDown, down);
  return motion;
}

/// The pulse channel's published states, step by step, under a finger
/// that touched down at time 0 and moved to [moves] (time, vertical
/// travel), by the observed rule: 30 steps a second from the flex's
/// touch-down, 1/60 s of spring time when the target changed, the time
/// that passed when it did not.
List<(double, double)> _channel(List<(double, double)> moves, int steps) {
  var x = 0.0;
  var v = 0.0;
  var target = 0.0;
  var last = _d;
  final out = <(double, double)>[];
  for (var k = 1; k <= steps; k++) {
    final at = _d + k * _period;
    var goal = 0.0;
    for (final (t, y) in moves) {
      if (t + _d <= at + 1e-9) goal = y;
    }
    final h = goal != target ? 1 / 60 : at - last;
    (x, v) = _step(x, v, goal, h);
    target = goal;
    last = at;
    out.add((x, v));
  }
  return out;
}

void _drag(MenuMotion motion, Offset start, List<(double, double)> moves) {
  motion.pointerDown(0, start);
  for (final (t, y) in moves) {
    motion.pointerMove(t, start.translate(0, y));
  }
}

({double scaleX, double scaleY, double driftX, double driftY}) _shown(
  MenuMotion motion,
) {
  final rest = motion.menuRect;
  final shown = motion.flexedMenuRect;
  final down = motion.opensDown;
  return (
    scaleX: shown.width / rest.width,
    scaleY: shown.height / rest.height,
    driftX: shown.center.dx - rest.center.dx,
    driftY: down ? shown.top - rest.top : shown.bottom - rest.bottom,
  );
}

void main() {
  group('flex targets match the equations read from UIKit', () {
    const size = Size(250, 250);
    void expectTargets(
      ({double scaleX, double scaleY, double driftX, double driftY}) actual,
      List<double> expected,
    ) {
      expect(actual.scaleX, moreOrLessEquals(expected[0], epsilon: 1e-9));
      expect(actual.scaleY, moreOrLessEquals(expected[1], epsilon: 1e-9));
      expect(actual.driftX, moreOrLessEquals(expected[2], epsilon: 1e-9));
      expect(actual.driftY, moreOrLessEquals(expected[3], epsilon: 1e-9));
    }

    ({double scaleX, double scaleY, double driftX, double driftY}) targets(
      Offset t,
      Offset it, {
      double velocity = 0,
      double side = 1,
    }) => _tuning.flexTargets(
      translation: t,
      inBounds: it,
      size: size,
      velocity: velocity,
      side: side,
    );

    test('the menu spec carries the native numbers', () {
      final flex = _tuning.flex;
      expect(flex, same(FlexSpec.menu));
      expect(flex.scaleDistanceThreshold, 6000);
      expect(flex.interactionPulseNormalizationFactor, 8000);
      expect(flex.interactionPulseScaleX, 50);
      expect(flex.interactionPulseScaleY, 32);
      expect(flex.interactionPulseDriftRatio, 0.7);
      expect(flex.movementMinScale, 0.9);
      expect(flex.movementMaxScale, 1.1);
      expect(flex.scaleSpring, const Spring.response(0.6, dampingRatio: 0.5));
      expect(_tuning.flexInBoundsPoints, 40);
      expect(
        _tuning.flexPulseSpring,
        const Spring.response(0.574, dampingRatio: 0.548),
      );
    });

    test('at rest', () {
      expectTargets(targets(Offset.zero, Offset.zero), [1, 1, 0, 0]);
    });

    test('a vertical drag inside and beyond the edge', () {
      expectTargets(targets(const Offset(0, -73), const Offset(0, -73)), [
        0.998053333333,
        1.001946666667,
        0,
        -0.486666666667,
      ]);
      expectTargets(targets(const Offset(0, -220), const Offset(0, -73)), [
        0.973553333333,
        1.026446666667,
        0,
        -6.611666666667,
      ]);
    });

    test('a horizontal drag beyond the edge', () {
      expectTargets(targets(const Offset(200, 0), const Offset(124, 0)), [
        1.015973333333,
        0.984026666667,
        3.993333333333,
        0,
      ]);
    });

    test('a diagonal drag combines both axes', () {
      expectTargets(targets(const Offset(150, -150), const Offset(124, -73)), [
        0.99286,
        1.00714,
        1.91,
        -3.695,
      ]);
    });

    test('the drift gain is 40/6000 inside and W/6000 beyond the edge', () {
      double drift(double t, double it) =>
          targets(Offset(t, 0), Offset(it, 0)).driftX;
      expect(drift(100, 100), moreOrLessEquals(100 * 40 / 6000));
      expect(drift(124, 124), moreOrLessEquals(124 * 40 / 6000));
      expect(
        drift(125, 124) - drift(124, 124),
        moreOrLessEquals(250 / 6000, epsilon: 1e-9),
      );
      expect(drift(-100, -100), moreOrLessEquals(-100 * 40 / 6000));
    });

    test('the scales clamp to the spec bounds', () {
      expectTargets(targets(const Offset(0, -3000), const Offset(0, -73)), [
        0.9,
        1.1,
        0,
        -122.445,
      ]);
    });

    test('the pulse follows the side the menu opens to', () {
      expectTargets(targets(Offset.zero, Offset.zero, velocity: 400), [
        0.99,
        1.0064,
        0,
        1.12,
      ]);
      expectTargets(
        targets(const Offset(0, 120), const Offset(0, 120), velocity: 600),
        [0.981848, 1.01283072, 0, 2.48],
      );
      expectTargets(
        targets(
          const Offset(0, -120),
          const Offset(0, -120),
          velocity: -600,
          side: -1,
        ),
        [0.981848, 1.01283072, 0, -2.48],
      );
      expectTargets(
        targets(
          const Offset(0, 60),
          const Offset(0, 60),
          velocity: 600,
          side: -1,
        ),
        [1.013376, 0.99198464, 0, 2.08],
      );
    });
  });

  group('the pulse channel (labeled approximation of its clock)', () {
    test('a retarget advances 1/60 s, a hold the time that passed', () {
      final motion = _open();
      final start = motion.menuRect.center;
      _drag(motion, start, const [(0.01, 10), (0.05, 20)]);
      motion.advance(_d + _period - 1e-4);
      expect(motion.flexPulse.velocity, 0);
      motion.advance(_d + _period);
      var (x, v) = _step(0, 0, 10, 1 / 60);
      expect(motion.flexPulse.value, moreOrLessEquals(x, epsilon: 1e-9));
      expect(motion.flexPulse.velocity, moreOrLessEquals(v, epsilon: 1e-9));
      motion.advance(_d + 1.5 * _period);
      expect(motion.flexPulse.value, moreOrLessEquals(x, epsilon: 1e-9));
      motion.advance(_d + 2 * _period);
      (x, v) = _step(x, v, 20, 1 / 60);
      expect(motion.flexPulse.value, moreOrLessEquals(x, epsilon: 1e-9));
      motion.advance(_d + 3 * _period);
      (x, v) = _step(x, v, 20, _period);
      expect(motion.flexPulse.value, moreOrLessEquals(x, epsilon: 1e-9));
      expect(motion.flexPulse.velocity, moreOrLessEquals(v, epsilon: 1e-9));
    });

    void replays(String name, List<(double, double)> moves, int steps) {
      test(name, () {
        final motion = _open();
        final start = motion.menuRect.center;
        motion.pointerDown(0, start);
        final expected = _channel(moves, steps);
        var next = 0;
        for (var k = 1; k <= steps; k++) {
          final at = _d + k * _period + 1e-6;
          while (next < moves.length && moves[next].$1 <= at) {
            final (t, y) = moves[next++];
            motion.pointerMove(t, start.translate(0, y));
          }
          motion.advance(at);
          final (x, v) = expected[k - 1];
          expect(
            motion.flexPulse.velocity,
            moreOrLessEquals(v, epsilon: 1e-6),
            reason: 'step $k',
          );
          expect(
            motion.flexPulse.value,
            moreOrLessEquals(x, epsilon: 1e-6),
            reason: 'step $k',
          );
        }
      });
    }

    replays('a steady drag, then a hold', [
      for (var i = 1; i <= 60; i++) (i / 120 + 0.002, 3.0 * i),
    ], 20);
    replays('sparse moves', const [(0.11, 30), (0.31, 30.5), (0.56, 80)], 30);
    replays('a reversal', [
      for (var i = 1; i <= 30; i++) (i / 120 + 0.002, 4.0 * i),
      for (var i = 1; i <= 30; i++) (0.252 + i / 120, 120 - 6.0 * i),
    ], 30);

    test('a held finger runs the spring in wall time, not at half', () {
      final motion = _open();
      final start = motion.menuRect.center;
      _drag(motion, start, const [(0.01, 60)]);
      motion.advance(_d + _period + 1e-6);
      final first = motion.flexPulse;
      motion.advance(_d + 10 * _period + 1e-6);
      final (x, v) = _step(first.value, first.velocity, 60, 9 * _period);
      expect(motion.flexPulse.value, moreOrLessEquals(x, epsilon: 1e-6));
      expect(motion.flexPulse.velocity, moreOrLessEquals(v, epsilon: 1e-6));
    });

    test('a lift zeroes the velocity and a new touch resets the channel', () {
      final motion = _open();
      final start = motion.menuRect.center;
      _drag(motion, start, [for (var i = 1; i <= 24; i++) (i / 120, 5.0 * i)]);
      motion.advance(0.2);
      expect(motion.flexPulse.velocity.abs(), greaterThan(50));
      motion.pointerUp(0.21, start.translate(0, 120));
      motion.advance(0.21 + _d);
      expect(motion.flexPulse.velocity, 0);
      final before = motion.flexedMenuRect;
      motion.advance(0.3);
      expect(motion.flexedMenuRect, isNot(before), reason: 'it returns');
      motion.pointerDown(0.3, start);
      motion.advance(0.3 + _d);
      expect(motion.flexPulse.value, 0);
      expect(motion.flexPulse.velocity, 0);
      motion.pointerMove(0.31, start.translate(0, 10));
      motion.advance(0.3 + _d + _period + 1e-6);
      final (x, v) = _step(0, 0, 10, 1 / 60);
      expect(motion.flexPulse.value, moreOrLessEquals(x, epsilon: 1e-9));
      expect(motion.flexPulse.velocity, moreOrLessEquals(v, epsilon: 1e-9));
    });

    test('a resting finger lets the clock doze between steps, then sleep', () {
      final motion = _open();
      motion.advance(2);
      final start = motion.menuRect.center;
      motion.pointerDown(2, start);
      motion.pointerMove(2.01, start.translate(0, 40));
      motion.advance(2 + _d + 3 * _period + 0.001);
      expect(motion.isSettled, isFalse);
      motion.advance(4);
      expect(motion.isSettled, isTrue);
      final shown = _shown(motion);
      final target = _tuning.flexTargets(
        translation: const Offset(0, 40),
        inBounds: const Offset(0, 40),
        size: motion.menuRect.size,
        velocity: 0,
        side: 1,
      );
      expect(
        (shown.driftY - target.driftY).abs(),
        lessThan(MenuTuning.flexPulseRest),
      );
    });
  });

  group('the flex while the finger is down and after it lifts', () {
    test('a finger that touches down beside the menu neither stretches nor '
        'lights it, even sliding onto it', () {
      final motion = _open();
      final rest = motion.menuRect;
      final beside = rest.centerRight.translate(4, 0);
      motion.pointerDown(0, beside);
      motion.pointerMove(0.01, beside.translate(120, 40));
      motion.advance(0.5);
      expect(motion.flexedMenuRect, rest);
      expect(motion.touchGlow, isNull);
      motion.pointerMove(0.51, rest.center);
      motion.advance(1);
      expect(motion.flexedMenuRect, rest);
      expect(motion.touchGlow, isNull);
    });

    test('the shown menu settles on the targets of a still finger', () {
      for (final down in [true, false]) {
        final motion = _open(down: down);
        final rest = motion.menuRect;
        final start = rest.center;
        motion.pointerDown(0, start);
        motion.pointerMove(0.01, start.translate(150, -260));
        motion.advance(0.01 + _d + 1.5);
        final inside = Offset(rest.right, math.max(rest.top, start.dy - 260));
        final target = _tuning.flexTargets(
          translation: const Offset(150, -260),
          inBounds: inside - start,
          size: rest.size,
          velocity: motion.flexPulse.velocity,
          side: down ? 1 : -1,
        );
        final shown = _shown(motion);
        expect(shown.scaleX, moreOrLessEquals(target.scaleX, epsilon: 1e-6));
        expect(shown.scaleY, moreOrLessEquals(target.scaleY, epsilon: 1e-6));
        expect(shown.driftX, moreOrLessEquals(target.driftX, epsilon: 1e-4));
        expect(shown.driftY, moreOrLessEquals(target.driftY, epsilon: 1e-4));
      }
    });

    test('a still finger lifts into the scale spring with the impulse', () {
      final motion = _open();
      final start = motion.menuRect.center;
      motion.pointerDown(0, start);
      motion.pointerMove(0.01, start.translate(200, 0));
      motion.advance(1);
      final d0 = _shown(motion).driftX;
      expect(d0, greaterThan(3));
      motion.pointerUp(1, start.translate(200, 0));
      motion.advance(1 + _d);
      expect(_shown(motion).driftX, moreOrLessEquals(d0, epsilon: 1e-6));
      const flex = FlexSpec.menu;
      final push = flex.scaleSpring.stiffness * flex.retargetImpulse * -d0;
      for (final after in [0.05, 0.2, 0.5]) {
        motion.advance(1 + _d + after);
        final (x, _) = _step(d0, push, 0, after, response: 0.6, damping: 0.5);
        expect(_shown(motion).driftX, moreOrLessEquals(x, epsilon: 1e-6));
      }
      motion.advance(4);
      final shown = motion.flexedMenuRect;
      final rest = motion.menuRect;
      for (final (a, b) in [
        (shown.left, rest.left),
        (shown.top, rest.top),
        (shown.right, rest.right),
        (shown.bottom, rest.bottom),
      ]) {
        expect(a, moreOrLessEquals(b, epsilon: MenuTuning.flexReturnRest));
      }
      expect(motion.isSettled, isTrue);
    });

    test('a moving menu lifts with the velocity it shows', () {
      final motion = _open();
      final start = motion.menuRect.center;
      final moves = [for (var i = 1; i <= 36; i++) (i / 120, 6.0 * i)];
      _drag(motion, start, moves);
      const lift = 0.3 + _d + 2 * _period - _d;
      motion.pointerUp(lift, start.translate(0, 216));
      motion.advance(lift + _d - 1e-6);
      final before = _shown(motion);
      motion.advance(lift + _d);
      final at = _shown(motion);
      expect(at.driftY, moreOrLessEquals(before.driftY, epsilon: 1e-4));
      motion.advance(lift + _d + 0.004);
      final next = _shown(motion);
      final slope = (next.driftY - at.driftY) / 0.004;
      expect(slope.abs(), greaterThan(1), reason: 'carries a velocity');
    });
  });
}
