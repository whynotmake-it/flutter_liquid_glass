import 'package:kinesis/src/input/interaction.dart';
import 'package:kinesis/src/input/interaction_event.dart';
import 'package:kinesis/src/input/interaction_input.dart';

/// The pointer resting over the region for [duration]: how a submenu
/// opens under the mouse.
///
/// UIKit: none on iOS; `NSMenu` opens a submenu after the pointer stays on
/// its item. SwiftUI: none. Flutter: `SubmenuButton.hoverOpenDelay`.
///
/// The wait starts when the pointer enters the region and ends when it
/// leaves; moving inside the region keeps it, as Flutter's submenu does. It
/// fires once per entry, at its due time on the motion clock however late
/// the frame that runs it, and takes no touch, so it sits beside a press.
class HoverDwellInteraction extends Interaction {
  /// Creates a dwell of [duration] seconds that calls [onDwell].
  HoverDwellInteraction({required this.duration, this.onDwell})
    : assert(duration >= 0, 'a dwell waits forward');

  /// How long the pointer rests before the dwell fires, in seconds.
  double duration;

  /// Called with the dwell's due time: [duration] after the pointer
  /// entered.
  void Function(double t)? onDwell;

  bool _inside = false;
  double? _due;

  /// Whether the pointer is over the region and the dwell has not fired.
  bool get waiting => _due != null;

  @override
  bool accepts(PointerDownInput down) => false;

  @override
  double? get nextDue => _due;

  @override
  InteractionUpdate handle(InteractionInput input) {
    if (input is! PointerHoverInput) return InteractionUpdate.none;
    if (input.inside) {
      if (_inside) return InteractionUpdate.none;
      _inside = true;
      _due = input.time + duration;
      return advance(input.time);
    }
    final update = advance(input.time);
    _inside = false;
    _due = null;
    return update;
  }

  @override
  InteractionUpdate advance(double time) {
    final due = _due;
    if (due == null || time < due) return InteractionUpdate.none;
    _due = null;
    onDwell?.call(due);
    return InteractionUpdate.none;
  }
}
