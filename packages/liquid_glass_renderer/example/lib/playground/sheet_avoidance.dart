import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer_example/bottom_bar/listenable_transform.dart';

/// Tells the stage content below it how far the settings sheet currently
/// covers the stage, so [AvoidSheet] can move it out of the way.
class SheetAvoidance extends InheritedWidget {
  const SheetAvoidance({
    required this.position,
    required this.coverage,
    required super.child,
    super.key,
  });

  /// The sheet's position, from 0 when closed to 1 when fully open.
  final Animation<double> position;

  /// How much of each side of the stage the fully open sheet covers.
  final EdgeInsets coverage;

  static SheetAvoidance? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SheetAvoidance>();

  @override
  bool updateShouldNotify(SheetAvoidance oldWidget) =>
      position != oldWidget.position || coverage != oldWidget.coverage;
}

/// Keeps [child] at [alignment] within the part of the stage that the
/// settings sheet leaves free, following the sheet as it is dragged and
/// animated.
///
/// The child keeps its full-stage layout and is only translated at paint
/// time, so the sheet's motion neither rebuilds nor re-lays out the stage,
/// and glass inside moves as retained geometry. Content aligned to the
/// stage's top leading corner needs no wrapper, as the sheet never covers
/// it.
class AvoidSheet extends StatelessWidget {
  const AvoidSheet({
    required this.child,
    this.alignment = Alignment.center,
    this.retainChild = true,
    super.key,
  });

  final Alignment alignment;

  /// Whether the child keeps its painting while it moves.
  ///
  /// Turn this off for content that maps itself to the screen when it
  /// paints, like a loupe, which has to repaint to show what is under its
  /// new position.
  final bool retainChild;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final avoidance = SheetAvoidance.maybeOf(context);
    if (avoidance == null) return child;
    final SheetAvoidance(:position, :coverage) = avoidance;
    final shift = Offset(
      coverage.left * (1 - alignment.x) / 2 -
          coverage.right * (1 + alignment.x) / 2,
      coverage.top * (1 - alignment.y) / 2 -
          coverage.bottom * (1 + alignment.y) / 2,
    );
    return ListenableTransform(
      listenable: position,
      transform: (_) {
        final offset = shift * position.value;
        return Matrix4.translationValues(offset.dx, offset.dy, 0);
      },
      child: retainChild ? RepaintBoundary(child: child) : child,
    );
  }
}
