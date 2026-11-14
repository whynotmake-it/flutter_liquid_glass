import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/src/liquid_shape.dart';

/// Clips its child using the given [shape].
///
/// Compared to using [ClipPath] directly, this widget uses Impeller's
/// specialized clip layers for ovals, rounded rects, and superellipses.
///
/// If [shape] is null or [clipBehavior] is [Clip.none], no clipping is applied.
@internal
class OptimizedClip extends StatelessWidget {
  const OptimizedClip({
    required this.shape,
    required this.child,
    this.clipBehavior = Clip.antiAlias,
    this.outset = 0,
    super.key,
  });

  final ShapeBorder? shape;

  final Clip clipBehavior;

  /// Extra room outside the widget bounds retained by the clip.
  final double outset;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (clipBehavior == Clip.none) {
      return child;
    }
    final shape = this.shape;
    if (shape != null && outset > 0) {
      return ClipPath(
        clipBehavior: clipBehavior,
        clipper: _OutsetShapeBorderClipper(shape: shape, outset: outset),
        child: child,
      );
    }
    return switch (shape) {
      null => child,
      LiquidRoundedSuperellipse(:final borderRadius) => ClipRSuperellipse(
        clipBehavior: clipBehavior,
        borderRadius: BorderRadius.circular(borderRadius),
        child: child,
      ),
      LiquidRoundedRectangle(:final borderRadius) => ClipRRect(
        clipBehavior: clipBehavior,
        borderRadius: BorderRadius.circular(borderRadius),
        child: child,
      ),
      LiquidOval() => ClipOval(
        clipBehavior: clipBehavior,
        child: child,
      ),
      RoundedSuperellipseBorder(:final borderRadius) => ClipRSuperellipse(
        clipBehavior: clipBehavior,
        borderRadius: borderRadius,
        child: child,
      ),
      RoundedRectangleBorder(:final borderRadius) => ClipRRect(
        clipBehavior: clipBehavior,
        borderRadius: borderRadius,
        child: child,
      ),
      OvalBorder() => ClipOval(
        clipBehavior: clipBehavior,
        child: child,
      ),
      LinearBorder() => ClipRect(
        clipBehavior: clipBehavior,
        child: child,
      ),
      _ => ClipPath(
        clipBehavior: clipBehavior,
        clipper: ShapeBorderClipper(
          shape: shape,
        ),
        child: child,
      ),
    };
  }
}

class _OutsetShapeBorderClipper extends CustomClipper<Path> {
  const _OutsetShapeBorderClipper({required this.shape, required this.outset});

  final ShapeBorder shape;
  final double outset;

  @override
  Path getClip(Size size) =>
      shape.getOuterPath((Offset.zero & size).inflate(outset));

  @override
  bool shouldReclip(covariant _OutsetShapeBorderClipper oldClipper) =>
      oldClipper.shape != shape || oldClipper.outset != outset;
}
