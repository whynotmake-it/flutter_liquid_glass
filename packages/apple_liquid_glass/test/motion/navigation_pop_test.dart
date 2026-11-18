import 'dart:convert';
import 'dart:math' as math;

import 'package:apple_liquid_glass/src/motions/navigation_motion.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

void main() {
  final fixture = jsonDecode(
    Fixtures.read(
      'test/fixtures/ios27-device/navigation/release-decision.json',
    ),
  ) as Map<String, Object?>;
  for (final raw in fixture['captures']! as List<Object?>) {
    final capture = raw! as Map<String, Object?>;
    test('native release: ${capture['name']}', () {
      final width = (capture['width']! as num).toDouble();
      final motion = NavigationPopMotion(width);
      final points = capture['points']! as List<Object?>;
      final begin = capture['begin']! as int;
      final first = points[begin]! as List<Object?>;
      final origin =
          (first[1]! as num).toDouble() -
          (capture['beginProgress']! as num).toDouble() * width;
      for (var i = 0; i < points.length; i++) {
        final point = points[i]! as List<Object?>;
        final t = (point[0]! as num).toDouble();
        final x = (point[1]! as num).toDouble();
        final phase = point[3]! as int;
        if (phase == 0 || phase == 1) motion.addPosition(t, x);
        final progress = (x - origin) / width;
        if (i == begin) {
          motion.begin(t, progress: progress);
        } else if (i > begin) {
          motion.update(t, progress, ending: phase == 3);
        }
      }
      expect(motion.sampleCount, capture['sampleCount']);
      expect(motion.velocity, closeTo(capture['velocity']! as num, 1e-5));
      expect(
        motion.settleVelocity,
        closeTo(capture['settleVelocity']! as num, 1e-5),
      );
      expect(
        motion.averageVelocity,
        closeTo(capture['averageVelocity']! as num, 1e-5),
      );
      expect(
        motion.averageAcceleration,
        closeTo(capture['averageAcceleration']! as num, 1e-5),
      );
      expect(
        motion.shouldPop((capture['releaseProgress']! as num).toDouble()),
        capture['popped'],
      );
      final spring = SpringSimulation(
        NavigationTuning.interactiveSpring.description,
        (capture['releaseProgress']! as num).toDouble() * width,
        capture['popped']! as bool ? width : 0,
        motion.settleVelocity * width,
      );
      final frames = capture['settle']! as List<Object?>;
      final period = (capture['framePeriod']! as num).toDouble();
      expect(frames.length, greaterThan(15));
      var best = double.infinity;
      for (var i = 0; i <= 600; i++) {
        final onset = i * 0.0001;
        var squared = 0.0;
        for (final rawFrame in frames) {
          final frame = rawFrame! as List<Object?>;
          final t = (frame[0]! as num).toDouble() - onset;
          // A presentation layer can already expose the following frame
          // under the current display-link timestamp (retained in the fixture).
          final x = spring.x(math.max(0, t));
          final next = spring.x(math.max(0, t + period));
          final measured = (frame[1]! as num).toDouble();
          final error =
              measured - measured.clamp(math.min(x, next), math.max(x, next));
          squared += error * error;
        }
        best = math.min(best, math.sqrt(squared / frames.length));
      }
      expect(best, lessThan(0.2), reason: 'release spring RMS, points');
    });
  }

  for (final raw in fixture['fastSpeedChecks']! as List<Object?>) {
    final capture = raw! as Map<String, Object?>;
    test('fast pan carries the native speed boost: ${capture['name']}', () {
      final width = (capture['width']! as num).toDouble();
      final speed = (capture['velocity']! as num).toDouble() * width;
      final motion = NavigationPopMotion(width);
      motion.addPosition(0, 0);
      motion.addPosition(0.02, speed * 0.02);
      motion.begin(0.02);
      motion.addPosition(0.04, speed * 0.04);
      motion.update(0.04, 0.1);
      motion.update(0.06, 0.2, ending: true);
      expect(
        motion.settleVelocity,
        closeTo(capture['settleVelocity']! as num, 1e-5),
      );
    });
  }

  test('a recognized drag without an update returns even beyond halfway', () {
    final motion = NavigationPopMotion(402);
    motion.addPosition(0, 0);
    motion.addPosition(0.02, 20);
    motion.begin(0.02);
    motion.update(0.02, 0.01);
    motion.update(0.5, 0.8, ending: true);
    expect(motion.shouldPop(0.8), isFalse);
  });

  test('a drag past either end of the travel rubber bands', () {
    expect(NavigationTuning.band.show(0.4), 0.4);
    expect(NavigationTuning.band.show(1.2), inExclusiveRange(1, 1.2));
    expect(NavigationTuning.band.show(-0.2), inExclusiveRange(-0.2, 0));
    expect(NavigationTuning.band.show(50), lessThan(1.5));
    expect(
      NavigationTuning.band.show(-0.2),
      closeTo(-(NavigationTuning.band.show(1.2) - 1), 1e-12),
    );
  });
}
