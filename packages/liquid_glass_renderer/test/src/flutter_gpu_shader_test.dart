import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';

void main() {
  const expectFallback = bool.fromEnvironment('EXPECT_FLUTTER_GPU_FALLBACK');
  test('flutter_gpu shader bundle loads', () async {
    final library = await gpu.ShaderLibrary.fromAsset(
      'build/shaderbundles/liquid_glass_renderer.shaderbundle',
    );
    expect(library, isNotNull);
    final vertexShader = library!['GeometryVertex'];
    final fragmentShader = library['GeometryTestFragment'];
    expect(vertexShader, isNotNull);
    expect(fragmentShader, isNotNull);
  }, skip: expectFallback);

  test('flutter_gpu geometry shader pipeline can be created', () async {
    final library = await gpu.ShaderLibrary.fromAsset(
      'build/shaderbundles/liquid_glass_renderer.shaderbundle',
    );
    expect(library, isNotNull);

    final vertexShader = library!['GeometryVertex'];
    final geometryFragmentShader = library['GeometryFragment'];
    expect(vertexShader, isNotNull);
    expect(geometryFragmentShader, isNotNull);

    final pipeline = gpu.gpuContext.createRenderPipeline(
      vertexShader!,
      geometryFragmentShader!,
    );
    expect(pipeline, isNotNull);

    // Verify uniform slot reflection works
    final uniformSlot = geometryFragmentShader.getUniformSlot(
      'GeometryUniforms',
    );
    expect(uniformSlot.sizeInBytes, greaterThan(0));
    expect(uniformSlot.getMemberOffsetInBytes('uOffset'), isNotNull);
    expect(uniformSlot.getMemberOffsetInBytes('uTextureSize'), isNotNull);
    expect(uniformSlot.getMemberOffsetInBytes('uOpticalProps'), isNotNull);
    expect(uniformSlot.getMemberOffsetInBytes('uContourProps'), isNotNull);
    expect(uniformSlot.getMemberOffsetInBytes('uShapeData'), isNotNull);
  }, skip: expectFallback);
}
