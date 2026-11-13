import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/rendering/flutter_gpu_geometry_renderer_members.dart';
import 'package:liquid_glass_renderer/src/rendering/geometry_tiling.dart';

/// Web stand-in for the Flutter GPU geometry renderer: the web has no
/// `flutter_gpu`, and every entry point that would submit GPU work throws.
class FlutterGpuGeometryRenderer implements GeometryRendererMembers {
  FlutterGpuGeometryRenderer._();

  /// Always fails on the web; callers fall back to fake glass.
  static Future<FlutterGpuGeometryRenderer> fromAsset(String assetKey) =>
      Future<FlutterGpuGeometryRenderer>.error(
        UnsupportedError('Flutter GPU is not available on the web.'),
      );

  /// Nothing is ever cached on the web.
  static FlutterGpuGeometryRenderer? tryCreateCached(String assetKey) => null;

  /// The web has no shader filters.
  @override
  LiquidGlassDeviceClass get deviceClass =>
      LiquidGlassDeviceClass.noShaderFilters;

  /// Always 0: nothing is drawn on the web.
  static int get debugTotalRenderCount => 0;

  /// Always 0: no renderer exists on the web.
  static int get debugActiveRendererCount => 0;

  /// Always 0: no atlas exists on the web.
  static int get debugActiveGeometryTextureCount => 0;

  /// Matches the native renderer's reuse horizon; nothing is reused here.
  static const int reuseAfterFrames = 1;

  /// Never counts on the web.
  static int debugReusedTextureCount = 0;

  /// Never counts on the web.
  static int debugAllocatedTextureCount = 0;

  /// Never counts on the web.
  static int debugDroppedTextureCount = 0;

  /// Nothing is ever drawn on the web.
  static void flush() {}

  /// Does nothing on the web.
  static void debugResetPages() {}

  /// Never counts on the web.
  static int debugBatchedSubmitCount = 0;

  /// Never counts on the web.
  static int debugDeferredPassCount = 0;

  /// Never counts on the web.
  static int debugPostFrameFlushCount = 0;

  /// Always null on the web.
  @override
  Object? get debugMatteTexture => null;

  /// Always null on the web.
  @override
  (int, int)? get debugMatteTextureSize => null;

  /// Nothing is drawn on the web, so nothing is left out.
  @override
  int get droppedShapes => 0;

  /// Never counts on the web.
  @override
  int debugRenderCount = 0;

  /// The renderer itself: there is no pipeline on the web.
  @override
  Object get debugPipelineIdentity => this;

  /// Always 0 on the web.
  @override
  int get debugScratchBuffers => 0;

  /// Always true: a web renderer holds nothing.
  @override
  bool get debugDisposed => true;

  /// Always null on the web.
  @override
  ui.Image? get atlasImage => null;

  /// Always empty on the web.
  @override
  List<ui.Image> get lookImages => const [];

  /// Does nothing on the web.
  @override
  void releaseAtlas() {}

  /// Does nothing on the web.
  @override
  void releaseOutput() {}

  /// Does nothing on the web.
  @override
  void dispose() {}
}

/// A web renderer for a host test: the web build itself never makes one.
@visibleForTesting
FlutterGpuGeometryRenderer debugWebGeometryRenderer() =>
    FlutterGpuGeometryRenderer._();

/// The renderer's atlas, which only the rendering library draws and reads.
extension FlutterGpuGeometryRendererAtlas on FlutterGpuGeometryRenderer {
  /// Always null on the web.
  AtlasPlace? get atlasPlace => null;

  /// Throws: the web has no Flutter GPU.
  ({ui.Image image, List<ui.Image> looks, AtlasPlace place}) renderAtlas(
    Tiling tiling,
  ) => throw UnsupportedError('Flutter GPU is not available on the web.');
}
