import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';

/// Asks the focused control for its context menu: the context menu key and
/// Shift+F10.
///
/// UIKit: the context menu a hardware keyboard opens on the focused view.
/// Flutter: none; the keys reach no widget by default.
///
/// An `InputRegion` or an `InputZones` zone whose interaction
/// [Interaction.opensContextMenu] (a `SecondaryClickInteraction`) binds
/// [defaultShortcuts] around its focus and turns the intent into a
/// [ContextMenuInput] at its centre, where a menu anchors. As with
/// activation, the focused, innermost host handles it, and an app replaces
/// what it does with an `Actions` above the host or binds more keys to it
/// with a `Shortcuts` above the host.
class ContextMenuIntent extends Intent {
  /// Asks for the context menu.
  const ContextMenuIntent();

  /// The keys a host binds: the context menu key and Shift+F10, as on
  /// Windows and Linux desktops.
  static const Map<ShortcutActivator, Intent> defaultShortcuts = {
    SingleActivator(LogicalKeyboardKey.contextMenu): ContextMenuIntent(),
    SingleActivator(LogicalKeyboardKey.f10, shift: true): ContextMenuIntent(),
  };
}

/// Asks the focused region to step its value: the intent of the arrows,
/// Home and End, Page Up and Page Down on a slider, a stepper or a page
/// control.
///
/// Flutter: the private adjustment intent of `Slider`.
///
/// An `InputRegion` whose interaction [Interaction.adjusts] binds
/// [defaultShortcuts] around its focus, as `Slider` does inside its own
/// widget, and turns the intent into an [AdjustInput]. An app replaces
/// what a command does with an `Actions` above the region (the region's
/// action is `Action.overridable`), and binds more keys to the intent with
/// a `Shortcuts` above the region; the keys the region binds itself come
/// first, as `Slider`'s do.
class AdjustValueIntent extends Intent {
  /// Asks for [command].
  const AdjustValueIntent(this.command);

  /// The step asked for.
  final ValueCommand command;

  static const Map<ShortcutActivator, Intent> _vertical = {
    SingleActivator(LogicalKeyboardKey.arrowUp): AdjustValueIntent(
      ValueCommand.increase,
    ),
    SingleActivator(LogicalKeyboardKey.arrowDown): AdjustValueIntent(
      ValueCommand.decrease,
    ),
    SingleActivator(LogicalKeyboardKey.home): AdjustValueIntent(
      ValueCommand.toMinimum,
    ),
    SingleActivator(LogicalKeyboardKey.end): AdjustValueIntent(
      ValueCommand.toMaximum,
    ),
    SingleActivator(LogicalKeyboardKey.pageUp): AdjustValueIntent(
      ValueCommand.increaseLarge,
    ),
    SingleActivator(LogicalKeyboardKey.pageDown): AdjustValueIntent(
      ValueCommand.decreaseLarge,
    ),
  };

  static const Map<ShortcutActivator, Intent> _leftToRight = {
    SingleActivator(LogicalKeyboardKey.arrowRight): AdjustValueIntent(
      ValueCommand.increase,
    ),
    SingleActivator(LogicalKeyboardKey.arrowLeft): AdjustValueIntent(
      ValueCommand.decrease,
    ),
  };

  static const Map<ShortcutActivator, Intent> _rightToLeft = {
    SingleActivator(LogicalKeyboardKey.arrowLeft): AdjustValueIntent(
      ValueCommand.increase,
    ),
    SingleActivator(LogicalKeyboardKey.arrowRight): AdjustValueIntent(
      ValueCommand.decrease,
    ),
  };

  static final Map<ShortcutActivator, Intent> _traditionalLeftToRight = {
    ..._leftToRight,
    ..._vertical,
  };

  static final Map<ShortcutActivator, Intent> _traditionalRightToLeft = {
    ..._rightToLeft,
    ..._vertical,
  };

  /// The keys a value region binds in [direction] under [navigation]: the
  /// arrow toward the end of the line increases (right in left-to-right,
  /// left in right-to-left), the other decreases, and in traditional
  /// navigation up increases, down decreases, Home and End go to the
  /// minimum and maximum, Page Up and Page Down take a larger step. In
  /// directional navigation (a TV remote) only the horizontal arrows are
  /// bound, so up and down still move focus.
  static Map<ShortcutActivator, Intent> defaultShortcuts(
    TextDirection direction,
    NavigationMode navigation,
  ) => switch ((navigation, direction)) {
    (NavigationMode.directional, TextDirection.ltr) => _leftToRight,
    (NavigationMode.directional, TextDirection.rtl) => _rightToLeft,
    (NavigationMode.traditional, TextDirection.ltr) => _traditionalLeftToRight,
    (NavigationMode.traditional, TextDirection.rtl) => _traditionalRightToLeft,
  };
}
