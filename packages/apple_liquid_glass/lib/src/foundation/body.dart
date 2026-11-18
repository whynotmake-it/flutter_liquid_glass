import 'package:apple_liquid_glass/src/foundation/frame.dart';
import 'package:apple_liquid_glass/src/foundation/outline.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/painting.dart';

/// Where a frame draws its body in the box its surface was laid out in, as
/// live glass draws it ([LiquidGlassBody]), and the shape it draws there.
///
/// What is drawn on the body (its fill, rim, ring, clip and glow) is drawn
/// in the body's own coordinates under [toBox] ([paintIn]).
@immutable
final class GlassBody extends LiquidGlassBody {
  /// The body [frame] draws in a box of [box].
  factory GlassBody.of(GlassFrame frame, Size box) => GlassBody._(
    box,
    rect: frame.bodyRect,
    scaleX: frame.scaleX,
    scaleY: frame.scaleY,
    shape: frame.shape,
    outline: frame.outline,
  );

  const GlassBody._(
    super.box, {
    required super.rect,
    required super.scaleX,
    required super.scaleY,
    required this.shape,
    required this.outline,
  });

  /// The body's shape.
  final LiquidShape shape;

  /// The body's own edge, in the box's coordinates, or null to draw
  /// [shape].
  final GlassOutline? outline;

  /// The radius of the body's corners in its own coordinates, its top
  /// corners' where the bottom ones differ ([glassCornerRadii]).
  double get radius => glassCornerRadii(shape, bounds.size).top;

  /// The radius of the body's corners as seen in the box: [radius] scaled
  /// with the body, by the lesser of its scales where they differ.
  double get drawnRadius => radius * (scaleX < scaleY ? scaleX : scaleY).abs();

  /// The body's edge in its own coordinates.
  Path get edge => switch (outline) {
    final outline? => outline.path.shift(-rect.topLeft),
    null => shape.getOuterPath(bounds),
  };

  /// What the body fills and casts its shadows by, in its own coordinates.
  LiquidGlassSilhouette get silhouette => outline == null
      ? LiquidGlassSilhouette.shape(shape, bounds)
      : LiquidGlassSilhouette.path(edge);

  /// The body's edge as drawn in the box.
  Path get edgeInBox {
    if (outline case final outline?) return outline.path;
    final toBox = this.toBox;
    return toBox == null ? edge : edge.transform(toBox.storage);
  }

  /// Runs [paint] with [canvas] in the body's coordinates, the box's top
  /// left at [offset].
  void paintIn(Canvas canvas, Offset offset, void Function(Canvas) paint) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    if (toBox case final toBox?) canvas.transform(toBox.storage);
    paint(canvas);
    canvas.restore();
  }

  @override
  bool operator ==(Object other) =>
      super == other &&
      other is GlassBody &&
      other.shape == shape &&
      other.outline == outline;

  @override
  int get hashCode => Object.hash(super.hashCode, shape, outline);
}

/// The radii [shape]'s top and bottom corners draw at in a box of [size]:
/// radii that overflow a side scaled down together, as Flutter scales them
/// (`scaleRadii`), and an oval's half its short side; none in an empty box.
({double top, double bottom}) glassCornerRadii(LiquidShape shape, Size size) {
  if (size.isEmpty) return (top: 0, bottom: 0);
  final box = Offset.zero & size;
  final drawn = switch (shape) {
    LiquidRoundedSuperellipse(:final borderRadius) =>
      borderRadius.toRSuperellipse(box).scaleRadii(),
    LiquidRoundedRectangle(:final radius) => RSuperellipse.fromRectAndRadius(
      box,
      Radius.circular(radius),
    ).scaleRadii(),
    LiquidOval() => null,
  };
  if (drawn == null) {
    final half = size.shortestSide / 2;
    return (top: half, bottom: half);
  }
  return (top: drawn.tlRadiusX, bottom: drawn.blRadiusX);
}
