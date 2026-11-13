import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/src/composer/copy_tuning.dart';
import 'package:liquid_glass_renderer/src/composer/frame_report.dart';

/// A Gaussian blur followed by a color matrix: a backdrop filter that the
/// renderer draws from an unblurred copy at a fraction of the screen's
/// pixels, frosted by a shader as it is drawn, wherever a copy serves and
/// the frost is narrow enough for the shader; otherwise the copy is
/// filtered.
///
/// NEAR: the shader's taps over a smaller copy are not Impeller's blur (see
/// [GlassCopyTuning.shaderFrost]).
@immutable
final class LiquidGlassBackdropFrost {
  /// Creates the filter: a blur by [sigma] logical pixels along both axes,
  /// reading past the backdrop's edge as [tileMode] says, then
  /// [colorMatrix] as [ui.ColorFilter.matrix] takes it, or none.
  LiquidGlassBackdropFrost({
    required this.sigma,
    this.colorMatrix,
    this.tileMode,
  }) : assert(sigma > 0, 'A frost blurs.'),
       assert(colorMatrix == null || colorMatrix.length == 20, '5 x 4 values.');

  /// The blur's sigma, in logical pixels.
  final double sigma;

  /// The color matrix applied after the blur, row by row, as
  /// [ui.ColorFilter.matrix] takes it; null for none.
  final List<double>? colorMatrix;

  /// What the live blur reads past the backdrop's edge, as
  /// [ui.ImageFilter.blur] takes it. A copy is frosted inside the screen,
  /// where it reads its own edge.
  final ui.TileMode? tileMode;

  /// The same filter as a backdrop filter, for what reads the backdrop.
  late final ui.ImageFilter filter = _filter();

  ui.ImageFilter _filter() {
    if (!kReleaseMode) GlassWork.filters++;
    final blur = ui.ImageFilter.blur(
      sigmaX: sigma,
      sigmaY: sigma,
      tileMode: tileMode,
    );
    final matrix = colorMatrix;
    if (matrix == null) return blur;
    return ui.ImageFilter.compose(
      outer: ui.ColorFilter.matrix(matrix),
      inner: blur,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LiquidGlassBackdropFrost &&
      other.sigma == sigma &&
      other.tileMode == tileMode &&
      listEquals(other.colorMatrix, colorMatrix);

  @override
  int get hashCode => Object.hash(
    sigma,
    tileMode,
    colorMatrix == null ? null : Object.hashAll(colorMatrix!),
  );
}
