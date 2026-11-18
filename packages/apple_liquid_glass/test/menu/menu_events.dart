import 'package:apple_liquid_glass/src/motions/menu_event.dart';
import 'package:apple_liquid_glass/src/motions/menu_motion.dart';

/// The rows of the root list whose actions [motion] ran since its events
/// were last drained, in order; drains every event.
List<int> menuSelections(MenuMotion motion) => [
  for (final event in motion.drainEvents())
    if (event case MenuActivated(card: 0, :final index)) index,
];
