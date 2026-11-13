import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/rendering/flutter_gpu_geometry_renderer_members.dart';
import 'package:liquid_glass_renderer/src/rendering/flutter_gpu_geometry_renderer_native.dart'
    as native;
import 'package:liquid_glass_renderer/src/rendering/flutter_gpu_geometry_renderer_web.dart'
    as web;

// Compiling this file on the host keeps the web stub compiling, and naming
// each static and atlas member on both classes keeps their names in step:
// `GeometryRendererMembers` covers only the instance members.
void main() {
  test('the web stub is fake glass with nothing drawn', () async {
    final GeometryRendererMembers renderer = web.debugWebGeometryRenderer();

    expect(renderer.deviceClass, LiquidGlassDeviceClass.noShaderFilters);
    expect(renderer.debugMatteTexture, isNull);
    expect(renderer.debugMatteTextureSize, isNull);
    expect(renderer.droppedShapes, 0);
    expect(renderer.debugRenderCount, 0);
    expect(renderer.debugPipelineIdentity, same(renderer));
    expect(renderer.debugScratchBuffers, 0);
    expect(renderer.debugDisposed, isTrue);
    expect(renderer.atlasImage, isNull);
    expect(renderer.lookImages, isEmpty);
    renderer
      ..releaseAtlas()
      ..releaseOutput()
      ..dispose();

    await expectLater(
      web.FlutterGpuGeometryRenderer.fromAsset('any'),
      throwsUnsupportedError,
    );
    expect(web.FlutterGpuGeometryRenderer.tryCreateCached('any'), isNull);
  });

  test('the web stub names every static and atlas member of the native '
      'renderer', () {
    final pairs = <(Object, Object)>[
      (
        web.FlutterGpuGeometryRenderer.fromAsset,
        native.FlutterGpuGeometryRenderer.fromAsset,
      ),
      (
        web.FlutterGpuGeometryRenderer.tryCreateCached,
        native.FlutterGpuGeometryRenderer.tryCreateCached,
      ),
      (
        web.FlutterGpuGeometryRenderer.debugTotalRenderCount,
        native.FlutterGpuGeometryRenderer.debugTotalRenderCount,
      ),
      (
        web.FlutterGpuGeometryRenderer.debugActiveRendererCount,
        native.FlutterGpuGeometryRenderer.debugActiveRendererCount,
      ),
      (
        web.FlutterGpuGeometryRenderer.debugActiveGeometryTextureCount,
        native.FlutterGpuGeometryRenderer.debugActiveGeometryTextureCount,
      ),
      (
        web.FlutterGpuGeometryRenderer.reuseAfterFrames,
        native.FlutterGpuGeometryRenderer.reuseAfterFrames,
      ),
      (
        web.FlutterGpuGeometryRenderer.debugReusedTextureCount,
        native.FlutterGpuGeometryRenderer.debugReusedTextureCount,
      ),
      (
        web.FlutterGpuGeometryRenderer.debugAllocatedTextureCount,
        native.FlutterGpuGeometryRenderer.debugAllocatedTextureCount,
      ),
      (
        web.FlutterGpuGeometryRenderer.debugDroppedTextureCount,
        native.FlutterGpuGeometryRenderer.debugDroppedTextureCount,
      ),
      (
        web.FlutterGpuGeometryRenderer.flush,
        native.FlutterGpuGeometryRenderer.flush,
      ),
      (
        web.FlutterGpuGeometryRenderer.debugResetPages,
        native.FlutterGpuGeometryRenderer.debugResetPages,
      ),
      (
        web.FlutterGpuGeometryRenderer.debugBatchedSubmitCount,
        native.FlutterGpuGeometryRenderer.debugBatchedSubmitCount,
      ),
      (
        web.FlutterGpuGeometryRenderer.debugDeferredPassCount,
        native.FlutterGpuGeometryRenderer.debugDeferredPassCount,
      ),
      (
        web.FlutterGpuGeometryRenderer.debugPostFrameFlushCount,
        native.FlutterGpuGeometryRenderer.debugPostFrameFlushCount,
      ),
      (
        (web.FlutterGpuGeometryRenderer r) => r.atlasPlace,
        (native.FlutterGpuGeometryRenderer r) => r.atlasPlace,
      ),
      (
        (web.FlutterGpuGeometryRenderer r) => r.renderAtlas,
        (native.FlutterGpuGeometryRenderer r) => r.renderAtlas,
      ),
    ];
    expect(pairs, hasLength(16));
    expect(
      web.FlutterGpuGeometryRenderer.reuseAfterFrames,
      native.FlutterGpuGeometryRenderer.reuseAfterFrames,
    );
  });
}
