import 'dart:convert';
import 'dart:math' as math;

import 'package:apple_liquid_glass/src/motions/menu_layout.dart';
import 'package:apple_liquid_glass/src/motions/menu_morph_spec.dart';
import 'package:apple_liquid_glass/src/motions/menu_motion.dart';
import 'package:apple_liquid_glass/src/motions/menu_tuning.dart';
import 'package:apple_liquid_glass/src/motions/menu_values.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';

import '../support/fixtures.dart';
import 'menu_events.dart';

const Offset _held = Offset(201, 300);
const Size _screen = Size(402, 874);
const double _frame = 1 / 120;

List<List<double>> _frames(Object? raw) => <List<double>>[
  for (final sample in (raw! as List).cast<List<Object?>>())
    <double>[for (final value in sample) (value! as num).toDouble()],
];

Map<String, Object?> _json(String name) => (jsonDecode(
  Fixtures.read('test/fixtures/ios27-device/context_menu/$name.json'),
) as Map).cast<String, Object?>();

Size _card(Map<String, Object?> c) {
  final size = (c['card']! as List).cast<num>();
  return Size(size[0].toDouble(), size[1].toDouble());
}

/// A context menu motion for a [size] view held at [_held], with a menu of
/// four rows [height] points tall in all.
MenuMotion _motion(Size size, {double height = 208}) {
  final held = Rect.fromCenter(
    center: _held,
    width: size.width,
    height: size.height,
  );
  final lift = _previewScale(size);
  return MenuMotion(
    source: MenuSource(held),
    bounds: _screen,
    tuning: MenuTuning.context,
    layout: ({required bool reversed}) => MenuLayout.uniform(
      4,
      rowHeight: (height - 20) / 4,
      reversed: reversed,
    ),
    attachment: MenuAttachment(
      held: held,
      preview: Rect.fromCenter(
        center: _held,
        width: size.width * lift,
        height: size.height * lift,
      ),
    ),
  );
}

/// The rms error of [device] samples (`(t, value)`) against [ours] at the
/// best placement of our zero within 0.25 s before the first device
/// sample.
double _replayError(
  List<(double, double)> device,
  List<(double, double)> ours,
) {
  double at(double t) {
    if (t <= ours.first.$1) return ours.first.$2;
    for (var i = 1; i < ours.length; i++) {
      final (t1, v1) = ours[i];
      if (t <= t1) {
        final (t0, v0) = ours[i - 1];
        return v0 + (v1 - v0) * (t - t0) / (t1 - t0);
      }
    }
    return ours.last.$2;
  }

  var best = double.infinity;
  for (var i = 0; i < 500; i++) {
    final zero = device.first.$1 - i / 2000;
    var squares = 0.0;
    for (final (t, value) in device) {
      final error = at(t - zero) - value;
      squares += error * error;
    }
    best = math.min(best, math.sqrt(squares / device.length));
  }
  return best;
}

