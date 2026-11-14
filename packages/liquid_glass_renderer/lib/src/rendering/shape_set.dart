import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/rendering/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/rendering/rounded_superellipse_parameters.dart';

/// The affine basis that maps [shape]'s local axes into its layer's matte;
/// null when the shape draws nothing there: at visibility 0, or through a
/// singular transform. Every count of a layer's shapes goes by this, so a
/// hidden shape gives the layer no look of its own to write.
@internal
({Offset axisX, Offset axisY, double determinant})? matteShapeBasis(
  ShapeGeometry shape,
  Matrix4 geometryToLayer,
) {
  if (shape.appearance.visibility <= 0) return null;
  final shapeToGeometry = shape.shapeToGeometry;
  Offset toMatte(Offset point) => MatrixUtils.transformPoint(
    geometryToLayer,
    shapeToGeometry == null
        ? point
        : MatrixUtils.transformPoint(shapeToGeometry, point),
  );
  final origin = toMatte(Offset.zero);
  final axisX = toMatte(const Offset(1, 0)) - origin;
  final axisY = toMatte(const Offset(0, 1)) - origin;
  final determinant = axisX.dx * axisY.dy - axisY.dx * axisX.dy;
  if (determinant.abs() < 1e-8) return null;
  return (axisX: axisX, axisY: axisY, determinant: determinant);
}

/// The room a matte keeps around its shapes, in logical pixels: centered SDF
/// antialiasing needs half a device pixel outside the shape, or the outer
/// side of the fade is clipped at the matte's edge, and a contour reaches
/// [contourOutset].
@internal
double matteRoom(double devicePixelRatio, double contourOutset) =>
    max(0.5 / devicePixelRatio, contourOutset);

/// Half-extents along the matte axes of a shape with local half-size
/// [halfSize] mapped by the affine basis ([axisX], [axisY]). The geometry
/// shader culls with these boxes instead of mapping every pixel into each
/// shape's local space. Ellipses and rounded rectangles are exact;
/// continuous corners extend further into the corner than a circular arc of
/// the same radius, so they use their box.
Size _matteHalfExtents(
  RawShapeType type,
  Size halfSize,
  double cornerRadius,
  Offset axisX,
  Offset axisY,
) {
  double extent(double x, double y) {
    switch (type) {
      case RawShapeType.ellipse:
        return sqrt(pow(x * halfSize.width, 2) + pow(y * halfSize.height, 2));
      case RawShapeType.roundedRectangle:
        final radius = min(cornerRadius, halfSize.shortestSide);
        return x.abs() * (halfSize.width - radius) +
            y.abs() * (halfSize.height - radius) +
            radius * sqrt(x * x + y * y);
      case RawShapeType.squircle:
      case RawShapeType.squirclePair:
        return x.abs() * halfSize.width + y.abs() * halfSize.height;
    }
  }

  return Size(extent(axisX.dx, axisY.dx), extent(axisX.dy, axisY.dy));
}

/// Whether large glass whose refraction fits its shape leans its normals to
/// its center: false keeps the normals of its edge, and its one shape worked
/// out by the shader. For comparing the two; null and true lean. Glass
/// follows it when it next paints.
bool? debugGlassLean;

/// A layer's drawable shapes as the geometry shaders read them, in device
/// pixels of its matte.
///
/// Each encode makes a new set, so a set is the same object exactly while
/// its shapes are.
@internal
@immutable
final class ShapeSet {
  const ShapeSet._({
    required this.shapes,
    required this.superellipses,
    required this.superellipsesLower,
    required this.boxes,
    required this.turns,
    required this.appearances,
  });

  ShapeSet._unmodifiable({
    required List<double> shapes,
    required List<double> superellipses,
    required List<double> superellipsesLower,
    required List<double> boxes,
    required List<double> turns,
    required List<LiquidGlassAppearance> appearances,
  }) : this._(
         shapes: List.unmodifiable(shapes),
         superellipses: List.unmodifiable(superellipses),
         superellipsesLower: List.unmodifiable(superellipsesLower),
         boxes: List.unmodifiable(boxes),
         turns: List.unmodifiable(turns),
         appearances: List.unmodifiable(appearances),
       );

