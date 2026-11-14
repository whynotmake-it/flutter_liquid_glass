import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/rendering/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/geometry_tiling.dart';
import 'package:liquid_glass_renderer/src/rendering/shaders.dart';
import 'package:liquid_glass_renderer/src/rendering/shape_set.dart';

/// Creates a renderer and registers cleanup for the end of the test.
Future<FlutterGpuGeometryRenderer> createGeometryRenderer() async {
  final renderer = await FlutterGpuGeometryRenderer.fromAsset(
    ShaderKeys.gpuGeometryShaderBundle,
  );
  addTearDown(renderer.dispose);
  return renderer;
}

/// The reach the renderer tests draw atlases with.
const testReach = GlassReach(inward: 12, outward: 2);

/// A 20 x 30 rounded rectangle with corners of 4, centered at ([centerX],
/// 32).
ShapeSet testRectangle({double centerX = 16}) => ShapeSet.rows(
  shapes: [
    3, 20, 30, 4, // Rounded rectangle.
    1, 0, 0, 1, // Identity inverse affine basis.
    centerX, 32, 1, -1, // Center, scale, new group marker.
  ],
  boxes: [centerX - 10, 17, centerX + 10, 47],
);

/// Draws [testRectangle] into the atlas of a 64 x 64 geometry buffer, with
/// [looks] beside it, and returns the atlas.
ui.Image renderTestRectangle(
  FlutterGpuGeometryRenderer renderer, {
  double centerX = 16,
  ShapeLooks? looks,
}) => renderer
    .renderAtlas(
      Tiling.shapes(
        testRectangle(centerX: centerX),
        width: 64,
        height: 64,
        reach: testReach,
        looks: looks,
      ),
    )
    .image;

/// A geometry atlas read back: four floats a texel, read through its table
/// as the final shader reads it.
final class AtlasTexels {
  AtlasTexels._(this.texels, this.width, this._tableX, this._tableY);

  /// Reads the atlas at [place] in [image], the page it shares; without a
  /// place, the first atlas of the page.
  static Future<AtlasTexels> read(ui.Image image, [AtlasPlace? place]) async {
    final data = await image.toByteData(
      format: ui.ImageByteFormat.rawExtendedRgba128,
    );
    final (tableX, tableY) = AtlasLayout.tableOrigin;
    return AtlasTexels._(
      Float32List.fromList(
        data!.buffer.asFloat32List(data.offsetInBytes, data.lengthInBytes ~/ 4),
      ),
      image.width,
      place?.tableX ?? tableX,
      place?.tableY ?? tableY,
    );
  }

  final int _tableX;
  final int _tableY;

  // The first row of the atlas in its page.
  int get _top => _tableY - AtlasLayout.tableOrigin.$2;

  /// The texels, four floats each.
  final Float32List texels;

  /// The atlas's width in texels.
  final int width;

  /// The texel at atlas ([x], [y]). The engine reads a texel back as if w
  /// were alpha, dividing the rest by it; texels with w = 0 (the constants
  /// and those far outside) come back as NaN.
  (double, double, double, double) at(int x, int y) {
    final i = (y * width + x) * 4;
    final w = texels[i + 3];
    if (w <= 0) return (double.nan, 0, 0, 0);
    return (texels[i] * w, texels[i + 1] * w, texels[i + 2] * w, w);
  }

  /// The table entry of tile [column], [row]: the corner of the texel of its
  /// pixel (0, 0), and texels a pixel (0 for a constant tile).
  (int, int, double) entry(int column, int row) {
    final (x, y, z, w) = at(_tableX + column, _tableY + row);
    expect(w, 1, reason: 'table texel of $column, $row');
    return (x.round(), y.round(), z);
  }

  /// Buffer pixel ([x], [y]) through the table, read linearly at the
  /// pixel's center as the final shader reads it. The constant tiles and
  /// the texels a strip skips come back as the constants they hold.
  (double, double, double, double) pixel(int x, int y) {
    final (entryX, entryY, scale) = entry(x ~/ Tiling.size, y ~/ Tiling.size);
    if (scale == 0) {
      // A tile no quad wrote holds the page's outside entry, the first
      // atlas's.
      final (outsideX, outsideY) = AtlasLayout.outsideEntry;
      return entryX == outsideX &&
              (entryY == outsideY || entryY == _top + outsideY)
          ? (kFarInward, 0, 0, 0)
          : (kDeepInward, 0, 0, 0);
    }
    (double, double, double, double) texel(int tx, int ty) {
      final value = at(tx, ty);
      return value.$1.isNaN ? (kFarInward, 0, 0, 0) : value;
    }

    return _linear(
      entryX + (x % Tiling.size + 0.5) * scale - 0.5,
      entryY + (y % Tiling.size + 0.5) * scale - 0.5,
      texel,
    );
  }

  /// The distance to the edge at buffer pixel ([x], [y]), positive inside.
  double inwardAt(int x, int y) => pixel(x, y).$1;

  /// The texel of [look], a texture beside this atlas, that buffer pixel
  /// ([x], [y]) reads, as read back, read linearly as [pixel] reads.
  (double, double, double, double) lookAt(AtlasTexels look, int x, int y) {
    final (entryX, entryY, scale) = entry(x ~/ Tiling.size, y ~/ Tiling.size);
    final texels = look.texels;
    return _linear(
      entryX + (x % Tiling.size + 0.5) * scale - 0.5,
      entryY + (y % Tiling.size + 0.5) * scale - 0.5,
      (tx, ty) {
        final i = (ty * look.width + tx) * 4;
        return (texels[i], texels[i + 1], texels[i + 2], texels[i + 3]);
      },
    );
  }

  // Texel space with texel (i, j) at (i, j): a bilinear blend of the four
  // texels around ([tx], [ty]), exact on a texel.
  static (double, double, double, double) _linear(
    double tx,
    double ty,
    (double, double, double, double) Function(int, int) texel,
  ) {
    final x0 = tx.floor();
    final y0 = ty.floor();
    final fx = tx - x0;
    final fy = ty - y0;
    var sum = (0.0, 0.0, 0.0, 0.0);
    for (final (dx, dy, weight) in [
      (0, 0, (1 - fx) * (1 - fy)),
      (1, 0, fx * (1 - fy)),
      (0, 1, (1 - fx) * fy),
      (1, 1, fx * fy),
    ]) {
      if (weight == 0) continue;
      final (r, g, b, a) = texel(x0 + dx, y0 + dy);
      sum = (
        sum.$1 + r * weight,
        sum.$2 + g * weight,
        sum.$3 + b * weight,
        sum.$4 + a * weight,
      );
    }
    return sum;
  }
}