void main() {
  test('the context morph runs on the preview spring both ways, without '
      'kicks or fusion', () {
    const spec = MenuMorphSpec.context;
    expect(spec.eject, _contextSpring);
    expect(spec.absorb, _contextSpring);
    expect(spec.speed, 1);
    expect(spec.kicks, isFalse);
    expect(spec.fuses, isFalse);
    expect(
      MenuTuning.context.openSpring,
      _contextSpring,
    );
    expect(
      MenuTuning.context.closeSpring,
      _contextSpring,
    );
  });

  test('the blob is 0.4 of the held view at its center on every recorded '
      'size', () {
    final growth = _json('growth');
    var count = 0;
    for (final c in (growth['cases']! as List).cast<Map<String, Object?>>()) {
      final blob = (c['blob'] as List?)?.cast<num>();
      if (blob == null) continue;
      final menu = (c['menu']! as List).cast<num>();
      final size = MenuAttachment.blobSize(_card(c), menu[3].toDouble());
      expect(
        size.width,
        closeTo(blob[0].toDouble(), 0.4),
        reason: '${c['name']}',
      );
      expect(
        size.height,
        closeTo(blob[1].toDouble(), 0.4),
        reason: '${c['name']}',
      );
      count++;
    }
    expect(count, 17);
  });

  test('the menu stands 16 points below the lifted preview, centered on it, '
      'and starts as the blob', () {
    final growth = _json('growth');
    for (final c in (growth['cases']! as List).cast<Map<String, Object?>>()) {
      final blob = (c['blob'] as List?)?.cast<num>();
      if (blob == null) continue;
      final menu = (c['menu']! as List).cast<num>();
      final motion = _motion(_card(c), height: menu[3].toDouble());
      motion.open(0);
      motion.advance(0);
      final start = motion.menuBlob.rect;
      expect(start.center.dx, closeTo(201, 1e-9), reason: '${c['name']}');
      expect(start.center.dy, closeTo(300, 1e-9), reason: '${c['name']}');
      expect(
        start.width,
        closeTo(blob[0].toDouble(), 0.4),
        reason: '${c['name']}',
      );
      expect(start.height, closeTo(blob[1].toDouble(), 0.4));
      expect(motion.drawsSource, isFalse);
      final bounds = motion.silhouette!.path.getBounds();
      expect((bounds.topLeft - start.topLeft).distance, lessThan(1e-3));
      expect(bounds.size.width, closeTo(start.width, 1e-3));
      motion.advance(2);
      final rect = motion.menuBlob.rect;
      expect(rect.center.dx, closeTo(menu[0].toDouble(), 0.01));
      expect(rect.center.dy, closeTo(menu[1].toDouble(), 0.01));
      expect(rect.width, closeTo(menu[2].toDouble(), 0.01));
      expect(rect.height, closeTo(menu[3].toDouble(), 0.01));
      expect(motion.previewShift, Offset.zero);
      expect(motion.opensDown, isTrue);
    }
  });

  final morph = _json('morph');
  final cases = (morph['cases']! as List).cast<Map<String, Object?>>();
  for (final name in <String>['ctxd-m-1', 'ctxd-l-1']) {
    test('$name: the menu replays the device morph, open and close', () {
      final c = cases.firstWhere((Map<String, Object?> c) => c['name'] == name);
      final size = _card(c);
      final rect = (c['menuRect']! as List).cast<num>();
      final menuY = rect[1].toDouble();
      final parts = (c['menu']! as Map).cast<String, Object?>();
      final motion = _motion(size, height: rect[3].toDouble());
      // A few frames at rest before each change: the device's first frames
      // may still be at rest, and the alignment only moves our zero
      // earlier.
      const preRoll = 6;
      final open = <(double, Rect)>[
        for (var i = -preRoll; i < 0; i++) (i * _frame, motion.menuBlob.rect),
      ];
      motion.open(0);
      for (var i = 0; i <= 240; i++) {
        motion.advance(i * _frame);
        open.add((i * _frame, motion.menuBlob.rect));
      }
      expect(motion.isSettled, isTrue);
      const closeAt = 3.0;
      final close = <(double, Rect)>[
        for (var i = -preRoll; i < 0; i++) (i * _frame, motion.menuBlob.rect),
      ];
      motion.close(closeAt);
      for (var i = 0; i <= 120; i++) {
        motion.advance(closeAt + i * _frame);
        close.add((i * _frame, motion.menuBlob.rect));
      }
      final deviceOpen = <(double, double)>[
        for (final f in _frames(parts['open']))
          (f[0], (f[2] - 300) / (menuY - 300)),
      ];
      final deviceClose = <(double, double)>[
        for (final f in _frames(parts['close']))
          if (f[2] > 300 + 0.05 * (menuY - 300))
            (f[0], (menuY - f[2]) / (menuY - 300)),
      ];
      final ourOpen = <(double, double)>[
        for (final (t, r) in open) (t, (r.center.dy - 300) / (menuY - 300)),
      ];
      final ourClose = <(double, double)>[
        for (final (t, r) in close) (t, (menuY - r.center.dy) / (menuY - 300)),
      ];
      final openError = _replayError(deviceOpen, ourOpen);
      final closeError = _replayError(deviceClose, ourClose);
      final sizes = <double>[];
      final peaks = <double>[];
      for (final axis in <int>[3, 4]) {
        final extent = rect[axis - 1].toDouble();
        final blob = _frames(parts['open']).first[axis];
        final device = <(double, double)>[
          for (final f in _frames(parts['open']))
            (f[0], (f[axis] - blob) / (extent - blob)),
        ];
        final ours = <(double, double)>[
          for (final (t, r) in open)
            (t, ((axis == 3 ? r.width : r.height) - blob) / (extent - blob)),
        ];
        sizes.add(_replayError(device, ours));
        peaks.add(ours.map(((double, double) f) => f.$2).reduce(math.max));
      }
      // ignore: avoid_print
      print(
        '$name menu replay: open $openError, close $closeError, '
        'width ${sizes[0]}, height ${sizes[1]}, peaks $peaks',
      );
      // Fractions of the travel. The close sits on the measured spring's
      // own floor for these frames (0.75 / 0.76 percent for l / m with the
      // spring released from rest at its best start).
      expect(openError, lessThan(0.005), reason: 'open');
      expect(closeError, lessThan(0.008), reason: 'close');
      expect(sizes[0], lessThan(0.008), reason: 'width');
      expect(sizes[1], lessThan(0.008), reason: 'height');
      for (final peak in peaks) {
        expect(peak, inInclusiveRange(1.01, 1.02));
      }
      expect((close.last.$2.center - _held).distance, lessThan(1e-3));
    });
  }

  test('a menu that does not fit below the preview stands above it, '
      'reversed; one that fits nowhere shifts the preview with it', () {
    final held = Rect.fromCenter(
      center: const Offset(201, 700),
      width: 120,
      height: 80,
    );
    final preview = held.inflate(9);
    final above = MenuMotion.placeAttached(
      attachment: MenuAttachment(held: held, preview: preview),
      size: const Size(250, 208),
      bounds: _screen,
    );
    expect(above.down, isFalse);
    expect(above.shift, Offset.zero);
    expect(above.rect.bottom, preview.top - 16);
    final tall = MenuMotion.placeAttached(
      attachment: MenuAttachment(held: held, preview: preview),
      size: const Size(250, 700),
      bounds: _screen,
    );
    expect(tall.down, isTrue);
    expect(tall.rect.bottom, 874 - MenuTuning.contextMargin);
    expect(tall.rect.top, preview.bottom + tall.shift.dy + 16);
    expect(tall.shift.dx, 0);
    expect(tall.shift.dy, lessThan(0));
  });

  test('a finger that held the menu open slides onto a row and chooses it '
      'on release; released on the preview it keeps the menu open', () {
    final motion = _motion(const Size(120, 80));
    motion.holdOpen(0, _held);
    motion.advance(1);
    final row = motion.menuRect.topCenter + const Offset(0, 10 + 47 * 1.5);
    motion.pointerMove(1.1, row);
    expect(motion.highlighted, 1);
    motion.pointerUp(1.2, row);
    motion.advance(1.5);
    expect(menuSelections(motion), [1]);
    expect(motion.isClosing || !motion.isPresented, isTrue);

    final kept = _motion(const Size(120, 80));
    kept.holdOpen(0, _held);
    kept.pointerMove(0.5, _held + const Offset(3, 2));
    kept.pointerUp(0.6, _held + const Offset(3, 2));
    kept.advance(2);
    expect(kept.isOpen, isTrue);
  });
}

// UIKit's context-menu morph spring and preview lift, measured on an
// iPhone 16 Pro (iOS 27), as the context menu uses them.
const _contextSpring = Spring.response(0.284, dampingRatio: 0.81);

double _previewScale(Size size) {
  final longest = size.longestSide;
  if (longest <= 0) return 1;
  return 1 + math.min(0.15 * longest, 26) / longest;
}