  /// The shapes of [geometries] that draw: visible, with an invertible
  /// transform into the matte. Shapes are gathered in cache order; the
  /// first shape of each geometry carries a negative blend marker, which
  /// starts a group, so shapes blend smoothly within their geometry and
  /// never with unrelated glass.
  ///
  /// With [turnsToCenter] the shapes of a group whose largest is more than
  /// [centerTurnShortSide] across turn their optical normals by
  /// [centerTurn], as iOS 27 regular glass does.
  factory ShapeSet.encode(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries, {
    required double devicePixelRatio,
    bool turnsToCenter = false,
  }) {
    final dpr = devicePixelRatio;
    final shapes = <double>[];
    final superellipses = <double>[];
    final superellipsesLower = <double>[];
    final boxes = <double>[];
    final turns = <double>[];
    final appearances = <LiquidGlassAppearance>[];

    for (final (_, geometry, geometryToLayer) in geometries) {
      var firstInGroup = true;
      final groupStart = appearances.length;
      var largestArea = 0.0;
      var largestShortSide = 0.0;
      for (final shape in geometry.shapes) {
        final basis = matteShapeBasis(shape, geometryToLayer);
        if (basis == null) continue;
        final shapeToGeometry = shape.shapeToGeometry;
        final (:axisX, :axisY, :determinant) = basis;

        // Inverse 2D affine basis maps matte-space physical pixels back to
        // the shape's own physical-pixel coordinate system.
        final inverse00 = axisY.dy / determinant;
        final inverse01 = -axisY.dx / determinant;
        final inverse10 = -axisX.dy / determinant;
        final inverse11 = axisX.dx / determinant;

        // The minimum singular value conservatively converts local SDF
        // distances back to screen pixels under non-uniform scaling.
        final trace =
            axisX.dx * axisX.dx +
            axisX.dy * axisX.dy +
            axisY.dx * axisY.dx +
            axisY.dy * axisY.dy;
        final discriminant = max(
          0,
          trace * trace - 4 * determinant * determinant,
        );
        final distanceScale = sqrt(
          max(0.0, (trace - sqrt(discriminant)) * 0.5),
        );

        final size = shape.renderObject.paintSize;
        final centerInGeometry = Offset(size.width / 2, size.height / 2);
        final centerInMatte = MatrixUtils.transformPoint(
          geometryToLayer,
          shapeToGeometry == null
              ? centerInGeometry
              : MatrixUtils.transformPoint(shapeToGeometry, centerInGeometry),
        );

        // The inverse affine basis above already maps matte coordinates back
        // into the shape's local coordinate system. Using the transformed
        // AABB here would apply scale a second time (and turn rotations into
        // oversized primitives), which is especially visible for stretched
        // shapes in a blend group.
        final pair = shape.encodedShapeType == RawShapeType.squirclePair;
        final rseParameters = pair
            ? roundedSuperellipsePairParameters(
                size,
                shape.encodedCornerRadius,
                shape.encodedBottomRadius,
                scale: dpr,
              )
            : roundedSuperellipseParameters(
                size,
                shape.encodedCornerRadius,
                scale: dpr,
              );
        // The geometry shader tests each cap's angular span as
        // 1 - cos(span); fake glass reads the spans themselves.
        for (var half = 0; half < rseParameters.length; half += 12) {
          rseParameters[half + 2] = 1.0 - cos(rseParameters[half + 2]);
          rseParameters[half + 3] = 1.0 - cos(rseParameters[half + 3]);
        }
        superellipses.addAll(rseParameters.take(12));
        superellipsesLower.addAll(
          pair ? rseParameters.skip(12) : List<double>.filled(12, 0),
        );
        final center = centerInMatte * dpr;
        // Every shader clamps a corner to half the short side already;
        // a clamped radius also lets the tiler's depth bound hold for a
        // capsule written with an oversized radius. A pair is fitted on
        // its own.
        final cornerRadius = pair
            ? shape.encodedCornerRadius
            : min(shape.encodedCornerRadius, size.shortestSide / 2);
        final halfExtents = _matteHalfExtents(
          shape.encodedShapeType,
          size * dpr / 2,
          cornerRadius * dpr,
          axisX,
          axisY,
        );
        boxes.addAll([
          center.dx - halfExtents.width,
          center.dy - halfExtents.height,
          center.dx + halfExtents.width,
          center.dy + halfExtents.height,
        ]);
        final blendMarker = firstInGroup
            ? -(geometry.blend * dpr + 1)
            : geometry.blend * dpr;

        shapes.addAll([
          // vec4 0: primitive parameters.
          shape.encodedShapeType.shaderIndex,
          size.width * dpr,
          size.height * dpr,
          cornerRadius * dpr,
          // vec4 1: inverse affine basis.
          inverse00,
          inverse01,
          inverse10,
          inverse11,
          // vec4 2: transformed center, distance scale, group marker.
          center.dx,
          center.dy,
          distanceScale,
          blendMarker,
        ]);
        appearances.add(shape.appearance);
        firstInGroup = false;
        final area = size.width * size.height * distanceScale * distanceScale;
        if (area > largestArea) {
          largestArea = area;
          largestShortSide = size.shortestSide * distanceScale;
        }
      }
      final turn = turnsToCenter && largestShortSide > centerTurnShortSide
          ? centerTurn
          : 0.0;
      for (var i = groupStart; i < appearances.length; i++) {
        turns.add(turn);
      }
    }
    return ShapeSet._unmodifiable(
      shapes: shapes,
      superellipses: superellipses,
      superellipsesLower: superellipsesLower,
      boxes: boxes,
      turns: turns,
      appearances: appearances,
    );
  }

