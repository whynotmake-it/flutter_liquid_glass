import 'dart:math' as math;

import 'package:apple_liquid_glass/src/motions/lens_motion.dart';
import 'package:apple_liquid_glass/src/motions/lens_tuning.dart';
import 'package:apple_liquid_glass/src/motions/lens_values.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/onset.dart';
import 'support/trace.dart';

const _device = 'test/fixtures/ios27-device/lens';
const _sim = 'test/fixtures/ios27/lens';

/// The resting lens of each segment of the recorded five-segment control
/// (`seg5`), read from the rest rows of the recordings.
const List<LensSlot> _seg5 = [
  (center: 56, width: 68),
  (center: 128, width: 68),
  (center: 200, width: 68),
  (center: 272, width: 68),
  (center: 344.5, width: 69),
];

/// The resting lens of each segment of the recorded two-segment control
/// (`seg2`).
const List<LensSlot> _seg2 = [
  (center: 110.5, width: 177),
  (center: 291.5, width: 177),
];

const _drags = [
  'segmented-seg5-dragslow-from-selected.jsonl',
  'segmented-seg5-scrub-offset-overrun-back.jsonl',
  'segmented-seg5-release-choice-rubberband.jsonl',
];

double _rms(Iterable<double> errors) => rms(errors);

/// The device recordings of taps and presses on segmented controls.
const _onsetFiles = [
  'segmented-seg2-taps.jsonl',
  'segmented-seg3-taps.jsonl',
  'segmented-seg5seg4-taps.jsonl',
  'segmented-narrow-content-content4-taps.jsonl',
  'segmented-seg2-hold1200.jsonl',
  'segmented-seg3-tap-selected.jsonl',
  ..._drags,
];

/// The lens lift onset of every touch in the device recording [file],
/// counted from the stamp of the touch that starts it: the touch-down
/// for a press on the selected segment, the release for a touch on
/// another one, which selects it.
List<({String label, bool pressedSelected, double onset})> _onsets(
  String file,
) {
  final trace = Trace.load('$_device/$file');
  final out = <({String label, bool pressedSelected, double onset})>[];
  for (var i = 0; i < trace.touches.length; i++) {
    final down = trace.touches[i];
    if (down.phase != 0) continue;
    final up = trace.touches.skip(i).firstWhere((t) => t.phase == 3);
    final level = trace.frames.firstWhere(
      (f) => f.raw['ctl'] != null && (f.y - down.y).abs() < 6,
    );
    final rows = [
      for (final f in trace.frames)
        if (f.raw['ctl'] == level.raw['ctl'] && (f.y - down.y).abs() < 6) f,
    ];
    final rest = rows.lastWhere((f) => f.t < down.t);
    final pressedSelected = (rest.x - down.x).abs() < rest.bw / 2;
    final from = pressedSelected ? down.t : up.t;
    out.add((
      label: '$file @${(down.t - trace.touches.first.t).toStringAsFixed(2)}',
      pressedSelected: pressedSelected,
      onset: lensLiftStart(rows, from) - from,
    ));
  }
  return out;
}

/// [LensTuning.segmented] with its press lift starting [pressDelay]
/// after the touch.
LensTuning _pressingAfter(double pressDelay) {
  const s = LensTuning.segmented;
  return LensTuning(
    selectsOnPointerDown: s.selectsOnPointerDown,
    liftWidth: s.liftWidth,
    liftHeight: s.liftHeight,
    hangTime: s.hangTime,
    hangTimePerPixel: s.hangTimePerPixel,
    hangFromTouch: s.hangFromTouch,
    presentationSpring: s.presentationSpring,
    followSpring: s.followSpring,
    rubberBand: s.rubberBand,
    pressDelay: pressDelay,
    pressHang: s.pressHang,
    releaseDelay: s.releaseDelay,
    travelSpring: s.travelSpring,
    liftSpring: s.liftSpring,
    startDelay: s.startDelay,
    flagLead: s.flagLead,
    hangReferenceDistance: s.hangReferenceDistance,
    chromeFlexes: s.chromeFlexes,
    chromeLag: s.chromeLag,
    chromeReleaseLag: s.chromeReleaseLag,
    chromeLandingLag: s.chromeLandingLag,
    reducedMotionTravelSpring: s.reducedMotionTravelSpring,
  );
}

