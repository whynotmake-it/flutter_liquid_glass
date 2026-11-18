import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// One way a glass shape moves what is drawn over it away from its rim:
/// by [amount] at the rim, falling along a quarter circle to nothing
/// [height] deep, as a lifted iOS lens does with what it selects.
@immutable
final class LiquidGlassContentBend {
  /// A bend of [amount] at the rim that reaches [height] deep, both in
  /// logical pixels.
  const LiquidGlassContentBend({required this.amount, required this.height});

  /// How far from its place the rim shows the content, in logical pixels.
  final double amount;

  /// How deep from the rim the bend reaches, in logical pixels.
  final double height;

  /// How deep from the rim lies what shows [depth] from it.
  double shownDepth(double depth) {
    if (depth < 0 || depth >= height) return depth;
    final x = 1 - depth / height;
    return depth + amount * (1 - math.sqrt(1 - x * x));
  }

  @override
  bool operator ==(Object other) =>
      other is LiquidGlassContentBend &&
      other.amount == amount &&
      other.height == height;

  @override
  int get hashCode => Object.hash(amount, height);
}
