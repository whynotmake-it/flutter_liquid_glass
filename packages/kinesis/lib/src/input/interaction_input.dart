import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';
import 'package:kinesis/src/input/interaction.dart';
import 'package:kinesis/src/input/interaction_values.dart';
import 'package:kinesis/src/input/press_reach.dart';

/// One stamped input to an [InteractionSession], at [time] on the motion
/// clock.
@immutable
sealed class InteractionInput {
  /// Creates an input at [time].
  const InteractionInput({required this.time});

  /// The motion time of the input, in seconds.
  final double time;
}

/// A pointer touched the region.
final class PointerDownInput extends InteractionInput {
  /// Creates a down input.
  const PointerDownInput({
    required super.time,
    required this.pointer,
    required this.position,
    required this.regionSize,
    double? contactTime,
    this.reach = PressReach.box,
    this._globalPosition,
    this.kind = PointerDeviceKind.touch,
    this.buttons = kPrimaryButton,
    this.scrollAxes = const {},
    this.contested = false,
    this.touchSlop = kTouchSlop,
  }) : contactTime = contactTime ?? time;

  /// The pointer.
  final int pointer;

  /// Where it touched, in the region's coordinates.
  final Offset position;

  final Offset? _globalPosition;

  /// Where it touched, in global coordinates; [position] when the input
  /// did not say, as a replay recorded in the region's coordinates.
  Offset get globalPosition => _globalPosition ?? position;

  /// Whether an interaction around the region takes touches from the
  /// controls inside it ([Interaction.contendsWithControls]), such as a
  /// sheet's pan: the claims of a control then do not hold the touch, so
  /// the pan takes it once the finger travels far enough, and a release
  /// before that still activates the control. A control that recognizes
  /// its gesture first, as a slider's pan along its track does, holds the
  /// touch all the same.
  final bool contested;

  /// The size of the region.
  final Size regionSize;

  /// Where the region takes pointers and where a press on it holds the
  /// finger.
  final PressReach reach;

  /// How far a finger travels before the gestures the region competes with
  /// in the arena take it: the device's touch slop, Flutter's `kTouchSlop`
  /// where the platform gives none.
  final double touchSlop;

  /// When it touched; differs from [time] when the delivery was held back.
  final double contactTime;

  /// What touched.
  final PointerDeviceKind kind;

  /// The buttons it pressed.
  final int buttons;

  /// The axes of the scroll views around the region.
  final Set<Axis> scrollAxes;

  /// This input with the given fields replaced.
  @internal
  PointerDownInput copyWith({
    double? time,
    Offset? position,
    Size? regionSize,
    PressReach? reach,
    Offset? globalPosition,
  }) => PointerDownInput(
    time: time ?? this.time,
    pointer: pointer,
    position: position ?? this.position,
    regionSize: regionSize ?? this.regionSize,
    contactTime: contactTime,
    reach: reach ?? this.reach,
    globalPosition: globalPosition ?? this.globalPosition,
    kind: kind,
    buttons: buttons,
    scrollAxes: scrollAxes,
    contested: contested,
    touchSlop: touchSlop,
  );
}

/// A tracked pointer moved.
final class PointerMoveInput extends InteractionInput {
  /// Creates a move input.
  const PointerMoveInput({
    required super.time,
    required this.pointer,
    required this.position,
    required this.regionBox,
    this._globalPosition,
  });

  /// The pointer.
  final int pointer;

  /// Where it is, in the region's coordinates.
  final Offset position;

  /// The region's box as it is at this input, in the coordinates of
  /// [position]: those of the region at the touch-down.
  final Rect regionBox;

  final Offset? _globalPosition;

  /// Where it is, in global coordinates; [position] when the input did not
  /// say.
  Offset get globalPosition => _globalPosition ?? position;

  /// This input with the given fields replaced; [globalPosition] stays as
  /// it reads now.
  @internal
  PointerMoveInput copyWith({
    double? time,
    Offset? position,
    Rect? regionBox,
  }) => PointerMoveInput(
    time: time ?? this.time,
    pointer: pointer,
    position: position ?? this.position,
    regionBox: regionBox ?? this.regionBox,
    globalPosition: globalPosition,
  );
}

/// A tracked pointer lifted.
final class PointerUpInput extends InteractionInput {
  /// Creates an up input.
  const PointerUpInput({
    required super.time,
    required this.pointer,
    required this.position,
    required this.regionBox,
    this.velocity = Offset.zero,
    this._globalPosition,
    this._globalVelocity,
  });

