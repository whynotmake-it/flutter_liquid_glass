import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:kinesis/src/input/drag_interaction.dart';
import 'package:kinesis/src/input/interaction_event.dart';
import 'package:kinesis/src/input/interaction_input.dart';
import 'package:kinesis/src/input/interaction_values.dart';

part 'package:kinesis/src/input/interaction_relations.dart';
part 'package:kinesis/src/input/interaction_session.dart';

/// One way a region answers input: a press, a long press, a drag, a scrub
/// or a tap, without widgets, clocks or I/O.
///
/// UIKit: a `UIGestureRecognizer` or a control's tracking. SwiftUI: a
/// `Gesture`. Flutter: a `GestureRecognizer` that does not join the arena
/// by itself.
///
/// An interaction is made once by its owner, like a recognizer, and keeps
/// the state of the touch it follows. Every input carries its own time, so
/// an interaction replays recorded input exactly.
abstract class Interaction {
  /// Creates an interaction with [role].
  Interaction({this.role = InteractionRole.gesture});

  /// How the interaction takes part in a touch that may also scroll.
  final InteractionRole role;

  /// Seconds after contact before a [InteractionRole.gesture] hears the
  /// touch; 0 unless an interaction overrides it with a measured onset.
  double get onset => 0;

  /// Whether the interaction takes a touch that starts with [down]; none
  /// when it does not [takesPointers].
  bool accepts(PointerDownInput down) =>
      takesPointers && down.buttons == kPrimaryButton;

  /// Whether the interaction takes pointers at all. A region none of whose
  /// interactions does is not hit itself, so a touch reaches what lies
  /// under it: a target that only the keyboard and accessibility reach,
  /// such as a sheet's grabber over the sheet's content, which the sheet's
  /// own drag answers.
  bool get takesPointers => true;

  /// Whether the region's scroll wheel and trackpad scrolls reach this
  /// interaction as [PointerScrollInput]s. While one does, the region keeps
  /// them from the scroll views around it.
  bool get takesWheel => false;

  /// Whether a touch presses the region through this interaction; the
  /// region is `WidgetState.pressed` while one does.
  bool get pressed => false;

  /// Whether this interaction drags; the region is `WidgetState.dragged`
  /// while one does.
  bool get dragged => false;

  /// Whether the keyboard (Space, Enter) and the accessibility tap
  /// activate the region through this interaction ([ActivateInput]).
  bool get activates => false;

  /// Whether this interaction takes touches from the controls inside its
  /// region: below it, a control's claims do not hold a touch
  /// ([PointerDownInput.contested]), so this one can take the touch once
  /// the finger travels, as a sheet's pan does from a button, unless the
  /// control recognizes its gesture first. A
  /// [DragInteraction] that [DragInteraction.contends] does.
  bool get contendsWithControls => false;

  /// Whether a request for the region's context menu that comes without a
  /// pointer reaches this interaction as a [ContextMenuInput]: the context
  /// menu key and Shift+F10 when the region has focus.
  bool get opensContextMenu => false;

  /// Whether the region's value commands reach this interaction as
  /// [AdjustInput]s: the arrows, Home and End, Page Up and Page Down when
  /// the region has focus, and the accessibility increase and decrease.
  bool get adjusts => false;

  /// Tells the interaction how its region's coordinates map to global ones.
  ///
  /// An input host calls it for each interaction it hosts before the first
  /// input; `InputPort.forward` hands positions on in global coordinates
  /// with it, and relations pass it to their parts. The default ignores it.
  void bindRegion(Offset Function(Offset local) toGlobal) {}

  /// Answers [input].
  InteractionUpdate handle(InteractionInput input);

  /// The time of its next timed reaction, or null.
  double? get nextDue => null;

  /// Runs its timed reactions due by [time].
  InteractionUpdate advance(double time) => InteractionUpdate.none;

  /// This interaction, or [other] if this one fails before it recognizes:
  /// [other] waits, across touches while this one is undecided, and then
  /// replays the pointer input it missed.
  Interaction exclusively(Interaction other) => _Exclusive(this, other);

  /// This interaction and [other] at once, each hearing the touch when its
  /// own role does.
  Interaction simultaneously(Interaction other) => _Simultaneous(this, other);

  /// This interaction, and once it recognizes, [next] too: [next] hears
  /// the rest of the touch from a down at the moment this one recognized,
  /// where the finger is then. A hold that opens a menu hands the finger
  /// on to the menu's rows this way, with `InputPort.forward` as [next].
  Interaction sequenced(Interaction next) => _Sequenced(this, next);
}