/// One replayed frame, model minus recording: the travel center (the
/// recorded center minus its drift), the visible center, the bounding box
/// and the layer scales, at a time in seconds after the touch-up.
typedef _Sample = ({
  double t,
  bool pressed,
  double travel,
  double center,
  double width,
  double height,
  double sx,
  double sy,
});

/// One replayed gesture of a recording.
class _Gesture {
  _Gesture(this.label, {required this.pressedSelected});

  final String label;

  /// Whether the touch-down landed on the selected segment, which lifts
  /// and drags it; otherwise the release selects like a tap.
  final bool pressedSelected;

  final List<_Sample> samples = [];

  /// The lifted bounds height, model minus recording, at every recorded
  /// change; drags compare it until 0.8 s after the touch-up.
  final List<({double t, double error})> lift = [];

  /// Whether the recorded lens stayed at rest until the touch-up.
  bool stillUntilUp = true;

  /// Whether the model's lens stayed at rest until the touch-up.
  bool modelStillUntilUp = true;

  int selected = -1;
  int expected = -1;

  Iterable<_Sample> get scrub => samples.where((s) => s.pressed);

  Iterable<_Sample> get release =>
      samples.where((s) => !s.pressed && s.t <= 0.8);

  /// The frames lens_scrub_test.dart compares for a scrub: from the
  /// touch-down to 0.8 s after the touch-up.
  Iterable<_Sample> get drag => samples.where((s) => s.t <= 0.8);

  /// The frames lens_test.dart compares for a tap: 1.5 s from the
  /// touch-up.
  Iterable<_Sample> get tap => samples.where((s) => s.t >= 0 && s.t <= 1.5);

  double get liftRms => _rms([
    for (final l in lift)
      if (l.t <= 0.8) l.error,
  ]);
}

int _nearest(List<LensSlot> slots, double x) {
  var best = 0;
  for (var i = 1; i < slots.length; i++) {
    if ((slots[i].center - x).abs() < (slots[best].center - x).abs()) {
      best = i;
    }
  }
  return best;
}

