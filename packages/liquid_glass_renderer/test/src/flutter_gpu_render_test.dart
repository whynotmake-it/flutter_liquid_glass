import 'dart:typed_data';

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('flutter_gpu renders to a persistent texture and produces a valid image', () {
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
      enableRenderTargetUsage: true,
      enableShaderReadUsage: true,
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
    final renderPass = commandBuffer.createRenderPass(renderTarget);
    renderPass.bindPipeline(pipeline);
    renderPass.bindVertexBuffer(
      gpu.BufferView(
        vertexBuffer,
        offsetInBytes: 0,
        lengthInBytes: vertices.lengthInBytes,
      ),
      4,
    );
    renderPass.draw();
    commandBuffer.submit();

    final image = texture.asImage();
    expect(image.width, equals(width));
    expect(image.height, equals(height));
  });
}
