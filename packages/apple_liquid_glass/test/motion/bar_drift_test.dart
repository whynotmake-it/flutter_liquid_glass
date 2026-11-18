import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:apple_liquid_glass/src/motions/bar_frames.dart';
import 'package:apple_liquid_glass/src/motions/bar_motion.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/bar.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

List<Map<String, Object?>> _rows(String path) => [
  for (final line in Fixtures.lines(path))
    if (line.trim().isNotEmpty)
      (jsonDecode(line) as Map).cast<String, Object?>(),
];

double _d(Map<String, Object?> r, String k) => (r[k]! as num).toDouble();

double _rms(List<double> e) =>
    math.sqrt(e.fold<double>(0, (a, v) => a + v * v) / e.length);

/// Whether the page the swipe drags ends past half the screen: the pop
/// committed.
bool _popped(List<Map<String, Object?>> rows) {
  final width = _d(rows.first, 'w');
  final down = _d(rows.firstWhere((r) => r['k'] == 'touch'), 't');
  final center = width / 2;
  final byLid = <Object?, List<Map<String, Object?>>>{};
  for (final r in rows) {
    if (r['cls'] == 'page') byLid.putIfAbsent(r['lid'], () => []).add(r);
  }
  final top = byLid.values.firstWhere((s) {
    final before = s.where((r) => _d(r, 't') <= down);
    return before.isNotEmpty &&
        (_d(before.last, 'x') - center).abs() < 1 &&
        s.any((r) => _d(r, 'x') > center + 5);
  });
  return _d(top.last, 'x') - center > width / 2;
}

void main() {
  test('the bar capsules lean toward the page below during a swipe', () {
    GlassBarCapsuleLayout capsule(Object id, double left, double width) =>
        GlassBarCapsuleLayout(id, Rect.fromLTWH(left, 62, width, 44), [
          GlassBarItemLayout((
            id,
            'item',
          ), Rect.fromLTWH(left + 4, 66, width - 8, 36)),
        ]);
    const leading = ('leading', 0);
    const outer = ('trailing', 0);
    const inner = ('trailing', 1);
    final detail = [
      capsule(leading, 16, 94),
      capsule(outer, 386 - 73.67, 73.67),
      capsule(inner, 248.5 - 103.67 / 2, 103.67),
    ];
    final list = [
      capsule(leading, 16, 62.33),
      capsule(outer, 386 - 99.33, 99.33),
    ];
    final errors = <double>[];
    for (final name in ['commit', 'cancel', 'slow25', 'slow40']) {
      final rows = _rows(
        'test/fixtures/ios27-device/bars/pop-edge-drift-$name.jsonl',
      );
      final width = _d(rows.first, 'w');
      final touches = [
        for (final r in rows)
          if (r['k'] == 'touch') r,
      ];
      final down = _d(touches.first, 't');
      final lift = _d(touches.last, 't');
      final popped = _popped(rows);
      final motion = GlassBarMotion();
      motion.setLayout(0, detail, animated: false);
      double? progress;
      final own = <double>[];
      for (final r in rows) {
        if (r['k'] != 'B') continue;
        final t = _d(r, 't');
        if (r['cls'] == 'page' && r['lid'] == 88) {
          progress = (_d(r, 'x') - width / 2) / width;
          continue;
        }
        final p = progress;
        if (r['cls'] != 'capsule' || p == null || t <= down) continue;
        if (popped && t > lift) continue;
        final x = _d(r, 'x');
        final w = _d(r, 'w');
        final Object? id = switch ((x - w / 2, x + w / 2)) {
          (final l, _) when (l - 16).abs() < 1.5 => leading,
          (_, final r) when (r - 386).abs() < 1.5 => outer,
          _ when (x - 248.5).abs() < 1.5 => inner,
          _ => null,
        };
        if (id == null) continue;
        motion.setDrift(list, glassBarDrift * p);
        final frame = motion.capsuleFrame(id)!.rect;
        own.add(frame.width - w);
        own.add(frame.center.dx - x);
      }
      expect(own.length, greaterThan(80), reason: name);
      expect(_rms(own), lessThan(0.4), reason: name);
      errors.addAll(own);
    }
    expect(_rms(errors), lessThan(0.3));
  });
}
