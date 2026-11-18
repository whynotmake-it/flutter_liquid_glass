import 'dart:ui' show Offset, lerpDouble;

import 'package:flutter/foundation.dart';

/// How a view enters or leaves: properties that run linearly with one
/// progress from 0 (absent) to 1 (present). Removal plays it backwards.
///
/// UIKit: the from-state of an insertion animation. SwiftUI:
/// `AnyTransition`. Flutter: an `AnimatedSwitcher` transition.
@immutable
final class MotionEffect {
  /// Creates an effect; each pair is (absent, present).
  const MotionEffect({
    this.opacity,
    this.scale,
    this.blur,
    this.offset,
    this._reduced,
  });

  /// No change: the view is present from the start.
  static const MotionEffect identity = MotionEffect();

  /// A fade from transparent.
  static const MotionEffect fade = MotionEffect(opacity: (0, 1));

  /// The opacity at progress 0 and 1, or null to leave it at 1.
  final (double, double)? opacity;

  /// The scale at progress 0 and 1, or null to leave it at 1.
  final (double, double)? scale;

  /// The blur sigma at progress 0 and 1, or null for none.
  final (double, double)? blur;

  /// The offset at progress 0, falling linearly to zero at 1.
  final Offset? offset;

  final MotionEffect? _reduced;

  /// The effect under Reduce Motion: this one's opacity alone unless
  /// given.
  MotionEffect get reduced => _reduced ?? MotionEffect(opacity: opacity);

  /// The opacity at [progress].
  double opacityAt(double progress) => _at(opacity, progress, 1);

  /// The scale at [progress].
  double scaleAt(double progress) => _at(scale, progress, 1);

  /// The blur sigma at [progress].
  double blurAt(double progress) => _at(blur, progress, 0);

  /// The offset at [progress].
  Offset offsetAt(double progress) =>
      (offset ?? Offset.zero) * (1 - progress.clamp(0.0, 1.0));

  static double _at((double, double)? pair, double progress, double rest) {
    if (pair == null) return rest;
    return lerpDouble(pair.$1, pair.$2, progress.clamp(0.0, 1.0))!;
  }

  @override
  bool operator ==(Object other) =>
      other is MotionEffect &&
      other.opacity == opacity &&
      other.scale == scale &&
      other.blur == blur &&
      other.offset == offset &&
      other._reduced == _reduced;

  @override
  int get hashCode => Object.hash(opacity, scale, blur, offset, _reduced);
}
