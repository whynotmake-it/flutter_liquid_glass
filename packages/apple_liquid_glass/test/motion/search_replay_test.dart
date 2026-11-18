import 'dart:convert';
import 'dart:math' as math;

import 'package:apple_liquid_glass/src/motions/glass_press.dart';
import 'package:apple_liquid_glass/src/motions/search_motion.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';

import '../support/fixtures.dart';

extension on SearchMotion {
  SearchMotion seenAt(double t) {
    advance(t);
    return this;
  }
}

GlassPress _lift(Size size) => GlassPress.search(size: size);

const _dir = 'test/fixtures/ios27/search';

/// The probe screen: the iOS 27 simulator's iPhone 18 Pro Max, 440 x 956
/// points, keyboard 347 points tall.
const double _w = 440;
const double _h = 956;
const double _keyboard = 347;
const double _frame = 1 / 60;

List<Map<String, Object?>> _rows(String file, {String dir = _dir}) => [
  for (final line in Fixtures.lines('$dir/$file'))
    if (line.trim().isNotEmpty)
      (jsonDecode(line) as Map).cast<String, Object?>(),
];

double _d(Map<String, Object?> r, String k) => (r[k]! as num).toDouble();

double _script(List<Map<String, Object?>> rows, String action) =>
    _d(rows.firstWhere((r) => r['k'] == 'evt' && r['a'] == action), 't');

double _rms(List<double> e) =>
    math.sqrt(e.fold<double>(0, (a, b) => a + b * b) / math.max(1, e.length));

Rect _rect(Map<String, Object?> r) => Rect.fromCenter(
  center: Offset(_d(r, 'x'), _d(r, 'y')),
  width: _d(r, 'w'),
  height: _d(r, 'h'),
);

/// Fits the call time of a transition: UIKit starts it some time after the
/// probe's call (the keyboard's bring-up on a focus). Returns the call time
/// within [window] after [call] whose transition fits [errors] best.
(double, double) _fit(
  double call,
  double window,
  List<double> Function(double) errors,
) {
  var best = call;
  var bestErr = double.infinity;
  for (var lag = 0.0; lag <= window; lag += 0.001) {
    final e = _rms(errors(call + lag));
    if (e < bestErr) {
      bestErr = e;
      best = call + lag;
    }
  }
  return (best, bestErr);
}

