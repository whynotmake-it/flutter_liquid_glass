import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';

void main() {
  const expectFallback = bool.fromEnvironment('EXPECT_FLUTTER_GPU_FALLBACK');
  test('flutter_gpu shader bundle loads', () {
    final library = gpu.ShaderLibrary.fromAsset(
      'build/shaderbundles/liquid_glass_renderer.shaderbundle',
    );
    expect(library, isNotNull);
    final vertexShader = library!['GeometryVertex'];
    final fragmentShader = library['GeometryTestFragment'];
    expect(vertexShader, isNotNull);
    expect(fragmentShader, isNotNull);
  }, skip: expectFallback);

  test('flutter_gpu geometry shader pipeline can be created', () {
    final library = gpu.ShaderLibrary.fromAsset(
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
    expect(uniformSlot.getMemberOffsetInBytes('uSize'), isNotNull);
    expect(uniformSlot.getMemberOffsetInBytes('uOpticalProps'), isNotNull);
    expect(uniformSlot.getMemberOffsetInBytes('uNumShapes'), isNotNull);
    expect(uniformSlot.getMemberOffsetInBytes('uShapeData'), isNotNull);
  }, skip: expectFallback);
}
