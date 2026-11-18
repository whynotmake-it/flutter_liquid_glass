import 'package:flutter/foundation.dart';
import 'package:kinesis/src/input/interaction_values.dart';

/// Something an interaction did at a modelled time, which a control may
/// answer with a haptic.
@immutable
sealed class InteractionEvent {
  /// Creates an event at [time].
  const InteractionEvent({required this.time});

  /// The motion time of the event.
  final double time;
}

/// The region was activated: a tap, a click or an activation input.
final class ActivationEvent extends InteractionEvent {
  /// Creates an activation event.
  const ActivationEvent({required super.time, required this.source});

  /// Where it came from.
  final ActivationSource source;
}

/// A long press was recognized.
final class LongPressStartEvent extends InteractionEvent {
  /// Creates a long press event.
  const LongPressStartEvent({required super.time});
}

/// A finger that slides across the targets of a control came onto another
/// one: what `InputZones(slides:)` reports to its feedback for each zone the
/// finger enters.
final class ScrubChangeEvent extends InteractionEvent {
  /// Creates the event for a finger now over [selected].
  const ScrubChangeEvent({
    required super.time,
    required this.selected,
    this.atDown = false,
  });

  /// The target now under the finger, or null.
  final Object? selected;

  /// Whether the change came with the touch-down rather than a move: a
  /// control plays its selection haptic only for a finger that slides.
  final bool atDown;
}

/// What an interaction made of an input.
@immutable
final class InteractionUpdate {
  /// Describes an update.
  const InteractionUpdate({
    this.claims = false,
    this.recognizes = false,
    this.fails = false,
    this.events = const [],
  });

  /// Nothing happened.
  static const InteractionUpdate none = InteractionUpdate();

  /// Whether the interaction holds the touch against other gestures, as a
  /// tap waiting for its second tap does.
  final bool claims;

  /// Whether the interaction recognized its gesture: the others in its
  /// region stop hearing the touch.
  final bool recognizes;

  /// Whether the interaction gave up the touch.
  final bool fails;

  /// What it did, for haptics.
  final List<InteractionEvent> events;
}
