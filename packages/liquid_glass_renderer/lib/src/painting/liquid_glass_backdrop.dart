import 'dart:ui';

import 'package:meta/meta.dart' show immutable;

/// Where the glass of a `LiquidGlassLayer` takes what it shows through.
///
/// A layer reads what is painted behind it ([LiquidGlassBackdrop.read], the
/// default). When the caller knows the backdrop is one opaque color, the
/// layer can skip reading it ([LiquidGlassBackdrop.solid]).
@immutable
sealed class LiquidGlassBackdrop {
  const LiquidGlassBackdrop._();

  /// The layer reads what is painted behind it with a backdrop filter.
  const factory LiquidGlassBackdrop.read() = LiquidGlassReadBackdrop._;

  /// The opaque [color] behind every shape of the layer: a list card, a
  /// sheet's surface.
  ///
  /// The layer then draws its glass as a paint shaded over [color] instead
  /// of a backdrop filter: no backdrop capture and no blur pass. A
  /// translucent [color] reads the backdrop instead. Anything painted between
  /// the color and the glass is not seen through it.
  ///
  /// Fake glass always reads what is behind it: a layer that draws fake
  /// glass, by `LiquidGlassLayer.fake` or where full glass does not draw,
  /// reads the backdrop whatever this says.
  const factory LiquidGlassBackdrop.solid(Color color) =
      LiquidGlassSolidBackdrop._;
}

/// The [LiquidGlassBackdrop] of a layer that reads what is painted behind it
/// ([LiquidGlassBackdrop.read]).
final class LiquidGlassReadBackdrop extends LiquidGlassBackdrop {
  const LiquidGlassReadBackdrop._() : super._();

  @override
  bool operator ==(Object other) => other is LiquidGlassReadBackdrop;

  @override
  int get hashCode => (LiquidGlassReadBackdrop).hashCode;

  @override
  String toString() => 'LiquidGlassBackdrop.read()';
}

/// The [LiquidGlassBackdrop] of a layer over one opaque color
/// ([LiquidGlassBackdrop.solid]).
final class LiquidGlassSolidBackdrop extends LiquidGlassBackdrop {
  const LiquidGlassSolidBackdrop._(this.color) : super._();

  /// The color behind every shape of the layer.
  final Color color;

  @override
  bool operator ==(Object other) =>
      other is LiquidGlassSolidBackdrop && other.color == color;

  @override
  int get hashCode => color.hashCode;

  @override
  String toString() => 'LiquidGlassBackdrop.solid($color)';
}
