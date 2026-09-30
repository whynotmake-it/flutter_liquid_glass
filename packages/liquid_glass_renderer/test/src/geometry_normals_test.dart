import 'dart:math' as math;

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';

const _expectFallback = bool.fromEnvironment('EXPECT_FLUTTER_GPU_FALLBACK');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'geometry normals are exact per pixel on tight curves',
    () async {
      final library = (await gpu.ShaderLibrary.fromAsset(
        'build/shaderbundles/liquid_glass_renderer.shaderbundle',
      ))!;
      final renderer = FlutterGpuGeometryRenderer(
        vertexShader: library['GeometryVertex']!,
        fragmentShader: library['GeometryFragment']!,
      );
      addTearDown(renderer.dispose);

      // A 12 px circle off the pixel grid. Normals from dFdx/dFdy of the
      // distance are shared by 2x2 quads and miss by up to ~50 degrees here.
      const radius = 12.0;
      const cx = 32.3;
      const cy = 31.7;
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
      );
      final bytes = (await result.image.toByteData())!;

      var worst = 0.0;
      var checked = 0;
      for (var y = 0; y < 64; y++) {
        for (var x = 0; x < 64; x++) {
          final i = (y * result.width + x) * 4;
          final dx = x + 0.5 - cx;
          final dy = y + 0.5 - cy;
          final r = math.sqrt(dx * dx + dy * dy);
          if (bytes.getUint8(i + 2) < 128 || r < 3 || r > radius - 0.5) {
            continue;
          }
          // Diamond-angle normal code, as decodeSurfaceNormal in
          // displacement_encoding.glsl.
          final diamond =
              (bytes.getUint8(i) * 16 + (bytes.getUint8(i + 1) >> 4)) / 1024;
          final nx = diamond < 2 ? 1 - diamond : diamond - 3;
          final ny = diamond < 1
              ? diamond
              : (diamond < 3 ? 2 - diamond : diamond - 4);
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