  /// The pointer.
  final int pointer;

  /// Where it lifted, in the region's coordinates.
  final Offset position;

  /// The region's box as it is at this input, in the coordinates of
  /// [position] (see [PointerMoveInput.regionBox]).
  final Rect regionBox;

  /// Its velocity at the lift, in logical pixels per second, estimated
  /// with the lift's own sample.
  final Offset velocity;

  final Offset? _globalPosition;
  final Offset? _globalVelocity;

  /// Where it lifted, in global coordinates; [position] when the input did
  /// not say.
  Offset get globalPosition => _globalPosition ?? position;

  /// [velocity] in global coordinates; [velocity] when the input did not
  /// say.
  Offset get globalVelocity => _globalVelocity ?? velocity;

  /// This input with the given fields replaced; [globalPosition] and
  /// [globalVelocity] stay as they read now.
  @internal
  PointerUpInput copyWith({
    Offset? position,
    Offset? velocity,
    Rect? regionBox,
  }) => PointerUpInput(
    time: time,
    pointer: pointer,
    position: position ?? this.position,
    regionBox: regionBox ?? this.regionBox,
    velocity: velocity ?? this.velocity,
    globalPosition: globalPosition,
    globalVelocity: globalVelocity,
  );
}

/// The gesture arena gave the region the touch of [pointer]: no other
/// gesture competes for it any more.
///
/// Flutter: `GestureArenaMember.acceptGesture`. An input host sends it when
/// the region is alone in the arena at the touch, when every other gesture
/// gave the touch up, or when the region's own claim took it.
final class PointerAcceptedInput extends InteractionInput {
  /// Creates an acceptance of [pointer].
  const PointerAcceptedInput({required super.time, required this.pointer});

  /// The pointer.
  final int pointer;
}

/// A tracked pointer ended without a release.
final class PointerCancelInput extends InteractionInput {
  /// Creates a cancel input.
  const PointerCancelInput({
    required super.time,
    required this.pointer,
    required this.reason,
  });

  /// The pointer.
  final int pointer;

  /// Why it ended.
  final PointerCancelReason reason;
}

/// The mouse moved over the region, or left it.
final class PointerHoverInput extends InteractionInput {
  /// Creates a hover input.
  const PointerHoverInput({
    required super.time,
    required this.position,
    required this.inside,
  });

  /// Where the mouse is, in the region's coordinates.
  final Offset position;

  /// Whether the mouse is over the region.
  final bool inside;
}

/// A scroll wheel or a trackpad scrolled over the region.
///
/// It reaches a region's interactions only when one of them
/// [Interaction.takesWheel]; the region then keeps the scroll from the
/// scroll views around it.
final class PointerScrollInput extends InteractionInput {
  /// Creates a scroll input.
  const PointerScrollInput({
    required super.time,
    required this.position,
    required this.scrollDelta,
    this.kind = PointerDeviceKind.mouse,
  });

  /// Where the pointer is, in the region's coordinates.
  final Offset position;

  /// How far the content would scroll, in logical pixels: positive `dy`
  /// scrolls down, toward the end.
  final Offset scrollDelta;

  /// What scrolled.
  final PointerDeviceKind kind;
}

/// The region was activated without a touch.
final class ActivateInput extends InteractionInput {
  /// Creates an activation.
  const ActivateInput({
    required super.time,
    this.source = ActivationSource.keyboard,
  });

  /// Where it came from.
  final ActivationSource source;
}

/// The region's value was asked to step without a touch: by a key or an
/// accessibility action.
final class AdjustInput extends InteractionInput {
  /// Creates a value command.
  const AdjustInput({
    required super.time,
    required this.command,
    this.source = ActivationSource.keyboard,
  });

  /// The step asked for.
  final ValueCommand command;

  /// Where it came from: the keyboard or accessibility.
  final ActivationSource source;
}

/// The region was asked for its context menu without a pointer: the
/// context menu key, Shift+F10, or an app's own key for it.
///
/// UIKit: the context menu a hardware keyboard opens on the focused view.
/// Flutter: none; `ContextMenuIntent` in `package:kinesis/widgets.dart`
/// is the intent an input host turns into this input.
final class ContextMenuInput extends InteractionInput {
  /// Creates a request at [position].
  const ContextMenuInput({
    required super.time,
    required this.position,
    this.source = ActivationSource.keyboard,
  });

  /// Where a menu opened for it anchors, in the region's coordinates: the
  /// centre of the region an input host was asked through.
  final Offset position;

  /// Where it came from.
  final ActivationSource source;
}
