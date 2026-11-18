import 'package:flutter/foundation.dart';

/// The zone ids of the open menu's top card: a row's id is its target
/// index, except that the focused zone carries over a card change, its id
/// then naming the row the keyboard moves to, swapped with that row's own
/// index.
@internal
class MenuZoneIds {
  int? _id;
  int? _target;

  /// The zone id of target [target].
  int idOf(int target) => target == _target
      ? _id!
      : target == _id
      ? _target!
      : target;

  /// The target zone [id] stands for.
  // The swap is its own inverse.
  int targetOf(int id) => idOf(id);

  /// Lets zone [id] stand for target [target], and [target]'s zone for
  /// [id]'s.
  void swap(int id, int target) {
    _id = id;
    _target = target;
  }

  /// Gives every target its own index as its id.
  void clear() {
    _id = null;
    _target = null;
  }
}
