import 'dart:ui' as ui;

import 'package:meta/meta.dart';

/// Web stand-in for the Flutter GPU geometry renderer.
///
/// Every entry point that would submit GPU work throws: the web has no
/// `flutter_gpu`, and real glass is not selected there because
/// `ImageFilter.isShaderFilterSupported` is false. Keeping the class shape
/// identical lets the render objects compile unchanged.
@internal
class FlutterGpuGeometryRenderer {
  FlutterGpuGeometryRenderer._();

  /// Always fails on the web; callers fall back to fake glass.
  static Future<FlutterGpuGeometryRenderer> fromAsset(String assetKey) =>
      Future<FlutterGpuGeometryRenderer>.error(
        UnsupportedError('Flutter GPU is not available on the web.'),
      );

  static int get debugTotalRenderCount => 0;
  static int get debugActiveRendererCount => 0;
  static int get debugActiveGeometryTextureCount => 0;
  static int get debugActiveMaterialTextureCount => 0;

  /// Material map texels per matte pixel; shared constant with the native
  /// renderer so uniform math stays identical.
  static const int materialRasterScale = 8;

  int debugRenderCount = 0;
  Object get debugPipelineIdentity => this;
  int get debugHostBufferBlockLength => 0;
  Object? get debugHostBufferIdentity => null;
  bool get debugDisposed => true;
  ui.Image? get materialImage => null;

  // ignore: avoid_unused_constructor_parameters
  ({ui.Image image, int width, int height}) render({
    required int width,
    required int height,
    required List<double> shapeData,
    required int numShapes,
    required double opticalIndex,
    required double thickness,
    required double offsetX,
    required double offsetY,
    double refractionSpread = 0.0,
    double? displacementScale,
    double contourExtent = 0.5,
    bool writeMaterials = false,
    bool writeTintOnly = false,
    List<double> appearanceData = const <double>[],
    List<double> rseData = const <double>[],
  }) =>
      throw UnsupportedError('Flutter GPU is not available on the web.');

  void releaseOutput() {}

  void dispose() {}
}

/// Web stand-in for the allocation diagnostics; always disabled.
@internal
class GpuAllocationDiagnostics {
  static int filterRecoveryHits = 0;
  static int filterRecoveryMisses = 0;
  static const enabled = false;
  static final allocations = <String>[];

  static void observe(String kind, Object value) {}

  static Map<String, Object> snapshot() => const {};
}
