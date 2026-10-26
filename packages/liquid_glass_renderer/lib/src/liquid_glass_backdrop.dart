import 'dart:ui';

import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:meta/meta.dart';

/// Where the glass of a [LiquidGlassLayer] takes what it shows through.
///
/// A layer reads what is painted behind it ([LiquidGlassBackdrop.read], the
/// default). When the caller knows more about that backdrop, the layer can
/// skip reading it: [LiquidGlassBackdrop.solid] for one opaque color.
@immutable
sealed class LiquidGlassBackdrop {
  const LiquidGlassBackdrop._();

  /// The layer reads what is painted behind it with a backdrop filter.
  const factory LiquidGlassBackdrop.read() = _ReadBackdrop;

  /// The opaque [color] behind every shape of the layer: a list card, a
  /// sheet's surface.
  ///
  /// The layer then draws its glass as a paint shaded over [color] instead
  /// of a backdrop filter: no backdrop capture and no blur pass. A
  /// translucent [color] reads the backdrop instead. Anything painted between
  /// the color and the glass is not seen through it.
  const factory LiquidGlassBackdrop.solid(Color color) = _SolidBackdrop;
}

final class _ReadBackdrop extends LiquidGlassBackdrop {
  const _ReadBackdrop() : super._();
}

final class _SolidBackdrop extends LiquidGlassBackdrop {
  const _SolidBackdrop(this.color) : super._();

  final Color color;

  @override
  bool operator ==(Object other) =>
      other is _SolidBackdrop && other.color == color;

  @override
  int get hashCode => color.hashCode;
}

/// The color of a [LiquidGlassBackdrop.solid], or null for any other backdrop.
@internal
Color? solidColorOf(LiquidGlassBackdrop backdrop) => switch (backdrop) {
  _SolidBackdrop(:final color) => color,
  _ReadBackdrop() => null,
};
