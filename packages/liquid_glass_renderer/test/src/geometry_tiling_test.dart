import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/composer/geometry_renderer_limits.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_field.dart';
import 'package:liquid_glass_renderer/src/rendering/geometry_tiling.dart';
import 'package:liquid_glass_renderer/src/rendering/shape_set.dart';

const _rectangle = 3.0;
const _ellipse = 2.0;

/// A shape as a test places it: a box of [width] x [height] in its own units,
/// turned by [angle] and stretched by [stretchX], [stretchY] into buffer
/// pixels around [centerX], [centerY].
final class _Shape {
  const _Shape({
    required this.type,
    required this.width,
    required this.height,
    required this.radius,
    required this.centerX,
    required this.centerY,
    this.angle = 0,
    this.stretchX = 1,
    this.stretchY = 1,
    this.blend = 0,
    this.startsGroup = true,
  });

  final double type;
  final double width;
  final double height;
  final double radius;
  final double centerX;
  final double centerY;
  final double angle;
  final double stretchX;
  final double stretchY;
  final double blend;
  final bool startsGroup;

  (double, double, double, double) get basis => (
    stretchX * cos(angle),
    -stretchY * sin(angle),
    stretchX * sin(angle),
    stretchY * cos(angle),
  );

  (double, double, double, double) get inverse {
    final (a, b, c, d) = basis;
    final determinant = a * d - b * c;
    return (
      d / determinant,
      -b / determinant,
      -c / determinant,
      a / determinant,
    );
  }

  double get distanceScale => min(stretchX, stretchY);

  List<double> get row {
    final (i00, i01, i10, i11) = inverse;
    return [
      type,
      width,
      height,
      radius,
      i00,
      i01,
      i10,
      i11,
      centerX,
      centerY,
      distanceScale,
      if (startsGroup) -(blend + 1) else blend,
    ];
  }

  List<double> get box {
    final (a, b, c, d) = basis;
    final hw = width / 2;
    final hh = height / 2;
    double extent(double x, double y) => type == _ellipse
        ? sqrt(pow(x * hw, 2) + pow(y * hh, 2))
        : x.abs() * (hw - radius) +
              y.abs() * (hh - radius) +
              radius * sqrt(x * x + y * y);
    final ex = extent(a, b);
    final ey = extent(c, d);
    return [centerX - ex, centerY - ey, centerX + ex, centerY + ey];
  }

  /// The geometry pass's signed distance at buffer point ([x], [y]).
  double distanceAt(double x, double y) {
    final (i00, i01, i10, i11) = inverse;
    final dx = x - centerX;
    final dy = y - centerY;
    final lx = i00 * dx + i01 * dy;
    final ly = i10 * dx + i11 * dy;
    final local = type == _ellipse
        ? _ellipseDistance(lx, ly, width / 2, height / 2)
        : _roundedBoxDistance(lx, ly, width / 2, height / 2, radius);
    return local * distanceScale;
  }
}

double _roundedBoxDistance(double x, double y, double bx, double by, double r) {
  final qx = x.abs() - bx + r;
  final qy = y.abs() - by + r;
  return min(max(qx, qy), 0) +
      sqrt(pow(max(qx, 0), 2) + pow(max(qy, 0), 2)) -
      r;
}

double _ellipseDistance(double x, double y, double rx, double ry) {
  final ax = max(rx, 1e-4);
  final ay = max(ry, 1e-4);
  final px = x.abs();
  final py = y.abs();
  var angle = ax * (px - ax) < ay * (py - ay) ? pi / 2 : 0.0;
  for (var i = 0; i < 5; i++) {
    final c = cos(angle);
    final s = sin(angle);
    final ux = ax * c;
    final uy = ay * s;
    final vx = -ax * s;
    final vy = ay * c;
    angle +=
        ((px - ux) * vx + (py - uy) * vy) /
        max((px - ux) * ux + (py - uy) * uy + vx * vx + vy * vy, 1e-6);
  }
  final distance = sqrt(
    pow(px - ax * cos(angle), 2) + pow(py - ay * sin(angle), 2),
  );
  return pow(px / ax, 2) + pow(py / ay, 2) > 1 ? distance : -distance;
}