void main() {
  final rest = searchBarLayout(
    width: _w,
    bottom: _h - SearchBarGeometry.restInset,
    focused: false,
  );
  final focused = searchBarLayout(
    width: _w,
    bottom: _h - _keyboard - SearchBarGeometry.keyboardGap,
    focused: true,
  );

  group('search toolbar replays the simulator', () {
    test('rest and focused geometry', () {
      expect(rest.field, const Rect.fromLTWH(28, 880, 384, 48));
      expect(focused.field, const Rect.fromLTWH(8, 551, 364, 48));
      expect(focused.close, const Rect.fromLTWH(384, 551, 48, 48));
      final items = searchBarLayout(
        width: _w,
        bottom: _h - 28,
        focused: false,
        leading: const [48],
        trailing: const [48],
      );
      expect(items.leading.single, const Rect.fromLTWH(28, 880, 48, 48));
      expect(items.field, const Rect.fromLTWH(88, 880, 264, 48));
      expect(items.trailing.single, const Rect.fromLTWH(364, 880, 48, 48));
    });

    for (final (source, dir, frame, size, keyboard) in [
      ('the simulator', _dir, _frame, const Size(_w, _h), _keyboard),
      (
        'an iPhone 16 Pro',
        'test/fixtures/ios27-device/search',
        1 / 120,
        const Size(402, 874),
        328.0,
      ),
    ]) {
      test('focus and cancel on $source: field, close button, one spring', () {
        final rest = searchBarLayout(
          width: size.width,
          bottom: size.height - SearchBarGeometry.restInset,
          focused: false,
        );
        final focused = searchBarLayout(
          width: size.width,
          bottom: size.height - keyboard - SearchBarGeometry.keyboardGap,
          focused: true,
        );
        final rows = _rows('search-toolbar.jsonl', dir: dir);
        final focusCall = _script(rows, 'focus');
        final cancelCall = _script(rows, 'cancel');
        // UIKit moves the close button a few frames behind the field (two
        // on the simulator; its opacity and scale are on time; a layout
        // artifact the port does not reproduce), so its position is compared
        // at the best lag of up to four frames.
        final glass = [
          for (final r in rows)
            if (r['k'] == 'V' &&
                (r['cls']! as String).endsWith('GlassInteractionView'))
              r,
        ];
        final field = [
          for (final r in glass)
            if (_d(r, 'bw') > 200) r,
        ];
        final close = [
          for (final r in glass)
            if (_d(r, 'bw') == 48 && _d(r, 't') > focusCall) r,
        ];
        List<double> fieldErrors(
          SearchMotion motion,
          double from,
          double to,
        ) => [
          for (final r in field)
            if (_d(r, 't') > from && _d(r, 't') < to)
              ...() {
                final t = _d(r, 't') + frame;
                final p = motion.seenAt(t).progress;
                final model = Rect.lerp(rest.field, focused.field, p)!;
                final seen = _rect(r);
                return [
                  model.left - seen.left,
                  model.width - seen.width,
                  model.top - seen.top,
                ];
              }(),
        ];
        SearchMotion focusAt(double call) {
          final motion = SearchMotion();
          motion.focus(call);
          return motion;
        }

        final (focusFit, focusRms) = _fit(
          focusCall,
          0.6,
          (call) => fieldErrors(focusAt(call), focusCall, cancelCall),
        );
        // The field travels over 300 points; 2 points rms is 0.6 percent,
        // the gap between the read spring and the free fits.
        expect(focusRms, lessThan(2));
        List<double> closeErrors(int lagFrames) {
          final motion = focusAt(focusFit);
          final lagging = focusAt(focusFit);
          return [
            for (final r in close)
              if (_d(r, 't') < cancelCall && _d(r, 'ea') > 0)
                ...() {
                  final t = _d(r, 't') + frame;
                  final p = motion.seenAt(t).progress;
                  final lagged = lagging.seenAt(t - lagFrames * frame).progress;
                  final model = Rect.lerp(rest.close, focused.close, lagged)!;
                  return [
                    (SearchMotion.appearScaleFor(p) - _d(r, 'w') / 48) * 48,
                    (p.clamp(0.0, 1.0) - _d(r, 'ea')) * 48,
                    model.center.dx - _d(r, 'x'),
                    model.center.dy - _d(r, 'y'),
                  ];
                }(),
          ];
        }

        final closeRms = [
          for (var lag = 0; lag <= 4; lag++) _rms(closeErrors(lag)),
        ].reduce(math.min);
        expect(closeRms, lessThan(2));
        List<double> cancelErrors(double call) {
          final m = SearchMotion();
          m.snap(0, focused: true);
          m.unfocus(call);
          return fieldErrors(m, cancelCall, double.infinity);
        }

        final (cancelFit, cancelRms) = _fit(
          cancelCall - 0.08,
          0.2,
          cancelErrors,
        );
        expect(cancelRms, lessThan(2));
        expect(cancelFit - cancelCall, closeTo(0, 0.04));
      });
    }

    test('the other toolbar items leave where they stand and come back', () {
      final rows = _rows('search-toolbar-items.jsonl');
      final focusCall = _script(rows, 'focus');
      final cancelCall = _script(rows, 'cancel');
      final items = searchBarLayout(
        width: _w,
        bottom: _h - 28,
        focused: false,
        leading: const [48],
        trailing: const [48],
      );
      final virtual = searchBarLayout(
        width: _w,
        bottom: _h - SearchBarGeometry.keyboardGap,
        focused: true,
        leading: const [48],
        trailing: const [48],
      );
      final glass = [
        for (final r in rows)
          if (r['k'] == 'V' &&
              (r['cls']! as String).endsWith('GlassInteractionView') &&
              _d(r, 'bw') == 48)
            r,
      ];
      final fieldRows = [
        for (final r in rows)
          if (r['k'] == 'V' &&
              (r['cls']! as String).endsWith('GlassInteractionView') &&
              _d(r, 'bw') > 200)
            r,
      ];
      final itemsFocused = searchBarLayout(
        width: _w,
        bottom: _h - _keyboard - SearchBarGeometry.keyboardGap,
        focused: true,
        leading: const [48],
        trailing: const [48],
      );
      List<double> fieldErrors(double call) {
        final m = SearchMotion();
        m.focus(call);
        return [
          for (final r in fieldRows)
            if (_d(r, 't') > focusCall && _d(r, 't') < cancelCall)
              Rect.lerp(
                    items.field,
                    itemsFocused.field,
                    m.seenAt(_d(r, 't') + _frame).progress,
                  )!.left -
                  _rect(r).left,
        ];
      }

      final (focusFit, fieldRms) = _fit(focusCall, 0.6, fieldErrors);
      expect(fieldRms, lessThan(1.5));
      final leaving = SearchMotion();
      leaving.focus(focusFit);
      final firstSeen = <int, double>{};
      for (final r in glass) {
        if (_d(r, 't') > focusCall) {
          firstSeen.putIfAbsent(r['id']! as int, () => _d(r, 'ea'));
        }
      }
      final out = <double>[];
      for (final r in glass) {
        final t = _d(r, 't') + _frame;
        if (_d(r, 't') <= focusCall || _d(r, 't') >= cancelCall) continue;
        if ((firstSeen[r['id']! as int] ?? 0) < 0.5) continue;
        final seen = _rect(r);
        final isLead = seen.center.dx < _w / 2;
        if (seen.center.dy < 700) continue;
        final p = leaving.seenAt(t).progress;
        final home = isLead ? items.leading.single : items.trailing.single;
        out.add(home.center.dx - seen.center.dx);
        out.add(home.center.dy - seen.center.dy);
        out.add(
          (SearchMotion.appearScaleFor(1 - p) - seen.width / 48) * 48,
        );
        out.add((1 - p).clamp(0.0, 1.0) * 48 - _d(r, 'ea') * 48);
      }
      expect(_rms(out), lessThan(1.5));
      List<double> back(double call) {
        final m = SearchMotion();
        m.snap(0, focused: true);
        m.unfocus(call);
        return [
          for (final r in glass)
            if (_d(r, 't') > cancelCall && _rect(r).center.dy > 700)
              ...() {
                final seen = _rect(r);
                final isLead = seen.center.dx < _w / 2;
                final p = m.seenAt(_d(r, 't') + _frame).progress;
                final from = isLead
                    ? virtual.leading.single
                    : virtual.trailing.single;
                final to = isLead
                    ? items.leading.single
                    : items.trailing.single;
                final model = Rect.lerp(from, to, 1 - p)!;
                return [
                  model.center.dx - seen.center.dx,
                  model.center.dy - seen.center.dy,
                  (1 - p).clamp(0.0, 1.0) * 48 - _d(r, 'ea') * 48,
                ];
              }(),
        ];
      }

      final (_, backRms) = _fit(cancelCall - 0.08, 0.2, back);
      expect(backRms, lessThan(1.5));
    });

    test('a held touch lifts the field like a glass button', () {
      final rows = _rows('search-hold.jsonl');
      final touches = [
        for (final r in rows)
          if (r['k'] == 'touch') r,
      ];
      final down = _d(touches.first, 't');
      final up = _d(touches.last, 't');
      final field = [
        for (final r in rows)
          if (r['k'] == 'V' &&
              (r['cls']! as String).endsWith('GlassInteractionView') &&
              _d(r, 'bw') == 384 &&
              _d(r, 't') < up)
            r,
      ];
      List<double> errors(double at) {
        final press = _lift(const Size(384, 48));
        press.pointerDown(at, Offset.zero);
        final out = <double>[];
        for (final r in field) {
          final t = _d(r, 't') + _frame;
          press.advance(t);
          out.add((press.scale - _d(r, 'w') / 384) * 384);
        }
        return out;
      }

      final (_, rms) = _fit(down - 0.02, 0.05, errors);
      expect(rms, lessThan(0.35));
    });
  });

  group('search toolbar touches replay an iPhone 16 Pro', () {
    const dir = 'test/fixtures/ios27-device/search';
    const size = Size(402, 874);
    const keyboard = 328.0;
    final rest = searchBarLayout(
      width: size.width,
      bottom: size.height - SearchBarGeometry.restInset,
      focused: false,
    );
    final focused = searchBarLayout(
      width: size.width,
      bottom: size.height - keyboard - SearchBarGeometry.keyboardGap,
      focused: true,
    );

    test('a tap focuses once the keyboard rises; the close button ends', () {
      final rows = _rows('search-tap.jsonl', dir: dir);
      final ups = [
        for (final r in rows)
          if (r['k'] == 'touch' && r['phase'] == 3) _d(r, 't'),
      ];
      final keyboardRise = _d(
        rows.firstWhere((r) => r['cls'] == 'keyboard' && _d(r, 't') > ups[0]),
        't',
      );
      final field = [
        for (final r in rows)
          if (r['cls'] == 'GlassInteractionView' && _d(r, 'bw') > 200) r,
      ];
      List<double> errors(SearchMotion motion, double from, double to) => [
        for (final r in field)
          if (_d(r, 't') > from && _d(r, 't') < to)
            ...() {
              final p = motion.seenAt(_d(r, 't')).progress;
              final model = Rect.lerp(rest.field, focused.field, p)!;
              return [model.top - _d(r, 'y') + 24];
            }(),
      ];
      SearchMotion at(double start, {required bool focus}) {
        final motion = SearchMotion();
        if (!focus) motion.snap(0, focused: true);
        if (focus) {
          motion.focus(start, delay: 0);
        } else {
          motion.unfocus(start - SearchTuning.transitionDelay);
        }
        return motion;
      }

      final (focusStart, focusRms) = _fit(
        ups[0],
        0.4,
        (start) => errors(at(start, focus: true), ups[0], ups[1]),
      );
      expect(focusRms, lessThan(2));
      expect(
        focusStart - keyboardRise,
        closeTo(SearchMotion.keyboardLag, 0.012),
      );
      final (closeStart, closeRms) = _fit(
        ups[1],
        0.2,
        (start) => errors(at(start, focus: false), ups[1], double.infinity),
      );
      expect(closeRms, lessThan(2));
      expect(
        closeStart - ups[1],
        closeTo(SearchTuning.transitionDelay, 0.02),
      );
    });

    test('a held touch lifts the field like a glass button', () {
      final rows = _rows('search-hold.jsonl', dir: dir);
      final touches = [
        for (final r in rows)
          if (r['k'] == 'touch') r,
      ];
      final down = _d(touches.first, 't');
      final up = _d(touches.last, 't');
      final width = rest.field.width;
      final field = [
        for (final r in rows)
          if (r['cls'] == 'GlassInteractionView' &&
              _d(r, 'bw') == width &&
              _d(r, 't') < up)
            r,
      ];
      List<double> errors(double at) {
        final press = _lift(Size(width, 48));
        press.pointerDown(at, Offset.zero);
        final out = <double>[];
        for (final r in field) {
          final t = _d(r, 't');
          press.advance(t);
          out.add((press.scale - _d(r, 'w') / width) * width);
        }
        return out;
      }

      // The device rows are compared as stamped: the lift shows 0.034 s
      // after the contact, GlassPress.searchDelay less the one 60 Hz
      // frame the simulator rows are shifted by.
      final (at, rms) = _fit(down - 0.05, 0.1, errors);
      expect(rms, lessThan(0.4));
      expect(at - down, closeTo(-1 / 60, 0.01));
    });
  });

  test('a tab bar search takes the focus mid-morph and falls straight back '
      '(iPhone 16 Pro, screen-recording session)', () {
    final rows = _rows(
      'vid-tab.jsonl',
      dir: 'test/fixtures/ios27-device/search',
    );
    final ups = [
      for (final r in rows)
        if (r['k'] == 'touch' && r['phase'] == 3) _d(r, 't'),
    ];
    final field = [
      for (final r in rows)
        if (r['cls'] == 'UISearchBarTextField') r,
    ];
    // The field reads its focused place 0.159 s after the lift of the tap
    // on the search circle, long before the morph settles.
    final present = _d(
      rows.firstWhere((r) => r['e'] == 'willPresentSearch'),
      't',
    );
    expect(present - ups[0], lessThan(SearchTuning.tabActivationDelay));
    // The close tap: the field falls from above the keyboard straight to
    // its place above the tab circle.
    final close = ups[1];
    const restY = 822.0;
    final focusedY = _d(field.lastWhere((r) => _d(r, 't') < close), 'y');
    var last = focusedY;
    for (final r in field) {
      final t = _d(r, 't');
      if (t <= close || t > close + 0.6) continue;
      expect(_d(r, 'y'), greaterThanOrEqualTo(last - 0.5));
      expect(_d(r, 'y'), lessThanOrEqualTo(restY + 0.5));
      last = _d(r, 'y');
    }
    final (fall, rms) = _fit(close, 0.12, (double start) {
      final motion = SearchMotion.tabFocus();
      motion.snap(0, focused: true);
      motion.unfocus(start, delay: 0);
      return [
        for (final r in field)
          if (_d(r, 't') > close && _d(r, 't') < close + 0.6)
            ...() {
              motion.advance(_d(r, 't'));
              final p = motion.seenAt(_d(r, 't')).progress;
              return [restY + (focusedY - restY) * p - _d(r, 'y')];
            }(),
      ];
    });
    expect(rms, lessThan(1));
    // 0.064 s here, 0.038 s in tab-search-focus: tabUnfocusDelay is the
    // middle of the two.
    expect(fall - close, closeTo(SearchTuning.tabUnfocusDelay, 0.016));
  });

  test('a tab bar search rises once the keyboard does (iPhone 16 Pro)', () {
    final rows = _rows(
      'tab-search-focus.jsonl',
      dir: 'test/fixtures/ios27-device/search',
    );
    final ups = [
      for (final r in rows)
        if (r['k'] == 'touch' && r['phase'] == 3) _d(r, 't'),
    ];
    final keyboardRise = _d(
      rows.firstWhere((r) => r['cls'] == 'keyboard' && _d(r, 't') > ups[0]),
      't',
    );
    final field = [
      for (final r in rows)
        if (r['cls'] == 'field') r,
    ];
    const restY = 822.0;
    final focusedY = _d(field.lastWhere((r) => _d(r, 't') < ups[1]), 'y');
    List<double> errors(double start, {required bool focus}) {
      final motion = SearchMotion.tabFocus();
      if (focus) {
        motion.focus(start, delay: 0);
      } else {
        motion.snap(0, focused: true);
        motion.unfocus(start, delay: 0);
      }
      final from = focus ? ups[0] : ups[1];
      final to = focus ? ups[1] : ups[1] + 0.6;
      return [
        for (final r in field)
          if (_d(r, 't') > from && _d(r, 't') < to)
            ...() {
              motion.advance(_d(r, 't'));
              final p = motion.seenAt(_d(r, 't')).progress;
              return [restY + (focusedY - restY) * p - _d(r, 'y')];
            }(),
      ];
    }

    final (rise, riseRms) = _fit(
      keyboardRise,
      0.2,
      (start) => errors(start, focus: true),
    );
    expect(riseRms, lessThan(1.5));
    expect(
      rise - keyboardRise,
      closeTo(SearchTuning.tabKeyboardLag, 0.015),
    );
    final (fall, fallRms) = _fit(
      ups[1],
      0.15,
      (start) => errors(start, focus: false),
    );
    expect(fallRms, lessThan(1.5));
    expect(fall - ups[1], closeTo(SearchTuning.tabUnfocusDelay, 0.015));
  });

  group('SearchMotion', () {
    test('the transition starts after the measured delay', () {
      final motion = SearchMotion();
      motion.focus(0);
      motion.advance(SearchTuning.transitionDelay - 0.001);
      expect(motion.seenAt(motion.now).progress, 0);
      motion.advance(1);
      expect(motion.seenAt(1).progress, closeTo(1, 1e-3));
      expect(motion.isSettled, isTrue);
    });

    test('a reversal mid-way keeps the velocity', () {
      final motion = SearchMotion();
      motion.focus(0);
      motion.advance(0.15);
      final p = motion.seenAt(0.15).progress;
      motion.unfocus(0.15);
      motion.advance(0.15 + SearchTuning.transitionDelay);
      expect(
        motion.seenAt(0.15 + SearchTuning.transitionDelay).progress,
        greaterThan(p),
      );
      motion.advance(2);
      expect(motion.seenAt(2).progress, closeTo(0, 1e-3));
    });

    test('a focus waits for the keyboard, and starts anyway at the limit', () {
      final waiting = SearchMotion();
      waiting.focusAfterKeyboard(0);
      expect(waiting.isFocused, isTrue);
      waiting.advance(0.2);
      expect(waiting.seenAt(0.2).progress, 0);
      waiting.keyboardRose(0.2, lag: SearchMotion.keyboardLag);
      expect(waiting.waitsForKeyboard, isFalse);
      expect(waiting.seenAt(0.2 + SearchMotion.keyboardLag).progress, 0);
      expect(waiting.seenAt(0.25).progress, greaterThan(0));
      final timedOut = SearchMotion();
      timedOut.focusAfterKeyboard(0);
      expect(timedOut.seenAt(SearchTuning.keyboardWaitLimit).progress, 0);
      expect(timedOut.waitsForKeyboard, isFalse);
      expect(timedOut.seenAt(0.4).progress, greaterThan(0));
      expect(timedOut.seenAt(2).progress, 1);
      expect(timedOut.isSettled, isTrue);
    });

    test('a quick tap barely lifts the field; reduced motion never does', () {
      final press = _lift(const Size(384, 48));
      press.pointerDown(0, Offset.zero);
      press.advance(0.04);
      expect(press.scale, 1);
      press.pointerUp(0.04, Offset.zero);
      press.advance(1);
      expect(press.scale, closeTo(1, 1e-4));
      MotionTraits.debugPlatformOverride = const MotionTraits(
        reduceMotion: true,
      );
      addTearDown(() => MotionTraits.debugPlatformOverride = null);
      final calm = _lift(const Size(384, 48));
      calm.pointerDown(0, Offset.zero);
      calm.advance(0.5);
      expect(calm.scale, 1);
    });
  });

  group('tab bar search replays the simulator', () {
    test('rest, searching and focused geometry', () {
      final g = searchTabLayout(
        size: const Size(_w, _h),
        barWidth: 188,
        keyboard: _keyboard,
      );
      expect(g.bar, const Rect.fromLTWH(21, 873, 188, 62));
      expect(g.search, const Rect.fromLTWH(357, 873, 62, 62));
      expect(g.tab, const Rect.fromLTWH(28, 880, 48, 48));
      expect(g.field, const Rect.fromLTWH(88, 880, 324, 48));
      expect(g.focusedField, const Rect.fromLTWH(8, 553, 368, 48));
      expect(g.close, const Rect.fromLTWH(384, 553, 48, 48));
    });

    test('the bar and the search circle trade places on the tab spring', () {
      final data = (jsonDecode(
        Fixtures.read('$_dir/tab-search-video.json'),
      ) as Map).cast<String, Object?>();
      final rows = (data['rows']! as List).cast<Map<String, Object?>>();
      final g = searchTabLayout(size: const Size(_w, _h), barWidth: 188);
      // The video's dark-pixel runs on row 924 cross each capsule where
      // its rounded end meets the row; a capsule of height h centered at
      // cy is that far inside its box: r - sqrt(r^2 - (924 - cy)^2).
      double inset(Rect r) {
        final radius = r.height / 2;
        final dy = (924 - r.center.dy).abs();
        return radius - math.sqrt(math.max(0, radius * radius - dy * dy));
      }

      List<double> errors(double start) {
        final spring = MotionValue<double>(
          0,
          spring: SearchTuning.tabSpring,
        );
        spring.retarget(start, 1);
        final out = <double>[];
        for (final row in rows) {
          final t = _d(row, 't');
          final runs = [
            for (final run in (row['runs']! as List).cast<List<Object?>>())
              if ((run[1]! as num) - (run[0]! as num) <= 3)
                (run[0]! as num).toDouble(),
          ];
          if (runs.length < 4 || t < start - 0.02) continue;
          final q = spring.valueAt(t);
          final bar = Rect.lerp(g.bar, g.tab, q)!;
          final search = Rect.lerp(g.search, g.field, q)!;
          double nearest(double x) =>
              runs.reduce((a, b) => (a - x).abs() < (b - x).abs() ? a : b);
          final barEdge = bar.right - inset(bar);
          final searchEdge = search.left + inset(search);
          final a = barEdge - nearest(barEdge);
          final b = searchEdge - nearest(searchEdge);
          // One frame of the video catches the glass mid-redraw without
          // the tab circle's edge; frames that far off are skipped.
          if (a.abs() > 12 || b.abs() > 12) continue;
          out.add(a);
          out.add(b);
        }
        return out;
      }

      final firstT = _d(rows.first, 't');
      final (_, rms) = _fit(firstT, 0.4, errors);
      expect(rms, lessThan(3));
    });
  });
}
