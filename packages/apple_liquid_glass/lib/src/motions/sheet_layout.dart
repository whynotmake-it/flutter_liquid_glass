import 'dart:math' as math;

import 'package:apple_liquid_glass/src/motions/sheet_detent.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// What a sheet's host tells its law (`SheetMotion.layout`): the room the
/// sheet has and the detents it rests at.
@immutable
final class SheetLayout {
  /// Creates a layout.
  const SheetLayout({
    required this.size,
    required this.detents,
    required this.selected,
    this.padding = EdgeInsets.zero,
    this.keyboard = 0,
    this.fittedHeight,
    this.largestUndimmed,
  });

  /// The container the sheet is laid out in, in pixels.
  final Size size;

  /// The safe area of the container; only its top and bottom count.
  final EdgeInsets padding;

  /// The height of the keyboard over the container's bottom, 0 without
  /// one.
  final double keyboard;

  /// The height of the content a [GlassSheetDetent.fitted] detent follows,
  /// null until the content has laid out.
  final double? fittedHeight;

  /// The sheet's detents, in the app's order.
  final List<GlassSheetDetent> detents;

  /// The detent the app's sheet rests at: the sheet's first layout rests
  /// there, and the sheet returns there when a keyboard hides.
  final GlassSheetDetent selected;

  /// The largest detent that leaves the page undimmed, or null when every
  /// detent dims.
  final GlassSheetDetent? largestUndimmed;

  /// The largest detent value: the container less its top and bottom safe
  /// areas.
  double get maximum =>
      math.max<double>(0, size.height - padding.top - padding.bottom);

  /// The height of a sheet at [maximum], bottom safe area included.
  double get fullHeight => maximum + padding.bottom;

  /// A copy with the given fields replaced.
  SheetLayout copyWith({double? keyboard, GlassSheetDetent? selected}) =>
      SheetLayout(
        size: size,
        padding: padding,
        keyboard: keyboard ?? this.keyboard,
        fittedHeight: fittedHeight,
        detents: detents,
        selected: selected ?? this.selected,
        largestUndimmed: largestUndimmed,
      );

  /// The detents resolved for this layout: their heights in pixels,
  /// ascending, bottom safe area included, each raised by the keyboard up
  /// to the maximum (as UIKit's, simulator capture); `order` maps each
  /// height to its detent's position in [detents].
  ({List<double> heights, List<int> order, int? docked, int? undimmed})
  resolve() {
    final values = [
      for (final d in detents)
        math.min(
              d.resolve(maximum, fittedHeight: fittedHeight) + keyboard,
              maximum,
            ) +
            padding.bottom,
    ];
    final order = List<int>.generate(detents.length, (i) => i);
    order.sort((a, b) => values[a].compareTo(values[b]));
    final docked = order.indexWhere((i) => detents[i].isLarge);
    final undimmed = largestUndimmed;
    final undimmedAt = undimmed == null
        ? -1
        : order.indexWhere((i) => detents[i] == undimmed);
    return (
      heights: [for (final i in order) values[i]],
      order: order,
      docked: docked < 0 ? null : docked,
      undimmed: undimmedAt < 0 ? null : undimmedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SheetLayout &&
      other.size == size &&
      other.padding == padding &&
      other.keyboard == keyboard &&
      other.fittedHeight == fittedHeight &&
      listEquals(other.detents, detents) &&
      other.selected == selected &&
      other.largestUndimmed == largestUndimmed;

  @override
  int get hashCode => Object.hash(
    size,
    padding,
    keyboard,
    fittedHeight,
    Object.hashAll(detents),
    selected,
    largestUndimmed,
  );
}
