import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:liquid_glass_renderer/composer.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/rendering/final_shader_variant.dart';
import 'package:liquid_glass_renderer/src/rendering/flutter_gpu_geometry_renderer_members.dart';
import 'package:liquid_glass_renderer/src/rendering/geometry_tiling.dart';
import 'package:liquid_glass_renderer/src/rendering/shape_set.dart';
import 'package:vector_math/vector_math.dart' as vm;

part 'package:liquid_glass_renderer/src/rendering/flutter_gpu_geometry_renderer_native_pages.dart';
part 'package:liquid_glass_renderer/src/rendering/flutter_gpu_geometry_renderer_native_quads.dart';
part 'package:liquid_glass_renderer/src/rendering/flutter_gpu_geometry_renderer_native_resources.dart';

/// The edge distance of a geometry atlas's outside tile and of its texels
/// far from every shape: `kFarInward` in `matte_encoding.glsl`.
@internal
const double kFarInward = -4096;

/// The edge distance of a geometry atlas's deep tile: past every inward
/// reach, and within a 16-bit float.
@internal
const double kDeepInward = 4096;

/// Floats per instance of tile_vertex.glsl: rectangle, value and ramp.
const int _quadFloats = 12;

/// What an atlas pass writes beside the atlas, by [Tiling.looks]: no look,
/// the tint, or the whole look (look_targets.glsl).
enum _LookTargets {
  none(0, ''),
  tint(1, 'Tint'),
  all(3, 'Looks');

  const _LookTargets(this.count, this.shaderSuffix);

  factory _LookTargets.of(ShapeLooks? looks) => switch (looks) {
    null => none,
    ShapeLooks(tintOnly: true) => tint,
    _ => all,
  };

  /// The look textures written.
  final int count;

  /// What the atlas shaders' names end in, before `Fragment`.
  final String shaderSuffix;
}

/// What the backend of the Flutter GPU context does differently from the
/// others, in the one place the renderer reads it from.
///
/// Flutter GPU names no backend, so Impeller's OpenGL ES backend is told
/// by a capability it lacks: rendering into a mip level. Everything here
/// follows from that backend. Read it only once the engine has created the
/// context: reading the context earlier blocks the UI thread on Android.
abstract final class _GpuBackend {
  /// Whether the context draws with Impeller's OpenGL ES backend.
  static final bool openGLES =
      !gpu.gpuContext.doesSupportFramebufferRenderMipmap;

  /// Whether a pass draws into one color attachment alone: a pass with
  /// more aborts the process there, so an atlas with looks takes a pass a
  /// target (`_SharedGeometryResources.onePerTarget`).
  static bool get oneColorAttachmentPerPass => openGLES;

  /// Whether a texture carries one filter for every sampler it is bound
  /// to, so that the atlas's table is bound filtered as its strips are
  /// ([atlasTableFilter]).
  static bool get oneFilterPerTexture => openGLES;

  // Also true of that backend, and held in the shaders instead of read
  // here: a runtime effect has no `texelFetch` (IMPELLER_TARGET_OPENGLES in
  // the final shaders).
}

const _tileVertexLayout = gpu.VertexLayout(
  buffers: [
    gpu.VertexBuffer(
      strideInBytes: 8,
      attributes: [
        gpu.VertexAttribute(name: 'corner', format: gpu.VertexFormat.float32x2),
      ],
    ),
    gpu.VertexBuffer(
      strideInBytes: _quadFloats * 4,
      stepMode: gpu.VertexStepMode.instance,
      attributes: [
        gpu.VertexAttribute(name: 'rect', format: gpu.VertexFormat.float32x4),
        gpu.VertexAttribute(
          name: 'value',
          format: gpu.VertexFormat.float32x4,
          offsetInBytes: 16,
        ),
        gpu.VertexAttribute(
          name: 'ramp',
          format: gpu.VertexFormat.float32x4,
          offsetInBytes: 32,
        ),
      ],
    ),
  ],
);

