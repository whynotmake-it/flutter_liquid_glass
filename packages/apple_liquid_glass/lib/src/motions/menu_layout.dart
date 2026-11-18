import 'dart:math' as math;
import 'dart:ui';

import 'package:apple_liquid_glass/src/motions/menu_metrics.dart';
import 'package:apple_liquid_glass/src/motions/menu_placed.dart';
import 'package:apple_liquid_glass/src/motions/menu_specs.dart';

/// The laid out content of one menu card: its height, what it draws and
/// where it reacts to touches.
class MenuLayout {
  /// Creates a layout.
  const MenuLayout({
    required this.height,
    required this.width,
    this.targets = const [],
    this.elements = const [],
    this.loading = false,
  });

  /// [rows] rows of [rowHeight] between [inset]s, reversed when
  /// [reversed]: target `i` is row `i`.
  ///
  /// [width], [rowHeight] and [inset] default to [MenuMetrics.width],
  /// [MenuMetrics.rowHeight] and [MenuMetrics.topInset] of
  /// [MenuMetrics.standard].
  factory MenuLayout.uniform(
    int rows, {
    double? width,
    double? rowHeight,
    double? inset,
    bool reversed = false,
  }) {
    const m = MenuMetrics.standard;
    final w = width ?? m.width;
    final row = rowHeight ?? m.rowHeight;
    final pad = inset ?? m.topInset;
    return MenuLayout(
      height: 2 * pad + row * rows,
      width: w,
      targets: [
        for (var i = 0; i < rows; i++)
          MenuTarget(
            rect: Rect.fromLTWH(
              0,
              pad + row * (reversed ? rows - 1 - i : i),
              w,
              row,
            ),
          ),
      ],
    );
  }

