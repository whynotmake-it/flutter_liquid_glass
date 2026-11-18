import 'dart:math' as math;

import 'package:meta/meta.dart';

/// How a floating tab bar on a phone sizes itself and its tabs, read from
/// UIKit (iOS 27; notes private) and checked against the bars of an iPhone
/// 16 Pro with 2 to 5 tabs and short, Russian and very long titles.
///
/// A bar of four or more tabs, or one that hosts a bottom accessory or a
/// search tab, spans what is available whatever its titles say, and its
/// tabs adapt inside it. A bar of two or three tabs is as wide as its widest
/// title asks. Height never depends on the titles.
///
/// At [phoneBelow] and wider UIKit changes to metrics this class does not
/// know, so a bar there keeps the width of a bar on an iPhone 16 Pro.
@immutable
final class TabBarLayout {
  const TabBarLayout._({required this.width, required this.buttons});

  /// Lays out tabs whose content is [naturals] wide in [available] points;
  /// [hosted] when the bar hosts an accessory or a search tab.
  factory TabBarLayout.of(
    List<double> naturals, {
    required double available,
    bool hosted = false,
  }) {
    final count = naturals.length;
    if (count == 0) return const TabBarLayout._(width: 0, buttons: []);
    final fills = count > 3 || hosted;
    var inset = count > 4 ? 15.0 : 24.0;
    final ideals = [
      for (final natural in naturals)
        math.max(minimumItem, natural + (fills ? 12 : 0)),
    ];
    final widest = ideals.reduce(math.max);
    final total = ideals.reduce((a, b) => a + b);
    final double width;
    if (fills) {
      width = available;
    } else {
      final asked =
          2 * inset +
          (count - 1) * sparseGap +
          count * math.max(minimumItem, naturals.reduce(math.max));
      width = math.min(available, asked);
    }
    final room = width - 2 * inset;
    final even = (room - (count - 1) * (fills ? 2 : sparseGap)) / count;
    final fitted = math.min(math.min(widest, room), even);
    List<double> uniform(double item) => List.filled(count, item);
    List<double> unequal() {
      final inner = width - 2 * inset;
      if (total >= inner) return ideals;
      return [for (final ideal in ideals) ideal * inner / total];
    }

    List<double> items;
    if (!fills) {
      items = uniform(fitted);
    } else if ((room - total) / (count - 1) < 14) {
      inset = math.min(inset, 14);
      items = unequal();
    } else if (widest <= minimumItem) {
      items = uniform(math.max(fitted, room / count - (inset - buttonInset)));
    } else {
      inset = math.min(inset, 18);
      items = widest <= even
          ? uniform(
              math.max(
                fitted,
                (width - 2 * inset) / count - (inset - buttonInset),
              ),
            )
          : unequal();
    }
    final inner = width - 2 * inset;
    items = _fit(items, inner);
    final used = items.reduce((a, b) => a + b);
    final gap = fills
        ? count == 1
              ? 0.0
              : (inner - used) / (count - 1)
        : sparseGap;
    final outset = inset - buttonInset;
    final buttons = <({double center, double width})>[];
    var left = inset;
    for (final item in items) {
      buttons.add((center: left + item / 2, width: item + 2 * outset));
      left += item + gap;
    }
    return TabBarLayout._(width: width, buttons: buttons);
  }

  // Tabs past the room give it back, the widest over the minimum first.
  static List<double> _fit(List<double> items, double room) {
    final fitted = List.of(items);
    var excess = fitted.reduce((a, b) => a + b) - room;
    while (excess > 1e-9) {
      final over = [
        for (final (i, item) in fitted.indexed)
          if (item > minimumItem) i,
      ];
      if (over.isEmpty) {
        final each = excess / fitted.length;
        return [for (final item in fitted) item - each];
      }
      final top = over.map((i) => fitted[i]).reduce(math.max);
      final widest = over.where((i) => fitted[i] >= top - 1e-9).toList();
      final next = over
          .map((i) => fitted[i])
          .where((item) => item < top - 1e-9)
          .fold(minimumItem, math.max);
      final take = math.min(top - next, excess / widest.length);
      for (final i in widest) {
        fitted[i] -= take;
      }
      excess -= take * widest.length;
    }
    return fitted;
  }

  /// The bar's height (tab bar passport, layout and device).
  static const double height = 62;

  /// The space between the screen's sides and bottom and the bar (tab bar
  /// passport, 402 point screen).
  static const double screenInset = 21;

  /// The width of a bar without a bound: an iPhone's 402 points, less
  /// [screenInset] at each side.
  static const double unboundWidth = 402 - 2 * screenInset;

  /// The bar width from which UIKit no longer uses a phone's metrics.
  static const double phoneBelow = 568;

  /// The least width of a tab's content: UIKit's minimum item dimension.
  static const double minimumItem = 54;

  /// The space between the tabs of a bar that does not fill its room.
  static const double sparseGap = 32;

  /// The space between a tab's button and the bar's edge.
  static const double buttonInset = 4;

  /// How much narrower than its button a title has to be: the button's
  /// rounded shape leaves it 21.72 points, read from UIKit.
  static const double titleMargin = 21.72;

  /// The bar's width.
  final double width;

  /// Each tab's button along the bar: UIKit's buttons, and the lens that
  /// rests on them, overlap their neighbours.
  final List<({double center, double width})> buttons;
}
