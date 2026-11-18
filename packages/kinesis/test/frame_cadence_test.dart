import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/src/motion/frame_cadence.dart';

const _vsync120 = 8333;

// Runs [count] vsyncs [period] microseconds apart after [start]; which draw.
List<bool> _run(
  CadencePolicy policy, {
  required int count,
  int period = _vsync120,
  int start = 0,
  void Function(int)? before,
}) => [
  for (var i = 0; i < count; i++) ...[
    () {
      before?.call(i);
      return policy.draws(Duration(microseconds: start + i * period));
    }(),
  ],
];

void main() {
  test(
    'a 120 Hz display draws every second vsync while nothing moves fast',
    () {
      final drawn = _run(CadencePolicy(), count: 9);
      expect(drawn, [true, false, true, false, true, false, true, false, true]);
    },
  );

  test('60 Hz and 90 Hz displays draw every vsync', () {
    expect(
      _run(CadencePolicy(), count: 8, period: 16667),
      everyElement(isTrue),
    );
    expect(
      _run(CadencePolicy(), count: 8, period: 11111),
      everyElement(isTrue),
    );
  });

  test('a 144 Hz display draws every second vsync', () {
    final drawn = _run(CadencePolicy(), count: 7, period: 6944);
    expect(drawn, [true, false, true, false, true, false, true]);
  });

  test('speed from 720 px/s draws every vsync until 64 ms after it stops', () {
    final policy = CadencePolicy();
    _run(policy, count: 4);
    policy.speed(1000);
    final drawn = _run(policy, count: 12, start: 4 * _vsync120);
    expect(drawn.take(8), everyElement(isTrue));
    expect(drawn.skip(8), contains(false));
  });

  test('five slow updates drop a fast scroll at once; fewer do not', () {
    final policy = CadencePolicy();
    _run(policy, count: 4);
    policy.speed(1000);
    for (var i = 0; i < 4; i++) {
      policy.speed(100);
    }
    expect(
      _run(policy, count: 4, start: 4 * _vsync120),
      everyElement(isTrue),
    );
    policy.speed(1000);
    for (var i = 0; i < 5; i++) {
      policy.speed(100);
    }
    expect(_run(policy, count: 4, start: 8 * _vsync120), contains(false));
  });

  test('a motion with a high floor holds every vsync while it moves', () {
    final policy = CadencePolicy();
    _run(policy, count: 4);
    expect(
      _run(
        policy,
        count: 20,
        start: 4 * _vsync120,
        before: (_) => policy.hold(),
      ),
      everyElement(isTrue),
    );
  });

  test('a slow report does not end a motion hold', () {
    final policy = CadencePolicy();
    _run(policy, count: 4);
    policy.hold();
    for (var i = 0; i < 6; i++) {
      policy.speed(10);
    }
    expect(_run(policy, count: 4, start: 4 * _vsync120), everyElement(isTrue));
  });

  test('a touch draws the next vsync', () {
    final policy = CadencePolicy();
    final drawn = _run(policy, count: 3);
    expect(drawn.last, isTrue);
    policy.drawNext();
    expect(_run(policy, count: 1, start: 3 * _vsync120).single, isTrue);
  });

  test('a scroll reads its speed over the gap between drawn frames', () {
    final policy = CadencePolicy();
    _run(policy, count: 5);
    // 16.67 ms between drawn frames: 12 device pixels are 720 px/s.
    policy.scrolled(-12.1);
    expect(_run(policy, count: 4, start: 5 * _vsync120), everyElement(isTrue));
  });

  group('a device that cannot keep up', () {
    void frames(
      CadencePolicy policy,
      int count, {
      required Duration raster,
      Duration build = Duration.zero,
    }) {
      for (var i = 0; i < count; i++) {
        policy.timed(
          vsync: Duration(microseconds: i * _vsync120),
          build: build,
          raster: raster,
        );
      }
    }

    test('stays at the lower rate for a while', () {
      final policy = CadencePolicy();
      _run(policy, count: 4);
      frames(policy, 40, raster: const Duration(milliseconds: 10));
      final drawn = _run(
        policy,
        count: 4,
        start: 4 * _vsync120,
        before: (_) => policy.speed(5000),
      );
      expect(drawn, contains(false));

      final later = _run(
        policy,
        count: 4,
        start: 31 * 1000000,
        before: (_) => policy.speed(5000),
      );
      expect(later.skip(1), everyElement(isTrue));
    });

    test('a device that keeps up stays at the full rate', () {
      final policy = CadencePolicy();
      _run(policy, count: 4);
      frames(policy, 60, raster: const Duration(milliseconds: 4));
      expect(
        _run(
          policy,
          count: 4,
          start: 4 * _vsync120,
          before: (_) => policy.speed(5000),
        ),
        everyElement(isTrue),
      );
    });

    test('frames at the lower rate are not counted against it', () {
      final policy = CadencePolicy();
      _run(policy, count: 4);
      for (var i = 0; i < 40; i++) {
        policy.timed(
          vsync: Duration(microseconds: i * 16667),
          build: Duration.zero,
          raster: const Duration(milliseconds: 12),
        );
      }
      expect(
        _run(
          policy,
          count: 4,
          start: 4 * _vsync120,
          before: (_) => policy.speed(5000),
        ),
        everyElement(isTrue),
      );
    });
  });
}
