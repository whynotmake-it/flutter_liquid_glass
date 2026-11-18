import 'dart:math' as math;

/// The measured layout of the inside of an iOS 27 menu.
///
/// Read from the view tree of `UIButton` menus on the iPhone 16 Pro (iOS
/// 27.0.1, light and dark, 2026-10-03): `_UIContextMenuListView`,
/// `_UIContextMenuCell`, `_UIContextMenuHeaderView`,
/// `_UIContextMenuSeparatorView`, `_UIContextMenuSubmenuTitleView`.
/// Lengths are points from the menu's leading edge or top.
class MenuMetrics {
  /// Creates metrics from explicit values.
  const MenuMetrics({
    this.width = 250,
    this.topInset = 10,
    this.bottomInset = 10,
    this.rowHeight = 42,
    this.subtitleRowHeight = 60,
    this.extraLineHeight = 22,
    this.imageCenter = 40,
    this.titleStart = 64,
    this.selectionCheckCenter = 27.7,
    this.selectionImageCenter = 55,
    this.selectionTitleStart = 79,
    this.selectionOnlyTitleStart = 52,
    this.plainTitleStart = 28,
    this.titleEnd = 222,
    this.chevronCenter = 219,
    this.headerHeight = 40.33,
    this.headerLabelTop = 12,
    this.headerStart = 28,
    this.selectionHeaderStart = 43,
    this.rowsAfterHeader = 38.33,
    this.cellsAfterHeader = 28.33,
    this.groupGap = 21,
    this.cellGroupGap = 1,
    this.separatorInset = 24,
    this.paletteCellWidth = 42.67,
    this.paletteMaxCellWidth = 62.67,
    this.paletteCellHeight = 54,
    this.paletteImageSize = 22,
    this.palettePlatter = 38,
    this.palettePlatterRadius = 10,
    this.cellInset = 8,
    this.smallCellHeight = 51.67,
    this.smallPerRow = 4,
    this.mediumCellHeight = 77,
    this.mediumPerRow = 3,
    this.mediumLabelTop = 44.67,
    this.cardHeaderHeight = 62,
    this.widgetInset = 16,
    this.maxHeight = 520,
  });

  /// The width of the menu.
  final double width;

  /// The space above the first row.
  final double topInset;

  /// The space below the last row.
  final double bottomInset;

  /// The height of a row.
  final double rowHeight;

  /// The height of a row with a subtitle (title 17 pt, subtitle 13 pt 23 pt
  /// below the title's top).
  final double subtitleRowHeight;

  /// The height a row gains per extra title line; not measured (the line
  /// height of the 17 pt title).
  final double extraLineHeight;

  /// The center of a row's glyph.
  final double imageCenter;

  /// The start of a row's title.
  final double titleStart;

  /// The center of the checkmark in a menu with a selection column.
  final double selectionCheckCenter;

  /// The center of a row's glyph in a menu with a selection column.
  final double selectionImageCenter;

  /// The start of a row's title in a menu with a selection column.
  final double selectionTitleStart;

  /// The start of a row's title in a menu with a selection column and no
  /// glyphs; not measured.
  final double selectionOnlyTitleStart;

  /// The start of a row's title in a menu without glyphs.
  final double plainTitleStart;

  /// The end of a row's title, before the trailing chevron.
  final double titleEnd;

  /// The center of a submenu row's chevron and of a card header's.
  final double chevronCenter;

  /// The height of a section header.
  final double headerHeight;

  /// The top of a section header's 13 pt label.
  final double headerLabelTop;

  /// The start of a section header's label.
  final double headerStart;

  /// The start of a section header's label in a menu with a selection
  /// column.
  final double selectionHeaderStart;

  /// The distance from a section header's top to its first row: the rows
  /// overlap the header's lower part.
  final double rowsAfterHeader;

  /// The distance from a section header's top to a row of cells.
  final double cellsAfterHeader;

  /// The gap between two groups of rows, with the hairline in its middle.
  final double groupGap;

  /// The gap after a group of small or medium cells, which holds the
  /// hairline; a palette is followed by no gap and no line.
  final double cellGroupGap;

  /// The inset of the group hairline from both sides of the menu.
  final double separatorInset;

  /// The width of each of five palette cells; the row keeps five cells'
  /// width, so fewer cells widen and more narrow.
  final double paletteCellWidth;

  /// The widest palette cell (three cells, SwiftUI's palette picker).
  final double paletteMaxCellWidth;

  /// The height of a palette cell.
  final double paletteCellHeight;

  /// The size of a palette cell's glyph.
  final double paletteImageSize;

