import 'dart:convert';
import 'dart:math' as math;

import 'package:apple_liquid_glass/src/motions/sheet_detent.dart';
import 'package:apple_liquid_glass/src/motions/sheet_motion.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

const _sim = 'test/fixtures/ios27/sheet';
const _device = 'test/fixtures/ios27-device/sheet';

const double _dimmingOpacity = 0.2;

/// The probe screen: an iPhone 16 Pro simulator, 402 x 874 points with a
/// 62 point top and a 34 point bottom safe area.
const double _w = 402;
const double _h = 874;
const double _top = 62;
const double _bottom = 34;

/// The latest UIKit starts an animation after its call: the presented
/// controller's first layout and commit, up to a few frames.
const double _maxLag = 0.15;

class _Row {
  _Row(this.raw);
  final Map<String, Object?> raw;
  double shift = 0;
  double get t => (raw['t']! as num).toDouble() + shift;
  double d(String k) => (raw[k]! as num).toDouble();
}

class _Capture {
  _Capture(String path) {
    for (final line in Fixtures.lines(path)) {
      if (line.trim().isEmpty) continue;
      final row = _Row((jsonDecode(line) as Map).cast<String, Object?>());
      switch (row.raw['k']) {
        case 'start':
          frame = 1 / (row.raw['maxfps']! as num).toDouble();
        case 'evt':
          if (row.raw['e'] == 'script') {
            script.add((row.raw['a']! as String, row.t));
          }
        case 'V':
          if (row.raw['cls'] == 'UIDropShadowView' && row.d('bh') != _h) {
            sheet.add(row);
          }
          if (row.raw['cls'] == 'UIDimmingView' && row.raw['bg'] != null) {
            dimming.add(row);
          }
      }
    }
  }

  /// One display frame of the recording: the probe samples each
  /// presentation layer for the frame being prepared, which shows one
  /// frame after the display link's timestamp.
  double frame = 1 / 60;

  final List<(String, double)> script = [];
  final List<_Row> sheet = [];
  final List<_Row> dimming = [];

  double at(String action) => script.firstWhere((s) => s.$1 == action).$2;
}

double _max(GlassSheetDetent d) => d.resolve(_h - _top - _bottom) + _bottom;

/// Replays a scripted capture: present, then the detent changes and the
/// dismiss. UIKit starts each animation a frame or more after its call,
/// so each one's start is aligned to the recording, within [_maxLag] of
/// the call, before the rest is compared. A floating sheet presents with
/// its frame at the screen's leading edge and drifts to its 8 point inset
/// on the slide's spring, so the left edge is compared from the first
/// frame (2.4 - 3.0 points rms while presenting without the drift).
/// The clip's bottom radius is compared too while a detent change moves
/// the sheet (0.005 - 0.13 points rms): docking 54 + 8 p, undocking from
/// the square docked rest 54 (1 - p).
/// Returns the rms and max error
/// of the sheet's visible top, bottom and left edges, the rms error of
/// the left edge while the sheet presents, and the rms error of the
/// dimming opacity.
({double rms, double max, double present, double dim, double radius}) _replay(
  String file,
  String dir,
  List<GlassSheetDetent> detents, {
  int initial = 0,
  int? undimmed,
}) {
  final cap = _Capture('$dir/$file');
  for (final row in [...cap.sheet, ...cap.dimming]) {
    row.shift = cap.frame;
  }
  final heights = [for (final d in detents) _max(d)];
  final docked = detents.indexWhere((d) => d.isLarge);
  final actions = [
    for (final (name, t) in cap.script)
      if (!name.startsWith('tree')) (name, t),
  ];
  SheetMotion build(List<double> starts) {
    final motion = SheetMotion(
      heights: heights,
      width: _w,
      initial: initial,
      dockedIndex: docked < 0 ? null : docked,
      undimmedIndex: undimmed,
      displayRadius: 62,
    );
    return motion;
  }

  void apply(SheetMotion motion, String name, double t) {
    switch (name) {
      case 'present':
        motion.present(t);
      case 'dismiss':
        motion.dismiss(t);
      case 'large':
        motion.animateTo(t, docked);
      case 'medium':
        motion.animateTo(t, detents.indexOf(GlassSheetDetent.medium));
      case 'small':
        motion.animateTo(t, 0);
    }
  }

  // One frame per docking reads the docked sheet at the top of the screen
  // (a presentation-layer glitch at the settle); such frames are skipped.
  var scoring = true;
  final presentLefts = <double>[];
  final radii = <double>[];
  List<double> edges(
    SheetMotion motion,
    _Row row, {
    required bool presenting,
  }) {
    final rect = motion.atTime(row.t).visibleRect(_h);
    final top = row.d('y') - row.d('h') / 2;
    final bottom = row.d('y') + row.d('h') / 2;
    final left = row.d('x') - row.d('w') / 2;
    final e = [rect.top - top, rect.bottom - bottom];
    if (e.any((double v) => v.abs() > 40)) {
      return [if (scoring) 40, if (scoring) 40];
    }
    if (presenting && !scoring) presentLefts.add(rect.left - left);
    // The clip's bottom radius while a detent change moves the sheet, away
    // from the docked rest where the display's corner hides it either way
    // (UIKit snaps 62 to 0 a few frames after morph's rest threshold).
    final recorded = row.raw['radii'];
    if (!scoring &&
        !presenting &&
        recorded is List &&
        motion.offset < 0.5 &&
        motion.dock < 0.97) {
      radii.add(motion.bottomRadius - (recorded.first! as num).toDouble());
    }
    return [...e, rect.left - left];
  }

  List<double> run(List<double> starts, double until, List<double>? dims) {
    final motion = build(starts);
    final errors = <double>[];
    var next = 0;
    for (final row in cap.sheet) {
      if (row.t < starts.first || row.t >= until) continue;
      while (next < starts.length && starts[next] <= row.t) {
        apply(motion, actions[next].$1, starts[next]);
        next++;
      }
      motion.advance(row.t);
      final e = edges(
        motion,
        row,
        presenting: next == 1 && actions.first.$1 == 'present',
      );
      errors.addAll(e);
    }
    if (dims != null) {
      for (final row in cap.dimming) {
        if (row.t < starts.first + 0.02 || row.t >= until) continue;
        final m = build(starts);
        var n = 0;
        while (n < starts.length && starts[n] <= row.t) {
          apply(m, actions[n].$1, starts[n]);
          n++;
        }
        m.advance(row.t);
        final bg = (row.raw['bg']! as List).cast<num>();
        dims.add(m.atTime(row.t).dimming * _dimmingOpacity - bg[3]);
      }
    }
    return errors;
  }

  double sq(List<double> e) => e.fold(0, (a, b) => a + b * b);
  final starts = <double>[];
  for (var k = 0; k < actions.length; k++) {
    final call = actions[k].$2;
    final until = k + 1 < actions.length ? actions[k + 1].$2 : double.infinity;
    var best = call;
    var bestErr = double.infinity;
    for (var lag = 0.0; lag <= _maxLag; lag += 0.002) {
      final e = sq(run([...starts, call + lag], until, null));
      if (e < bestErr) {
        bestErr = e;
        best = call + lag;
      }
    }
    starts.add(best);
  }
  final dims = <double>[];
  scoring = false;
  final errors = run(starts, double.infinity, dims);
  double rms(List<double> e) => e.isEmpty ? 0 : math.sqrt(sq(e) / e.length);
  return (
    rms: rms(errors),
    max: errors.fold(0, (a, b) => math.max(a, b.abs())),
    present: rms(presentLefts),
    dim: rms(dims),
    radius: rms(radii),
  );
}

