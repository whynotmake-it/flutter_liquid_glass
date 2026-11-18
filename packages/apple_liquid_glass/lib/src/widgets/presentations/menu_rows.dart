import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/src/widgets/presentations/menu_appearance.dart';
import 'package:apple_liquid_glass/src/widgets/presentations/menu_content.dart';
import 'package:apple_liquid_glass/src/widgets/presentations/menu_entries.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

part 'package:apple_liquid_glass/src/widgets/presentations/menu_rows_header.dart';
part 'package:apple_liquid_glass/src/widgets/presentations/menu_rows_marks.dart';

/// A chain of render-object widgets that follows the frames of a menu's
/// motion: [template] makes the chain again from each frame, which updates
/// the render objects and builds nothing.
@internal
MotionDriven menuDriven<T>(
  ValueListenable<T> frames,
  SingleChildRenderObjectWidget Function(T frame) template, {
  Widget? child,
  Key? key,
}) => MotionDriven(
  key: key,
  template: () => template(frames.value),
  child: child,
);

/// Lays its child out at [rect]'s size and draws it at [rect]'s corner,
/// taking all the room it is given: a move repaints, a resize lays out.
/// [inner] continues the chain inside it.
@internal
SingleChildRenderObjectWidget menuPlacement(
  Rect rect, [
  SingleChildRenderObjectWidget? inner,
]) => OverflowBox(
  alignment: Alignment.topLeft,
  minWidth: rect.width,
  maxWidth: rect.width,
  minHeight: rect.height,
  maxHeight: rect.height,
  child: Transform.translate(offset: rect.topLeft, child: inner),
);

/// A clip to [rrect] in the clipped box's coordinates; touches outside it
/// pass through.
@internal
class MenuClip extends CustomClipper<RRect> {
  /// Creates a clip to [rrect].
  const MenuClip(this.rrect);

  /// The clip.
  final RRect rrect;

  @override
  RRect getClip(Size size) => rrect;

  @override
  bool shouldReclip(MenuClip oldClipper) => oldClipper.rrect != rrect;
}

/// The elements of one card, each at its frame in the card's content.
///
/// The element widgets are made once per layout, style and content, so
/// building the rows again with the same three rebuilds none of them.
@internal
class MenuRows extends StatefulWidget {
  /// Creates the rows of [layout]; the submenu row [hidden] names is drawn
  /// by its card instead.
  const MenuRows({
    required this.layout,
    required this.style,
    required this.hidden,
    required this.content,
    super.key,
  });

  /// The card's layout.
  final MenuLayout layout;

  /// The target of the submenu row a card grows out of, or null.
  final int? hidden;

  /// The colors.
  final MenuAppearance style;

  /// The menu's entries and their state.
  final MenuContent content;

  @override
  State<MenuRows> createState() => _MenuRowsState();
}

class _MenuRowsState extends State<MenuRows> {
  List<Widget>? _children;

  @override
  void didUpdateWidget(MenuRows oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.layout, widget.layout) ||
        !identical(oldWidget.style, widget.style) ||
        !identical(oldWidget.content, widget.content)) {
      _children = null;
    } else if (oldWidget.hidden != widget.hidden) {
      _rehide(oldWidget.hidden, widget.hidden);
    }
  }

  // Only the rows that hide or show again are made anew; the others keep
  // their widgets, so they do not build.
  void _rehide(int? from, int? to) {
    final children = _children;
    if (children == null) return;
    final elements = widget.layout.elements;
    var slot = 0;
    for (var i = 0; i < elements.length; i++) {
      final element = elements[i];
      if (element.kind == MenuPlacedKind.cardHeader) continue;
      if (element.target >= 0 &&
          (element.target == from || element.target == to)) {
        children[slot] = _element(i);
      }
      slot++;
    }
    _children = List.of(children);
  }

  Widget _element(int i) {
    final layout = widget.layout;
    final element = layout.elements[i];
    return _MenuElement(
      key: ValueKey<int>(i),
      element: element,
      style: widget.style,
      width: layout.width,
      content: widget.content,
      hidden:
          element.kind == MenuPlacedKind.row &&
          element.entry is GlassSubmenu &&
          widget.hidden == element.target,
    );
  }

  List<Widget> _build() => [
    for (var i = 0; i < widget.layout.elements.length; i++)
      if (widget.layout.elements[i].kind != MenuPlacedKind.cardHeader)
        _element(i),
  ];

  @override
  Widget build(BuildContext context) {
    final layout = widget.layout;
    final all = _children ??= _build();
    return SizedBox(
      width: layout.width,
      height: layout.height,
      child: Stack(
        clipBehavior: .none,
        children: all,
      ),
    );
  }
}