  /// The side of the platter under the selected palette cell, read from a
  /// screenshot.
  final double palettePlatter;

  /// The corner radius of the palette platter; not measured.
  final double palettePlatterRadius;

  /// The inset of small and medium cells from the menu's sides.
  final double cellInset;

  /// The height of a small cell.
  final double smallCellHeight;

  /// Small cells per line.
  final int smallPerRow;

  /// The height of a medium cell.
  final double mediumCellHeight;

  /// Medium cells per line.
  final int mediumPerRow;

  /// The top of a medium cell's 12 pt label.
  final double mediumLabelTop;

  /// The height of a submenu card's header.
  final double cardHeaderHeight;

  /// The inset of a free-form row from the menu's sides; this package's
  /// own (no native element).
  final double widgetInset;

  /// The tallest a menu gets; taller content scrolls inside it.
  final double maxHeight;

  /// The measured iOS 27 menu.
  static const standard = MenuMetrics();

  /// These metrics for a menu whose row titles are drawn [titleSize] tall,
  /// in a space [availableWidth] wide.
  ///
  /// Fitted to one reading beside the default one (iPhone 16 Pro simulator,
  /// iOS 27.2, 402 wide): at the third accessibility text size, where a
  /// title of 17 is drawn at 40, the menu is 370 wide, 16 from the screen's
  /// sides, a plain row is 96.67 tall, and its title still starts at 28 and
  /// ends 28 from the trailing edge. So a row grows along the line through
  /// the two readings, what ends at the trailing edge follows the width,
  /// and what starts at the leading edge stays.
  ///
  /// Not measured, and grown by the row's own factor: rows with a subtitle,
  /// further title lines, section headers, a submenu card's header, the
  /// label part of a medium cell, and the width on its way to
  /// [availableWidth] less 16 on each side. Glyphs, checkmarks, palette and
  /// small cells, the gaps between groups and [maxHeight] stay as they are.
  /// Titles of 17 or smaller keep these metrics.
  MenuMetrics scaled({
    required double titleSize,
    required double availableWidth,
  }) {
    final grown =
        (titleSize - _standardTitleSize) /
        (_largeTitleSize - _standardTitleSize);
    if (grown <= 0) return this;
    final growth = 1 + grown * (_largeRowGrowth - 1);
    final grownWidth = math.min(
      width * growth,
      math.max(width, availableWidth - 2 * _largeTextMargin),
    );
    return MenuMetrics(
      width: grownWidth,
      topInset: topInset,
      bottomInset: bottomInset,
      rowHeight: rowHeight * growth,
      subtitleRowHeight: subtitleRowHeight * growth,
      extraLineHeight: extraLineHeight * growth,
      imageCenter: imageCenter,
      titleStart: titleStart,
      selectionCheckCenter: selectionCheckCenter,
      selectionImageCenter: selectionImageCenter,
      selectionTitleStart: selectionTitleStart,
      selectionOnlyTitleStart: selectionOnlyTitleStart,
      plainTitleStart: plainTitleStart,
      titleEnd: grownWidth - (width - titleEnd),
      chevronCenter: grownWidth - (width - chevronCenter),
      headerHeight: headerHeight * growth,
      headerLabelTop: headerLabelTop * growth,
      headerStart: headerStart,
      selectionHeaderStart: selectionHeaderStart,
      rowsAfterHeader: rowsAfterHeader * growth,
      cellsAfterHeader: cellsAfterHeader * growth,
      groupGap: groupGap,
      cellGroupGap: cellGroupGap,
      separatorInset: separatorInset,
      paletteCellWidth: paletteCellWidth,
      paletteMaxCellWidth: paletteMaxCellWidth,
      paletteCellHeight: paletteCellHeight,
      paletteImageSize: paletteImageSize,
      palettePlatter: palettePlatter,
      palettePlatterRadius: palettePlatterRadius,
      cellInset: cellInset,
      smallCellHeight: smallCellHeight,
      smallPerRow: smallPerRow,
      mediumCellHeight:
          mediumLabelTop + (mediumCellHeight - mediumLabelTop) * growth,
      mediumPerRow: mediumPerRow,
      mediumLabelTop: mediumLabelTop,
      cardHeaderHeight: cardHeaderHeight * growth,
      widgetInset: widgetInset,
      maxHeight: maxHeight,
    );
  }

  // A title's size at the default text size and at the third accessibility
  // one, how many times taller a plain row is there, and how far the menu
  // stays from the screen's sides.
  static const double _standardTitleSize = 17;
  static const double _largeTitleSize = 40;
  static const double _largeRowGrowth = 96.67 / 42;
  static const double _largeTextMargin = 16;
}
