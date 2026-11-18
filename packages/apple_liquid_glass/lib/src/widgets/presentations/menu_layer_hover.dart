import 'package:apple_liquid_glass/src/widgets/presentations/menu_layer_keys.dart';
import 'package:apple_liquid_glass/src/widgets/presentations/menu_layer_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The mouse over an open menu: the row it rests on takes the focus, and
/// leaving an open submenu card for the menu beside it sends the card
/// back. A submenu row opens on a click, as it does on a tap: resting on
/// it opens nothing.
@internal
class MenuLayerHover {
  /// Creates the mouse of the layer it is given, which focuses and chooses
  /// through [keys].
  MenuLayerHover(this._layer, {required this.keys});

  final MenuLayerScope _layer;

  /// The keys, whose zones and choices the mouse uses.
  final MenuLayerKeys keys;

  bool _cardEntered = false;

  /// The top card changed: the mouse has not entered the new one yet.
  void cardChanged() => _cardEntered = false;

  /// The mouse rests on zone [id]: the focus moves there, as Flutter's
  /// menu items do; a row scrolled out of the list takes nothing.
  void rowEntered(int id) {
    if (!_layer.current) return;
    final motion = _layer.motion;
    final rect = motion.targetRect(keys.ids.targetOf(id));
    if (rect == null) return;
    if (!motion.menuRect.contains(rect.center)) return;
    keys.zones.requestFocus(id);
  }

  /// The mouse moved to [position] in the overlay: one that leaves an open
  /// submenu card for the menu beside it sends the card back, as a menu on
  /// the Mac closes a submenu when the pointer moves to another item.
  void hovered(Offset position) {
    final motion = _layer.motion;
    if (!_layer.current || _layer.built.top == 0) return;
    if (motion.isOnCard(position)) {
      _cardEntered = true;
    } else if (_cardEntered && motion.isBesideCard(position)) {
      _cardEntered = false;
      keys.back(keys: false);
    }
  }
}
