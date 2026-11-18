import 'package:apple_liquid_glass/src/motions/flex_interaction.dart';
import 'package:apple_liquid_glass/src/motions/flex_spec.dart';
import 'package:apple_liquid_glass/src/motions/menu_flex.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';

/// The open menu's driftY channel returning from a lift, as an iPhone 16
/// Pro (iOS 27.0.1) published it every 33.339 ms: progress toward the new
/// target and velocity, both per unit of the target change, starting at
/// the update that took the change. Our measurement of UIKit's channel
/// (read from UIKit, notes private).
const _release = [
  (0.0, 1.7546),
  (0.10227, 4.1772),
  (0.26584, 5.4605),
  (0.45597, 5.8095),
  (0.64548, 5.4639),
  (0.81525, 4.6638),
  (0.95380, 3.6244),
  (1.05623, 2.5222),
  (1.12275, 1.4880),
  (1.15716, 0.6069),
  (1.16543, -0.0763),
];

/// The open menu's scaleX channel retargeted from rest while a finger
/// tracks, published 1/60 s and 1/30 s after the change (same device).
const _tracking = [(1 / 60, 0.4988, 29.18), (1 / 30, 0.9155, 19.91)];

void main() {
  test('an equal target is skipped, spring switch included', () {
    const spring = Spring.response(
      0.6,
      dampingRatio: 0.5,
      tracking: Spring.response(0.15, dampingRatio: 0.5),
    );
    final channel = MotionValue<double>(1, spring: spring);
    chaseFlexChannel(channel, 0, 1, spring);
    expect(channel.restsAt(0, 1e-12), isTrue);
    chaseFlexChannel(channel, 0, 2, spring, tracking: true);
    chaseFlexChannel(channel, 0.1, 2, spring);
    final reference = MotionValue<double>(1, spring: spring.trackingSpring);
    reference.retarget(0, 2);
    expect(channel.valueAt(0.3), reference.valueAt(0.3));
  });

  test('a changed target pushes by stiffness x impulse x change', () {
    const tracking = Spring.response(0.15, dampingRatio: 0.5);
    const spring = Spring.response(
      0.6,
      dampingRatio: 0.5,
      tracking: tracking,
      impulse: 0.016,
    );
    final channel = MotionValue<double>(0, spring: spring);
    chaseFlexChannel(channel, 0, 2, spring, tracking: true);
    expect(channel.velocityAt(0), moreOrLessEquals(tracking.stiffness * 0.032));
    final before = channel.velocityAt(0.01);
    chaseFlexChannel(channel, 0.01, 1, spring);
    expect(
      channel.velocityAt(0.01) - before,
      moreOrLessEquals(-spring.stiffness * 0.016),
    );
  });

  test('the menu channel returns from a lift as the device published', () {
    final spring = FlexSpec.menu.channelSpring;
    final channel = MotionValue<double>(-1, spring: spring);
    chaseFlexChannel(channel, 0, 0, spring);
    for (var i = 0; i < _release.length; i++) {
      final (progress, velocity) = _release[i];
      final t = i * 0.033339;
      expect(channel.valueAt(t) + 1, moreOrLessEquals(progress, epsilon: 2e-3));
      expect(channel.velocityAt(t), moreOrLessEquals(velocity, epsilon: 0.02));
    }
  });

  test('the menu channel tracks a finger as the device published', () {
    final spring = FlexSpec.menu.channelSpring;
    final channel = MotionValue<double>(-1, spring: spring);
    chaseFlexChannel(channel, 0, 0, spring, tracking: true);
    for (final (t, progress, velocity) in _tracking) {
      expect(channel.valueAt(t) + 1, moreOrLessEquals(progress, epsilon: 2e-3));
      expect(channel.velocityAt(t), moreOrLessEquals(velocity, epsilon: 0.05));
    }
  });

  test('the pulse advances a changed target by the retarget step', () {
    const spring = Spring.response(0.574, dampingRatio: 0.548);
    final pulse = FlexPulse(spring, retargetStep: 1 / 60);
    final reference = MotionValue<double>(0, spring: spring);
    pulse.snap(0);
    pulse.step(1 / 30, 10);
    reference.retarget(0, 10);
    expect(pulse.value, reference.valueAt(1 / 60));
    expect(pulse.velocity, reference.velocityAt(1 / 60));
    pulse.step(2 / 30, 10);
    expect(pulse.value, moreOrLessEquals(reference.valueAt(1 / 60 + 1 / 30)));
    expect(pulse.holdsWithin(10, 1, 0.25), isFalse);
    expect(pulse.holdsWithin(11, 1e-9, 0.25), isFalse);
  });
}
