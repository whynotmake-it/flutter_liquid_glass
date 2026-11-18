import 'package:meta/meta.dart';

/// How the elements of a group of a menu are laid out.
enum MenuSpecSize {
  /// Full-width rows.
  rows,

  /// Small cells, four to a row.
  small,

  /// Medium cells, three to a row.
  medium,

  /// One row of palette cells.
  palette,
}

/// What the layout of a menu reads of one of its entries: its kind, its
/// size and whether it has an icon, with no widget.
///
/// The presenter builds the specs from its entries and keeps each entry in
/// [entry], which the layout hands back on the elements and targets it
/// places for it without reading it.
@immutable
sealed class MenuSpec {
  const MenuSpec({this.entry});

  /// The presenter's entry behind the spec, opaque to the layout.
  final Object? entry;
}

/// An item or a submenu: a row, or a cell in a group of cells.
final class MenuRowSpec extends MenuSpec {
  /// Describes a row titled [title].
  const MenuRowSpec({
    required this.title,
    this.subtitle,
    this.hasIcon = false,
    this.enabled = true,
    this.keepsOpen = false,
    this.marked = false,
    this.submenu = false,
    super.entry,
  });

  /// The title, measured when it may wrap.
  final String title;

  /// The line under the title, or null; a row with one is taller.
  final String? subtitle;

  /// Whether the row shows an icon, which opens the icon column.
  final bool hasIcon;

  /// Whether choosing the row does anything; a disabled row is no target.
  final bool enabled;

  /// Whether the menu stays open after the row's action.
  final bool keepsOpen;

  /// Whether the row shows a selection mark, which opens the selection
  /// column.
  final bool marked;

  /// Whether the row opens a submenu card.
  final bool submenu;
}

/// A free-form row of the presenter's own.
final class MenuWidgetSpec extends MenuSpec {
  /// Describes a free-form row [height] high, or as high as measured under
  /// [key] when null.
  const MenuWidgetSpec({this.height, this.key, super.entry});

  /// The row's height, or null for its measured one.
  final double? height;

  /// The identity of the row's measured height, or null for its place
  /// among the free-form rows.
  final Object? key;
}

/// The line between two groups of a list.
final class MenuDividerSpec extends MenuSpec {
  /// Describes a divider.
  const MenuDividerSpec({super.entry});
}

/// A row that stands for a group still loading.
final class MenuLoadingSpec extends MenuSpec {
  /// Describes a loading row titled [title].
  const MenuLoadingSpec(this.title, {super.entry});

  /// The row's title.
  final String title;
}

/// A group of its own, with an optional header.
final class MenuSectionSpec extends MenuSpec {
  /// Describes a section of [children].
  const MenuSectionSpec({
    required this.children,
    this.title,
    this.singleSelection = false,
    this.size = MenuSpecSize.rows,
    this.maxTitleLines,
    super.entry,
  });

  /// The section's entries.
  final List<MenuSpec> children;

  /// The header, or null for none.
  final String? title;

  /// Whether the section is a single choice, which opens the selection
  /// column.
  final bool singleSelection;

  /// How the section's entries are laid out.
  final MenuSpecSize size;

  /// The most lines a row title wraps to, or null for one.
  final int? maxTitleLines;
}
