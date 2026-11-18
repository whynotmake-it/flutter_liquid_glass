import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_backdrop_filter.dart';
import 'package:liquid_glass_renderer/src/plan/copy_place.dart';
import 'package:meta/meta.dart';

/// How a scroll edge looks where it lies this frame, which glass over it
/// draws in its own filter.
@immutable
final class BandLook {
  /// Creates the look.
  const BandLook({
    required this.sigma,
    required this.band,
    required this.dissolve,
    required this.origin,
    required this.shown,
    required this.devicePixelRatio,
  });

  /// Its frost as drawn, in logical pixels.
  final double sigma;

  /// The band.
  final LiquidGlassFrostBand band;

  /// Where its frost dissolves, in the rows of its layer's coordinates.
  final FrostDissolve dissolve;

  /// Where its layer's coordinates begin on the screen.
  final Offset origin;

  /// What it covers on the screen.
  final Rect shown;

  /// The device pixels of its view per logical pixel.
  final double devicePixelRatio;

  @override
  bool operator ==(Object other) =>
      other is BandLook &&
      other.sigma == sigma &&
      other.band == band &&
      other.dissolve == dissolve &&
      other.origin == origin &&
      other.shown == shown &&
      other.devicePixelRatio == devicePixelRatio;

  @override
  int get hashCode =>
      Object.hash(sigma, band, dissolve, origin, shown, devicePixelRatio);
}

/// Where the frost of [band], drawn over [clip], dissolves into what lies
/// under it, in the rows of [clip]'s coordinates.
@internal
FrostDissolve frostDissolveOf(LiquidGlassFrostBand band, Rect clip) =>
    switch (band.fadeRows(clip)) {
      (:final whole, :final gone) => FrostDissolve(whole, gone),
      null => FrostDissolve.none,
    };
