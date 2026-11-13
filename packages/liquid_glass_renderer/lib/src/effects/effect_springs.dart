import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart';
import 'package:meta/meta.dart';

/// The spring a value follows a finger with: quick, with a little bounce.
@internal
final interactiveSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 150),
  bounce: 0.14,
);

/// The spring a released stretch springs back on.
@internal
final bouncySpring = SpringDescription.withDurationAndBounce(bounce: 0.3);

/// A spring that settles in about [duration] without overshoot.
@internal
SpringDescription smoothSpring([
  Duration duration = const Duration(milliseconds: 500),
]) => SpringDescription.withDurationAndBounce(duration: duration);

/// Moves [controller], an unbounded controller, to [target] on [spring],
/// starting from where it is, or from [from], with the velocity it has, and
/// settling exactly on [target].
///
/// A retarget mid-flight keeps the velocity of the last frame, so a touch
/// that interrupts a motion bends it instead of restarting it.
@internal
void springTo(
  AnimationController controller,
  SpringDescription spring,
  double target, {
  double? from,
}) {
  controller.animateWith(
    SpringSimulation(
      spring,
      from ?? controller.value,
      target,
      controller.velocity,
      snapToEnd: true,
    ),
  );
}
