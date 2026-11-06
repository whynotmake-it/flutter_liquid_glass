import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';

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
      const scale = 2;
      final result = renderer.render(
        width: 64,
        height: 64,
        shapeData: const [
          2, 2 * radius, 2 * radius, 0, //
          1, 0, 0, 1, //
          cx, cy, 1, -1, //
        ],
        numShapes: 1,
        refractionHeight: 20,
        refractionAmount: 60,
        offsetX: 0,
        offsetY: 0,
        matteScale: scale,
      );
      final field = await readGeometryField(result.image);

      // Texel (i, j) is computed at the center of matte pixel (i * scale,
      // j * scale).
      var worst = 0.0;
      var checked = 0;
      for (var j = 0; j <= 64 ~/ scale; j++) {
        for (var i = 0; i <= 64 ~/ scale; i++) {
          final k = (j * result.textureWidth + i) * 4;
          final dx = i * scale + 0.5 - cx;
          final dy = j * scale + 0.5 - cy;
          final r = math.sqrt(dx * dx + dy * dy);
          if (field[k] <= 0 || r < 3 || r > radius - 0.5) continue;
          // The stored direction may be shortened; only its angle matters here.
          final nx = field[k + 1];
          final ny = field[k + 2];
          final cosine =
              (nx * dx + ny * dy) / (math.sqrt(nx * nx + ny * ny) * r);
          worst = math.max(worst, math.acos(cosine.clamp(-1.0, 1.0)));
          checked++;
        }
      }

      expect(checked, greaterThan(80));
      expect(worst * 180 / math.pi, lessThan(1.5));
    },
    skip: _expectFallback,
  );
}
