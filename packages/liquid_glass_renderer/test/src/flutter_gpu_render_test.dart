import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const expectFallback = bool.fromEnvironment('EXPECT_FLUTTER_GPU_FALLBACK');
  test(
    'flutter_gpu renders to a persistent texture and produces a valid image',
    () {
      final library = gpu.ShaderLibrary.fromAsset(
        'build/shaderbundles/liquid_glass_renderer.shaderbundle',
      );
      expect(library, isNotNull);

      final vertexShader = library!['GeometryVertex'];
      final fragmentShader = library['GeometryTestFragment'];
      expect(vertexShader, isNotNull);
      expect(fragmentShader, isNotNull);

      final pipeline = gpu.gpuContext.createRenderPipeline(
        vertexShader!,
        fragmentShader!,
      );

      const width = 256;
      const height = 256;

      final texture = gpu.gpuContext.createTexture(
        gpu.StorageMode.devicePrivate,
        width,
        height,
      );
      expect(texture.isValid, isTrue);

      final renderTarget = gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(texture: texture),
      );

      // Full-screen triangle strip: position.xy, texCoord.xy per vertex.
      final vertices = Float32List.fromList([
        -1.0, -1.0, 0.0, 0.0, //
        1.0, -1.0, 1.0, 0.0, //
        -1.0, 1.0, 0.0, 1.0, //
        1.0, 1.0, 1.0, 1.0, //
      ]);

      final vertexBuffer = gpu.gpuContext.createDeviceBufferWithCopy(
        ByteData.sublistView(vertices),
      );
      expect(vertexBuffer.isValid, isTrue);

      final commandBuffer = gpu.gpuContext.createCommandBuffer();
      commandBuffer.createRenderPass(renderTarget)
        ..bindPipeline(pipeline)
        ..bindVertexBuffer(
          gpu.BufferView(
            vertexBuffer,
            offsetInBytes: 0,
            lengthInBytes: vertices.lengthInBytes,
          ),
          4,
        )
        ..draw();
      commandBuffer.submit();

      final image = texture.asImage();
      expect(image.width, equals(width));
      expect(image.height, equals(height));
    },
    skip: expectFallback,
  );

  test(
    'asset renderers share immutable pipeline resources',
    () {
      final first = FlutterGpuGeometryRenderer.fromAsset(
        'build/shaderbundles/liquid_glass_renderer.shaderbundle',
      );
      final second = FlutterGpuGeometryRenderer.fromAsset(
        'build/shaderbundles/liquid_glass_renderer.shaderbundle',
      );
      addTearDown(first.dispose);
      addTearDown(second.dispose);

      expect(
        identical(first.debugPipelineIdentity, second.debugPipelineIdentity),
        isTrue,
      );

      const unusedShape = <double>[
        1, 8, 8, 0, //
        1, 0, 0, 1, //
        8, 8, 1, -1, //
      ];
      first.render(
        width: 16,
        height: 16,
        shapeData: unusedShape,
        numShapes: 1,
        refractiveIndex: 1.2,
        thickness: 4,
        offsetX: 0,
        offsetY: 0,
      );

      expect(
        identical(
          first.debugHostBufferIdentity,
          second.debugHostBufferIdentity,
        ),
        isTrue,
      );
      expect(first.debugHostBufferBlockLength, greaterThan(0));
      expect(first.debugHostBufferBlockLength, lessThan(64 * 1024));
    },
    skip: expectFallback,
  );

  test(
    'geometry renderer buckets and reuses its native render target',
    () {
      final library = gpu.ShaderLibrary.fromAsset(
        'build/shaderbundles/liquid_glass_renderer.shaderbundle',
      )!;
      final renderer = FlutterGpuGeometryRenderer(
        vertexShader: library['GeometryVertex']!,
        fragmentShader: library['GeometryFragment']!,
      );
      addTearDown(renderer.dispose);

      ({ui.Image image, int width, int height}) render(int size) =>
          renderer.render(
            width: size,
            height: size,
            shapeData: const [
              1, 40, 30, 8, // Rounded rectangle.
              1, 0, 0, 1, // Identity inverse affine basis.
              32, 32, 1, -1, // Center, distance scale, new group marker.
            ],
            numShapes: 1,
            refractiveIndex: 1.2,
            thickness: 10,
            offsetX: 0,
            offsetY: 0,
          );

      final first = render(33);
      final sameBucket = render(63);
      final larger = render(65);
      final smallerAgain = render(32);

      expect((first.width, first.height), (64, 64));
      expect(identical(first.image, sameBucket.image), isTrue);
      expect((larger.width, larger.height), (128, 128));
      expect(identical(first.image, larger.image), isFalse);
      expect((smallerAgain.width, smallerAgain.height), (128, 128));
      expect(identical(larger.image, smallerAgain.image), isTrue);
    },
    skip: expectFallback,
  );

  test(
    'geometry image keeps asymmetric rows in top-down order',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final library = gpu.ShaderLibrary.fromAsset(
        'build/shaderbundles/liquid_glass_renderer.shaderbundle',
      )!;
      final renderer = FlutterGpuGeometryRenderer(
        vertexShader: library['GeometryVertex']!,
        fragmentShader: library['GeometryFragment']!,
      );
      addTearDown(renderer.dispose);

      final result = renderer.render(
        width: 64,
        height: 64,
        shapeData: const [
          1, 20, 20, 0, // Narrow rectangle on the top row.
          1, 0, 0, 1,
          32, 16, 1, -1,
          1, 50, 20, 0, // Wide rectangle on the bottom row.
          1, 0, 0, 1,
          32, 48, 1, -1,
        ],
        numShapes: 2,
        refractiveIndex: 1.2,
        thickness: 10,
        offsetX: 0,
        offsetY: 0,
      );
      final bytes = await result.image.toByteData();
      expect(bytes, isNotNull);

      int alphaAt(int x, int y) =>
          bytes!.getUint8((y * result.width + x) * 4 + 3);

      expect(alphaAt(10, 16), 0, reason: 'top row must stay narrow');
      expect(
        alphaAt(10, 48),
        greaterThan(0),
        reason: 'bottom row must be wide',
      );
    },
    skip: expectFallback,
  );

  test(
    'shared host buffer handles more than 32 layer submissions per frame',
    () async {
      const shape = <double>[
        1, 12, 8, 0,
        1, 0, 0, 1,
        8, 8, 1, -1,
      ];
      final renderers = List.generate(
        40,
        (_) => FlutterGpuGeometryRenderer.fromAsset(
          'build/shaderbundles/liquid_glass_renderer.shaderbundle',
        ),
      );
      addTearDown(() {
        for (final renderer in renderers) {
          renderer.dispose();
        }
      });

      ui.Image? finalImage;
      for (var i = 0; i < renderers.length; i++) {
        final result = renderers[i].render(
          width: 16,
          height: 16,
          shapeData: shape,
          numShapes: 1,
          refractiveIndex: 1.2,
          thickness: 4,
          offsetX: i.isEven ? 0 : 1,
          offsetY: 0,
        );
        finalImage = result.image;
      }

      final bytes = await finalImage!.toByteData();
      expect(bytes, isNotNull);
      expect(bytes!.lengthInBytes, greaterThan(0));
    },
    skip: expectFallback,
  );
}