/// The scene's distance folded like sdf.glsl's sceneSample over [members]
/// (whole groups, chain order): each smooth union at its full radius, the
/// lowest any blend angle gives, or hard unions, the highest.
double _sceneDistance(
  List<_Shape> shapes,
  Iterable<int> members,
  double x,
  double y, {
  required bool smooth,
}) {
  var result = double.infinity;
  var group = double.infinity;
  var blend = 0.0;
  for (final i in members) {
    final shape = shapes[i];
    final d = shape.distanceAt(x, y);
    if (shape.startsGroup) {
      result = min(result, group);
      group = d;
      blend = shape.blend;
    } else if (!smooth || blend <= 0) {
      group = min(group, d);
    } else {
      final e = max(blend - (group - d).abs(), 0);
      group = min(group, d) - e * e * 0.25 / blend;
    }
  }
  return min(result, group);
}

/// [_sceneDistance] over the shapes a run lists ([TileRun.listed]), each
/// starting its group where the list says so.
double _listedDistance(
  List<_Shape> shapes,
  List<(int, bool)> listed,
  double x,
  double y, {
  required bool smooth,
}) {
  var result = double.infinity;
  var group = double.infinity;
  for (final (i, starts) in listed) {
    final shape = shapes[i];
    final d = shape.distanceAt(x, y);
    if (starts) {
      result = min(result, group);
      group = d;
    } else if (!smooth || shape.blend <= 0) {
      group = min(group, d);
    } else {
      final e = max(shape.blend - (group - d).abs(), 0);
      group = min(group, d) - e * e * 0.25 / shape.blend;
    }
  }
  return min(result, group);
}

ShapeSet _encode(List<_Shape> shapes) => ShapeSet.rows(
  shapes: [for (final shape in shapes) ...shape.row],
  boxes: [for (final shape in shapes) ...shape.box],
);

List<_Shape> _randomScene(
  Random random, {
  required int count,
  required double width,
  required double height,
  double largest = 240,
}) {
  final shapes = <_Shape>[];
  var blend = 0.0;
  var groupX = 0.0;
  var groupY = 0.0;
  for (var i = 0; i < count; i++) {
    final startsGroup = i == 0 || random.nextDouble() < 0.45;
    if (startsGroup) {
      blend = random.nextDouble() < 0.3 ? 0 : random.nextDouble() * 40;
      groupX = -40 + random.nextDouble() * (width + 80);
      groupY = -40 + random.nextDouble() * (height + 80);
    }
    final type = random.nextBool() ? _rectangle : _ellipse;
    final w = 4 + random.nextDouble() * largest;
    final h = 4 + random.nextDouble() * largest;
    final tilted = random.nextDouble() < 0.4;
    final stretched = random.nextDouble() < 0.4;
    shapes.add(
      _Shape(
        type: type,
        width: w,
        height: h,
        radius: type == _rectangle ? random.nextDouble() * min(w, h) / 2 : 0,
        centerX: groupX + (random.nextDouble() - 0.5) * largest,
        centerY: groupY + (random.nextDouble() - 0.5) * largest,
        angle: tilted ? random.nextDouble() * pi : 0,
        stretchX: stretched ? 0.5 + random.nextDouble() * 1.2 : 1,
        stretchY: stretched ? 0.5 + random.nextDouble() * 1.2 : 1,
        blend: blend,
        startsGroup: startsGroup,
      ),
    );
  }
  return shapes;
}

