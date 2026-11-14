import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/rendering/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/geometry_tiling.dart';

import 'gpu_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  runGpuImageOwnershipTests();
}

/// Also runs directly on the device, without a second scene traversal.
void runGpuImageOwnershipTests() {
  testWidgets(
    'cloned atlases and looks survive replacement and disposal',
    (tester) async {
      await tester.runAsync(() async {
        final renderer = await createGeometryRenderer();
        final initialCount = FlutterGpuGeometryRenderer.debugTotalRenderCount;

        ui.Image render(int index) => renderTestRectangle(
          renderer,
          centerX: 16.0 + index * 3,
          looks: ShapeLooks([
            if (index.isEven) 1 else 0,
            if (index.isEven) 0 else 1,
            0,
            1,
            1,
            1,
            0,
            1,
          ], tintOnly: false),
        );

        Future<Uint8List> pixels(ui.Image image) async {
          final bytes = await image.toByteData();
          expect(bytes, isNotNull);
          return Uint8List.fromList(
            bytes!.buffer.asUint8List(
              bytes.offsetInBytes,
              bytes.lengthInBytes,
            ),
          );
        }

        final first = render(0);
        final originalMaterial = renderer.lookImages.first;
        final geometry = first.clone();
        final material = originalMaterial.clone();
        addTearDown(geometry.dispose);
        addTearDown(material.dispose);
        expect(geometry.isCloneOf(first), isTrue);
        expect(material.isCloneOf(originalMaterial), isTrue);
        final originalGeometryPixels = await pixels(geometry);
        final originalMaterialPixels = await pixels(material);

        // Queue several immutable replacements without a readback between them.
        late ui.Image latest;
        for (var index = 1; index <= 7; index++) {
          latest = render(index);
        }
        expect(first.debugDisposed, isTrue);
        expect(originalMaterial.debugDisposed, isTrue);
        expect(
          await pixels(latest),
          isNot(orderedEquals(originalGeometryPixels)),
        );
        expect(
          await pixels(renderer.lookImages.first),
          isNot(orderedEquals(originalMaterialPixels)),
        );
        renderer.releaseOutput();
        expect(latest.debugDisposed, isTrue);
        expect(renderer.debugDisposed, isFalse);
        expect(await pixels(geometry), orderedEquals(originalGeometryPixels));
        expect(await pixels(material), orderedEquals(originalMaterialPixels));
        final afterRelease = render(8);
        expect(afterRelease.debugDisposed, isFalse);
        renderer.dispose();
        expect(afterRelease.debugDisposed, isTrue);

        expect(geometry.debugDisposed, isFalse);
        expect(material.debugDisposed, isFalse);
        expect(await pixels(geometry), orderedEquals(originalGeometryPixels));
        expect(await pixels(material), orderedEquals(originalMaterialPixels));
        expect(
          FlutterGpuGeometryRenderer.debugTotalRenderCount - initialCount,
          9,
        );
      });
    },
  );
}
