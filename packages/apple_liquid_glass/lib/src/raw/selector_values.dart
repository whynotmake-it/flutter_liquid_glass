import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/src/raw/selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';

/// What turns a tab bar selector into a circle and back: the same bar
/// throughout, its glass and content following [morph], whatever asks for
/// it (a scroll, a search).
abstract interface class GlassSelectorCollapse {
  /// The way from the bar (0) to the circle (1); a spring may overshoot both.
  MotionSelection<double> get morph;

  /// How far a finger has lifted the circle, 0 to 1, or null if it never
  /// does.
  MotionSelection<double>? get press;

  /// The circle in the bar's box of [size].
  Rect circleIn(Size size);

  /// Whether a finger on the bar now means the circle, not a tab.
  bool get takesFinger;

  /// A finger went down on the circle at [x] along the bar, at time [t].
  void pressDown(double t, double x);

  /// The finger moved to [x]; true on the move that hands it to the bar's
  /// selection drag.
  bool pressMove(double t, double x);

  /// The finger lifted without having moved along the bar.
  void pressUp(double t);

  /// The touch was taken away.
  void pressCancel(double t);

  /// A key or a screen reader activated the circle.
  void activate();
}

/// Builds the item at [index] of a [RawGlassSelector] for [states]: the
/// item's own states, which include [WidgetState.selected] for the selected
/// item, [WidgetState.disabled] for an item that cannot be selected, and
/// the pressed, hovered and focused states of the item's own target: a
/// touch presses the item it lands on until the finger moves and the lens
/// takes it.
///
/// Every item is built twice: without [WidgetState.selected] for the row
/// under the lens, and with it for the copy the lens shows wherever it is,
/// as UIKit masks a selected copy of every tab by the lens.
typedef GlassSelectorItemBuilder = Widget Function(
  BuildContext context,
  int index,
  Set<WidgetState> states,
);

/// Builds a glass selector from [details]; it runs again when the
/// selector's states, selection or items change, never while the lens
/// moves.
typedef GlassSelectorBuilder = Widget Function(
  BuildContext context,
  GlassSelectorDetails details,
);

/// What a [GlassSelectorBuilder] builds a selector from.
@immutable
final class GlassSelectorDetails {
  /// Describes a selector.
  const GlassSelectorDetails({
    required this.body,
    required this.lens,
    required this._items,
    required this.selectedIndex,
    required this.states,
    @internal this.lensContent,
  });

  /// The frames of the track or bar, which fills the selector: the glow a
  /// finger raises on a tab bar.
  final MotionSelection<GlassFrame> body;

  /// The frames of the lens in the selector's box: where it sits, how it
  /// stretches, and how far a finger has lifted it into glass.
  final MotionSelection<GlassFrame> lens;

  final Widget Function(Widget? lens) _items;

  /// The items laid out in their slots, with [lens] filling the selector
  /// over their regular look. Their selected look shows only inside the
  /// lens and over it, as in UIKit: a lifted lens bends it at its rim the
  /// way its renderer shows content ([GlassLensContent]), and its glass
  /// bends the items around it. The builder places this once, over the
  /// body: it gives the selector its size.
  Widget items({Widget? lens}) => _items(lens);

  /// The selected item, or null when none is and the lens is hidden.
  final int? selectedIndex;

  /// The states the selector is in.
  final Set<WidgetState> states;

  /// Where the renderer of the lens given to [items] reports how its lens
  /// shows the selected copies the selector draws over it.
  @internal
  final ValueNotifier<GlassLensContent?>? lensContent;
}
