import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:motor/motor.dart';

/// Where the selection indicator of a tab bar is and how far it has turned
/// from the resting platter into the loupe.
///
/// Everything that follows the indicator (the platter, the tint mask, the
/// icon scale and the loupe itself) reads these two controllers at paint
/// time through [listenable], so moving the indicator never rebuilds or
/// re-lays out a widget.
class TabSelection {
  TabSelection({
    required this.position,
    required this.press,
    required this.tabCount,
  });

  /// Center of the indicator in tab indices. Fractional while it moves, and
  /// slightly outside `0..tabCount - 1` while overdragged.
  final SingleMotionController position;

  /// `0` for the resting platter, `1` for the loupe.
  final SingleMotionController press;

  int tabCount;

  late final Listenable listenable = Listenable.merge([position, press]);

  /// How far the loupe reaches past the platter on each side.
  static const loupeOutset = Size(12, 10);

  /// Scale every icon gains while the bar is held. Icons under the loupe
  /// get no extra enlargement: the loupe itself shrinks what it covers.
  static const pressScale = .1;

  /// Horizontal speed, in logical pixels per second, at which the indicator
  /// stretches the most.
  static const _jellySpeed = 2400.0;
  static const _jellyStretch = .18;

  double get _pressAmount => math.max(press.value, 0);

  /// The indicator within a tab row of [size], before jelly.
  Rect restingRect(Size size, {double? pressAmount}) {
    final slot = size.width / tabCount;
    final p = pressAmount ?? _pressAmount;
    return Rect.fromCenter(
      center: Offset((position.value + .5) * slot, size.height / 2),
      width: slot + 2 * loupeOutset.width * p,
      height: size.height + 2 * loupeOutset.height * p,
    );
  }

  /// The indicator within a tab row of [size], stretched along its motion.
  Rect rect(Size size) {
    final rect = restingRect(size);
    final jelly = _jelly(size);
    if (jelly == 0) return rect;
    return Rect.fromCenter(
      center: rect.center,
      width: rect.width * (1 + jelly),
      height: rect.height * (1 - jelly / 2),
    );
  }

  RRect rrect(Size size) {
    final rect = this.rect(size);
    return RRect.fromRectAndRadius(
      rect,
      Radius.circular(rect.shortestSide / 2),
    );
  }

  double _jelly(Size size) {
    if (!position.isAnimating) return 0;
    final slot = size.width / tabCount;
    final speed = (position.velocity * slot).abs();
    final p = _pressAmount.clamp(0.0, 1.0);
    return (speed / _jellySpeed).clamp(0.0, 1.0) * _jellyStretch * p;
  }

  /// Scale of each tab's icon and label.
  double get iconScale => 1 + _pressAmount * pressScale;
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

  /// Room for scaled icons that grow past the row.
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

/// Lays tabs out in equal slots and scales each one about its center at
/// paint time.
class TabRowDelegate extends FlowDelegate {
  TabRowDelegate(this.selection) : super(repaint: selection.listenable);

  final TabSelection selection;

  @override
  Size getSize(BoxConstraints constraints) => constraints.biggest;

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) =>
      BoxConstraints.tight(
        Size(constraints.maxWidth / selection.tabCount, constraints.maxHeight),
      );

  @override
  void paintChildren(FlowPaintingContext context) {
    final slot = context.size.width / context.childCount;
    final center = context.size.height / 2;
    final scale = selection.iconScale;
    for (var i = 0; i < context.childCount; i++) {
      final x = slot * i;
      if (scale == 1) {
        context.paintChild(i, transform: Matrix4.translationValues(x, 0, 0));
        continue;
      }
      final cx = x + slot / 2;
      context.paintChild(
        i,
        transform: Matrix4.translationValues(cx, center, 0)
          ..scaleByDouble(scale, scale, 1, 1)
          ..translateByDouble(-slot / 2, -center, 0, 1),
      );
    }
  }

  @override
  bool shouldRelayout(TabRowDelegate oldDelegate) =>
      oldDelegate.selection != selection;

  @override
  bool shouldRepaint(TabRowDelegate oldDelegate) =>
      oldDelegate.selection != selection;
}