class _MenuElement extends StatelessWidget {
  const _MenuElement({
    required this.element,
    required this.style,
    required this.width,
    required this.content,
    this.hidden = false,
    super.key,
  });

  final bool hidden;

  final MenuPlaced element;
  final MenuAppearance style;
  final double width;
  final MenuContent content;

  Color get _title => style.textStyle.color!;

  Color _colorOf({required bool enabled, required bool destructive}) => !enabled
      ? style.disabledColor
      : destructive
      ? style.destructiveColor
      : _title;

  // A row that is a target is described by its zone in the menu's layer;
  // one that is not (a disabled row) describes itself.
  Widget _described(Widget child, {required Widget Function(Widget) own}) =>
      element.target >= 0 ? ExcludeSemantics(child: child) : own(child);

  Widget _at(double center, double extent, Widget child) =>
      PositionedDirectional(
        start: center - extent / 2,
        width: extent,
        top: 0,
        bottom: 0,
        child: Center(child: child),
      );

  Widget _text(
    BuildContext context,
    String text,
    TextStyle base,
    Color color, {
    int maxLines = 1,
    TextAlign? align,
  }) => Text(
    text,
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
    textAlign: align,
    style: GlassTextScale.of(context).resolve(base).copyWith(color: color),
  );

  @override
  Widget build(BuildContext context) {
    final element = this.element;
    final rect = element.rect;
    return Positioned.fromRect(
      rect: rect,
      child: switch (element.kind) {
        MenuPlacedKind.row when hidden => Opacity(
          opacity: 0,
          child: _row(context),
        ),
        MenuPlacedKind.row => _row(context),
        MenuPlacedKind.header => _header(context),
        MenuPlacedKind.separator => ColoredBox(
          color: style.separatorColor,
        ),
        MenuPlacedKind.palette ||
        MenuPlacedKind.small ||
        MenuPlacedKind.medium => _cell(context),
        MenuPlacedKind.loading => _loading(context),
        MenuPlacedKind.widget => _widget(),
        MenuPlacedKind.cardHeader => const SizedBox.shrink(),
      },
    );
  }

