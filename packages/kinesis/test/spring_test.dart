import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';

void main() {
  group('Spring', () {
    test('maps duration and bounce to response and damping ratio', () {
      const spring = Spring(
        duration: Duration(milliseconds: 400),
        bounce: 0.25,
      );
      expect(spring.response, 0.4);
      expect(spring.dampingRatio, 0.75);
      expect(spring.bounce, 0.25);
      expect(spring.duration, const Duration(milliseconds: 400));
    });

    test('a negative bounce is overdamped as 1 / (1 + bounce)', () {
      const spring = Spring(bounce: -0.5);
      expect(spring.dampingRatio, 2);
      expect(const Spring.response(0.5, dampingRatio: 2).bounce, -0.5);
    });

    test('response and damping ratio map back to duration and bounce', () {
      const spring = Spring.response(0.35, dampingRatio: 0.8);
      expect(spring.duration, const Duration(milliseconds: 350));
      expect(spring.bounce, moreOrLessEquals(0.2));
    });

    test('equal physics in either form are equal springs', () {
      const swiftUI = Spring(
        duration: Duration(milliseconds: 400),
        bounce: 0.25,
      );
      const uiKit = Spring.response(0.4, dampingRatio: 0.75);
      expect(swiftUI, uiKit);
      expect(swiftUI.hashCode, uiKit.hashCode);
    });

    test('presets are SwiftUI springs', () {
      expect(Spring.smooth.response, 0.5);
      expect(Spring.smooth.dampingRatio, 1);
      expect(Spring.snappy.dampingRatio, moreOrLessEquals(0.85));
      expect(Spring.bouncy.dampingRatio, moreOrLessEquals(0.7));
      expect(Spring.interactive.response, 0.15);
      expect(Spring.interactive.dampingRatio, moreOrLessEquals(0.85));
    });

    test('stiffness and damping follow UIKit for a unit mass', () {
      const spring = Spring.response(0.3, dampingRatio: 0.99);
      const omega = 2 * math.pi / 0.3;
      expect(spring.stiffness, omega * omega);
      expect(spring.damping, 2 * 0.99 * omega);
      final description = spring.description;
      expect(description.mass, 1);
      expect(description.stiffness, spring.stiffness);
      expect(description.damping, spring.damping);
    });

    test('a ratio within 1e-9 of 1 is described as exactly critical', () {
      const spring = Spring.response(0.4, dampingRatio: 1 + 1e-12);
      const omega = 2 * math.pi / 0.4;
      expect(spring.description.damping, 2 * omega);
      final simulation = SpringSimulation(spring.description, 0, 1, 0);
      expect(simulation.x(10), moreOrLessEquals(1, epsilon: 1e-12));
    });

    test('resolves its Reduce Motion alternative and its tracking spring', () {
      const reduced = Spring.response(0.3);
      const tracking = Spring.response(0.15, dampingRatio: 0.86);
      const spring = Spring(tracking: tracking, reduced: reduced);
      expect(spring.resolve(reduceMotion: true), reduced);
      expect(spring.resolve(reduceMotion: false), spring);
      expect(spring.trackingSpring, tracking);
      expect(Spring.smooth.trackingSpring, Spring.smooth);
      expect(Spring.smooth.resolve(reduceMotion: true), Spring.smooth);
    });

    test('projects as UIScrollView decelerates by default', () {
      expect(Spring.normalProjection, moreOrLessEquals(0.998 / (1000 * 0.002)));
      expect(Spring.smooth.projection, Spring.normalProjection);
      expect(
        const Spring.response(0.3, projection: 0.143),
        isNot(const Spring.response(0.3)),
      );
      expect(Spring.immediate.projection, 0);
    });

    test('lerp interpolates response and damping ratio', () {
      final mid = Spring.lerp(
        const Spring.response(0.2, dampingRatio: 0.6),
        const Spring.response(0.4),
        0.5,
      );
      expect(mid.response, moreOrLessEquals(0.3));
      expect(mid.dampingRatio, moreOrLessEquals(0.8));
    });

    test('copyWith keeps the physics', () {
      const spring = Spring.response(0.3, dampingRatio: 0.9);
      final copy = spring.copyWith(impulse: 0.016, projection: 0.1);
      expect(copy.response, 0.3);
      expect(copy.dampingRatio, 0.9);
      expect(copy.impulse, 0.016);
      expect(copy.projection, 0.1);
      expect(Spring.immediate.copyWith(impulse: 1), Spring.immediate);
    });
  });
}
