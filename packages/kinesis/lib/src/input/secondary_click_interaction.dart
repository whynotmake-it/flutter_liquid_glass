import 'package:flutter/gestures.dart';
import 'package:kinesis/src/input/interaction.dart';
import 'package:kinesis/src/input/interaction_event.dart';
import 'package:kinesis/src/input/interaction_input.dart';

/// A press of the secondary button: a right click, or a two-finger click
/// on a trackpad.
///
/// UIKit: `UIContextMenuInteraction` opened by a secondary click. SwiftUI:
/// `contextMenu` on iPadOS and macOS. Flutter: `onSecondaryTapDown`.
///
/// It reports the press as it happens, where a context menu opens on
/// iPadOS and macOS, and holds the touch until the button lifts. Other
/// interactions take primary presses only, so a region adds this one beside
/// its press without either hearing the other's button. It also
/// [opensContextMenu]: the context menu key and Shift+F10 on the focused
/// region report a click at the region's centre.
class SecondaryClickInteraction extends Interaction {
  /// Creates a secondary click that calls [onClick].
  SecondaryClickInteraction({super.role, this.onClick});

  /// Called with the time of the press, or of the key, and where it is, in
  /// the region's coordinates.
  void Function(double t, Offset position)? onClick;

  int? _pointer;

  @override
  bool get opensContextMenu => true;

  @override
  bool accepts(PointerDownInput down) =>
      _pointer == null && down.buttons & kSecondaryButton != 0;

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput():
        if (!accepts(input)) return InteractionUpdate.none;
        _pointer = input.pointer;
        onClick?.call(input.time, input.position);
        return const InteractionUpdate(claims: true, recognizes: true);
      case ContextMenuInput():
        onClick?.call(input.time, input.position);
        return InteractionUpdate.none;
      case PointerUpInput(:final pointer) || PointerCancelInput(:final pointer)
          when pointer == _pointer:
        _pointer = null;
        return InteractionUpdate.none;
      default:
        return InteractionUpdate.none;
    }
  }
}
