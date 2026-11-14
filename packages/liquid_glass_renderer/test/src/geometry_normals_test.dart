import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/rendering/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/geometry_tiling.dart';
import 'package:liquid_glass_renderer/src/rendering/shape_set.dart';

import 'gpu_test_helpers.dart';

const _expectFallback = bool.fromEnvironment('EXPECT_FLUTTER_GPU_FALLBACK');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'geometry normals are exact per pixel on tight curves',
    () async {
      final renderer = await FlutterGpuGeometryRenderer.fromAsset(
        'build/shaderbundles/liquid_glass_renderer.shaderbundle',
      );
      addTearDown(renderer.dispose);

      // A 12 px circle off the pixel grid. Normals from dFdx/dFdy of the
      // distance are shared by 2x2 quads and miss by up to ~50 degrees here.
      const radius = 12.0;
      const cx = 32.3;
      const cy = 31.7;
      final atlas = await AtlasTexels.read(
        renderer
            .renderAtlas(
              Tiling.shapes(
                ShapeSet.rows(
                  shapes: const [
                    2, 2 * radius, 2 * radius, 0, //
                    1, 0, 0, 1, //
                    cx, cy, 1, -1, //
                  ],
                  boxes: const [
                    cx - radius,
                    cy - radius,
                    cx + radius,
                    cy + radius,
                  ],
                ),
                width: 64,
                height: 64,
                reach: const GlassReach(inward: 20, outward: 2),
              ),
            )
            .image,
      );

      var worst = 0.0;
      var checked = 0;
      for (var y = 0; y < 64; y++) {
        for (var x = 0; x < 64; x++) {
          final (inward, nx, ny, _) = atlas.pixel(x, y);
          final dx = x + 0.5 - cx;
          final dy = y + 0.5 - cy;
          final r = math.sqrt(dx * dx + dy * dy);
          if (inward <= 0 || r < 3 || r > radius - 0.5) continue;
          // The stored direction may be shortened; only its angle matters here.
          final cosine =
              (nx * dx + ny * dy) / (math.sqrt(nx * nx + ny * ny) * r);
          worst = math.max(worst, math.acos(cosine.clamp(-1.0, 1.0)));
          checked++;
        }
      }

      expect(checked, greaterThan(300));
      expect(worst * 180 / math.pi, lessThan(1.5));
    },
    skip: _expectFallback,
  );
}
