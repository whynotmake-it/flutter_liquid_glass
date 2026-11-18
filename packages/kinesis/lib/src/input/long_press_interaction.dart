import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';
import 'package:kinesis/src/input/interaction.dart';
import 'package:kinesis/src/input/interaction_event.dart';
import 'package:kinesis/src/input/interaction_input.dart';

/// A press held still long enough.
///
/// UIKit: `UILongPressGestureRecognizer`. SwiftUI: `LongPressGesture`.
/// Flutter: `LongPressGestureRecognizer`.
class LongPressInteraction extends Interaction {
  /// Creates a long press of [duration] seconds that fails beyond
  /// [allowableMovement] of travel; the defaults are UIKit's
  /// `UILongPressGestureRecognizer` ones.
  LongPressInteraction({
    super.role,
    this.duration = 0.5,
    this.allowableMovement = 10,
    this.onStart,
    this.onCommit,
    this.onCancel,
  });

  /// How long the press is held, from contact, in seconds.
  double duration;

  /// How far the finger may travel before the press fails.
  double allowableMovement;

  /// Called when the press is recognized, at its due time: [duration]
  /// after contact, however late the frame that runs it. It then holds the
  /// touch.
  void Function(double t)? onStart;

  /// Called on the release after the press was recognized.
  void Function(double t)? onCommit;

  /// Called when a recognized press ends without a release.
  void Function(double t)? onCancel;

  int? _pointer;
  Offset _origin = Offset.zero;
  double? _due;
  bool _recognized = false;

  @override
  double? get nextDue => _due;

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput():
        if (_pointer != null || !accepts(input)) return InteractionUpdate.none;
        _pointer = input.pointer;
        _origin = input.position;
        _recognized = false;
        final due = _due = input.contactTime + duration;
        if (input.time >= due) return advance(input.time);
        return InteractionUpdate.none;
      case PointerMoveInput() when input.pointer == _pointer:
        if (_recognized) return InteractionUpdate.none;
        if ((input.position - _origin).distance <= allowableMovement) {
          return InteractionUpdate.none;
        }
        _reset();
        return const InteractionUpdate(fails: true);
      case PointerUpInput() when input.pointer == _pointer:
        final recognized = _recognized;
        _reset();
        if (!recognized) return const InteractionUpdate(fails: true);
        onCommit?.call(input.time);
        return InteractionUpdate.none;
      case PointerCancelInput() when input.pointer == _pointer:
        final recognized = _recognized;
        _reset();
        if (recognized) onCancel?.call(input.time);
        return const InteractionUpdate(fails: true);
      default:
        return InteractionUpdate.none;
    }
  }

  @override
  InteractionUpdate advance(double time) {
    final due = _due;
    if (due == null || time < due) return InteractionUpdate.none;
    _due = null;
    _recognized = true;
    onStart?.call(due);
    return InteractionUpdate(
      claims: true,
      recognizes: true,
      events: [LongPressStartEvent(time: due)],
    );
  }

  void _reset() {
    _pointer = null;
    _due = null;
    _recognized = false;
  }
}
