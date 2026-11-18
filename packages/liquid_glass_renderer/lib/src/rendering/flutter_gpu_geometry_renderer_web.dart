import 'package:flutter/foundation.dart';

import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/rendering/atlas_lease.dart';
import 'package:liquid_glass_renderer/src/rendering/geometry_tiling.dart';

/// Web stand-in for the geometry shader bundle: the web has no
/// `flutter_gpu`, so none loads.
@internal
abstract final class GeometryBundle {
  /// Always fails on the web.
  static Future<GeometryBundle> load(String assetKey) =>
      Future<GeometryBundle>.error(
        UnsupportedError('Flutter GPU is not available on the web.'),
      );

  /// Throws: no bundle loads on the web to say what GPU it runs on.
  LiquidGlassDeviceClass get deviceClass =>
      throw UnsupportedError('Flutter GPU is not available on the web.');
}

/// Web stand-in for the Flutter GPU geometry renderer: the web has no
/// `flutter_gpu`, and every entry point that would submit GPU work throws.
///
/// It names only what the library calls; the native renderer's debug
/// counters are read by host tests, which run native.
class FlutterGpuGeometryRenderer {
  /// Throws: no bundle loads on the web for a renderer to draw with.
  factory FlutterGpuGeometryRenderer(GeometryBundle bundle) =>
      throw UnsupportedError(
        'Flutter GPU is not available on the web; $bundle draws nothing.',
      );

  FlutterGpuGeometryRenderer._();

  /// Nothing is ever drawn on the web.
  static void flush() {}

  /// Does nothing on the web.
  void releaseAtlas() {}

  /// Does nothing on the web.
  void dispose() {}
}

/// A web renderer for a host test: the web build itself never makes one.
@visibleForTesting
FlutterGpuGeometryRenderer debugWebGeometryRenderer() =>
    FlutterGpuGeometryRenderer._();

/// The renderer's atlas, which only the rendering library draws and reads.
extension FlutterGpuGeometryRendererAtlas on FlutterGpuGeometryRenderer {
  /// Throws: the web has no Flutter GPU.
  AtlasLease renderAtlas(Tiling tiling) =>
      throw UnsupportedError('Flutter GPU is not available on the web.');
}