/// Renders liquid glass geometry atlases (geometry_tiling.dart) and the
/// looks beside them using flutter_gpu.
///
/// The atlases placed between two flushes share a page: one texture, drawn
/// in one pass and submitted once ([flush]). A renderer holds one atlas,
/// its latest, and with it the page: nothing draws over a page while a
/// renderer holds an atlas in it, nor for [reuseAfterFrames] frames after,
/// while the scenes that read it may still be drawn.
///
/// The image handles are the pages', disposed once every atlas of a page
/// is released. Recorded scenes hold independent native references; a
/// scene rasterized more than [reuseAfterFrames] frames after its atlas was
/// released may show other atlases.
class FlutterGpuGeometryRenderer implements GeometryRendererMembers {
  factory FlutterGpuGeometryRenderer._fromResolved(
    String assetKey,
    _SharedGeometryResources resources,
  ) {
    try {
      return FlutterGpuGeometryRenderer._fromShared(resources);
    } on Object {
      // Drop resources that failed to build a renderer so the next layer
      // reloads the bundle instead of failing the same way.
      if (identical(_resolvedAssetResources[assetKey], resources)) {
        _resolvedAssetResources.remove(assetKey);
      }
      rethrow;
    }
  }

  FlutterGpuGeometryRenderer._fromShared(this._resources)
    : assert(() {
        _debugActiveRendererCount++;
        return true;
      }(), 'Track live geometry renderers in debug builds.');

  /// The class of the GPU the Flutter GPU context runs on, read from its
  /// capabilities: the backend as [_GpuBackend] tells it, and ASTC HDR,
  /// which starts at the A13 (Apple6). A renderer exists only once the
  /// engine has created the context; reading it earlier blocks the UI
  /// thread on Android.
  @override
  LiquidGlassDeviceClass get deviceClass {
    final context = gpu.gpuContext;
    if (_GpuBackend.openGLES) {
      // Only an Android device without a usable Vulkan driver is short of
      // GPU on OpenGL ES; a desktop has plenty.
      return Platform.isAndroid
          ? LiquidGlassDeviceClass.gles
          : LiquidGlassDeviceClass.capable;
    }
    if (Platform.isIOS &&
        !context.supportsTextureCompression(
          gpu.TextureCompressionFamily.astcHdr,
        )) {
      return LiquidGlassDeviceClass.appleBeforeA13;
    }
    return LiquidGlassDeviceClass.capable;
  }

  /// Loads the geometry shader bundle at [assetKey] and creates a renderer on
  /// it; a later call for the same bundle reuses what the first one loaded.
  static Future<FlutterGpuGeometryRenderer> fromAsset(String assetKey) async {
    if (_resolvedAssetResources[assetKey] case final resources?) {
      return FlutterGpuGeometryRenderer._fromResolved(assetKey, resources);
    }
    final resourcesFuture = _assetResources[assetKey] ??= () async {
      final library = await gpu.ShaderLibrary.fromAsset(assetKey);
      gpu.Shader shader(String name) =>
          library?[name] ??
          (throw StateError(
            'LiquidGlass requires Flutter GPU. Run with Flutter 3.47 or newer '
            'and enable Flutter GPU for the target platform.',
          ));
      atlasTableFilter = _GpuBackend.oneFilterPerTexture
          ? ui.FilterQuality.low
          : ui.FilterQuality.none;
      return _SharedGeometryResources(
        shader,
        oneTargetPerPass: _GpuBackend.oneColorAttachmentPerPass,
      );
    }();
    try {
      final resources = await resourcesFuture;
      final renderer = FlutterGpuGeometryRenderer._fromShared(resources);
      _resolvedAssetResources[assetKey] = resources;
      if (identical(_assetResources[assetKey], resourcesFuture)) {
        unawaited(_assetResources.remove(assetKey));
      }
      return renderer;
    } on Object {
      // Forget the failed load so a later layer retries it instead of
      // awaiting the same failed Future.
      if (identical(_assetResources[assetKey], resourcesFuture)) {
        unawaited(_assetResources.remove(assetKey));
      }
      rethrow;
    }
  }