  Widget _row(BuildContext context) {
    final entry = element.entry;
    final String title;
    final String? subtitle;
    final Widget? icon;
    final bool enabled;
    final bool destructive;
    var state = GlassMenuItemState.off;
    var submenu = false;
    Color? iconColor;
    switch (entry) {
      case GlassMenuItem():
        title = entry.title;
        subtitle = entry.subtitle;
        state = entry.state;
        icon = entry.iconVisibility == GlassMenuIconVisibility.hidden
            ? null
            : state != GlassMenuItemState.off && entry.selectedIcon != null
            ? entry.selectedIcon
            : entry.icon;
        enabled = entry.enabled;
        destructive = entry.destructive;
        iconColor = entry.iconColor;
      case GlassSubmenu():
        title = entry.title;
        subtitle = entry.subtitle;
        icon = entry.icon;
        enabled = entry.enabled;
        destructive = entry.destructive;
        submenu = true;
      default:
        return const SizedBox.shrink();
    }
    final color = _colorOf(enabled: enabled, destructive: destructive);
    final check = element.checkCenter;
    final image = element.imageCenter;
    return _described(
      own: (child) => Semantics(
        button: true,
        role: ui.SemanticsRole.menuItem,
        enabled: enabled,
        checked: state == GlassMenuItemState.off || submenu
            ? null
            : state == GlassMenuItemState.on,
        mixed: state == GlassMenuItemState.mixed ? true : null,
        expanded: submenu ? false : null,
        label: title,
        value: subtitle,
        excludeSemantics: true,
        child: child,
      ),
      Stack(
        children: [
          if (check != null && state != GlassMenuItemState.off)
            _at(
              check,
              MenuAppearance.markSlot,
              CustomPaint(
                size: state == GlassMenuItemState.on
                    ? MenuAppearance.checkSize
                    : MenuAppearance.mixedSize,
                painter: _MarkPainter(
                  color: color,
                  mixed: state == GlassMenuItemState.mixed,
                ),
              ),
            ),
          if (image != null && icon != null)
            _at(
              image,
              MenuAppearance.imageSlot,
              IconTheme.merge(
                data: IconThemeData(
                  size: MenuAppearance.rowIconSize,
                  color: iconColor ?? color,
                ),
                child: icon,
              ),
            ),
          PositionedDirectional(
            start: element.titleStart,
            end: width - element.titleEnd,
            top: 0,
            bottom: 0,
            child: Column(
              mainAxisAlignment: .center,
              crossAxisAlignment: .start,
              children: [
                _text(
                  context,
                  title,
                  style.textStyle,
                  color,
                  maxLines: element.maxLines,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: MenuAppearance.subtitleGap),
                  _text(
                    context,
                    subtitle,
                    _subtitleStyle,
                    style.secondaryColor,
                  ),
                ],
              ],
            ),
          ),
          if (submenu)
            _at(
              _metrics.chevronCenter,
              MenuAppearance.markSlot,
              Transform.flip(
                flipX: content.rtl,
                child: CustomPaint(
                  size: MenuAppearance.chevronSize,
                  painter: _ChevronPainter(color: color),
                ),
              ),
            ),
        ],
      ),
    );
  }

  MenuMetrics get _metrics => content.metrics;

  static const _subtitleStyle = TextStyle(fontSize: 13);

  Widget _header(BuildContext context) {
    return Semantics(
      header: true,
      label: element.title,
      excludeSemantics: true,
      child: Stack(
        children: [
          PositionedDirectional(
            start: element.titleStart,
            end: width - element.titleEnd,
            top: _metrics.headerLabelTop,
            child: _text(
              context,
              element.title ?? '',
              _subtitleStyle,
              style.secondaryColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context) {
    final entry = element.entry;
    final String title;
    final Widget? icon;
    final bool enabled;
    final bool destructive;
    var selected = false;
    Color? iconColor;
    switch (entry) {
      case GlassMenuItem():
        title = entry.title;
        selected = entry.state != GlassMenuItemState.off;
        icon = selected && entry.selectedIcon != null
            ? entry.selectedIcon
            : entry.icon;
        enabled = entry.enabled;
        destructive = entry.destructive;
        iconColor = entry.iconColor;
      case GlassSubmenu():
        title = entry.title;
        icon = entry.icon;
        enabled = entry.enabled;
        destructive = entry.destructive;
      default:
        return const SizedBox.shrink();
    }
    final color = _colorOf(enabled: enabled, destructive: destructive);
    final kind = element.kind;
    final Widget body;
    if (kind == MenuPlacedKind.medium) {
      body = Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: _metrics.mediumLabelTop,
            child: Center(
              child: icon == null
                  ? null
                  : IconTheme.merge(
                      data: IconThemeData(
                        size: MenuAppearance.rowIconSize,
                        color: iconColor ?? color,
                      ),
                      child: icon,
                    ),
            ),
          ),
          Positioned(
            left: 2,
            right: 2,
            top: _metrics.mediumLabelTop,
            child: _text(
              context,
              title,
              const TextStyle(fontSize: 12),
              color,
              align: TextAlign.center,
            ),
          ),
        ],
      );
    } else {
      final palette = kind == MenuPlacedKind.palette;
      body = Stack(
        alignment: Alignment.center,
        children: [
          if (palette && selected)
            SizedBox.square(
              dimension: _metrics.palettePlatter,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: style.paletteSelectionColor,
                  borderRadius: .circular(_metrics.palettePlatterRadius),
                ),
              ),
            ),
          if (icon != null)
            IconTheme.merge(
              data: IconThemeData(
                size: palette
                    ? _metrics.paletteImageSize
                    : MenuAppearance.rowIconSize,
                color: iconColor ?? color,
              ),
              child: icon,
            ),
        ],
      );
    }
    return _described(
      own: (child) => Semantics(
        button: true,
        role: ui.SemanticsRole.menuItem,
        enabled: enabled,
        selected: selected,
        label: title,
        excludeSemantics: true,
        child: child,
      ),
      body,
    );
  }

  Widget _loading(BuildContext context) {
    final check = element.imageCenter ?? _metrics.imageCenter;
    return Semantics(
      label: element.title,
      liveRegion: true,
      excludeSemantics: true,
      child: Stack(
        children: [
          _at(
            check,
            MenuAppearance.imageSlot,
            _Spinner(color: style.disabledColor),
          ),
          PositionedDirectional(
            start: element.titleStart,
            end: width - element.titleEnd,
            top: 0,
            bottom: 0,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: _text(
                context,
                element.title ?? '',
                style.textStyle,
                style.disabledColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _widget() {
    final entry = element.entry;
    if (entry is! GlassMenuWidget) return const SizedBox.shrink();
    final key = element.key;
    final Widget child = Builder(builder: entry.builder);
    return OverflowBox(
      alignment: .topCenter,
      minHeight: 0,
      maxHeight: double.infinity,
      child: Padding(
        padding: .symmetric(horizontal: _metrics.widgetInset),
        child: entry.height != null || key == null
            ? child
            : MotionMeasure(
                onSize: (_, size) => content.reportHeight(key, size.height),
                child: child,
              ),
      ),
    );
  }
}
