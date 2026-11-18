import 'dart:convert';
import 'dart:math' as math;

import 'package:apple_liquid_glass/src/motions/menu_motion.dart';
import 'package:apple_liquid_glass/src/motions/menu_tuning.dart';
import 'package:apple_liquid_glass/src/motions/menu_values.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

List<Map<String, Object?>> _rows(String name) => [
  for (final line in Fixtures.lines(
    'test/fixtures/ios27-device/menuglow/$name.jsonl',
  ))
    if (line.isNotEmpty) jsonDecode(line) as Map<String, Object?>,
];

double _d(Map<String, Object?> row, String key) =>
    (row[key]! as num).toDouble();

/// Plays a capture's stroke on the menu's touch glow: a stroke that held
/// the menu open lights it at its first move, any other at its touch.
/// Returns the rms and the largest error of the spot's opacity and the
/// largest error of its scale while it shows.
({double rms, double worst, double scale}) _replay(String name) {
  final glow = MenuTuning.standard.touchGlow();
  final rows = _rows(name);
  final fromMove = rows.first['starts'] == 'move';
  var sum = 0.0;
  var count = 0;
  var worst = 0.0;
  var scale = 0.0;
  for (final row in rows.skip(1)) {
    final t = _d(row, 't');
    if (row['k'] == 'touch') {
      final at = Offset(_d(row, 'x'), _d(row, 'y'));
      switch (row['phase']) {
        case 0 when !fromMove:
          glow.pointerDown(t, at);
        case 1 when glow.isDown:
          glow.pointerMove(t, at);
        case 1:
          glow.pointerDown(t, at);
        case 3 || 4:
          glow.pointerUp(t);
      }
      continue;
    }
    final a = _d(row, 'a');
    final error = (glow.spotOpacity(t) - a).abs();
    sum += error * error;
    count++;
    worst = math.max(worst, error);
    if (a > 0.02) {
      scale = math.max(scale, (glow.spotScale(t) - _d(row, 's')).abs());
    }
  }
  return (rms: math.sqrt(sum / count), worst: worst, scale: scale);
}

void main() {
  test('the open menu glows with its flex spec: a 0.5 spot, no wash', () {
    final glow = MenuTuning.standard.touchGlow();
    expect(glow.spotPeak, 0.5);
    expect(glow.washPeak, 0);
    expect(glow.diameter, 160);
  });

  test('a finger dragged over the rows replays the device glow', () {
    final errors = _replay('dragselect');
    expect(errors.rms, lessThan(0.015), reason: 'spot opacity rms');
    expect(errors.worst, lessThan(0.06), reason: 'one 120 Hz frame of rise');
    expect(errors.scale, lessThan(0.2), reason: 'twice as wide while dragged');
  });

  for (final name in [
    'select',
    'sub-dark',
    'swiftui-light',
    'palette',
    'sub-tap',
    'reopen-80',
    'reopen-250',
  ]) {
    test('a tap on the open menu replays the device glow ($name)', () {
      final errors = _replay(name);
      // A tap's fall starts 40 - 87 ms after its lift across these
      // captures; the minimum lit time sits in that spread.
      expect(errors.rms, lessThan(0.03), reason: 'spot opacity rms');
      expect(errors.scale, lessThan(0.5), reason: 'spot growth on the fall');
    });
  }

  group('MenuMotion', () {
    const button = Rect.fromLTWH(177, 413, 48, 48);
    MenuMotion menu() {
      final motion = MenuMotion(
        source: MenuSource(button),
        itemCount: 3,
        bounds: const Size(402, 874),
        padding: const EdgeInsets.only(top: 62, bottom: 34),
      );
      motion.advance(0);
      return motion;
    }

    test('a finger that held the menu open lights it only once it moves', () {
      final motion = menu();
      motion.holdOpen(0, button.center);
      motion.advance(0.8);
      expect(motion.touchGlow, isNull);
      motion.pointerMove(0.8, button.center + const Offset(0, 4));
      motion.advance(0.95);
      final glow = motion.touchGlow;
      expect(glow, isNotNull);
      expect(glow!.center, button.center + const Offset(0, 4));
    });

    test('a touch on the open menu lights it after the rise lag', () {
      final motion = menu();
      motion.open(0);
      motion.advance(1);
      final row = motion.menuRect.center;
      motion.pointerDown(1, row);
      motion.advance(1 + MenuTuning.standard.glowRiseLag / 2);
      expect(motion.touchGlow, isNull);
      motion.advance(1.15);
      expect(motion.touchGlow?.center, row);
    });

    test('the glow of a tap keeps the menu awake until it has faded', () {
      final motion = menu();
      motion.dismissOnSelect = false;
      motion.open(0);
      motion.advance(1);
      final row = motion.menuRect.center;
      motion.pointerDown(1, row);
      motion.advance(1.06);
      motion.pointerUp(1.06, row);
      var t = 1.06;
      var lit = 0.0;
      while (!motion.isSettled && t < 6) {
        t += 1 / 120;
        motion.advance(t);
        if (motion.touchGlow != null) lit = t;
      }
      expect(motion.isSettled, isTrue);
      expect(motion.touchGlow, isNull);
      expect(lit, greaterThan(1.5), reason: 'the glow fades on its own');
    });
  });
}
