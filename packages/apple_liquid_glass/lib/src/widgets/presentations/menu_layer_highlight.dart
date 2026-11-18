import 'dart:math' as math;

import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/src/widgets/presentations/menu_appearance.dart';
import 'package:apple_liquid_glass/src/widgets/presentations/menu_layer_scope.dart';
import 'package:apple_liquid_glass/src/widgets/presentations/menu_zone_ids.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

/// The highlight of an open menu's cards: which row it shows on, from the
/// focus or the motion, and where, painted as they move.
@internal
class MenuLayerHighlight {
  /// Creates the highlight of the layer it is given, whose top card's rows
  /// are the zones of [zones] under [ids].
  MenuLayerHighlight(this._layer, {required this.zones, required this.ids});

  final MenuLayerScope _layer;

  /// The zones of the top card's rows.
  final InputZonesController<int> zones;

  /// The ids of those zones.
  final MenuZoneIds ids;

  /// The target of [card] the highlight shows on now: the focused row of
  /// the top card while the keyboard or the mouse is in use, else the row
  /// the motion highlights (under the finger, or the one chosen).
  int? lit(int card) {
    final motion = _layer.motion;
    final built = _layer.built;
    final focused = zones.focusedZone;
    if (focused != null &&
        card == built.top &&
        _layer.current &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional) {
      return ids.targetOf(focused);
    }
    if (motion.highlightedCard != card) return null;
    final index = motion.highlighted;
    final targets = built.layouts[card].targets;
    if (index == null || index >= targets.length) return null;
    // A tapped submenu row gives way to its card at once.
    return switch (targets[index].kind) {
      MenuTargetKind.back => null,
      MenuTargetKind.submenu when !motion.isSliding => null,
      _ => index,
    };
  }

  /// The highlight of [card], painted from the motion and the focus as they
  /// move: a row changing hands repaints it and rebuilds nothing.
  Widget of(MenuLayout layout, MenuAppearance style, int card) =>
      Positioned.fill(
        child: CustomPaint(
          painter: _HighlightPainter(
            highlight: this,
            card: card,
            layout: layout,
            color: style.highlightColor,
          ),
        ),
      );

  /// Where the highlight of [card] shows in its content, with its corner
  /// radius, or null for none.
  RRect? rrectOf(int card, MenuLayout layout) {
    if (card >= _layer.built.layouts.length) return null;
    final index = lit(card);
    if (index == null || index >= layout.targets.length) return null;
    final target = layout.targets[index];
    final element = target.element < 0 ? null : layout.elements[target.element];
    final cell = switch (element?.kind) {
      MenuPlacedKind.palette ||
      MenuPlacedKind.small ||
      MenuPlacedKind.medium => true,
      _ => false,
    };
    const inset = MenuAppearance.highlightInset;
    final rect = cell
        ? target.rect
        : Rect.fromLTRB(
            target.rect.left + inset,
            target.rect.top,
            target.rect.right - inset,
            target.rect.bottom,
          );
    return RRect.fromRectAndRadius(
      rect,
      Radius.circular(
        cell
            ? MenuAppearance.cellHighlightRadius
            : math.min(rect.height / 2, _layer.motion.rowHeight / 2),
      ),
    );
  }
}

/// Paints the highlight of one card where the layer says it is now.
class _HighlightPainter extends CustomPainter {
  _HighlightPainter({
    required this.highlight,
    required this.card,
    required this.layout,
    required this.color,
  }) : super(
         repaint: Listenable.merge([highlight._layer.frames, highlight.zones]),
       );

  final MenuLayerHighlight highlight;
  final int card;
  final MenuLayout layout;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (!highlight._layer.mounted) return;
    final rrect = highlight.rrectOf(card, layout);
    if (rrect == null) return;
    final paint = Paint();
    paint.color = color;
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_HighlightPainter oldDelegate) =>
      !identical(oldDelegate.layout, layout) ||
      oldDelegate.card != card ||
      oldDelegate.color != color;
}
