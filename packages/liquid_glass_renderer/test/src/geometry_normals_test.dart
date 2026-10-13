import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';

const _expectFallback = bool.fromEnvironment('EXPECT_FLUTTER_GPU_FALLBACK');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'geometry displacement follows the inward normal on tight curves',
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
      // The matte is fp16: channels R and G hold the displacement vector in
      // pixels, channel B the signed inward edge distance.
      final bytes = (await result.image.toByteData(
        format: ui.ImageByteFormat.rawExtendedRgba128,
      ))!;
      final pixels = Float32List.sublistView(bytes);

      var worst = 0.0;
      var checked = 0;
      for (var y = 0; y < 64; y++) {
        for (var x = 0; x < 64; x++) {
          final i = (y * result.width + x) * 4;
          final signedEdgeDistance = pixels[i + 2];
          final dx = x + 0.5 - cx;
          final dy = y + 0.5 - cy;
          final r = math.sqrt(dx * dx + dy * dy);
          // Only the bevel band refracts, and only pixels strictly inside
          // carry a usable inward distance.
          if (signedEdgeDistance <= 0 || r < 3 || r > radius - 0.5) {
            continue;
          }
          final disX = pixels[i];
          final disY = pixels[i + 1];
          final disLength = math.sqrt(disX * disX + disY * disY);
          if (disLength < 1e-3) continue;
          // The displacement points opposite the outward normal, so
          // -displacement should align with the radial direction.
          final cosine = -(disX * dx + disY * dy) / (disLength * r);
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