  /// Synchronously builds a renderer from already resolved shared resources.
  ///
  /// Returns null when [fromAsset] has not resolved [assetKey] yet, or when
  /// the build fails, so callers can fall back to the asynchronous path.
  static FlutterGpuGeometryRenderer? tryCreateCached(String assetKey) {
    final resources = _resolvedAssetResources[assetKey];
    if (resources == null) return null;
    try {
      return FlutterGpuGeometryRenderer._fromResolved(assetKey, resources);
    } on Object {
      return null;
    }
  }

  static final Map<String, Future<_SharedGeometryResources>> _assetResources =
      {};
  static final Map<String, _SharedGeometryResources> _resolvedAssetResources =
      {};

  /// One scratch for the quads and uniform blocks of every page, so a
  /// layer adds no buffers of its own.
  static final _GpuScratch _scratch = _GpuScratch();

  // These ownership counters exclude clones held by callers and native
  // references retained by submitted scenes; they are not GPU memory metrics.
  static int _debugActiveRendererCount = 0;
  static int _debugActiveGeometryTextureCount = 0;
  static int _debugTotalRenderCount = 0;

  /// Counts atlases drawn across all owners, including temporary renderers.
  @visibleForTesting
  static int get debugTotalRenderCount => _debugTotalRenderCount;

  /// Renderers created and not yet disposed.
  @visibleForTesting
  static int get debugActiveRendererCount => _debugActiveRendererCount;

  /// Renderers that hold an atlas.
  @visibleForTesting
  static int get debugActiveGeometryTextureCount =>
      _debugActiveGeometryTextureCount;

  final _SharedGeometryResources _resources;
  final _FieldTextures _fieldTextures = _FieldTextures();

  // The page holding the latest atlas, which it keeps from being drawn over.
  _Page? _page;
  ui.Image? _atlasImage;
  List<ui.Image> _lookImages = const [];
  AtlasPlace? _atlasPlace;

  /// The geometry pipeline, which renderers of one bundle share.
  @visibleForTesting
  @override
  Object get debugPipelineIdentity => _resources.pipelines.first.geometry;

  /// How many host-visible buffers the scratch every renderer shares
  /// holds for quads and uniform blocks.
  @visibleForTesting
  @override
  int get debugScratchBuffers => _scratch.debugBuffers;

  /// Number of atlases rendered.
  @visibleForTesting
  @override
  int debugRenderCount = 0;

  /// Whether [dispose] ran.
  @visibleForTesting
  @override
  bool get debugDisposed => _disposed;

  bool _disposed = false;

  // The corners of the unit square as two triangles, which every quad of
  // every atlas is an instance of.
  static gpu.BufferView? _corners;

  /// The latest geometry atlas, in the page it shares.
  @override
  ui.Image? get atlasImage => _atlasImage;

  /// The looks beside the latest atlas: none, the tint, or tint, response
  /// and color model shares.
  @override
  List<ui.Image> get lookImages => _lookImages;

  /// How many shapes the latest atlas left out: past
  /// [geometryMaxShapesPerDraw] reaching one tile (Tiling.droppedShapes).
  @override
  int droppedShapes = 0;

  /// Lets go of the latest atlas: its page is drawn over once no renderer
  /// holds an atlas in it. Its images are not to be drawn with after this.
  @override
  void releaseAtlas() {
    final page = _page;
    if (page == null) return;
    _page = null;
    _atlasImage = null;
    _lookImages = const [];
    _atlasPlace = null;
    page.owner.release(page);
    assert(() {
      _debugActiveGeometryTextureCount--;
      return true;
    }(), 'Track released geometry atlases in debug builds.');
  }

  // A copy recorded before a render pass on the same command buffer is
  // encoded ahead of it on Vulkan and GLES. Metal opens a blit encoder when
  // the copy is recorded and closes it only on submit, so the render pass's
  // encoder would nest: there the copy gets its own command buffer,
  // submitted first.
  static final bool _uploadsShareCommandBuffer =
      !(Platform.isIOS || Platform.isMacOS);

