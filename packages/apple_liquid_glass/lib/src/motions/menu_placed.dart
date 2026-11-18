import 'dart:ui';

import 'package:apple_liquid_glass/src/motions/menu_layout.dart';
import 'package:apple_liquid_glass/src/motions/menu_specs.dart';

/// What choosing a [MenuTarget] does.
enum MenuTargetKind {
  /// Runs an item's action.
  action,

  /// Opens a submenu card.
  submenu,

  /// Closes the top submenu card.
  back,
}

/// A place in a menu that reacts to a touch.
class MenuTarget {
  /// Creates a target.
  const MenuTarget({
    required this.rect,
    this.kind = MenuTargetKind.action,
    this.keepsOpen = false,
    this.entry,
    this.element = -1,
  });

  /// The frame, in the coordinates of its card's content.
  final Rect rect;

  /// What choosing the target does.
  final MenuTargetKind kind;

  /// Whether the menu stays open after the target's action.
  final bool keepsOpen;

  /// The entry behind the target ([MenuSpec.entry]).
  final Object? entry;

  /// The index of the element the target belongs to in
  /// [MenuLayout.elements], or -1.
  final int element;
}

/// The kind of a [MenuPlaced] element.
enum MenuPlacedKind {
  /// A full-width row of an item or a submenu.
  row,

  /// A section header.
  header,

  /// The hairline between two groups.
  separator,

  /// A palette cell.
  palette,

  /// A small cell.
  small,

  /// A medium cell.
  medium,

  /// The row shown while a deferred group loads.
  loading,

  /// A free-form row.
  widget,

  /// The header of a submenu card.
  cardHeader,
}

/// One element of a laid out menu.
class MenuPlaced {
  /// Creates an element.
  const MenuPlaced({
    required this.kind,
    required this.rect,
    this.entry,
    this.title,
    this.checkCenter,
    this.imageCenter,
    this.titleStart = 0,
    this.titleEnd = 0,
    this.maxLines = 1,
    this.target = -1,
    this.key,
  });

  /// The kind of the element.
  final MenuPlacedKind kind;

  /// The frame, in the coordinates of its card's content.
  final Rect rect;

  /// The entry drawn ([MenuSpec.entry]), if any.
  final Object? entry;

  /// The text of a header or a loading row.
  final String? title;

  /// The center of the selection mark from the leading edge, when the
  /// menu has a selection column.
  final double? checkCenter;

  /// The center of the glyph from the leading edge, when the menu has a
  /// glyph column.
  final double? imageCenter;

  /// The start of the title from the leading edge.
  final double titleStart;

  /// The end of the title from the leading edge.
  final double titleEnd;

  /// The most lines the title wraps to.
  final int maxLines;

  /// The index of the element's target in [MenuLayout.targets], or -1.
  final int target;

  /// The identity of a free-form row's measured height.
  final Object? key;
}