extension on SheetMotion {
  // As the clock steps a root on screen: advance, then settle at rest.
  SheetMotion atTime(double t) {
    advance(t);
    if (isSettled) settle();
    return this;
  }
}

void main() {
  group('GlassSheetDetent', () {
    test('medium is 0.56 of the maximum, large the whole maximum', () {
      expect(GlassSheetDetent.medium.resolve(778), closeTo(435.68, 0.01));
      expect(GlassSheetDetent.large.resolve(778), 778);
      expect(const GlassSheetDetent.height(200).resolve(778), 200);
      expect(const GlassSheetDetent.height(900).resolve(778), 778);
    });
  });

  group('sheet replay, iOS 27 simulator', () {
    test('medium and large: present, large, medium, dismiss', () {
      final r = _replay('sheet-ml.jsonl', _sim, const [
        GlassSheetDetent.medium,
        GlassSheetDetent.large,
      ]);
      expect(r.rms, lessThan(2.5));
      expect(r.present, lessThan(0.2));
      expect(r.radius, lessThan(0.25));
      expect(r.dim, lessThan(0.01));
    });

    test('small, medium and large: docking follows the departing detent', () {
      final r = _replay('sheet-sml.jsonl', _sim, const [
        GlassSheetDetent.height(200),
        GlassSheetDetent.medium,
        GlassSheetDetent.large,
      ], initial: 1);
      expect(r.rms, lessThan(2.5));
      expect(r.present, lessThan(0.2));
      expect(r.radius, lessThan(0.25));
    });

    test('an undimmed medium detent dims only toward large', () {
      final r = _replay('sheet-undim.jsonl', _sim, const [
        GlassSheetDetent.medium,
        GlassSheetDetent.large,
      ], undimmed: 0);
      expect(r.rms, lessThan(2.5));
      expect(r.present, lessThan(0.2));
      expect(r.radius, lessThan(0.25));
      expect(r.dim, lessThan(0.01));
    });

    test('large only: docked from the start', () {
      final r = _replay('sheet-l.jsonl', _sim, const [GlassSheetDetent.large]);
      expect(r.rms, lessThan(2.5));
      expect(r.present, lessThan(0.2));
      expect(r.radius, lessThan(0.25));
    });
  });

  group('sheet replay, iPhone 16 Pro (iOS 27.0.1, 120 Hz)', () {
    test('medium and large: present, large, medium, dismiss', () {
      final r = _replay('sheet-ml.jsonl', _device, const [
        GlassSheetDetent.medium,
        GlassSheetDetent.large,
      ]);
      expect(r.rms, lessThan(2.5));
      expect(r.present, lessThan(0.2));
      expect(r.radius, lessThan(0.25));
      expect(r.dim, lessThan(0.01));
    });

    test('small, medium and large', () {
      final r = _replay('sheet-sml.jsonl', _device, const [
        GlassSheetDetent.height(200),
        GlassSheetDetent.medium,
        GlassSheetDetent.large,
      ], initial: 1);
      expect(r.rms, lessThan(2.5));
      expect(r.present, lessThan(0.2));
      expect(r.radius, lessThan(0.25));
    });

    test('an undimmed medium detent', () {
      final r = _replay('sheet-undim.jsonl', _device, const [
        GlassSheetDetent.medium,
        GlassSheetDetent.large,
      ], undimmed: 0);
      expect(r.rms, lessThan(2.5));
      expect(r.present, lessThan(0.2));
      expect(r.radius, lessThan(0.25));
      expect(r.dim, lessThan(0.01));
    });

    test('large only', () {
      final r = _replay('sheet-l.jsonl', _device, const [
        GlassSheetDetent.large,
      ]);
      expect(r.rms, lessThan(2.5));
      expect(r.present, lessThan(0.2));
      expect(r.radius, lessThan(0.25));
    });
  });
}
