import 'dart:ui';

import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:meta/meta.dart';

/// Where the glass of a [LiquidGlassLayer] takes what it shows through.
///
/// A layer reads what is painted behind it ([LiquidGlassBackdrop.read], the
/// default). When the caller knows more about that backdrop, the layer can
/// skip reading it: [LiquidGlassBackdrop.solid] for one opaque color,
/// [LiquidGlassBackdrop.cached] for a kept copy of a page that holds still.
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

  /// A copy of what lies under the layer's glass, kept by [cache]: for glass
  /// over a page that holds still, such as a sheet's or an alert's over the
  /// route below.
  ///
  /// While the copy is exact the layer paints its glass over it instead of
  /// reading the backdrop; any other frame reads the backdrop. See
  /// [LiquidGlassBackdropCache].
  const factory LiquidGlassBackdrop.cached(LiquidGlassBackdropCache cache) =
      _CachedBackdrop;
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

final class _CachedBackdrop extends LiquidGlassBackdrop {
  const _CachedBackdrop(this.cache) : super._();

  final LiquidGlassBackdropCache cache;

  @override
  bool operator ==(Object other) =>
      other is _CachedBackdrop && identical(other.cache, cache);

  @override
  int get hashCode => identityHashCode(cache);
}

/// The color of a [LiquidGlassBackdrop.solid], or null for any other backdrop.
@internal
Color? solidColorOf(LiquidGlassBackdrop backdrop) => switch (backdrop) {
  _SolidBackdrop(:final color) => color,
  _ReadBackdrop() || _CachedBackdrop() => null,
};

/// The cache of a [LiquidGlassBackdrop.cached], or null for any other backdrop.
@internal
LiquidGlassBackdropCache? backdropCacheOf(LiquidGlassBackdrop backdrop) =>
    switch (backdrop) {
      _CachedBackdrop(:final cache) => cache,
      _ReadBackdrop() || _SolidBackdrop() => null,
    };
