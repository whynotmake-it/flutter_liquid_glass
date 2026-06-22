import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('flutter_gpu shader bundle loads', () {
    // When running within the package, the asset path is relative.
    // When used as a dependency, it's prefixed with packages/liquid_glass_renderer/
    gpu.ShaderLibrary? library;
    try {
      library = gpu.ShaderLibrary.fromAsset(
        'build/shaderbundles/liquid_glass_renderer.shaderbundle',
      );
    } catch (_) {
      library = gpu.ShaderLibrary.fromAsset(
        'packages/liquid_glass_renderer/build/shaderbundles/'
        'liquid_glass_renderer.shaderbundle',
      );
    }
    expect(library, isNotNull);
    final vertexShader = library!['GeometryVertex'];
    final fragmentShader = library['GeometryTestFragment'];
    expect(vertexShader, isNotNull);
    expect(fragmentShader, isNotNull);
  });
}