  /// The shapes of [sets] in one, each moved by its offset in device pixels
  /// of the matte.
  factory ShapeSet.join(List<(ShapeSet, Offset)> sets) {
    final shapes = <double>[];
    final superellipses = <double>[];
    final superellipsesLower = <double>[];
    final boxes = <double>[];
    final turns = <double>[];
    final appearances = <LiquidGlassAppearance>[];
    for (final (set, by) in sets) {
      final from = shapes.length;
      shapes.addAll(set.shapes);
      for (var i = from + 8; i < shapes.length; i += 12) {
        shapes[i] += by.dx;
        shapes[i + 1] += by.dy;
      }
      final box = boxes.length;
      boxes.addAll(set.boxes);
      for (var i = box; i < boxes.length; i += 2) {
        boxes[i] += by.dx;
        boxes[i + 1] += by.dy;
      }
      superellipses.addAll(set.superellipses);
      superellipsesLower.addAll(set.superellipsesLower);
      turns.addAll(set.turns);
      appearances.addAll(set.appearances);
    }
    return ShapeSet._unmodifiable(
      shapes: shapes,
      superellipses: superellipses,
      superellipsesLower: superellipsesLower,
      boxes: boxes,
      turns: turns,
      appearances: appearances,
    );
  }

  /// Shapes already in the shaders' layout, each with the default
  /// appearance.
  factory ShapeSet.rows({
    required List<double> shapes,
    required List<double> boxes,
    List<double>? superellipses,
    List<double>? superellipsesLower,
  }) {
    final count = shapes.length ~/ 12;
    return ShapeSet._(
      shapes: List.unmodifiable(shapes),
      superellipses: List.unmodifiable(
        superellipses ?? List<double>.filled(count * 12, 0),
      ),
      superellipsesLower: List.unmodifiable(
        superellipsesLower ?? List<double>.filled(count * 12, 0),
      ),
      boxes: List.unmodifiable(boxes),
      turns: List.filled(count, 0),
      appearances: List.filled(count, const LiquidGlassAppearance()),
    );
  }

  /// No shapes.
  static const empty = ShapeSet._(
    shapes: [],
    superellipses: [],
    superellipsesLower: [],
    boxes: [],
    turns: [],
    appearances: [],
  );

  /// How far iOS 27 turns the optical normal of large regular glass from
  /// its edge's to the line from its center, the two mixed and made a unit
  /// again. Read from UIKit on iOS 27.
  static const double centerTurn = 0.5;

  /// The short side, in logical pixels, past which iOS 27 regular glass
  /// turns its normals by [centerTurn]; glass no larger keeps its edge's.
  static const double centerTurnShortSide = 64;

  /// 12 floats a shape: primitive, inverse basis, center, distance scale and
  /// blend marker.
  final List<double> shapes;

  /// 12 floats a shape: its superellipse, or a pair's top half.
  final List<double> superellipses;

  /// 12 floats a shape: a pair's bottom half, zeros for every other shape.
  final List<double> superellipsesLower;

  /// 4 floats a shape: its box in the matte.
  final List<double> boxes;

  /// A float a shape: how far its optical normal turns to the line from its
  /// center, [centerTurn] or 0. The shapes of a blend group turn alike, by
  /// the size of the largest of them, as the elements of an iOS 27
  /// container do.
  final List<double> turns;

  /// Each shape's appearance.
  final List<LiquidGlassAppearance> appearances;

  /// How many shapes the set has.
  int get count => appearances.length;

  /// Whether any shape turns its normal ([turns]).
  bool get leans => turns.any((turn) => turn > 0);

  /// Half the short side that sizes the lens of shape [index], in device
  /// pixels of the matte: the smallest of the shapes of its blend group.
  ///
  /// iOS 27 gives the glass of a container one lens, sized by its smallest
  /// element: a large shape that merges with a small one bends the backdrop
  /// no further than the small one does, all around its rim.
  double lensOf(int index) {
    var first = index;
    while (first > 0 && shapes[first * 12 + 11] >= 0) {
      first--;
    }
    var least = double.infinity;
    for (var i = first; i < count; i++) {
      if (i > first && shapes[i * 12 + 11] < 0) break;
      final half =
          min(shapes[i * 12 + 1], shapes[i * 12 + 2]) / 2 * shapes[i * 12 + 10];
      if (half < least) least = half;
    }
    return least;
  }

  /// The first [most] shapes.
  ShapeSet take(int most) => count <= most
      ? this
      : ShapeSet._(
          shapes: shapes.sublist(0, most * 12),
          superellipses: superellipses.sublist(0, most * 12),
          superellipsesLower: superellipsesLower.sublist(0, most * 12),
          boxes: boxes.sublist(0, most * 4),
          turns: turns.sublist(0, most),
          appearances: appearances.sublist(0, most),
        );
}