/// Pixel centers of tile [column], [row] inside a [width] x [height] buffer.
Iterable<(double, double)> _pixels(
  int column,
  int row,
  int width,
  int height,
) sync* {
  for (
    var y = row * Tiling.size;
    y < min(height, (row + 1) * Tiling.size);
    y++
  ) {
    for (
      var x = column * Tiling.size;
      x < min(width, (column + 1) * Tiling.size);
      x++
    ) {
      yield (x + 0.5, y + 0.5);
    }
  }
}

void _expectRunsPartitionRing(Tiling tiling) {
  final covered = Uint8List(tiling.columns * tiling.rows);
  for (final run in tiling.runs) {
    expect(run.length, inInclusiveRange(1, Tiling.maxRunTiles));
    expect(run.tall, inInclusiveRange(1, Tiling.blockTiles));
    for (var down = 0; down < run.tall; down++) {
      for (var i = 0; i < run.length; i++) {
        final tile = (run.row + down) * tiling.columns + run.column + i;
        expect(tiling.kindAt(run.column + i, run.row + down), TileKind.ring);
        covered[tile]++;
      }
    }
  }
  // The deep rectangles hold every deep tile once, with its look.
  final deep = Uint8List(tiling.columns * tiling.rows);
  final deeps = tiling.deeps;
  for (var i = 0; i < deeps.length; i += 5) {
    for (var row = deeps[i + 1]; row < deeps[i + 1] + deeps[i + 3]; row++) {
      for (var column = deeps[i]; column < deeps[i] + deeps[i + 2]; column++) {
        expect(tiling.kindAt(column, row), TileKind.deep);
        expect(tiling.deepLookAt(column, row), deeps[i + 4]);
        deep[row * tiling.columns + column]++;
      }
    }
  }
  for (var row = 0; row < tiling.rows; row++) {
    for (var column = 0; column < tiling.columns; column++) {
      final kind = tiling.kindAt(column, row);
      final reason = 'tile $column, $row';
      final tile = row * tiling.columns + column;
      expect(covered[tile], kind == TileKind.ring ? 1 : 0, reason: reason);
      expect(deep[tile], kind == TileKind.deep ? 1 : 0, reason: reason);
    }
  }
}