  /// Lays out [specs] as the iOS 27 menu does.
  ///
  /// [header] makes it a submenu card under that submenu's header; [size]
  /// lays out the entries outside sections. [widgetHeight] answers the
  /// height of a free-form row (keyed by its key or its place);
  /// [titleLines] answers how many lines a title takes when it may wrap to
  /// more than one. [reversed] reverses the groups and the rows inside
  /// them, for a menu opening upward; [rtl] mirrors the frames.
  factory MenuLayout.build(
    List<MenuSpec> specs, {
    MenuMetrics metrics = MenuMetrics.standard,
    bool reversed = false,
    bool rtl = false,
    bool singleSelection = false,
    MenuSpecSize size = MenuSpecSize.rows,
    MenuRowSpec? header,
    double? Function(Object key)? widgetHeight,
    int Function(String title, double width, int maxLines)? titleLines,
  }) {
    final groups = <_Group>[];
    var loading = false;
    _Group? open;
    var widgetIndex = 0;
    void flush() {
      final group = open;
      if (group != null && group.items.isNotEmpty) groups.add(group);
      open = null;
    }

    void add(
      List<MenuSpec> list,
      MenuSpecSize kind,
      int maxLines, {
      required bool section,
    }) {
      for (final spec in list) {
        switch (spec) {
          case MenuRowSpec():
            (open ??= _Group(kind, maxLines)).items.add(spec);
          case MenuWidgetSpec():
            (open ??= _Group(
              kind,
              maxLines,
            )).items.add(_WidgetSlot(spec, spec.key ?? widgetIndex));
            widgetIndex++;
          case MenuDividerSpec():
            if (!section) flush();
          case MenuLoadingSpec():
            loading = true;
            (open ??= _Group(kind, maxLines)).items.add(spec);
          case MenuSectionSpec():
            flush();
            open = _Group(
              spec.size,
              spec.maxTitleLines ?? 1,
              header: spec.title,
              singleSelection: spec.singleSelection,
            );
            add(
              spec.children,
              spec.size,
              spec.maxTitleLines ?? 1,
              section: true,
            );
            flush();
        }
      }
    }

    add(specs, size, 1, section: false);
    flush();
    if (reversed) {
      groups.setAll(0, groups.reversed.toList());
      for (final group in groups) {
        if (group.kind == MenuSpecSize.rows) {
          group.items.setAll(0, group.items.reversed.toList());
        }
      }
    }

    var selection = singleSelection;
    for (final group in groups) {
      if (group.singleSelection) selection = true;
      if (group.kind != MenuSpecSize.rows) continue;
      for (final item in group.items) {
        if (item is MenuRowSpec && item.marked) selection = true;
      }
    }
    bool imagesOf(_Group group) => group.items.any(
      (Object item) => switch (item) {
        MenuRowSpec(:final hasIcon) => hasIcon,
        MenuLoadingSpec() => true,
        _ => false,
      },
    );
    final m = metrics;
    final width = m.width;
    final check = selection ? m.selectionCheckCenter : null;
    final headerStart = selection ? m.selectionHeaderStart : m.headerStart;

    final elements = <MenuPlaced>[];
    final targets = <MenuTarget>[];
    Rect mirror(Rect r) => rtl
        ? Rect.fromLTRB(width - r.right, r.top, width - r.left, r.bottom)
        : r;
    void place(
      MenuPlaced Function(int target) element, {
      required Rect rect,
      MenuTargetKind? kind,
      bool keepsOpen = false,
      Object? entry,
    }) {
      final index = elements.length;
      var target = -1;
      if (kind != null) {
        target = targets.length;
        targets.add(
          MenuTarget(
            rect: mirror(rect),
            kind: kind,
            keepsOpen: keepsOpen,
            entry: entry,
            element: index,
          ),
        );
      }
      elements.add(element(target));
    }

    void placeCell(MenuRowSpec spec, Rect rect, MenuPlacedKind kind) => place(
      (int target) => MenuPlaced(
        kind: kind,
        rect: mirror(rect),
        entry: spec.entry,
        target: target,
      ),
      kind: _targetKind(spec),
      keepsOpen: spec.keepsOpen,
      entry: spec.entry,
      rect: rect,
    );

    var y = 0.0;
    if (header != null) {
      final rect = Rect.fromLTWH(0, 0, width, m.cardHeaderHeight);
      place(
        (int target) => MenuPlaced(
          kind: MenuPlacedKind.cardHeader,
          rect: mirror(rect),
          entry: header.entry,
          title: header.title,
          imageCenter: header.hasIcon ? m.imageCenter : null,
          titleStart: header.hasIcon ? m.titleStart : m.plainTitleStart,
          titleEnd: m.titleEnd,
          target: target,
        ),
        kind: MenuTargetKind.back,
        entry: header.entry,
        rect: rect,
      );
      y = m.cardHeaderHeight;
    }
    MenuSpecSize? previous;
    for (final group in groups) {
      if (previous == null) {
        if (group.header == null) y += m.topInset;
      } else {
        final gap = switch (previous) {
          MenuSpecSize.rows => m.groupGap,
          MenuSpecSize.small || MenuSpecSize.medium => m.cellGroupGap,
          MenuSpecSize.palette => 0.0,
        };
        if (previous != MenuSpecSize.palette) {
          final line = y + gap / 2;
          elements.add(
            MenuPlaced(
              kind: MenuPlacedKind.separator,
              rect: Rect.fromLTRB(
                m.separatorInset,
                line - 0.5,
                width - m.separatorInset,
                line + 0.5,
              ),
            ),
          );
        }
        y += gap;
      }
      final title = group.header;
      if (title != null) {
        elements.add(
          MenuPlaced(
            kind: MenuPlacedKind.header,
            rect: mirror(Rect.fromLTWH(0, y, width, m.headerHeight)),
            title: title,
            titleStart: headerStart,
            titleEnd: m.titleEnd,
          ),
        );
        y += group.kind == MenuSpecSize.rows
            ? m.rowsAfterHeader
            : m.cellsAfterHeader;
      }
      switch (group.kind) {
        case MenuSpecSize.rows:
          final images = imagesOf(group);
          final image = images
              ? (selection ? m.selectionImageCenter : m.imageCenter)
              : null;
          final titleStart = switch ((selection, images)) {
            (true, true) => m.selectionTitleStart,
            (false, true) => m.titleStart,
            (true, false) => m.selectionOnlyTitleStart,
            (false, false) => m.plainTitleStart,
          };
          for (final item in group.items) {
            switch (item) {
              case MenuRowSpec():
                var lines = 1;
                if (!item.submenu && group.maxLines > 1 && titleLines != null) {
                  lines = math.min(
                    group.maxLines,
                    titleLines(
                      item.title,
                      m.titleEnd - titleStart,
                      group.maxLines,
                    ),
                  );
                }
                final height =
                    (item.subtitle == null
                        ? m.rowHeight
                        : m.subtitleRowHeight) +
                    (lines - 1) * m.extraLineHeight;
                final rect = Rect.fromLTWH(0, y, width, height);
                place(
                  (int target) => MenuPlaced(
                    kind: MenuPlacedKind.row,
                    rect: mirror(rect),
                    entry: item.entry,
                    checkCenter: check,
                    imageCenter: image,
                    titleStart: titleStart,
                    titleEnd: m.titleEnd,
                    maxLines: item.submenu ? 1 : group.maxLines,
                    target: target,
                  ),
                  kind: _targetKind(item),
                  keepsOpen: item.keepsOpen,
                  entry: item.entry,
                  rect: rect,
                );
                y += height;
              case _WidgetSlot(:final spec, :final key):
                final height =
                    spec.height ?? widgetHeight?.call(key) ?? m.rowHeight;
                elements.add(
                  MenuPlaced(
                    kind: MenuPlacedKind.widget,
                    rect: mirror(Rect.fromLTWH(0, y, width, height)),
                    entry: spec.entry,
                    titleStart: m.widgetInset,
                    titleEnd: width - m.widgetInset,
                    key: key,
                  ),
                );
                y += height;
              case MenuLoadingSpec(:final title):
                elements.add(
                  MenuPlaced(
                    kind: MenuPlacedKind.loading,
                    rect: mirror(Rect.fromLTWH(0, y, width, m.rowHeight)),
                    title: title,
                    checkCenter: check,
                    imageCenter: image ?? m.imageCenter,
                    titleStart: images ? titleStart : m.titleStart,
                    titleEnd: m.titleEnd,
                  ),
                );
                y += m.rowHeight;
            }
          }
        case MenuSpecSize.palette:
          final cells = group.items.whereType<MenuRowSpec>().toList();
          final n = math.max(1, cells.length);
          final cell = math.min(
            m.paletteMaxCellWidth,
            m.paletteCellWidth * 5 / n,
          );
          var x = (width - cell * n) / 2;
          for (final entry in cells) {
            final rect = Rect.fromLTWH(x, y, cell, m.paletteCellHeight);
            placeCell(entry, rect, MenuPlacedKind.palette);
            x += cell;
          }
          y += m.paletteCellHeight;
        case MenuSpecSize.small || MenuSpecSize.medium:
          final small = group.kind == MenuSpecSize.small;
          final perRow = small ? m.smallPerRow : m.mediumPerRow;
          final height = small ? m.smallCellHeight : m.mediumCellHeight;
          final cells = group.items.whereType<MenuRowSpec>().toList();
          final cell = (width - 2 * m.cellInset) / perRow;
          for (var i = 0; i < cells.length; i++) {
            final column = i % perRow;
            if (column == 0 && i > 0) y += height;
            final rect = Rect.fromLTWH(
              m.cellInset + column * cell,
              y,
              cell,
              height,
            );
            placeCell(
              cells[i],
              rect,
              small ? MenuPlacedKind.small : MenuPlacedKind.medium,
            );
          }
          if (cells.isNotEmpty) y += height;
      }
      previous = group.kind;
    }
    y += groups.isEmpty && header == null ? m.topInset : m.bottomInset;
    return MenuLayout(
      height: y,
      width: width,
      targets: targets,
      elements: elements,
      loading: loading,
    );
  }

  /// The height of the content.
  final double height;

  /// The width of the content.
  final double width;

  /// The places that react to touches.
  final List<MenuTarget> targets;

  /// What the content draws.
  final List<MenuPlaced> elements;

  /// Whether a deferred group is still loading.
  final bool loading;

  /// The index of the target at [position] in content coordinates, or
  /// null.
  int? targetAt(Offset position) {
    for (var i = 0; i < targets.length; i++) {
      if (targets[i].rect.contains(position)) return i;
    }
    return null;
  }
}

MenuTargetKind? _targetKind(MenuRowSpec spec) => !spec.enabled
    ? null
    : spec.submenu
    ? MenuTargetKind.submenu
    : MenuTargetKind.action;

class _Group {
  _Group(this.kind, this.maxLines, {this.header, this.singleSelection = false});

  final MenuSpecSize kind;
  final int maxLines;
  final String? header;
  final bool singleSelection;
  final List<Object> items = [];
}

class _WidgetSlot {
  const _WidgetSlot(this.spec, this.key);

  final MenuWidgetSpec spec;
  final Object key;
}
