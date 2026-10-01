import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  runGpuImageOwnershipTests();
}

/// Also runs directly on the device, without a second scene traversal.
void runGpuImageOwnershipTests() {
  testWidgets(
    'cloned geometry and material survive replacement and disposal',
    (tester) async {
      await tester.runAsync(() async {
        final renderer = await FlutterGpuGeometryRenderer.fromAsset(
          ShaderKeys.gpuGeometryShaderBundle,
        );
        addTearDown(renderer.dispose);
        final initialCount = FlutterGpuGeometryRenderer.debugTotalRenderCount;

        ({ui.Image image, int width, int height}) render(int index) {
          final appearances = List<double>.filled(128, 0);
          for (var shape = 0; shape < 16; shape++) {
            appearances[shape * 4 + (index.isEven ? 0 : 1)] = 1;
            appearances[shape * 4 + 3] = 1;
            appearances[64 + shape * 4] = 0.25;
            appearances[64 + shape * 4 + 1] = 0.25;
            appearances[64 + shape * 4 + 3] = 0.2;
          }
          return renderer.render(
            width: 64,
            height: 64,
            shapeData: [
              1,
              20,
              30,
              4,
              1,
              0,
              0,
              1,
              16.0 + index * 3,
              32,
              1,
              -1,
            ],
            numShapes: 1,
            opticalIndex: 1.2,
            thickness: 10,
            offsetX: 0,
            offsetY: 0,
            writeMaterials: true,
            appearanceData: appearances,
          );
        }

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
        final originalMaterial = renderer.materialImage!;
        final geometry = first.image.clone();
        final material = originalMaterial.clone();
        addTearDown(geometry.dispose);
        addTearDown(material.dispose);
        expect(geometry.isCloneOf(first.image), isTrue);
        expect(material.isCloneOf(originalMaterial), isTrue);
        final originalGeometryPixels = await pixels(geometry);
        final originalMaterialPixels = await pixels(material);

        // Queue several immutable replacements without a readback between them.
        late ui.Image latest;
        for (var index = 1; index <= 7; index++) {
          latest = render(index).image;
        }
        expect(first.image.debugDisposed, isTrue);
        expect(originalMaterial.debugDisposed, isTrue);
        expect(
          await pixels(latest),
          isNot(orderedEquals(originalGeometryPixels)),
        );
        expect(
          await pixels(renderer.materialImage!),
          isNot(orderedEquals(originalMaterialPixels)),
        );
        renderer.releaseOutput();
        expect(latest.debugDisposed, isTrue);
        expect(renderer.debugDisposed, isFalse);
        expect(await pixels(geometry), orderedEquals(originalGeometryPixels));
        expect(await pixels(material), orderedEquals(originalMaterialPixels));
        final afterRelease = render(8);
        expect(afterRelease.image.debugDisposed, isFalse);
        renderer.dispose();
        expect(afterRelease.image.debugDisposed, isTrue);

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