void main() {
  const width = 480;
  const height = 360;
  const reaches = [
    GlassReach(inward: 24, outward: 2),
    GlassReach(inward: 6, outward: 0.5),
    GlassReach(inward: 60, outward: 12),
    GlassReach(inward: 24, outward: 2, coarseTexel: 4),
  ];

  test('constant tiles hold only pixels past the reach', () {
    final random = Random(7);
    final seen = {for (final kind in TileKind.values) kind: 0};
    for (var scene = 0; scene < 12; scene++) {
      final shapes = _randomScene(
        random,
        count: 1 + random.nextInt(geometryMaxShapesPerDraw),
        width: width.toDouble(),
        height: height.toDouble(),
      );
      final all = List<int>.generate(shapes.length, (i) => i);
      for (final reach in reaches) {
        final tiling = Tiling.shapes(
          _encode(shapes),
          width: width,
          height: height,
          reach: reach,
        );
        expect(tiling.shapeSets, [all]);
        expect(tiling.droppedShapes, 0);
        _expectRunsPartitionRing(tiling);
        for (var row = 0; row < tiling.rows; row++) {
          for (var column = 0; column < tiling.columns; column++) {
            final kind = tiling.kindAt(column, row);
            seen[kind] = seen[kind]! + 1;
            if (kind == TileKind.ring) continue;
            for (final (x, y) in _pixels(column, row, width, height)) {
              if (kind == TileKind.outside) {
                final d = _sceneDistance(shapes, all, x, y, smooth: true);
                expect(
                  d,
                  greaterThanOrEqualTo(reach.outward),
                  reason: 'scene $scene, outside tile $column, $row at $x, $y',
                );
              } else {
                final d = _sceneDistance(shapes, all, x, y, smooth: false);
                expect(
                  d,
                  lessThanOrEqualTo(-reach.inward),
                  reason: 'scene $scene, deep tile $column, $row at $x, $y',
                );
              }
            }
          }
        }
      }
    }
    for (final kind in TileKind.values) {
      expect(seen[kind], greaterThan(100), reason: '$kind');
    }
  });

  test('a ring run lists every shape that changes a texel a read blends', () {
    final random = Random(23);
    var listed = 0;
    var shorter = 0;
    for (var scene = 0; scene < 24; scene++) {
      final shapes = _randomScene(
        random,
        count: 1 + random.nextInt(geometryMaxShapesPerDraw),
        width: width.toDouble(),
        height: height.toDouble(),
        largest: scene.isEven ? 240 : 90,
      );
      final all = List<int>.generate(shapes.length, (i) => i);
      for (final reach in reaches) {
        final tiling = Tiling.shapes(
          _encode(shapes),
          width: width,
          height: height,
          reach: reach,
        );
        final blended = reach.outward + 1.5 * reach.coarseTexel;
        final apron = reach.coarseTexel / 2;
        for (final run in tiling.runs) {
          if (run.members == 0) continue;
          final members = run.listed;
          listed++;
          if (members.length < shapes.length) shorter++;
          expect(members.length, inInclusiveRange(1, Tiling.maxListed));
          expect(members.first.$2, isTrue);
          expect(
            [for (final (i, _) in members) i],
            orderedEquals([for (final (i, _) in members) i]..sort()),
          );
          // The run's texels and its apron's, a pixel apart.
          final left = run.column * Tiling.size - apron;
          final top = run.row * Tiling.size - apron;
          final right = (run.column + run.length) * Tiling.size + apron;
          final bottom = (run.row + run.tall) * Tiling.size + apron;
          for (var y = top; y <= bottom; y += 1) {
            for (var x = left; x <= right; x += 1) {
              for (final smooth in [true, false]) {
                final full = _sceneDistance(shapes, all, x, y, smooth: smooth);
                final list = _listedDistance(
                  shapes,
                  members,
                  x,
                  y,
                  smooth: smooth,
                );
                final reason = 'scene $scene, $members at $x, $y';
                if (full < blended) {
                  expect(list, full, reason: reason);
                } else {
                  expect(list, greaterThanOrEqualTo(blended), reason: reason);
                }
              }
            }
          }
        }
      }
    }
    expect(listed, greaterThan(500));
    expect(shorter, greaterThan(250));
  });

  test('a tiling with slack holds for its shapes moved within it', () {
    final random = Random(29);
    const slack = 3.0;
    const reach = GlassReach(inward: 24, outward: 2, coarseTexel: 4);
    final blended = reach.outward + 1.5 * reach.coarseTexel;
    var held = 0;
    for (var scene = 0; scene < 16; scene++) {
      final shapes = _randomScene(
        random,
        count: 1 + random.nextInt(8),
        width: width.toDouble(),
        height: height.toDouble(),
        largest: scene.isEven ? 240 : 90,
      );
      final tiled = Tiling.shapes(
        _encode(shapes),
        width: width,
        height: height,
        reach: reach,
        slack: slack,
      );
      for (var step = 0; step < 3; step++) {
        final moved = [
          for (final shape in shapes)
            () {
              final angle = random.nextDouble() * 2 * pi;
              final far = step == 2 ? slack : random.nextDouble() * slack;
              return _Shape(
                type: shape.type,
                width: shape.width,
                height: shape.height,
                radius: shape.radius,
                centerX: shape.centerX + far * 0.999 * cos(angle),
                centerY: shape.centerY + far * 0.999 * sin(angle),
                angle: shape.angle,
                stretchX: shape.stretchX,
                stretchY: shape.stretchY,
                blend: shape.blend,
                startsGroup: shape.startsGroup,
              );
            }(),
        ];
        final tiling = tiled.held(_encode(moved), reach: reach);
        expect(tiling, isNotNull, reason: 'scene $scene, step $step');
        held++;
        expect(tiling!.runs, same(tiled.runs));
        expect(tiling.layout, same(tiled.layout));
        final all = List<int>.generate(moved.length, (i) => i);
        for (var row = 0; row < tiling.rows; row++) {
          for (var column = 0; column < tiling.columns; column++) {
            final kind = tiling.kindAt(column, row);
            if (kind == TileKind.ring) continue;
            for (final (x, y) in _pixels(column, row, width, height)) {
              final reason = 'scene $scene, $kind tile $column, $row';
              if (kind == TileKind.outside) {
                expect(
                  _sceneDistance(moved, all, x, y, smooth: true),
                  greaterThanOrEqualTo(reach.outward),
                  reason: reason,
                );
              } else {
                expect(
                  _sceneDistance(moved, all, x, y, smooth: false),
                  lessThanOrEqualTo(-reach.inward),
                  reason: reason,
                );
              }
            }
          }
        }
        for (final run in tiling.runs) {
          if (run.members == 0) continue;
          final members = run.listed;
          for (
            var y = run.row * Tiling.size - 2.0;
            y <= (run.row + run.tall) * Tiling.size + 2;
            y += 2
          ) {
            for (
              var x = run.column * Tiling.size - 2.0;
              x <= (run.column + run.length) * Tiling.size + 2;
              x += 2
            ) {
              for (final smooth in [true, false]) {
                final full = _sceneDistance(moved, all, x, y, smooth: smooth);
                final list = _listedDistance(
                  moved,
                  members,
                  x,
                  y,
                  smooth: smooth,
                );
                if (full < blended) {
                  expect(list, full, reason: 'scene $scene at $x, $y');
                } else {
                  expect(list, greaterThanOrEqualTo(blended));
                }
              }
            }
          }
        }
      }
      // Past the slack, with another size or another reach it holds no more.
      _Shape first({double by = 0, double wider = 0}) => _Shape(
        type: shapes.first.type,
        width: shapes.first.width + wider,
        height: shapes.first.height,
        radius: shapes.first.radius,
        centerX: shapes.first.centerX + by,
        centerY: shapes.first.centerY,
        angle: shapes.first.angle,
        stretchX: shapes.first.stretchX,
        stretchY: shapes.first.stretchY,
        blend: shapes.first.blend,
      );
      expect(
        tiled.held(
          _encode([first(by: slack * 1.01), ...shapes.skip(1)]),
          reach: reach,
        ),
        isNull,
      );
      expect(
        tiled.held(
          _encode([first(wider: 0.5), ...shapes.skip(1)]),
          reach: reach,
        ),
        isNull,
      );
      expect(
        tiled.held(
          _encode(shapes),
          reach: const GlassReach(inward: 25, outward: 2, coarseTexel: 4),
        ),
        isNull,
      );
      expect(
        Tiling.shapes(
          _encode(shapes),
          width: width,
          height: height,
          reach: reach,
        ).held(_encode(shapes), reach: reach),
        isNull,
        reason: 'a tiling without slack holds for nothing',
      );
    }
    expect(held, 48);
  });

  test('a ring tile of a large scene evaluates every group that reaches it, '
      'in chain order', () {
    final random = Random(11);
    for (var scene = 0; scene < 4; scene++) {
      final shapes = _randomScene(
        random,
        count: 40,
        width: width.toDouble(),
        height: height.toDouble(),
        largest: 60,
      );
      final all = List<int>.generate(shapes.length, (i) => i);
      const reach = GlassReach(inward: 24, outward: 2);
      final tiling = Tiling.shapes(
        _encode(shapes),
        width: width,
        height: height,
        reach: reach,
      );
      expect(tiling.droppedShapes, 0);
      expect(tiling.shapeSets.length, greaterThan(1));
      _expectRunsPartitionRing(tiling);
      for (final run in tiling.runs) {
        final members = tiling.shapeSets[run.shapes];
        expect(members.length, lessThanOrEqualTo(geometryMaxShapesPerDraw));
        expect(members, orderedEquals([...members]..sort()));
        expect(shapes[members.first].startsGroup, isTrue);
        for (var i = 0; i < run.length; i++) {
          for (final (x, y) in _pixels(
            run.column + i,
            run.row,
            width,
            height,
          )) {
            final full = _sceneDistance(shapes, all, x, y, smooth: true);
            final set = _sceneDistance(shapes, members, x, y, smooth: true);
            if (full < reach.outward) {
              expect(set, full, reason: 'scene $scene at $x, $y');
            } else {
              expect(set, greaterThanOrEqualTo(reach.outward));
            }
          }
        }
      }
    }
  });

  test('a deep tile reads one look only where no other look weighs in', () {
    final random = Random(13);
    const reach = GlassReach(inward: 24, outward: 2);
    var deep = 0;
    var evaluated = 0;
    for (var scene = 0; scene < 8; scene++) {
      final shapes = _randomScene(
        random,
        count: 2 + random.nextInt(geometryMaxShapesPerDraw - 1),
        width: width.toDouble(),
        height: height.toDouble(),
      );
      final looks = ShapeLooks([
        for (final _ in shapes) ...[random.nextInt(3) / 2, 0, 0, 1, 1, 1, 0, 1],
      ], tintOnly: true);
      // 1.25 times the blends of each shape's group, and a pixel.
      final lookReach = List<double>.filled(shapes.length, 0);
      for (var i = 0, start = 0; i <= shapes.length; i++) {
        if (i < shapes.length && !shapes[i].startsGroup) continue;
        var blends = 0.0;
        for (var j = start + 1; j < i; j++) {
          blends += shapes[j].blend;
        }
        lookReach.fillRange(start, i, blends * 1.25 + 1);
        start = i;
      }
      final plain = Tiling.shapes(
        _encode(shapes),
        width: width,
        height: height,
        reach: reach,
      );
      final tiling = Tiling.shapes(
        _encode(shapes),
        width: width,
        height: height,
        reach: reach,
        looks: looks,
      );
      _expectRunsPartitionRing(tiling);
      for (var row = 0; row < tiling.rows; row++) {
        for (var column = 0; column < tiling.columns; column++) {
          final kind = tiling.kindAt(column, row);
          if (plain.kindAt(column, row) != TileKind.deep) {
            expect(kind, plain.kindAt(column, row));
            continue;
          }
          if (kind == TileKind.ring) {
            evaluated++;
            continue;
          }
          deep++;
          final look = tiling.deepLookAt(column, row);
          final center = _pixels(column, row, width, height).first;
          expect(
            [
              for (var i = 0; i < shapes.length; i++)
                if (looks.lookOf[i] == look &&
                    shapes[i].distanceAt(center.$1, center.$2) < lookReach[i])
                  i,
            ],
            isNotEmpty,
            reason: 'scene $scene, tile $column, $row reads a look it has',
          );
          for (final (x, y) in _pixels(column, row, width, height)) {
            for (var i = 0; i < shapes.length; i++) {
              if (looks.lookOf[i] == look) continue;
              expect(
                shapes[i].distanceAt(x, y),
                greaterThanOrEqualTo(lookReach[i]),
                reason: 'scene $scene, shape $i at $x, $y',
              );
            }
          }
        }
      }
    }
    expect(deep, greaterThan(50));
    expect(evaluated, greaterThan(10));
  });

  test('a field tiles by the nodes over each tile', () {
    const step = 6.0;
    const pixelsPerUnit = 2.0;
    const cols = 70;
    const rows = 50;
    const originX = -12.0;
    const originY = -9.0;
    final samples = Float32List(cols * rows * 4);
    const shape = _Shape(
      type: _rectangle,
      width: 300,
      height: 200,
      radius: 40,
      centerX: 200,
      centerY: 150,
    );
    for (var j = 0; j < rows; j++) {
      for (var i = 0; i < cols; i++) {
        samples[(j * cols + i) * 4] =
            shape.distanceAt(originX + i * step, originY + j * step) /
            pixelsPerUnit;
      }
    }
    final field = BufferField(
      LiquidGlassField(
        samples: samples,
        cols: cols,
        rows: rows,
        origin: const Offset(originX / pixelsPerUnit, originY / pixelsPerUnit),
        step: step / pixelsPerUnit,
      ),
      layerToBuffer: (pixelsPerUnit, 0, 0, pixelsPerUnit, 0, 0),
    );
    expect(field.distanceScale, closeTo(pixelsPerUnit, 1e-9));
    double fieldAt(double x, double y) {
      final gx = ((x - originX) / step).clamp(0, cols - 1);
      final gy = ((y - originY) / step).clamp(0, rows - 1);
      final cx = min(gx.floor(), cols - 2);
      final cy = min(gy.floor(), rows - 2);
      final fx = gx - cx;
      final fy = gy - cy;
      double node(int i, int j) => samples[(j * cols + i) * 4];
      final top = node(cx, cy) * (1 - fx) + node(cx + 1, cy) * fx;
      final bottom = node(cx, cy + 1) * (1 - fx) + node(cx + 1, cy + 1) * fx;
      return (top * (1 - fy) + bottom * fy) * pixelsPerUnit;
    }

    for (final reach in reaches) {
      final tiling = Tiling.field(
        field,
        width: width,
        height: height,
        reach: reach,
      );
      _expectRunsPartitionRing(tiling);
      final kinds = {for (final kind in TileKind.values) kind: 0};
      for (var row = 0; row < tiling.rows; row++) {
        for (var column = 0; column < tiling.columns; column++) {
          final kind = tiling.kindAt(column, row);
          kinds[kind] = kinds[kind]! + 1;
          if (kind == TileKind.ring) continue;
          for (final (x, y) in _pixels(column, row, width, height)) {
            final d = fieldAt(x, y);
            if (kind == TileKind.outside) {
              expect(d, greaterThanOrEqualTo(reach.outward));
            } else {
              expect(d, lessThanOrEqualTo(-reach.inward));
            }
          }
        }
      }
      for (final kind in TileKind.values) {
        expect(kinds[kind], greaterThan(0), reason: '$reach $kind');
      }
    }
  });

  test(
    'the atlas keeps the constant tiles, the table and the strips apart',
    () {
      final random = Random(3);
      for (var scene = 0; scene < 6; scene++) {
        final shapes = _randomScene(
          random,
          count: 12,
          width: 1200,
          height: 900,
          largest: 500,
        );
        // Every other scene with coarse texels, whose smooth blocks are
        // strips as tall as the fine ones.
        final tiling = Tiling.shapes(
          _encode(shapes),
          width: 1200,
          height: 900,
          reach: GlassReach(
            inward: 40,
            outward: 4,
            coarseTexel: scene.isEven ? 1 : 4,
          ),
        );
        if (scene.isOdd) {
          expect(tiling.runs.where((run) => run.tall > 1), isNotEmpty);
          expect(
            tiling.runs.where((run) => run.tall == 1 && run.texel > 1),
            isNotEmpty,
          );
        }
        final atlas = tiling.layout;
        expect(atlas.width, lessThanOrEqualTo(AtlasLayout.maxSize));
        expect(atlas.height, lessThanOrEqualTo(AtlasLayout.maxSize));
        final (tableX, tableY) = AtlasLayout.tableOrigin;
        final rects = <(int, int, int, int)>[
          (0, 0, 18, 18),
          (18, 0, 18, 18),
          (tableX, tableY, tiling.columns, tiling.rows),
          for (var i = 0; i < tiling.runs.length; i++)
            (
              atlas.strips[i * 2],
              atlas.strips[i * 2 + 1],
              tiling.runs[i].length * Tiling.size ~/ tiling.runs[i].texel + 2,
              tiling.runs[i].tall * Tiling.size ~/ tiling.runs[i].texel + 2,
            ),
        ];
        for (final (x, y, w, h) in rects) {
          expect(x, greaterThanOrEqualTo(0));
          expect(y, greaterThanOrEqualTo(0));
          expect(x + w, lessThanOrEqualTo(atlas.width));
          expect(y + h, lessThanOrEqualTo(atlas.height));
        }
        for (var a = 0; a < rects.length; a++) {
          for (var b = a + 1; b < rects.length; b++) {
            final (ax, ay, aw, ah) = rects[a];
            final (bx, by, bw, bh) = rects[b];
            final apart =
                ax + aw <= bx ||
                bx + bw <= ax ||
                ay + ah <= by ||
                by + bh <= ay;
            expect(
              apart,
              isTrue,
              reason: 'scene $scene: ${rects[a]} ${rects[b]}',
            );
          }
        }
        for (var i = 0; i < tiling.runs.length; i++) {
          final texels = Tiling.size ~/ tiling.runs[i].texel;
          expect(atlas.entryOf(i, 2, 1), (
            atlas.strips[i * 2] + 1 + 2 * texels,
            atlas.strips[i * 2 + 1] + 1 + texels,
          ));
        }
      }
    },
  );

  test('a ring past one atlas is tiled again with a shallower inward '
      'reach', () {
    final shapes = _encode([
      for (var i = 0; i < 8; i++)
        _Shape(
          type: _rectangle,
          width: 1400,
          height: 1400,
          radius: 0,
          centerX: 800.0 + i % 4 * 1600,
          centerY: 800.0 + i ~/ 4 * 1600,
        ),
    ]);
    Tiling tile(double inward) => Tiling.shapes(
      shapes,
      width: 6400,
      height: 3200,
      reach: GlassReach(inward: inward, outward: 4),
    );
    final tiling = tile(400);
    expect(tiling.reach.inward, lessThan(400));
    expect(tiling.reach.outward, 4);
    expect(
      tiling.layout.height,
      lessThanOrEqualTo(AtlasLayout.maxSize),
    );
    final twice = tiling.reach.inward * 2;
    expect(tile(twice).reach.inward, lessThan(twice));
  });

  test('members out of reach of one another tile as if each were alone', () {
    List<_Shape> pair({required double blend}) => [
      for (final (x, y) in [(90.0, 80.0), (380.0, 270.0)])
        _Shape(
          type: _rectangle,
          width: 60,
          height: 40,
          radius: 12,
          centerX: x,
          centerY: y,
          blend: blend,
          startsGroup: x == 90 || blend == 0,
        ),
    ];
    const reach = GlassReach(inward: 24, outward: 2, coarseTexel: 4);
    Tiling tile(List<_Shape> shapes) => Tiling.shapes(
      _encode(shapes),
      width: width,
      height: height,
      reach: reach,
    );
    final fused = tile(pair(blend: 40));
    final alone = tile(pair(blend: 0));
    expect(fused.kinds, alone.kinds);
    expect(fused.runs.map((run) => run.texel), alone.runs.map((r) => r.texel));
  });

  test('a wider reach covers a narrower one', () {
    const wide = GlassReach(inward: 30, outward: 4);
    expect(wide.covers(const GlassReach(inward: 20, outward: 4)), isTrue);
    expect(wide.covers(const GlassReach(inward: 31, outward: 1)), isFalse);
    expect(wide.covers(const GlassReach(inward: 10, outward: 5)), isFalse);
    const coarse = GlassReach(inward: 20, outward: 4, coarseTexel: 4);
    expect(wide.covers(coarse), isTrue);
    expect(coarse.covers(const GlassReach(inward: 20, outward: 4)), isFalse);
  });
}
