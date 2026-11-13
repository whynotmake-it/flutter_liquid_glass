import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/painting.dart';

/// The instance members of `FlutterGpuGeometryRenderer`, declared once for
/// the native class and its web stand-in, which both implement it: a member
/// one has and the other lacks does not compile.
///
/// Static members and the atlas extension cannot be declared here; the host
/// test `flutter_gpu_geometry_renderer_web_test.dart` names each of them on
/// both classes instead.
@internal
abstract interface class GeometryRendererMembers {
  /// The class of the GPU the renderer draws on.
  LiquidGlassDeviceClass get deviceClass;

  /// The texture of the page holding the latest atlas, compared by identity
  /// in tests.
  @visibleForTesting
  Object? get debugMatteTexture;

  /// Size of the page holding the latest atlas.
  @visibleForTesting
  (int, int)? get debugMatteTextureSize;

  /// How many shapes the latest atlas left out.
  int get droppedShapes;

  /// Number of atlases rendered.
  @visibleForTesting
  int get debugRenderCount;

  /// The geometry pipeline, which renderers of one bundle share.
  @visibleForTesting
  Object get debugPipelineIdentity;

  /// How many host-visible buffers the scratch every renderer shares
  /// holds for quads and uniform blocks.
  @visibleForTesting
  int get debugScratchBuffers;

  /// Whether [dispose] ran.
  @visibleForTesting
  bool get debugDisposed;

  /// The latest geometry atlas, in the page it shares.
  ui.Image? get atlasImage;

  /// The looks beside the latest atlas.
  List<ui.Image> get lookImages;

  /// Lets go of the latest atlas.
  void releaseAtlas();

  /// Releases the latest atlas and the field textures, keeping the
  /// pipelines.
  void releaseOutput();

  /// Releases the current output and retires this renderer.
  void dispose();
}