  // The pages with atlases placed and not yet drawn.
  static final List<_Pages> _openPages = [];
  static bool _postFrameFlushScheduled = false;

  /// Pages drawn and submitted by [flush].
  @visibleForTesting
  static int debugBatchedSubmitCount = 0;

  /// Flushes left to the post-frame safety net because no glass layer of the
  /// frame's scene flushed first.
  @visibleForTesting
  static int debugPostFrameFlushCount = 0;

  /// Atlases placed in a page that a later [flush] drew.
  @visibleForTesting
  static int debugDeferredPassCount = 0;

  // Only the paint and compositing phases are followed by a scene build that
  // flushes before the scene reaches the raster thread.
  static bool get _deferring =>
      SchedulerBinding.instance.schedulerPhase ==
      SchedulerPhase.persistentCallbacks;

  // Covers atlases whose layer was painted but not composited.
  static void _flushAfterFrame() {
    if (_postFrameFlushScheduled) return;
    _postFrameFlushScheduled = true;
    // After the frame: no scene flushed them this frame, nor shows them.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _postFrameFlushScheduled = false;
      if (_openPages.isEmpty) return;
      assert(() {
        debugPostFrameFlushCount++;
        return true;
      }(), 'Count safety-net flushes in debug builds.');
      flush();
    });
  }

  /// Draws the pages holding the atlases placed since the last flush, each
  /// in one pass, and submits them.
  ///
  /// The composer calls this while the scene is built, which is before the
  /// scene is handed to the raster thread, so every atlas a scene samples
  /// has been submitted ahead of it on the GPU queue. A post-frame callback
  /// flushes atlases of layers that were painted but not composited.
  static void flush() {
    if (_openPages.isEmpty) return;
    final open = List.of(_openPages);
    _openPages.clear();
    for (final pages in open) {
      pages.flush();
    }
  }

  /// Forgets the size the pages grew to and drops the spares, as a new
  /// process starts. Where an atlas lies in its page moves a pixel's last
  /// bit, so a test that compares pixels starts from here, whatever ran
  /// before it.
  @visibleForTesting
  static void debugResetPages() {
    flush();
    for (final resources in _resolvedAssetResources.values) {
      for (final pages in resources.pages) {
        pages.reset();
      }
    }
  }

  /// Frames to wait after a page's last atlas is released before drawing
  /// into it again.
  ///
  /// A page released in frame E was last read by frame E - 1. The engine's
  /// two-frame pipeline (`Animator.FramePipeline(2)`) submits that scene before
  /// frame E + 1 paints. Flutter GPU uses the same queue, which orders the next
  /// write after those reads (Metal/Vulkan hazards; GLES posting order).
  static const int reuseAfterFrames = 1;

  static int _completedFrames = 0;
  static bool _countingFrames = false;

  /// Counts scene-submitting frames for page reuse.
  ///
  /// Renders outside a frame, as in unit tests, do not advance the count,
  /// so their pages are never reused.
  static void _ensureFrameCounter() {
    if (_countingFrames) return;
    _countingFrames = true;
    SchedulerBinding.instance.addPersistentFrameCallback((_) {
      if (!RendererBinding.instance.sendFramesToEngine) return;
      _completedFrames++;
    });
  }

  /// The texture of the page holding the latest atlas, compared by identity
  /// in tests.
  @visibleForTesting
  @override
  Object? get debugMatteTexture => _page?.texture;

  /// Size of the page holding the latest atlas.
  @visibleForTesting
  @override
  (int, int)? get debugMatteTextureSize => switch (_page) {
    final page? => (page.width, page.height),
    null => null,
  };

  /// Pages drawn into a texture kept from an earlier one instead of a new
  /// one.
  @visibleForTesting
  static int debugReusedTextureCount = 0;

  /// Textures allocated, pages and their looks.
  @visibleForTesting
  static int debugAllocatedTextureCount = 0;

  /// Textures dropped. Once a texture has lived a few young GCs its wrapper
  /// is promoted, and dropping it pins its storage until an old-generation
  /// GC.
  @visibleForTesting
  static int debugDroppedTextureCount = 0;

  /// Releases the latest atlas and the field textures, keeping the
  /// pipelines.
  ///
  /// Callers retaining an output must clone its images before calling this.
  /// Independent clones and submitted native scenes remain valid.
  @override
  void releaseOutput() {
    releaseAtlas();
    _fieldTextures.release();
  }

  /// Releases the current output and retires this renderer.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    releaseOutput();
    assert(() {
      _debugActiveRendererCount--;
      return true;
    }(), 'Track disposed geometry renderers in debug builds.');
  }
}

