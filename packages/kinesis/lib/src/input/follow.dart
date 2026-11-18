import 'package:flutter/painting.dart';
import 'package:kinesis/src/input/interaction.dart';
import 'package:kinesis/src/input/interaction_event.dart';
import 'package:kinesis/src/input/interaction_input.dart';

/// What follows one touch as it goes: a press body, a lens, a slider's
/// knob, a menu's card. It decides nothing about the touch; the region's
/// other interactions do.
abstract class PointerFollower {
  /// A finger touched at [input]'s position.
  void down(PointerDownInput input);

  /// The finger moved.
  void move(PointerMoveInput input);

  /// The finger lifted.
  void up(PointerUpInput input);

  /// The touch ended without a release.
  void cancel(PointerCancelInput input);

  /// The mouse moved over the region, or left it.
  void hover(PointerHoverInput input) {}
}

/// Feeds one pointer at a time to [follower], its positions mirrored left
/// to right when [mirrored] (a right-to-left layout), and the hover as it
/// is; it claims nothing and never fails.
///
/// A gesture by default, so it hears the touch at contact even inside a
/// scroll view, which holds back only the region's press: a glass button
/// lifts at once there, as UIKit's does.
final class FollowInteraction extends Interaction {
  /// Creates an interaction that feeds [follower].
  FollowInteraction(this.follower, {super.role, this.mirrored = false});

  /// What hears the touch.
  final PointerFollower follower;

  /// Whether positions are mirrored left to right.
  bool mirrored;

  int? _pointer;
  double _width = 0;

  Offset _x(Offset p) => mirrored ? Offset(_width - p.dx, p.dy) : p;

  Rect _box(Rect box) =>
      Rect.fromLTRB(_width - box.right, box.top, _width - box.left, box.bottom);

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput() when _pointer == null && accepts(input):
        _pointer = input.pointer;
        _width = input.regionSize.width;
        follower.down(
          mirrored ? input.copyWith(position: _x(input.position)) : input,
        );
      case PointerMoveInput() when input.pointer == _pointer:
        follower.move(
          mirrored
              ? input.copyWith(
                  position: _x(input.position),
                  regionBox: _box(input.regionBox),
                )
              : input,
        );
      case PointerUpInput() when input.pointer == _pointer:
        _pointer = null;
        follower.up(
          mirrored
              ? input.copyWith(
                  position: _x(input.position),
                  velocity: Offset(-input.velocity.dx, input.velocity.dy),
                  regionBox: _box(input.regionBox),
                )
              : input,
        );
      case PointerCancelInput() when input.pointer == _pointer:
        _pointer = null;
        follower.cancel(input);
      case PointerHoverInput():
        follower.hover(input);
      default:
    }
    return InteractionUpdate.none;
  }
}
