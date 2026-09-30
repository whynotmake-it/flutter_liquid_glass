import 'dart:math' as math;

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

  /// Center of the indicator in tab indices. Fractional while it moves, and
  /// slightly outside `0..tabCount - 1` while overdragged.
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

  /// How far the loupe reaches past the platter on every side.
  static const loupeOutset = 14.0;

  double get _pressAmount => math.max(press.value, 0);

  /// The indicator within a tab row of [size], before squash and stretch.
  Rect restingRect(Size size, {double? pressAmount}) {
    final slot = size.width / tabCount;
    final grow = 2 * loupeOutset * (pressAmount ?? _pressAmount);
    return Rect.fromCenter(
      center: Offset((position.value + .5) * slot, size.height / 2),
      width: slot + grow,
      height: size.height + grow,
    );
  }

  /// Squash along the motion and stretch across it, from
  /// `buildJellyTransform` in the original example bottom bar.
  ({double x, double y}) get jellyScale {
    // That bar measured velocity in alignment units, where -1 to 1 spans
    // the first to the last tab.
    final alignmentVelocity = jelly.value * 2 / math.max(tabCount - 1, 1);
    final distortion = (alignmentVelocity.abs() / 10).clamp(0.0, 1.0) * .8;
    return (x: 1 - distortion * .5, y: 1 + distortion * .3);
  }

  /// The indicator within a tab row of [size].
  Rect rect(Size size) {
    final rect = restingRect(size);
    final (:x, :y) = jellyScale;
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
  TabPlatterPainter(this.selection, {required this.color})
    : super(repaint: selection.listenable);

  final TabSelection selection;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final opacity = (1 - selection.press.value).clamp(0.0, 1.0);
    if (opacity == 0) return;
    canvas.drawRRect(
      selection.rrect(size),
      Paint()..color = color.withValues(alpha: color.a * opacity),
    );
  }

  @override
  bool shouldRepaint(TabPlatterPainter oldDelegate) =>
      oldDelegate.selection != selection || oldDelegate.color != color;
}

/// Places the loupe over the indicator of a tab row inset by [padding].
///
/// Relayouts on every move without rebuilding; the child's constraints only
/// change while the loupe grows or shrinks.
class LoupeLayoutDelegate extends SingleChildLayoutDelegate {
  LoupeLayoutDelegate(this.selection, {required this.padding})
    : super(relayout: selection.listenable);

  final TabSelection selection;
  final double padding;

  Rect _rect(Size size) => selection
      .restingRect(Size(size.width - 2 * padding, size.height - 2 * padding))
      .shift(Offset(padding, padding));

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.tight(_rect(constraints.biggest).size);

  @override
  Offset getPositionForChild(Size size, Size childSize) => _rect(size).topLeft;

  @override
  bool shouldRelayout(LoupeLayoutDelegate oldDelegate) =>
      oldDelegate.selection != selection || oldDelegate.padding != padding;
}
