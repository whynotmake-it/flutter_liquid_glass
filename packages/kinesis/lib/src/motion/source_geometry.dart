import 'package:flutter/painting.dart';
import 'package:kinesis/src/motion/motion.dart';
import 'package:meta/meta.dart';

/// Where a presentation grows from, in global coordinates.
@immutable
final class SourceGeometry {
  /// Creates the geometry of a source at [rect] with [radius].
  const SourceGeometry({required this.rect, this.radius = BorderRadius.zero});

  /// The source's bounds, in global coordinates.
  final Rect rect;

  /// The source's corners.
  final BorderRadius radius;

  @override
  bool operator ==(Object other) =>
      other is SourceGeometry && other.rect == rect && other.radius == radius;

  @override
  int get hashCode => Object.hash(rect, radius);
}

/// A motion that grows out of a source and back into it: the shell tells
/// it where the source is when it commits and in every frame's resolve
/// phase after that, before paint.
mixin Sourced on Motion {
  /// The source is at [geometry] at time [t]; null once nothing shows it
  /// (its widget went away), and the motion decides how to end without it.
  void sourceMoved(double t, SourceGeometry? geometry);
}
