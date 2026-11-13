import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/rendering/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/geometry_tiling.dart';
import 'package:liquid_glass_renderer/src/rendering/shape_set.dart';

import 'gpu_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const expectFallback = bool.fromEnvironment('EXPECT_FLUTTER_GPU_FALLBACK');
  test(
    'asset renderers share immutable pipeline resources',
    () async {
      final first = await createGeometryRenderer();
      final second = await createGeometryRenderer();

      expect(
        identical(first.debugPipelineIdentity, second.debugPipelineIdentity),
        isTrue,
      );

      renderTestRectangle(first);
      renderTestRectangle(second);
      expect(first.debugScratchBuffers, greaterThan(0));
      expect(first.debugScratchBuffers, second.debugScratchBuffers);
    },
    skip: expectFallback,
  );

  test(
    'bytes a pass reads are written over only once the GPU has run the pass',
    () async {
      final renderer = await createGeometryRenderer();
      // Passes the GPU has not run yet hold their bytes: the scratch grows
      // instead of writing over them.
      final before = renderer.debugScratchBuffers;
      var renders = 0;
      while (renderer.debugScratchBuffers < before + 2) {
        renderTestRectangle(renderer, centerX: 16.0 + renders % 7);
        renders++;
        expect(renders, lessThan(4000));
      }
      // Once the GPU has run them, the same amount of drawing fits in the
      // buffers there are. The first passes wait for their pipelines, so
      // how long that takes is not known.
      var reused = false;
      for (var round = 0; round < 100 && !reused; round++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final held = renderer.debugScratchBuffers;
        for (var index = 0; index < renders; index++) {
          renderTestRectangle(renderer, centerX: 16.0 + index % 7);
        }
        reused = renderer.debugScratchBuffers == held;
      }
      expect(reused, isTrue);
    },
    skip: expectFallback,
  );

  test(
    'a new atlas releases the image of the last, which scenes hold',
    () async {
      final renderer = await createGeometryRenderer();

      ui.Image render(int size) => renderer
          .renderAtlas(
            Tiling.shapes(
              testRectangle(),
              width: size,
              height: size,
              reach: testReach,
            ),
          )
          .image;

      final first = render(33);
      final larger = render(130);
      final smallerAgain = render(32);

      expect(identical(first, larger), isFalse);
      expect(first.debugDisposed, isTrue);
      expect(larger.debugDisposed, isTrue);
      expect(smallerAgain.debugDisposed, isFalse);
    },
    skip: expectFallback,
  );

  test(
    'geometry image keeps asymmetric rows in top-down order',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final renderer = await createGeometryRenderer();

      final image = renderer
          .renderAtlas(
            Tiling.shapes(
              ShapeSet.rows(
                shapes: const [
                  1, 20, 20, 0, // Narrow rectangle on the top row.
                  1, 0, 0, 1,
                  32, 16, 1, -1,
                  1, 50, 20, 0, // Wide rectangle on the bottom row.
                  1, 0, 0, 1,
                  32, 48, 1, -1,
                ],
                boxes: const [22, 6, 42, 26, 7, 38, 57, 58],
              ),
              width: 64,
              height: 64,
              reach: testReach,
            ),
          )
          .image;
      final atlas = await AtlasTexels.read(image);

      expect(
        atlas.inwardAt(10, 16),
        lessThan(0),
        reason: 'top row must stay narrow',
      );
      expect(
        atlas.inwardAt(10, 48),
        greaterThan(0),
        reason: 'bottom row must be wide',
      );
    },
    skip: expectFallback,
  );

  test(
    'shared host buffer handles more than 32 layer submissions per frame',
    () async {
      final renderers = await Future.wait(
        List.generate(40, (_) => createGeometryRenderer()),
      );

      ui.Image? finalImage;
      for (var i = 0; i < renderers.length; i++) {
        finalImage = renderTestRectangle(
          renderers[i],
          centerX: i.isEven ? 16 : 17,
        );
      }

      final atlas = await AtlasTexels.read(finalImage!);
      expect(atlas.inwardAt(17, 32), greaterThan(0));
    },
    skip: expectFallback,
  );
}
