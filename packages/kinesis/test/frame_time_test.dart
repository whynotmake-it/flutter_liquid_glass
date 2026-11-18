import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/src/motion/frame_time.dart';

Duration _us(num micros) => Duration(microseconds: micros.round());

class _Engine {
  Duration now = Duration.zero;
  Duration? offset = Duration.zero;
  double dilation = 1;

  FrameTime frames() => FrameTime(
    engineNow: () => now,
    pointerClockOffset: () => offset,
    dilation: () => dilation,
    frameRate: () => 60,
  );
}

void main() {
  const frame = 1e6 / 60;

  test('frames advance on the grid, and the same stamp twice counts once', () {
    final engine = _Engine();
    final frames = engine.frames();
    final times = <double>[];
    for (var i = 0; i < 12; i++) {
      final stamp = _us(i * frame);
      engine.now = stamp;
      frames.advance(stamp, stamp);
      frames.advance(stamp, stamp);
      times.add(frames.time);
    }
    expect(times.first, 0);
    for (var i = 2; i < times.length; i++) {
      expect(times[i] - times[i - 1], closeTo(1 / 60, 1e-6));
    }
    expect(frames.period, closeTo(1 / 60, 1e-6));
  });

  test('an input between frames gets the time from the latest frame to its '
      'own stamp', () {
    final engine = _Engine();
    final frames = engine.frames();
    for (var i = 0; i < 4; i++) {
      final stamp = _us(i * frame);
      engine.now = stamp;
      frames.advance(stamp, stamp);
    }
    final tick = frames.time;
    final touch = _us(3 * frame + 5000);
    engine.now = _us(3 * frame + 8000);
    expect(frames.stamp(touch), closeTo(tick + 0.005, 1e-4));
  });

  test('a doze keeps time running where the stamps agree', () {
    final engine = _Engine();
    final frames = engine.frames();
    for (var i = 0; i < 3; i++) {
      final stamp = _us(i * frame);
      engine.now = stamp;
      frames.advance(stamp, stamp);
    }
    final dozedAt = frames.time;
    final last = _us(2 * frame);
    frames.dozed();
    expect(frames.dozing, isTrue);
    engine.now = last + const Duration(milliseconds: 500);
    expect(frames.read(), closeTo(dozedAt + 0.5, 1e-6));
    final inFrame = last + const Duration(milliseconds: 300);
    expect(frames.read(frameStamp: inFrame), closeTo(dozedAt + 0.3, 1e-6));
    final woken = last + const Duration(milliseconds: 500);
    frames.advance(woken, woken);
    expect(frames.time, closeTo(dozedAt + 0.5, 1e-4));
    expect(frames.dozing, isFalse);
  });

  test('time stands still asleep under a fake frame clock', () {
    final engine = _Engine();
    final frames = engine.frames();
    for (var i = 0; i < 3; i++) {
      final stamp = _us(i * frame);
      frames.advance(stamp, stamp);
      engine.now = stamp + const Duration(seconds: 10);
    }
    final slept = frames.time;
    frames.sleep();
    expect(frames.dozing, isFalse);
    expect(frames.read(), slept);
    final woken = _us(2 * frame) + const Duration(seconds: 3);
    frames.advance(woken, woken);
    expect(frames.time, closeTo(slept, 0.02));
  });

  test('asleep where the stamps agree, the wait counts and a touch held '
      'still keeps its time', () {
    final engine = _Engine();
    final frames = engine.frames();
    for (var i = 0; i < 3; i++) {
      final stamp = _us(i * frame);
      engine.now = stamp;
      frames.advance(stamp, stamp);
    }
    final slept = frames.time;
    frames.sleep();
    expect(frames.dozing, isTrue);
    engine.now = _us(2 * frame) + const Duration(seconds: 3);
    expect(frames.read(), closeTo(slept + 3, 1e-6));
    expect(frames.stamp(engine.now), closeTo(slept + 3, 1e-4));
  });

  test('touches before the first frame keep their spacing, slowed by '
      'dilation, and the clock never runs backwards after the wake', () {
    final engine = _Engine();
    engine.dilation = 2;
    final frames = engine.frames();
    final down = frames.stamp(const Duration(seconds: 100));
    final up = frames.stamp(const Duration(seconds: 100, milliseconds: 80));
    expect(up - down, closeTo(0.04, 1e-9));
    const first = Duration(seconds: 7);
    frames.advance(first, first);
    expect(frames.time, greaterThanOrEqualTo(up));
  });
}
