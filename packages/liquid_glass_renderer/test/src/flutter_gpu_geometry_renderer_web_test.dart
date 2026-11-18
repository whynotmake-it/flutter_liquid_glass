import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/rendering/flutter_gpu_geometry_renderer_native.dart'
    as native;
import 'package:liquid_glass_renderer/src/rendering/flutter_gpu_geometry_renderer_web.dart'
    as web;

// Compiling this file on the host keeps the web stub compiling, and naming
// each member the library calls on both classes keeps their names in step.
void main() {
  test('the web stub is fake glass with nothing drawn', () async {
    web.debugWebGeometryRenderer()
      ..releaseAtlas()
      ..dispose();
    web.FlutterGpuGeometryRenderer.flush();

    await expectLater(web.GeometryBundle.load('any'), throwsUnsupportedError);
  });

  test('the web stub names every member the library calls', () {
    final pairs = <(Object, Object)>[
      (web.GeometryBundle.load, native.GeometryBundle.load),
      (
        (web.GeometryBundle bundle) => bundle.deviceClass,
        (native.GeometryBundle bundle) => bundle.deviceClass,
      ),
      (
        web.FlutterGpuGeometryRenderer.new,
        native.FlutterGpuGeometryRenderer.new,
      ),
      (
        web.FlutterGpuGeometryRenderer.flush,
        native.FlutterGpuGeometryRenderer.flush,
      ),
      (
        (web.FlutterGpuGeometryRenderer r) => r.releaseAtlas,
        (native.FlutterGpuGeometryRenderer r) => r.releaseAtlas,
      ),
      (
        (web.FlutterGpuGeometryRenderer r) => r.dispose,
        (native.FlutterGpuGeometryRenderer r) => r.dispose,
      ),
      (
        (web.FlutterGpuGeometryRenderer r) => r.renderAtlas,
        (native.FlutterGpuGeometryRenderer r) => r.renderAtlas,
      ),
    ];
    expect(pairs, hasLength(7));
  });
}
