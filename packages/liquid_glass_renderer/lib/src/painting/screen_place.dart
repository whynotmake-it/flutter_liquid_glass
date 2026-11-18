import 'dart:ui';

import 'package:meta/meta.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4;

/// How a site's coordinates lie on the screen: shifted, scaled along the
/// axes, or turned.
@internal
@immutable
sealed class ScreenPlace {
  const ScreenPlace();

  /// The place [toScreen] puts its coordinates in.
  factory ScreenPlace.of(Matrix4 toScreen) {
    final m = toScreen.storage;
    bool near(double value, double to) => (value - to).abs() <= tolerance;
    if (m[0] <= 0 ||
        m[5] <= 0 ||
        !near(m[1], 0) ||
        !near(m[4], 0) ||
        !near(m[3], 0) ||
        !near(m[7], 0) ||
        !near(m[15], 1)) {
      return const Turned();
    }
    if (near(m[0], 1) && near(m[5], 1)) return Shifted(Offset(m[12], m[13]));
    return Scaled(m[0], m[5]);
  }

  /// How far an entry may lie from its value and still count as it.
  static const double tolerance = 1e-6;
}

/// Coordinates moved by [offset] and nothing else.
@internal
final class Shifted extends ScreenPlace {
  /// Coordinates moved by [offset].
  const Shifted(this.offset);

  /// The shift, in logical pixels.
  final Offset offset;

  @override
  bool operator ==(Object other) => other is Shifted && other.offset == offset;

  @override
  int get hashCode => offset.hashCode;
}

/// Coordinates scaled by [x] and [y] along the axes, then moved.
@internal
final class Scaled extends ScreenPlace {
  /// Coordinates scaled by [x] and [y], then moved.
  const Scaled(this.x, this.y);

  /// The scales along the axes, both positive.
  final double x;
  final double y;

  @override
  bool operator ==(Object other) =>
      other is Scaled && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}

/// Coordinates flipped, rotated, skewed or seen in perspective.
@internal
final class Turned extends ScreenPlace {
  /// Turned coordinates.
  const Turned();

  @override
  bool operator ==(Object other) => other is Turned;

  @override
  int get hashCode => (Turned).hashCode;
}
