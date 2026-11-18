import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

/// Hold-drag-to-select: a finger moves across what [hit] answers, and a
/// release on one commits it.
///
/// A fixture for the tests of hand-offs and relations: controls slide a
/// finger across their parts with `InputZones(slides:)`.
///
/// [hit] answers what lies under a position in the region's coordinates
/// (a slot map the layout writes, a motion's row at a point), or null.
class ScrubInteraction extends Interaction {
  /// Creates a scrub over what [hit] answers.
  ScrubInteraction({
    required this.hit,
    super.role,
    this.onChanged,
    this.onCommit,
  });

  /// What lies under a position, or null.
  Object? Function(Offset position) hit;

  /// Called when the finger touches or moves onto something else, or off
  /// everything, with the input's time; with null when the scrub is
  /// cancelled or the finger lifts over nothing.
  void Function(Object? selected, double t)? onChanged;

  /// Called with what lies under a release, and its time.
  void Function(Object selected, double t)? onCommit;

  int? _pointer;
  Object? _selected;

  InteractionUpdate _select(
    double time,
    Offset position, {
    bool atDown = false,
  }) {
    final selected = hit(position);
    if (selected == _selected) return InteractionUpdate.none;
    _selected = selected;
    onChanged?.call(selected, time);
    return InteractionUpdate(
      events: [
        ScrubChangeEvent(time: time, selected: selected, atDown: atDown),
      ],
    );
  }

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput():
        if (_pointer != null || !accepts(input)) return InteractionUpdate.none;
        _pointer = input.pointer;
        _selected = null;
        return _select(input.time, input.position, atDown: true);
      case PointerMoveInput() when input.pointer == _pointer:
        return _select(input.time, input.position);
      case PointerUpInput() when input.pointer == _pointer:
        _pointer = null;
        final selected = hit(input.position);
        final was = _selected;
        _selected = null;
        if (selected == null) {
          if (was != null) onChanged?.call(null, input.time);
          return const InteractionUpdate(fails: true);
        }
        onCommit?.call(selected, input.time);
        return const InteractionUpdate(recognizes: true);
      case PointerCancelInput() when input.pointer == _pointer:
        _pointer = null;
        _selected = null;
        onChanged?.call(null, input.time);
        return const InteractionUpdate(fails: true);
      default:
        return InteractionUpdate.none;
    }
  }
}