/// Seconds the travel step response needs to reach [progress].
double _timeToReach(double progress) {
  final spring = LensTuning.segmented.travelSpring;
  final w0 = spring.omega;
  final zeta = spring.dampingRatio;
  final wd = w0 * math.sqrt(1 - zeta * zeta);
  double step(double t) =>
      1 -
      math.exp(-zeta * w0 * t) *
          (math.cos(wd * t) + zeta * w0 / wd * math.sin(wd * t));
  var lo = 0.0;
  var hi = 0.2;
  for (var i = 0; i < 50; i++) {
    final mid = (lo + hi) / 2;
    if (step(mid) < progress) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/// Replays every gesture of the recording at [path] on the lens of
/// [control], each on a fresh lens resting where the recorded one rests at
/// its touch-down.
///
/// The touches are fed at their recorded stamps, as lens_scrub_test.dart
/// feeds its scrubs. A press on another segment than the selected one
/// selects like a tap on its release, so its start is solved from the
/// first moving frame as lens_test.dart solves a tap's: the delay from the
/// touch-up to the motion is input latency.
List<_Gesture> _replay(
  String path,
  String control,
  List<LensSlot> slots, {
  required double frameRate,
  LensTuning tuning = LensTuning.segmented,
}) {
  final trace = Trace.load(path);
  final rows = [
    for (final f in trace.frames)
      if (f.raw['ctl'] == control) f,
  ];
  final downs = [
    for (var i = 0; i < trace.touches.length; i++)
      if (trace.touches[i].phase == 0) i,
  ];
  final gestures = <_Gesture>[];
  for (var g = 0; g < downs.length; g++) {
    final touches = trace.touches.sublist(
      downs[g],
      g + 1 < downs.length ? downs[g + 1] : trace.touches.length,
    );
    final down = touches.first;
    final up = touches.lastWhere((t) => t.phase == 3);
    final end = g + 1 < downs.length
        ? trace.touches[downs[g + 1]].t
        : double.infinity;
    final rest = rows.lastWhere((f) => f.t < down.t);
    final frames = [
      for (final f in rows)
        if (f.t >= down.t && f.t < end) f,
    ];
    final selected = _nearest(slots, rest.x);
    final gesture = _Gesture(
      '${path.split('/').last} '
      '@${(down.t - trace.touches.first.t).toStringAsFixed(2)}',
      pressedSelected: _nearest(slots, down.x) == selected,
    );
    var delay = tuning.startDelay;
    if (!gesture.pressedSelected) {
      final moved = frames.firstWhere(
        (f) => f.t > up.t && (f.x - rest.x).abs() > 0.05,
      );
      final progress = (moved.x - rest.x) / (frames.last.x - rest.x);
      delay = math.max(0, moved.t - _timeToReach(progress) - up.t);
    }
    final motion = LensMotion(
      tuning: tuning,
      slots: slots,
      selected: selected,
      height: rest.bh,
      frameRate: frameRate,
      startDelay: delay,
    );
    motion.advance(down.t - 0.5);
    var next = 0;
    var pressed = false;
    var previous = rest;
    var previousHeight = rest.bh;
    for (final f in frames) {
      while (next < touches.length && touches[next].t <= f.t) {
        final touch = touches[next++];
        switch (touch.phase) {
          case 0:
            pressed = true;
            motion.pointerDown(touch.t, touch.x);
          case 3:
            if (motion.center != rest.x || motion.lift != 0) {
              gesture.modelStillUntilUp = false;
            }
            pressed = false;
            motion.pointerUp(touch.t, touch.x);
          case _:
            motion.pointerMove(touch.t, touch.x);
        }
      }
      motion.advance(f.t);
      if (f.t < up.t && (f.x != rest.x || f.bw != rest.bw)) {
        gesture.stillUntilUp = false;
      }
      if (previousHeight != f.bh) {
        gesture.lift.add((t: f.t - up.t, error: motion.size.height - f.bh));
      }
      previousHeight = f.bh;
      // On a 120 Hz iPhone UIKit refreshes the lens geometry about every
      // other frame; a repeated sample is that hold, not motion to match.
      final stale = previous.x == f.x && previous.w == f.w;
      previous = f;
      if (stale) continue;
      final size = motion.size;
      gesture.samples.add((
        t: f.t - up.t,
        pressed: pressed,
        travel: motion.travelCenter - (f.x - (f.opt('p_driftX') ?? 0)),
        center: motion.center - f.x,
        width: size.width * motion.scaleX - f.w,
        height: size.height * motion.scaleY - f.h,
        sx: motion.scaleX - f.sx,
        sy: motion.scaleY - f.sy,
      ));
    }
    gesture.selected = motion.selected;
    gesture.expected = _nearest(slots, frames.last.x);
    gestures.add(gesture);
  }
  return gestures;
}

List<_Gesture> _device5(String file) =>
    _replay('$_device/$file', 'seg5', _seg5, frameRate: 120);

List<_Gesture> _sim5(String file) =>
    _replay('$_sim/$file', 'seg5', _seg5, frameRate: 60);

/// The device gestures that press the selected segment and drag it.
List<_Gesture> _deviceDrags() => [
  for (final file in _drags)
    for (final g in _device5(file))
      if (g.pressedSelected) g,
];

void main() {
  test('a held press on another segment waits for the release, then moves '
      'like a tap', () {
    // Tolerances: lens_test.dart's segmented taps, device 120 Hz and
    // simulator 60 Hz (rms of the visible frame).
    final cases = [
      (
        _replay(
          '$_device/segmented-seg2-hold1200.jsonl',
          'seg2',
          _seg2,
          frameRate: 120,
        ),
        (center: 1.6, width: 1.8, height: 0.85, sx: 0.012, sy: 0.009),
      ),
      (
        _replay(
          '$_sim/segmented-seg2-hold1200.jsonl',
          'seg2',
          _seg2,
          frameRate: 60,
        ),
        (center: 1.0, width: 1.6, height: 0.6, sx: 0.01, sy: 0.011),
      ),
    ];
    var count = 0;
    for (final (gestures, limit) in cases) {
      for (final g in gestures) {
        count++;
        expect(g.pressedSelected, isFalse, reason: g.label);
        expect(g.stillUntilUp, isTrue, reason: '${g.label} recorded hold');
        expect(g.modelStillUntilUp, isTrue, reason: '${g.label} model hold');
        final tap = g.tap.toList();
        expect(tap.length, greaterThan(40), reason: g.label);
        expect(
          _rms(tap.map((s) => s.center)),
          lessThan(limit.center),
          reason: '${g.label} center',
        );
        expect(
          _rms(tap.map((s) => s.width)),
          lessThan(limit.width),
          reason: '${g.label} width',
        );
        expect(
          _rms(tap.map((s) => s.height)),
          lessThan(limit.height),
          reason: '${g.label} height',
        );
        expect(
          _rms(tap.map((s) => s.sx)),
          lessThan(limit.sx),
          reason: '${g.label} sx',
        );
        expect(
          _rms(tap.map((s) => s.sy)),
          lessThan(limit.sy),
          reason: '${g.label} sy',
        );
        expect(g.selected, g.expected, reason: '${g.label} selection');
      }
    }
    expect(count, 3);
  });

  test('a dragged selected segment follows the finger like the device', () {
    // Tolerances: the travel center of lens_scrub_test.dart's device
    // scrubs (rms per recording up to 1.35, all together 1.05) and the
    // visible center of lens_test.dart's device segmented taps (1.6).
    final drags = _deviceDrags();
    expect(drags.length, 4);
    final all = <double>[];
    for (final g in drags) {
      final scrub = [for (final s in g.scrub) s.travel];
      expect(scrub.length, greaterThan(90), reason: g.label);
      expect(_rms(scrub), lessThan(1.35), reason: '${g.label} travel');
      expect(
        _rms(g.drag.map((s) => s.center)),
        lessThan(1.6),
        reason: '${g.label} center',
      );
      all.addAll(scrub);
    }
    expect(_rms(all), lessThan(1.05));
  });

  test('a release picks the segment nearest the finger, not the lens', () {
    final gestures = [
      for (final file in _drags) ..._device5(file),
      for (final file in _drags) ..._sim5(file),
    ];
    expect(gestures.length, 10);
    for (final g in gestures) {
      expect(g.selected, g.expected, reason: g.label);
    }
    final choice = _device5('segmented-seg5-release-choice-rubberband.jsonl');
    expect(choice.map((g) => g.selected), [2, 3, 0]);
  });

  test(
    'a press on another segment dragged to a third one lands like a tap',
    () {
      // Tolerances: lens_test.dart's device segmented taps.
      final g = _device5(
        'segmented-seg5-release-choice-rubberband.jsonl',
      ).singleWhere((g) => !g.pressedSelected);
      final tap = g.tap.toList();
      expect(tap.length, greaterThan(40));
      expect(_rms(tap.map((s) => s.center)), lessThan(1.6));
      expect(_rms(tap.map((s) => s.width)), lessThan(1.8));
      expect(_rms(tap.map((s) => s.height)), lessThan(0.85));
      expect(_rms(tap.map((s) => s.sx)), lessThan(0.012));
      expect(_rms(tap.map((s) => s.sy)), lessThan(0.009));
    },
  );

  test('a touch on another segment lifts the lens when the device does, '
      'from the release stamp', () {
    // The onset is counted from the release's stamp, which selects. The
    // device's own taps spread around their median by UIKit's delivery and
    // its main-thread setup of the lift (support/onset.dart).
    final taps = [
      for (final file in _onsetFiles)
        for (final o in _onsets(file))
          if (!o.pressedSelected) o,
    ];
    expect(taps, hasLength(35));
    final delay = LensTuning.segmented.startDelay;
    expect(
      median([for (final o in taps) o.onset]),
      closeTo(delay, deviceFrame / 2),
    );
    for (final o in taps) {
      expect(
        o.onset,
        closeTo(delay, deliverySpread + setupSpread),
        reason: o.label,
      );
    }
  });

  test('a press on the selected segment lifts the lens when the device '
      'does', () {
    final presses = [
      for (final file in _onsetFiles)
        for (final o in _onsets(file))
          if (o.pressedSelected) o,
    ];
    expect(presses, hasLength(8));
    final delay = LensTuning.segmented.pressDelay;
    expect(
      median([for (final o in presses) o.onset]),
      closeTo(delay, deviceFrame / 2),
    );
    for (final o in presses) {
      expect(
        o.onset,
        closeTo(delay, deliverySpread + setupSpread),
        reason: o.label,
      );
    }
  });

  test('a released drag travels to its segment like the device', () {
    // Tolerance: the release of lens_scrub_test.dart's device scrubs
    // (travel center rms up to 0.4 per recording).
    for (final g in _deviceDrags()) {
      expect(
        _rms(g.release.map((s) => s.travel)),
        lessThan(0.4),
        reason: '${g.label} release',
      );
    }
  });

  test('a pressed selected segment lifts and widens like the device once '
      'it lifts', () {
    // Tolerances: the lift of lens_scrub_test.dart's segmented tap on the
    // selected segment (bounds height rms 0.6) and the visible width of
    // lens_test.dart's device segmented taps (1.8). Each drag lifts where
    // its recording does; the test above checks those onsets.
    final onsets = {
      for (final file in _drags)
        for (final o in _onsets(file))
          if (o.pressedSelected) o.label: o.onset,
    };
    var count = 0;
    for (final file in _drags) {
      final labels = [
        for (final o in _onsets(file))
          if (o.pressedSelected) o.label,
      ];
      for (final label in labels) {
        final gestures = _replay(
          '$_device/$file',
          'seg5',
          _seg5,
          frameRate: 120,
          tuning: _pressingAfter(onsets[label]!),
        );
        final g = gestures.singleWhere((g) => g.label == label);
        count++;
        expect(g.liftRms, lessThan(0.6), reason: '${g.label} lift');
        expect(
          _rms(g.drag.map((s) => s.width)),
          lessThan(1.8),
          reason: '${g.label} width',
        );
      }
    }
    expect(count, 4);
  });

  test(
    'the simulator drags follow the finger like the device ones',
    () {
      // Tolerances: as for the device drags (lens_scrub_test.dart scrubs).
      final drags = [
        for (final file in _drags)
          for (final g in _sim5(file))
            if (g.pressedSelected) g,
      ];
      expect(drags.length, 4);
      for (final g in drags) {
        expect(
          _rms(g.scrub.map((s) => s.travel)),
          lessThan(1.35),
          reason: '${g.label} travel',
        );
        expect(g.liftRms, lessThan(0.6), reason: '${g.label} lift');
      }
    },
    skip:
        'simulator travel rms 2.71 / 2.03 / 3.02 / 0.26 vs 1.35, lift rms '
        '2.93 / 1.16 / 1.49 / 0.59 (max 10.8) vs 0.6: the simulator first '
        'lifts 53 - 174 ms after its touch stamp (the device 44 - 90), its '
        'XCUITest stamps do not follow the device clock reference; the same '
        'drags pass on the device',
  );
}
