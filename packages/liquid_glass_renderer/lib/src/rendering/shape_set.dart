import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/painting/ios27_measures.dart';
import 'package:liquid_glass_renderer/src/painting/shader_constants.dart';
import 'package:liquid_glass_renderer/src/rendering/appearance.dart';
import 'package:liquid_glass_renderer/src/rendering/frame_shapes.dart';
import 'package:liquid_glass_renderer/src/rendering/rounded_superellipse_parameters.dart';

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
    required List<WornAppearance> appearances,
  }) : this._(
         shapes: List.unmodifiable(shapes),
         superellipses: List.unmodifiable(superellipses),
         superellipsesLower: List.unmodifiable(superellipsesLower),
         boxes: List.unmodifiable(boxes),
         turns: List.unmodifiable(turns),
         appearances: List.unmodifiable(appearances),
       );

  /// The [drawn] shapes of a frame, in their order; the first shape of each
  /// geometry carries a negative blend marker, which starts a group.
  ///
  /// With [turnsToCenter] the shapes of a group whose largest is more than
  /// [centerTurnShortSide] across turn their optical normals by
  /// [centerTurn], as iOS 27 regular glass does.
  factory ShapeSet.encode(
    List<FrameShape> drawn, {
    required double devicePixelRatio,
    bool turnsToCenter = false,
  }) {
    final dpr = devicePixelRatio;
    final shapes = <double>[];
    final superellipses = <double>[];
    final superellipsesLower = <double>[];
    final boxes = <double>[];
    final turns = <double>[];
    final appearances = <WornAppearance>[];

    var groupStart = 0;
    var largestArea = 0.0;
    var largestShortSide = 0.0;
    void endGroup() {
      final turn = turnsToCenter && largestShortSide > centerTurnShortSide
          ? centerTurn
          : 0.0;
      for (var i = groupStart; i < appearances.length; i++) {
        turns.add(turn);
      }
      groupStart = appearances.length;
      largestArea = 0;
      largestShortSide = 0;
    }

    for (final (index, frameShape) in drawn.indexed) {
      final firstInGroup =
          index == 0 ||
          !identical(
            drawn[index - 1].committed.cache,
            frameShape.committed.cache,
          );
      if (firstInGroup) endGroup();
      final FrameShape(
        :shape,
        committed: CommittedGeometry(cache: geometry),
        :basis,
      ) = frameShape;
      final (:axisX, :axisY, :determinant) = basis;

      final inverse00 = axisY.dy / determinant;
      final inverse01 = -axisY.dx / determinant;
      final inverse10 = -axisX.dy / determinant;
      final inverse11 = axisX.dx / determinant;

      final distanceScale = leastSingularValue(
        axisX.dx,
        axisY.dx,
        axisX.dy,
        axisY.dy,
      );

      final localSize = shape.renderObject.paintSize;
      final centerInMatte = MatrixUtils.transformPoint(
        frameShape.toLayer,
        localSize.center(Offset.zero),
      );

      final pair = shape.encodedShapeType == RawShapeType.squirclePair;
      if (pair) {
        final halves = roundedSuperellipsePairParameters(
          localSize,
          shape.encodedCornerRadius,
          shape.encodedBottomRadius,
          scale: dpr,
        );
        superellipses.addAll(halves.top.floats);
        superellipsesLower.addAll(halves.geometryBottomFloats);
      } else {
        superellipses.addAll(
          roundedSuperellipseParameters(
            localSize,
            shape.encodedCornerRadius,
            scale: dpr,
          ).floats,
        );
        superellipsesLower.addAll(List<double>.filled(squircleFloats, 0));
      }
      final center = centerInMatte * dpr;
      final cornerRadius = shape.encodedCornerRadius * dpr;
      final halfExtents = _matteHalfExtents(
        shape.encodedShapeType,
        localSize * dpr / 2,
        cornerRadius,
        axisX,
        axisY,
      );
      boxes.addAll([
        center.dx - halfExtents.width,
        center.dy - halfExtents.height,
        center.dx + halfExtents.width,
        center.dy + halfExtents.height,
      ]);
      shapes.addAll(
        row(
          type: shape.encodedShapeType,
          width: localSize.width * dpr,
          height: localSize.height * dpr,
          radius: cornerRadius,
          inverse: (inverse00, inverse01, inverse10, inverse11),
          center: center,
          distanceScale: distanceScale,
          blend: geometry.blend * dpr,
          startsGroup: firstInGroup,
        ),
      );
      appearances.add(shape.appearance);
      final area =
          localSize.width * localSize.height * distanceScale * distanceScale;
      if (area > largestArea) {
        largestArea = area;
        largestShortSide = localSize.shortestSide * distanceScale;
      }
    }
    endGroup();
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
    final appearances = <WornAppearance>[];
    for (final (set, by) in sets) {
      final from = shapes.length;
      shapes.addAll(set.shapes);
      for (var i = from; i < shapes.length; i += rowFloats) {
        shapes[i + ShapeLane.centerX.index] += by.dx;
        shapes[i + ShapeLane.centerY.index] += by.dy;
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
    final count = shapes.length ~/ rowFloats;
    return ShapeSet._(
      shapes: List.unmodifiable(shapes),
      superellipses: List.unmodifiable(
        superellipses ?? List<double>.filled(count * squircleFloats, 0),
      ),
      superellipsesLower: List.unmodifiable(
        superellipsesLower ?? List<double>.filled(count * squircleFloats, 0),
      ),
      boxes: List.unmodifiable(boxes),
      turns: List.filled(count, 0),
      appearances: List.filled(count, WornAppearance.plain),
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
  static final double centerTurnShortSide = ios27SizeRamp.control;

  /// The floats of a shape's row in [shapes].
  static final int rowFloats = ShapeLane.values.length;

  /// A shape's row in [shapes]: a [type] [width] by [height] with corners of
  /// [radius] at [center], in device pixels of the matte, read through
  /// [inverse] (the matte-to-shape basis, row by row), its distances scaled
  /// by [distanceScale]. [blend] is its blend group's radius; the shape
  /// starts that group where [startsGroup].
  static List<double> row({
    required RawShapeType type,
    required double width,
    required double height,
    required double radius,
    required Offset center,
    (double, double, double, double) inverse = (1, 0, 0, 1),
    double distanceScale = 1,
    double blend = 0,
    bool startsGroup = true,
  }) {
    final (xx, xy, yx, yy) = inverse;
    return laneRow(ShapeLane.values, {
      ShapeLane.type: type.shaderIndex,
      ShapeLane.width: width,
      ShapeLane.height: height,
      ShapeLane.radius: radius,
      ShapeLane.inverseXX: xx,
      ShapeLane.inverseXY: xy,
      ShapeLane.inverseYX: yx,
      ShapeLane.inverseYY: yy,
      ShapeLane.centerX: center.dx,
      ShapeLane.centerY: center.dy,
      ShapeLane.distanceScale: distanceScale,
      ShapeLane.blendMarker: startsGroup ? -(blend + 1) : blend,
    });
  }

  /// The floats of a shape's row in [superellipses] and
  /// [superellipsesLower].
  static final int squircleFloats = SquircleLane.values.length;

  /// A row of [ShapeLane]s a shape.
  final List<double> shapes;

  /// A row of [SquircleLane]s a shape: its superellipse, or a pair's top
  /// half.
  final List<double> superellipses;

  /// A row of [SquircleLane]s a shape: a pair's bottom half, zeros for every
  /// other shape.
  final List<double> superellipsesLower;

  /// [lane] of shape [shape]'s row.
  double at(int shape, ShapeLane lane) =>
      shapes[shape * rowFloats + lane.index];

  /// [lane] of shape [shape]'s superellipse, or with [lower] of a pair's
  /// bottom half.
  double squircleAt(int shape, SquircleLane lane, {bool lower = false}) =>
      (lower ? superellipsesLower : superellipses)[shape * squircleFloats +
          lane.index];

  /// 4 floats a shape: its box in the matte.
  final List<double> boxes;

  /// A float a shape: how far its optical normal turns to the line from its
  /// center, [centerTurn] or 0. The shapes of a blend group turn alike, by
  /// the size of the largest of them, as the elements of an iOS 27
  /// container do.
  final List<double> turns;

  /// Each shape's appearance.
  final List<WornAppearance> appearances;

  /// How many shapes the set has.
  int get count => appearances.length;

  /// Whether shape [index] starts its blend group ([row]).
  bool startsGroupAt(int index) => at(index, ShapeLane.blendMarker) < 0;

  /// The blend group radius shape [index] carries: 0 for the shape that
  /// starts the group ([row]).
  double blendAt(int index) => max(at(index, ShapeLane.blendMarker), 0);

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
    while (first > 0 && !startsGroupAt(first)) {
      first--;
    }
    var least = double.infinity;
    for (var i = first; i < count; i++) {
      if (i > first && startsGroupAt(i)) break;
      final half =
          min(at(i, ShapeLane.width), at(i, ShapeLane.height)) /
          2 *
          at(i, ShapeLane.distanceScale);
      if (half < least) least = half;
    }
    return least;
  }

  /// The first [most] shapes.
  ShapeSet take(int most) => count <= most
      ? this
      : ShapeSet._(
          shapes: shapes.sublist(0, most * rowFloats),
          superellipses: superellipses.sublist(0, most * squircleFloats),
          superellipsesLower: superellipsesLower.sublist(
            0,
            most * squircleFloats,
          ),
          boxes: boxes.sublist(0, most * 4),
          turns: turns.sublist(0, most),
          appearances: appearances.sublist(0, most),
        );
}

/// The smaller singular value of the 2 x 2 matrix `[[xx, xy], [yx, yy]]`:
/// the least a unit distance can shrink to under it.
double leastSingularValue(double xx, double xy, double yx, double yy) {
  final determinant = xx * yy - xy * yx;
  final trace = xx * xx + xy * xy + yx * yx + yy * yy;
  final spread = sqrt(max(0, trace * trace - 4 * determinant * determinant));
  return sqrt(max(0, (trace - spread) / 2));
}
