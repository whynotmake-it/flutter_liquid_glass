import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Clips its child using the given [shape].
///
/// Compared to using [ClipPath] directly, this widget optimizes for
/// performance by using more efficient clipping methods when possible.
///
/// If [shape] is null, no clipping is applied.
@internal
class OptimizedClip extends StatelessWidget {
  const OptimizedClip({
    required this.shape,
    required this.child,
    this.clipBehavior = Clip.antiAlias,
    super.key,
  });

  final ShapeBorder? shape;

  final Clip clipBehavior;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shape = this.shape;
    return switch (shape) {
      null => child,
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
        )
    };
  }
}
