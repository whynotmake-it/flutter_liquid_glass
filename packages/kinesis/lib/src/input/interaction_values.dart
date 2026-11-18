import 'package:flutter/foundation.dart';
import 'package:kinesis/src/input/interaction.dart';

/// How a region takes part in a touch that may also scroll.
///
/// UIKit: a control (`UIControl`), content in a scroll view
/// (`delaysContentTouches`) or a gesture recognizer. SwiftUI: a button, a
/// tap in a scroll view, or a `DragGesture`. Flutter: no equivalent.
///
/// The role sets when an interaction hears a touch, and whether its claims
/// hold the touch.
enum InteractionRole {
  /// Hears the touch at once outside a scroll view and
  /// [InteractionSession.scrollDelay] after contact inside one; its claims
  /// hold the touch against the scroll. Under an interaction that contends
  /// with controls (`PointerDownInput.contested`) only its recognition
  /// does.
  control,

  /// Hears the touch as a control does, but its claims are ignored: a
  /// scroll that starts later takes the touch.
  content,

  /// Hears the touch at contact plus its onset; its claims hold the touch.
  gesture,

  /// Hears every pointer input of each touch on the region at once, at its
  /// stamp, outside the gesture arena: its claims are ignored, a gesture
  /// that takes the touch does not cancel it, and it hears the release or
  /// the platform's cancel however the arena decided. It hears every
  /// pointer it [Interaction.accepts], several at once. A region whose
  /// interactions only observe never joins the arena, so it blocks no
  /// gesture below or around it.
  ///
  /// Flutter: a `Listener`. UIKit: a gesture recognizer that recognizes
  /// simultaneously with every other and cancels no touch.
  observer,
}

/// A haptic a control plays for an interaction event.
///
/// UIKit: `UIFeedbackGenerator`. SwiftUI: `SensoryFeedback`. Flutter:
/// `HapticFeedback`.
enum MotionHaptic {
  /// A selection change.
  selection,

  /// A light impact.
  lightImpact,

  /// A medium impact.
  mediumImpact,

  /// A heavy impact.
  heavyImpact,
}

/// Where an activation came from.
enum ActivationSource {
  /// A finger, a pen or the mouse.
  pointer,

  /// The keyboard.
  keyboard,

  /// An accessibility action.
  accessibility,
}

/// A step a keyboard key or an accessibility action asks of a value: what
/// a slider, a stepper or a page control does with the arrows, Home and
/// End, Page Up and Page Down.
///
/// UIKit: `accessibilityIncrement` and `accessibilityDecrement`. Flutter:
/// a slider's adjustment intent.
enum ValueCommand {
  /// One step up.
  increase,

  /// One step down.
  decrease,

  /// A larger step up, such as a page.
  increaseLarge,

  /// A larger step down, such as a page.
  decreaseLarge,

  /// To the smallest value.
  toMinimum,

  /// To the largest value.
  toMaximum,
}

/// Which ways an adjustable value can move now: a value at its maximum
/// cannot increase, one at its minimum cannot decrease.
///
/// UIKit: none; a control leaves `accessibilityIncrement` without effect
/// at its end. Flutter: `SemanticsProperties.onIncrease` left null at the
/// maximum, as `Slider` does.
///
/// An input host offers only the value commands it [allows]: the
/// accessibility increase and decrease, and the keys of
/// `AdjustValueIntent`; a key it does not take reaches what lies around
/// the host, as when nothing adjusts.
@immutable
final class AdjustRange {
  /// A value that can [canIncrease] and [canDecrease].
  const AdjustRange({this.canIncrease = true, this.canDecrease = true});

  /// The room of [value] between [min] and [max].
  const AdjustRange.of(
    double value, {
    required double min,
    required double max,
  }) : canIncrease = value < max,
       canDecrease = value > min;

  /// A value with room both ways: what a host assumes when it is given no
  /// range.
  static const AdjustRange open = AdjustRange();

  /// Whether the value can go up.
  final bool canIncrease;

  /// Whether the value can go down.
  final bool canDecrease;

  /// Whether [command] can move the value now.
  bool allows(ValueCommand command) => switch (command) {
    .increase || .increaseLarge || .toMaximum => canIncrease,
    .decrease || .decreaseLarge || .toMinimum => canDecrease,
  };

  @override
  bool operator ==(Object other) =>
      other is AdjustRange &&
      other.canIncrease == canIncrease &&
      other.canDecrease == canDecrease;

  @override
  int get hashCode => Object.hash(canIncrease, canDecrease);

  @override
  String toString() =>
      'AdjustRange(canIncrease: $canIncrease, canDecrease: $canDecrease)';
}

/// Why a touch ended without a release.
enum PointerCancelReason {
  /// The platform cancelled it.
  platform,

  /// Another gesture, such as a scroll, took it.
  taken,

  /// The region was disabled.
  disabled,
}