/// The renderer's atlas, which only the rendering library draws and reads.
extension FlutterGpuGeometryRendererAtlas on FlutterGpuGeometryRenderer {
  /// Where the latest atlas lies in [atlasImage].
  AtlasPlace? get atlasPlace => _atlasPlace;

  /// Places the geometry atlas of [tiling] (geometry_tiling.dart) in the
  /// page of this frame: the constant tiles, the table and every ring
  /// strip, the strips evaluating the tiling's shapes, or its field. With
  /// [Tiling.looks] the page holds each texel's look beside it, in textures
  /// of its size.
  ///
  /// Table texels hold their tile's entry in x and y, the strip's texels a
  /// pixel in z (0 for a constant tile) and 1 in w. The page is drawn by
  /// [flush]: at once outside a frame, else once for every atlas of the
  /// frame, before its scene is built.
  ///
  /// The images are the page's: do not dispose them. This renderer keeps
  /// the page from being drawn over until it renders another atlas or
  /// releases this one. The images are disposed once every atlas of the
  /// page is released; a clone lives on, and [reuseAfterFrames] frames
  /// later may show other atlases.
  ({ui.Image image, List<ui.Image> looks, AtlasPlace place}) renderAtlas(
    Tiling tiling,
  ) {
    assert(() {
      debugRenderCount++;
      FlutterGpuGeometryRenderer._debugTotalRenderCount++;
      return true;
    }(), 'Track geometry submissions in debug builds.');
    FlutterGpuGeometryRenderer._ensureFrameCounter();
    assert(
      tiling.layout.height <= AtlasLayout.maxSize,
      'A geometry atlas outgrew ${AtlasLayout.maxSize} rows at an inward '
      'reach of 1.',
    );
    final pages = _resources.pages[_LookTargets.of(tiling.looks).index];
    final (page, place) = pages.add(tiling, _fieldTextures);
    page.leases++;
    releaseAtlas();
    _page = page;
    assert(() {
      FlutterGpuGeometryRenderer._debugActiveGeometryTextureCount++;
      return true;
    }(), 'Track held geometry atlases in debug builds.');
    droppedShapes = tiling.droppedShapes;
    if (FlutterGpuGeometryRenderer._deferring) {
      assert(() {
        FlutterGpuGeometryRenderer.debugDeferredPassCount++;
        return true;
      }(), 'Count deferred atlases in debug builds.');
      FlutterGpuGeometryRenderer._flushAfterFrame();
    } else {
      FlutterGpuGeometryRenderer.flush();
    }
    return (
      image: _atlasImage = page.image,
      looks: _lookImages = page.lookImages,
      place: _atlasPlace = place,
    );
  }
}

/// What a draw of a field atlas binds besides the shapes.
final class _FieldDraw {
  const _FieldDraw(this.uniforms, this.texture);

  final gpu.BufferView uniforms;
  final gpu.Texture texture;
}

/// A run of a page's quads: where the run starts and how many it has, the
/// block its shapes are read from where the pipeline reads shapes, and what
/// the field pipeline binds where the run is a field's.
typedef _Draw = ({
  int first,
  int count,
  gpu.BufferView? shapes,
  _FieldDraw? field,
});
