import 'dart:convert';
import 'dart:math' as math;

import 'package:apple_liquid_glass/src/motions/zoom_page_motion.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

import '../support/fixtures.dart';

extension on ZoomPageMotion {
  ZoomPageMotion seenAt(double t) {
    advance(t);
    return this;
  }
}

ZoomPageMotion _opened(
  double t,
  Rect source,
  Rect page, {
  double sourceRadius = 0,
}) {
  final motion = ZoomPageMotion(page: page);
  motion.sourceMoved(
    t,
    SourceGeometry(
      rect: source,
      radius: BorderRadius.all(Radius.circular(sourceRadius)),
    ),
  );
  motion.open(t);
  motion.start(t);
  return motion;
}

void _close(ZoomPageMotion motion, double t, Rect source) {
  motion.sourceMoved(t, SourceGeometry(rect: source));
  motion.leave(t, DismissTrigger.programmatic);
}

Rect _rect(List<Object?> v) => Rect.fromLTRB(
  (v[0]! as num).toDouble(),
  (v[1]! as num).toDouble(),
  (v[2]! as num).toDouble(),
  (v[3]! as num).toDouble(),
);

Map<String, Object?> _fixture() => jsonDecode(
  Fixtures.read('test/fixtures/ios27-device/push_zoom/push_zoom.json'),
) as Map<String, Object?>;

List<Map<String, Object?>> _list(Object? v) =>
    (v! as List<Object?>).cast<Map<String, Object?>>();

double _edgeRms(Iterable<(Rect, Rect)> pairs) {
  var sum = 0.0;
  var n = 0;
  for (final (a, b) in pairs) {
    for (final d in [
      a.left - b.left,
      a.top - b.top,
      a.right - b.right,
      a.bottom - b.bottom,
    ]) {
      sum += d * d;
      n++;
    }
  }
  return n == 0 ? 0 : math.sqrt(sum / n);
}

const _page = Rect.fromLTWH(0, 0, 402, 874);

const _rowsTrail = 1 / 60;

const _velocityWindow = 0.05;

const _dragLimits = {
  'pd-down-150': (3.0, 2.5),
  'pd-down-110': (3.0, 2.0),
  'pd-down-125': (4.5, 7.5),
  'pd-down-140': (3.0, 2.5),
  'pd-flick-100': (15.0, 45.0),
  'pd-flick': (8.0, 10.0),
  'push-zoom-swipe-down': (3.0, 6.0),
  'push-zoom-swipe-cancel': (3.5, 1.5),
  'pd-right-mid': (6.0, 0.5),
  'push-zoom-edge': (10.0, 9.0),
};
const _card = Rect.fromLTWH(121.33, 250, 160, 100);

