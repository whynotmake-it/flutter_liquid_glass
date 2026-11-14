import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_field.dart';
import 'package:liquid_glass_renderer/src/rendering/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/geometry_tiling.dart';
import 'package:liquid_glass_renderer/src/rendering/rounded_superellipse_parameters.dart';
import 'package:liquid_glass_renderer/src/rendering/shape_set.dart';

import 'gpu_test_helpers.dart';

/// Every tile within reach, so every texel is evaluated.
const _everything = GlassReach(inward: 100000, outward: 100000);

/// The atlas of [tiling] read back.
Future<AtlasTexels> _draw(
  FlutterGpuGeometryRenderer renderer,
  Tiling tiling,
) => AtlasTexels.read(renderer.renderAtlas(tiling).image);

/// Buffer pixel ([x], [y]) as its strip holds it: NaN where the strip skips
/// it.
(double, double, double, double) _strip(AtlasTexels atlas, int x, int y) {
  final (ex, ey, _) = atlas.entry(x ~/ Tiling.size, y ~/ Tiling.size);
  return atlas.at(ex + x % Tiling.size, ey + y % Tiling.size);
}

/// One shape of each kind the geometry pass draws, placed at random. With
/// [roundCorners] no side is many corner radii long: the host's software
/// GPU takes pow(0, y) for pow(FLT_MIN, y), which bends the distance of
/// such a side of a continuous corner around its middle.
ShapeSet _scene(
  Random random,
  int count,
  int width,
  int height, {
  bool roundCorners = false,
}) {
  final shapes = <double>[];
  final superellipses = <double>[];
  final lower = <double>[];
  final boxes = <double>[];
  var blend = 0.0;
  var groupX = 0.0;
  var groupY = 0.0;
  for (var i = 0; i < count; i++) {
    final starts = i == 0 || random.nextDouble() < 0.5;
    if (starts) {
      blend = random.nextDouble() < 0.3 ? 0 : random.nextDouble() * 30;
      groupX = random.nextDouble() * width;
      groupY = random.nextDouble() * height;
    }
    final type = 1 + random.nextInt(4);
    final w = 8 + random.nextDouble() * 120;
    final h = 8 + random.nextDouble() * 120;
    final shorter = min(w, h) / 2;
    final least = roundCorners ? min(shorter, max(w, h) / 8) : 0.0;
    final top = least + random.nextDouble() * (shorter - least);
    final bottom = roundCorners
        ? top * (0.5 + random.nextDouble() * 0.5)
        : random.nextDouble() * shorter * 0.5;
    final radius = type == 2 ? 0.0 : top;
    final angle = random.nextDouble() < 0.4 ? random.nextDouble() * pi : 0.0;
    final stretch = random.nextDouble() < 0.4;
    final sx = stretch ? 0.6 + random.nextDouble() : 1.0;
    final sy = stretch ? 0.6 + random.nextDouble() : 1.0;
    final a = sx * cos(angle);
    final b = -sy * sin(angle);
    final c = sx * sin(angle);
    final d = sy * cos(angle);
    final determinant = a * d - b * c;
    final cx = groupX + (random.nextDouble() - 0.5) * 80;
    final cy = groupY + (random.nextDouble() - 0.5) * 80;
    shapes.addAll([
      type.toDouble(),
      w,
      h,
      radius,
      d / determinant,
      -b / determinant,
      -c / determinant,
      a / determinant,
      cx,
      cy,
      min(sx, sy),
      if (starts) -(blend + 1) else blend,
    ]);
    final rse = type == 4
        ? roundedSuperellipsePairParameters(ui.Size(w, h), top, bottom)
        : roundedSuperellipseParameters(ui.Size(w, h), radius);
    for (var half = 0; half < rse.length; half += 12) {
      rse[half + 2] = 1 - cos(rse[half + 2]);
      rse[half + 3] = 1 - cos(rse[half + 3]);
    }
    superellipses.addAll(rse.take(12));
    lower.addAll(type == 4 ? rse.skip(12) : List.filled(12, 0));
    double extent(double x, double y) => type == 2
        ? sqrt(pow(x * w / 2, 2) + pow(y * h / 2, 2))
        : x.abs() * w / 2 + y.abs() * h / 2;
    final ex = extent(a, b);
    final ey = extent(c, d);
    boxes.addAll([cx - ex, cy - ey, cx + ex, cy + ey]);
  }
  return ShapeSet.rows(
    shapes: shapes,
    boxes: boxes,
    superellipses: superellipses,
    superellipsesLower: lower,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const width = 256;
  const height = 192;

  test('the table points every tile at its constant or its strip', () async {
    final renderer = await createGeometryRenderer();
    final shapes = _scene(Random(5), 6, width, height);
    final tiling = Tiling.shapes(
      shapes,
      width: width,
      height: height,
      reach: const GlassReach(inward: 12, outward: 2),
    );
    expect(tiling.runs, isNotEmpty);
    final atlas = await _draw(renderer, tiling);
    final layout = tiling.layout;
    final expected = <(int, int), (int, int)>{};
    for (var i = 0; i < tiling.runs.length; i++) {
      final run = tiling.runs[i];
      for (var down = 0; down < run.tall; down++) {
        for (var t = 0; t < run.length; t++) {
          expected[(run.column + t, run.row + down)] = layout.entryOf(
            i,
            t,
            down,
          );
        }
      }
    }
    for (var row = 0; row < tiling.rows; row++) {
      for (var column = 0; column < tiling.columns; column++) {
        final (x, y, scale) = atlas.entry(column, row);
        expect(
          (x, y),
          switch (tiling.kindAt(column, row)) {
            TileKind.outside => AtlasLayout.outsideEntry,
            TileKind.deep => AtlasLayout.deepEntryOf(0),
            TileKind.ring => expected[(column, row)],
          },
          reason: 'tile $column, $row',
        );
        expect(
          scale,
          tiling.kindAt(column, row) == TileKind.ring ? 1 : 0,
          reason: 'tile $column, $row',
        );
      }
    }
  });

  test('a rounded rectangle reads its distance through the table', () async {
    final renderer = await createGeometryRenderer();
    final shapes = ShapeSet.rows(
      shapes: const [3, 100, 60, 12, 1, 0, 0, 1, 128, 96, 1, -1],
      boxes: const [78, 66, 178, 126],
    );
    final atlas = await _draw(
      renderer,
      Tiling.shapes(
        shapes,
        width: width,
        height: height,
        reach: const GlassReach(inward: 16, outward: 3),
      ),
    );
    // R is the distance inside, the left edge at x = 78.
    expect(atlas.inwardAt(82, 96), closeTo(4.5, 0.01));
    expect(atlas.inwardAt(76, 96), closeTo(-1.5, 0.01));
    expect(atlas.inwardAt(128, 70), closeTo(4.5, 0.01));
  });

  test('ring strips hold what a pass over every texel writes', () async {
    final renderer = await createGeometryRenderer();
    final dense = await createGeometryRenderer();
    final random = Random(9);
    for (var scene = 0; scene < 6; scene++) {
      final shapes = _scene(random, 2 + random.nextInt(10), width, height);
      for (final reach in const [
        GlassReach(inward: 16, outward: 2),
        GlassReach(inward: 4, outward: 0.5),
      ]) {
        final tiling = Tiling.shapes(
          shapes,
          width: width,
          height: height,
          reach: reach,
        );
        final sparse = await _draw(renderer, tiling);
        final every = await _draw(
          dense,
          Tiling.shapes(
            shapes,
            width: width,
            height: height,
            reach: _everything,
          ),
        );
        for (var y = 0; y < height; y++) {
          for (var x = 0; x < width; x++) {
            final kind = tiling.kindAt(x ~/ Tiling.size, y ~/ Tiling.size);
            final exact = _strip(every, x, y);
            final reason = 'scene $scene, $reach, pixel $x, $y: $exact';
            switch (kind) {
              case TileKind.ring:
                // A strip is exact as far out as a read blends texels; past
                // that it skips texels and the shapes that only reach those.
                final read = _strip(sparse, x, y);
                final blended = reach.outward + 1.5 * reach.coarseTexel;
                if (exact.$4 > 0 && exact.$1 > -blended) {
                  expect(read, exact, reason: reason);
                } else if (read.$4 > 0) {
                  expect(
                    read.$1,
                    lessThanOrEqualTo(-blended),
                    reason: reason,
                  );
                }
              case TileKind.outside:
                if (exact.$4 > 0) {
                  expect(
                    exact.$1,
                    lessThanOrEqualTo(-reach.outward),
                    reason: reason,
                  );
                }
              case TileKind.deep:
                expect(exact.$4, greaterThan(0), reason: reason);
                expect(
                  exact.$1,
                  greaterThanOrEqualTo(reach.inward),
                  reason: reason,
                );
            }
          }
        }
      }
    }
  });

  test('a coarse tile reads within NEAR of the exact geometry', () async {
    final renderer = await createGeometryRenderer();
    final dense = await createGeometryRenderer();
    final random = Random(17);
    const reach = GlassReach(inward: 24, outward: 3, coarseTexel: 4);
    var coarseTiles = 0;
    var worstDistance = 0.0;
    var worstEdgeNormal = 0.0;
    var worstNormal = 0.0;
    for (var scene = 0; scene < 12; scene++) {
      final shapes = _scene(
        random,
        1 + random.nextInt(8),
        width,
        height,
        roundCorners: true,
      );
      final tiling = Tiling.shapes(
        shapes,
        width: width,
        height: height,
        reach: reach,
      );
      final read = await _draw(renderer, tiling);
      final every = await _draw(
        dense,
        Tiling.shapes(shapes, width: width, height: height, reach: _everything),
      );
      for (final run in tiling.runs) {
        if (run.texel == 1) continue;
        coarseTiles += run.length * run.tall;
        for (
          var x = run.column * Tiling.size;
          x < min(width, (run.column + run.length) * Tiling.size);
          x++
        ) {
          for (
            var y = run.row * Tiling.size;
            y < min(height, (run.row + run.tall) * Tiling.size);
            y++
          ) {
            final exact = _strip(every, x, y);
            if (exact.$1 <= -reach.outward || exact.$1 >= reach.inward) {
              continue;
            }
            final (inward, nx, ny, _) = read.pixel(x, y);
            final normal =
                sqrt(pow(nx - exact.$2, 2) + pow(ny - exact.$3, 2)) /
                sqrt(pow(exact.$2, 2) + pow(exact.$3, 2));
            worstDistance = max(worstDistance, (inward - exact.$1).abs());
            worstNormal = max(worstNormal, normal);
            if (exact.$1 < 4) worstEdgeNormal = max(worstEdgeNormal, normal);
          }
        }
      }
    }
    expect(coarseTiles, greaterThan(50));
    expect(worstDistance, lessThan(0.25));
    expect(worstEdgeNormal, lessThan(0.1));
    expect(worstNormal, lessThan(0.2));
  });

  test('a field atlas holds what a pass over every texel writes', () async {
    final renderer = await createGeometryRenderer();
    final dense = await createGeometryRenderer();
    const cols = 40;
    const rows = 30;
    const step = 4.0;
    final samples = Float32List(cols * rows * 4);
    for (var j = 0; j < rows; j++) {
      for (var i = 0; i < cols; i++) {
        final x = i * step - 80;
        final y = j * step - 60;
        final r = sqrt(x * x + y * y);
        final o = (j * cols + i) * 4;
        samples[o] = r - 40;
        samples[o + 1] = r > 0 ? x / r : 0;
        samples[o + 2] = r > 0 ? y / r : 0;
        samples[o + 3] = 40;
      }
    }
    final field = BufferField(
      LiquidGlassField(
        samples: samples,
        cols: cols,
        rows: rows,
        origin: const ui.Offset(-10, -5),
        step: step,
      ),
      layerToBuffer: (2, 0, 0, 2, 20, 10),
    );
    const reach = GlassReach(inward: 20, outward: 2);
    final tiling = Tiling.field(
      field,
      width: width,
      height: height,
      reach: reach,
    );
    expect(
      {for (var t = 0; t < tiling.kinds.length; t++) tiling.kinds[t]},
      {for (final kind in TileKind.values) kind.index},
    );
    final sparse = await _draw(renderer, tiling);
    final every = await _draw(
      dense,
      Tiling.field(field, width: width, height: height, reach: _everything),
    );
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final exact = _strip(every, x, y);
        final reason = 'pixel $x, $y: $exact';
        switch (tiling.kindAt(x ~/ Tiling.size, y ~/ Tiling.size)) {
          case TileKind.ring:
            expect(_strip(sparse, x, y), exact, reason: reason);
          case TileKind.outside:
            expect(exact.$1, lessThanOrEqualTo(-reach.outward), reason: reason);
          case TileKind.deep:
            expect(
              exact.$1,
              greaterThanOrEqualTo(reach.inward),
              reason: reason,
            );
        }
      }
    }
    // The circle of radius 40 logical pixels sits at buffer (20, 10) +
    // 2 * ((-10, -5) + (80, 60)) = (160, 120), 80 pixels in radius; the
    // grid's bilinear cone rounds its tip.
    expect(every.inwardAt(160, 120), closeTo(80, 2));
    expect(every.inwardAt(160 + 70, 120), closeTo(10, 1));
  });

  test('a coarse field tile reads within NEAR of the field', () async {
    final renderer = await createGeometryRenderer();
    final dense = await createGeometryRenderer();
    // Two circles fused by a smooth union, as a menu fused with its button:
    // a neck, and a ridge between the two where the gradient turns round.
    const cols = 44;
    const rows = 30;
    const step = 4.0;
    const blend = 24.0;
    (double, double, double) circle(double x, double y, double radius) {
      final r = sqrt(x * x + y * y);
      return (r - radius, r > 0 ? x / r : 0, r > 0 ? y / r : 0);
    }

    final samples = Float32List(cols * rows * 4);
    for (var j = 0; j < rows; j++) {
      for (var i = 0; i < cols; i++) {
        final x = i * step;
        final y = j * step;
        final (da, ax, ay) = circle(x - 60, y - 58, 36);
        final (db, bx, by) = circle(x - 124, y - 58, 22);
        final weight = (0.5 + (db - da) / (2 * blend)).clamp(0.0, 1.0);
        final bite = max(blend - (da - db).abs(), 0);
        final o = (j * cols + i) * 4;
        samples[o] = min(da, db) - bite * bite * 0.25 / blend;
        samples[o + 1] = bx + (ax - bx) * weight;
        samples[o + 2] = by + (ay - by) * weight;
        samples[o + 3] = 22 + (36 - 22) * weight;
      }
    }
    final field = BufferField(
      LiquidGlassField(
        samples: samples,
        cols: cols,
        rows: rows,
        origin: ui.Offset.zero,
        step: step,
      ),
      layerToBuffer: (1.5, 0, 0, 1.5, 0, 0),
    );
    const reach = GlassReach(inward: 24, outward: 3, coarseTexel: 4);
    final tiling = Tiling.field(
      field,
      width: width,
      height: height,
      reach: reach,
    );
    final read = await _draw(renderer, tiling);
    final every = await _draw(
      dense,
      Tiling.field(field, width: width, height: height, reach: _everything),
    );
    var coarseTiles = 0;
    var fineTiles = 0;
    var worstDistance = 0.0;
    var worstEdgeNormal = 0.0;
    var worstNormal = 0.0;
    for (final run in tiling.runs) {
      if (run.texel == 1) {
        fineTiles += run.length;
        continue;
      }
      coarseTiles += run.length * run.tall;
      for (
        var x = run.column * Tiling.size;
        x < min(width, (run.column + run.length) * Tiling.size);
        x++
      ) {
        for (
          var y = run.row * Tiling.size;
          y < min(height, (run.row + run.tall) * Tiling.size);
          y++
        ) {
          final exact = _strip(every, x, y);
          if (exact.$1 <= -reach.outward || exact.$1 >= reach.inward) continue;
          final (inward, nx, ny, _) = read.pixel(x, y);
          final normal = sqrt(pow(nx - exact.$2, 2) + pow(ny - exact.$3, 2));
          worstDistance = max(worstDistance, (inward - exact.$1).abs());
          worstNormal = max(worstNormal, normal);
          if (exact.$1 < 4) worstEdgeNormal = max(worstEdgeNormal, normal);
        }
      }
    }
    expect(coarseTiles, greaterThan(50));
    expect(fineTiles, greaterThan(0));
    // The body creases along its grid's lines, six pixels apart here, and
    // a coarse texel that straddles a crease rounds it: by 0.42 of a pixel
    // in the neck, where the gradient turns a quarter radian a node.
    expect(worstDistance, lessThan(0.5));
    expect(worstEdgeNormal, lessThan(0.05));
    expect(worstNormal, lessThan(0.1));
  });
}
