import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/src/widgets/presentations/menu_content.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

/// What an open menu's layer builds its tree from; it builds only when this
/// changes.
@internal
@immutable
class MenuLayerStructure {
  /// Creates the structure of cards laid out as [layouts].
  const MenuLayerStructure({
    required this.layouts,
    required this.hidden,
    required this.open,
    required this.scrolls,
    required this.top,
  });

  /// The layout of each card, the root first.
  final List<MenuLayout> layouts;

  /// The row each card hides under the submenu card grown out of it.
  final List<int?> hidden;

  /// Whether the menu is open.
  final bool open;

  /// Whether the root list is taller than it shows and scrolls.
  final bool scrolls;

  /// The card whose rows take the keys, the mouse and the highlight.
  final int top;

  /// Target [index] of the [top] card, or null past its targets.
  MenuTarget? targetAt(int index) {
    final targets = layouts[top].targets;
    return index >= 0 && index < targets.length ? targets[index] : null;
  }

  @override
  bool operator ==(Object other) {
    if (other is! MenuLayerStructure ||
        other.open != open ||
        other.scrolls != scrolls ||
        other.top != top ||
        other.layouts.length != layouts.length) {
      return false;
    }
    for (var i = 0; i < layouts.length; i++) {
      if (!identical(other.layouts[i], layouts[i]) ||
          other.hidden[i] != hidden[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(open, scrolls, top, layouts.length);
}

/// The open menu's layer as its parts see it: the motion and its frames,
/// what the layer built last, and the commands it gives the motion.
@internal
abstract interface class MenuLayerScope {
  /// The layer's context.
  BuildContext get context;

  /// Whether the layer is in the tree.
  bool get mounted;

  /// The menu's motion.
  MenuMotion get motion;

  /// The motion's frames, one per step.
  MotionSelection<MenuMotion> get frames;

  /// The structure the layer built last.
  MenuLayerStructure get built;

  /// The menu's entries laid out.
  MenuContent get content;

  /// Whether the rows the zones stand for are the top card's now.
  bool get current;

  /// Advances the motion to now and runs [command] on it.
  void command(void Function(MenuMotion motion, double t) command);
}
