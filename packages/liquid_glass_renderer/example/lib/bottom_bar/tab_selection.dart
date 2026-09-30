import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:motor/motor.dart';

/// Where the selection indicator of a tab bar is and how far it has turned
/// from the resting platter into the loupe.
///
/// Everything that follows the indicator (the platter, the tint mask, the
/// tint's shrink compensation and the loupe itself) reads these controllers
/// at paint or layout time through [listenable], so moving the indicator
/// never rebuilds a widget.
class TabSelection {
  TabSelection({
    required this.position,
    required this.press,
    required this.jelly,
    required this.tabCount,
    required this.backdropShrink,
  });

  /// Center of the indicator in tab indices, fractional while it moves.
  final SingleMotionController position;

  /// `0` for the resting platter, `1` for the loupe. Also the loupe's glass
  /// visibility.
  final SingleMotionController press;

  /// Smoothed indicator velocity in tabs per second, for squash and stretch.
  final SingleMotionController jelly;

  int tabCount;

  /// The loupe's `LiquidGlassSettings.backdropShrink`.
  double backdropShrink;

  late final Listenable listenable = Listenable.merge([position, press, jelly]);

  /// How far the resting platter reaches past its slot on each side: the
  /// iOS 27 platter is 77 pt wide over 68.7 pt slots.
  static const platterOutset = 4.15;

  /// How far the loupe reaches past the platter on each side: a 97 × 73 pt
  /// loupe over the 77 × 54 pt platter of iOS 27.
  static const loupeOutset = Size(10, 9.5);

  /// Room between the tab row and the bar's ends, which the loupe may use
  /// but never cross.
  double sidePadding = 0;

  double get _pressAmount => math.max(press.value, 0);

  /// The indicator within a tab row of [size], before squash and stretch.
  ///
  /// The platter is centered on its tab, inside the bar's padding. The loupe
  /// is centered on it too but, like Apple's, never crosses the bar's ends,
  /// so at the end tabs it sits flush with them.
  Rect restingRect(Size size, {double? pressAmount}) {
    final amount = pressAmount ?? _pressAmount;
    final slot = size.width / tabCount;
    final grow = loupeOutset * 2 * amount;
    final width = math.min(
      slot + 2 * platterOutset + grow.width,
      size.width + 2 * sidePadding,
    );
    final center = ((position.value + .5) * slot).clamp(
      width / 2 - sidePadding,
      size.width + sidePadding - width / 2,
    );
    return Rect.fromCenter(
      center: Offset(center, size.height / 2),
      width: width,
      height: size.height + grow.height,
    );
  }

  /// Indicator speed in points per second at which [jellyScale] is halfway
  /// to its strongest.
  static const _jellySpeed = 300.0;

  /// Squash across the motion, fitted to fast drags on iOS 27: at 270, 540
  /// and 1100 pt/s the loupe keeps about 0.95 of its width and 0.75, 0.67
  /// and 0.6 of its height, so it reads as stretched along the motion. For
  /// tabs [slot] points wide.
  ({double x, double y}) jellyScale(double slot) {
    final speed = jelly.value.abs() * slot;
    final amount = speed / (speed + _jellySpeed);
    return (x: 1 - .1 * amount, y: 1 - .51 * amount);
  }

  /// The indicator within a tab row of [size].
  Rect rect(Size size) {
    final rect = restingRect(size);
    final (:x, :y) = jellyScale(size.width / tabCount);
    return Rect.fromCenter(
      center: rect.center,
      width: rect.width * x,
      height: rect.height * y,
    );
  }

  RRect rrect(Size size) {
    final rect = this.rect(size);
    return RRect.fromRectAndRadius(
      rect,
      Radius.circular(rect.shortestSide / 2),
    );
  }

  /// Scale about the loupe center that the loupe's shrunk backdrop undoes,
  /// so the tinted icons under it keep the size of the others.
  ///
  /// The glass samples the backdrop at `1 + (1 / (1 - shrink) - 1) * v`
  /// times the distance from its center at visibility `v`.
  double get tintScale {
    final shrink = backdropShrink.clamp(0.0, .75);
    final visibility = press.value.clamp(0.0, 1.0);
    return 1 + (1 / (1 - shrink) - 1) * visibility;
  }
}

/// Clips to the indicator, or with [inverse] to everything outside it.
///
/// A tab row is painted twice: once in the label color clipped outside the
/// indicator and once in the tint clipped inside it, so the tint follows the
/// indicator's edge instead of switching per icon.
class TabSelectionClipper extends CustomClipper<Path> {
  TabSelectionClipper(this.selection, {this.inverse = false})
    : super(reclip: selection.listenable);

  final TabSelection selection;
  final bool inverse;

  /// Room for content that the bar's own scale pushes past the row.
  static const _overflow = 24.0;

  @override
  Path getClip(Size size) {
    final path = Path()..addRRect(selection.rrect(size));
    if (!inverse) return path;
    return path
      ..addRect((Offset.zero & size).inflate(_overflow))
      ..fillType = PathFillType.evenOdd;
  }

  @override
  Rect getApproximateClipRect(Size size) =>
      inverse ? (Offset.zero & size).inflate(_overflow) : selection.rect(size);

  @override
  bool shouldReclip(TabSelectionClipper oldClipper) =>
      oldClipper.selection != selection || oldClipper.inverse != inverse;
}

/// The resting selection platter. It fades out as the loupe takes over.
class TabPlatterPainter extends CustomPainter {
  TabPlatterPainter(this.selection, {required this.layers})
    : super(repaint: selection.listenable);

  final TabSelection selection;

  /// Colors painted over the glass one after the other, each with its blend
  /// mode.
  final List<(Color, BlendMode)> layers;

  @override
  void paint(Canvas canvas, Size size) {
    final opacity = (1 - selection.press.value).clamp(0.0, 1.0);
    if (opacity == 0) return;
    final rrect = selection.rrect(size);
    for (final (color, blendMode) in layers) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = color.withValues(alpha: color.a * opacity)
          ..blendMode = blendMode,
      );
    }
  }

  @override
  bool shouldRepaint(TabPlatterPainter oldDelegate) =>
      oldDelegate.selection != selection ||
      !listEquals(oldDelegate.layers, layers);
}

/// Places the loupe over the indicator of a tab row inset by [padding].
///
/// Relayouts on every move without rebuilding; the child's constraints only
/// change while the loupe grows or shrinks.
class LoupeLayoutDelegate extends SingleChildLayoutDelegate {
  LoupeLayoutDelegate(this.selection, {required this.padding})
    : super(relayout: selection.listenable);

  final TabSelection selection;
  final EdgeInsets padding;

  Rect _rect(Size size) =>
      selection.restingRect(padding.deflateSize(size)).shift(padding.topLeft);

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.tight(_rect(constraints.biggest).size);

  @override
  Offset getPositionForChild(Size size, Size childSize) => _rect(size).topLeft;

  @override
  bool shouldRelayout(LoupeLayoutDelegate oldDelegate) =>
      oldDelegate.selection != selection || oldDelegate.padding != padding;
}