void main() {
  group('device replay', () {
    for (final segment in _list(_fixture()['segments'])) {
      final name = segment['name']! as String;
      final way = segment['way']! as String;
      test('$name follows the recording', () {
        final from = _rect(segment['from']! as List<Object?>);
        final to = _rect(segment['to']! as List<Object?>);
        final page = way == 'open' ? to : from;
        final ZoomPageMotion motion;
        if (way == 'open') {
          motion = _opened(0, from, to);
        } else {
          motion = _opened(-10, to, from);
          motion.advance(0);
          _close(motion, 0, to);
        }
        final pairs = <(Rect, Rect)>[];
        var fadeError = 0.0;
        for (final f in _list(segment['frames'])) {
          final t = (f['t']! as num).toDouble();
          if (t < 0) continue;
          motion.advance(t);
          pairs.add((
            motion.seenAt(t).rect.shift(page.topLeft),
            _rect(f['rect']! as List<Object?>),
          ));
          final fade = f['fade'] as num?;
          if (fade != null) {
            fadeError = math.max(
              fadeError,
              (motion.seenAt(t).fade - fade.toDouble()).abs(),
            );
          }
        }
        expect(_edgeRms(pairs), lessThan(way == 'open' ? 1.6 : 1.0));
        expect(fadeError, lessThan(0.12));
      });
    }
  });

  group('device drags', () {
    for (final drag in _list(_fixture()['drags'])) {
      final name = drag['name']! as String;
      test('$name follows the finger and ends as UIKit did', () {
        final touches = [
          for (final v in (drag['touches']! as List<Object?>))
            [for (final x in (v! as List<Object?>)) (x! as num).toDouble()],
        ];
        final lift = (drag['lift']! as num).toDouble() - _rowsTrail;
        final motion = _opened(-10, _card, _page);
        motion.advance(0);
        motion.dragStart(0, Offset(touches.first[1], touches.first[2]));
        var next = 1;
        bool? dismissed;
        var dragSum = 0.0;
        var dragN = 0;
        var endSum = 0.0;
        var endN = 0;
        for (final f in _list(drag['frames'])) {
          final t = (f['t']! as num).toDouble();
          while (next < touches.length && touches[next][0] <= t) {
            final p = touches[next];
            if (p[0] < lift) {
              motion.dragUpdate(p[0], Offset(p[1], p[2]));
            }
            next++;
          }
          if (dismissed == null && t >= lift) {
            final last = touches.last;
            final before = touches.firstWhere(
              (p) => p[0] >= last[0] - _velocityWindow,
            );
            final dt = math.max(1e-3, last[0] - before[0]);
            final velocity = Offset(
              (last[1] - before[1]) / dt,
              (last[2] - before[2]) / dt,
            );
            motion.dragUpdate(lift, Offset(last[1], last[2]));
            dismissed = motion.dragEnd(lift, velocity);
            if (dismissed) _close(motion, lift, _card);
          }
          motion.advance(t);
          final r = motion.seenAt(t).rect;
          final want = f['rect']! as List<Object?>;
          final got = [r.left, r.top, r.right, r.bottom];
          for (var i = 0; i < 4; i++) {
            final w = want[i] as num?;
            if (w == null) continue;
            final d = got[i] - w.toDouble();
            if (t < lift) {
              dragSum += d * d;
              dragN++;
            } else {
              endSum += d * d;
              endN++;
            }
          }
        }
        final dragRms = math.sqrt(dragSum / math.max(1, dragN));
        final endRms = math.sqrt(endSum / math.max(1, endN));
        final (dragLimit, endLimit) = _dragLimits[name]!;
        expect(dismissed, drag['outcome'] == 'dismiss');
        expect(dragRms, lessThan(dragLimit));
        expect(endRms, lessThan(endLimit));
      });
    }
  });

  group('motion', () {
    test('a pop mid-open turns around with the velocity it had', () {
      final motion = _opened(0, _card, _page);
      final opening = _opened(0, _card, _page);
      final ahead = opening.seenAt(0.081).rect;
      final before = motion.seenAt(0.08).rect;
      _close(motion, 0.08, _card);
      expect(motion.rect, before);
      final after = motion.seenAt(0.081).rect;
      expect((after.width - ahead.width).abs(), lessThan(0.5));
    });

    test('the corner radius runs from the source to the display', () {
      final motion = _opened(0, _card, _page, sourceRadius: 16);
      motion.displayRadius = 62;
      expect(motion.seenAt(0).radius, closeTo(16, 1e-9));
      motion.advance(3);
      expect(motion.seenAt(3).radius, closeTo(62, 0.1));
      expect(motion.presence, PresenceStatus.shown);
    });

    test('a close rests on the source', () {
      final motion = _opened(0, _card, _page);
      motion.advance(2);
      _close(motion, 2, _card);
      motion.advance(4);
      expect(motion.presence, PresenceStatus.hidden);
      final r = motion.seenAt(4).rect;
      expect(r.left, closeTo(_card.left, 0.1));
      expect(r.height, closeTo(_card.height, 0.1));
    });
  });
}
