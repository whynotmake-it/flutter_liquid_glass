import 'package:flutter/painting.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:meta/meta.dart';

/// The outline of a glass body that no [LiquidShape] describes, such as a
/// popover and its arrow as one shape.
///
/// [path] is the body's edge in the coordinates of the box its surface
/// was laid out in: the flat renderer fills it and clips the content to
/// it. [field] is the body's signed distance field in the same
/// coordinates, from which the liquid renderer shades the body as one
/// glass, edge light and refraction included, when the surface has a
/// layer of its own; without a field and in a shared group the liquid
/// renderer draws the body flat.
///
/// The field is computed the first time a renderer reads it, so a
/// renderer that only fills the body never pays for it.
final class GlassOutline {
  /// Creates the outline whose edge is [path] and whose field, if any,
  /// [field] computes when first read.
  GlassOutline(this.path, {LiquidGlassField? Function()? field})
    : _fieldOf = field;

  /// The edge of the body.
  final Path path;

  final LiquidGlassField? Function()? _fieldOf;

  /// Whether the body has a [field] to shade it from.
  @internal
  bool get hasField => _fieldOf != null;

  /// The body's signed distance field, or null.
  late final LiquidGlassField? field = _fieldOf?.call();

  /// The box the body occupies.
  Rect get bounds => path.getBounds();
}
