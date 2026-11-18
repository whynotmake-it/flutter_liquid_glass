import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/painting/shader_constants.dart';
import 'package:liquid_glass_renderer/src/rendering/atlas_lease.dart';
import 'package:liquid_glass_renderer/src/rendering/atlas_shaders.dart';
import 'package:liquid_glass_renderer/src/rendering/final_shader_variant.dart';
import 'package:liquid_glass_renderer/src/rendering/geometry_tiling.dart';
import 'package:liquid_glass_renderer/src/rendering/shape_set.dart';
import 'package:vector_math/vector_math.dart' as vm;

part 'package:liquid_glass_renderer/src/rendering/flutter_gpu_geometry_renderer_native_pages.dart';
part 'package:liquid_glass_renderer/src/rendering/flutter_gpu_geometry_renderer_native_quads.dart';
part 'package:liquid_glass_renderer/src/rendering/flutter_gpu_geometry_renderer_native_resources.dart';

/// Floats per instance of tile_vertex.glsl: rectangle, value and ramp.
const int _quadFloats = 12;

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
  /// target (`_Pages._onePerTarget`).
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
class FlutterGpuGeometryRenderer {
  /// A renderer on [_bundle], with an atlas of its own, which the caller
  /// disposes.
  FlutterGpuGeometryRenderer(this._bundle)
    : assert(() {
        _debugActiveRendererCount++;
        return true;
      }(), 'Track live geometry renderers in debug builds.');

  /// One scratch for the quads and uniform blocks of every page, so a
  /// layer adds no buffers of its own.
  static final _GpuScratch _scratch = _GpuScratch();

  // These ownership counters exclude clones held by callers and native
  // references retained by submitted scenes; they are not GPU memory metrics.
  static int _debugActiveRendererCount = 0;
  static int _debugActiveAtlasCount = 0;
  static int _debugTotalRenderCount = 0;

  /// Counts atlases drawn across all owners, including temporary renderers.
  @visibleForTesting
  static int get debugTotalRenderCount => _debugTotalRenderCount;

  /// Renderers created and not yet disposed.
  @visibleForTesting
  static int get debugActiveRendererCount => _debugActiveRendererCount;

  /// Renderers that hold an atlas.
  @visibleForTesting
  static int get debugActiveAtlasCount => _debugActiveAtlasCount;

  final GeometryBundle _bundle;
  final _FieldTextures _fieldTextures = _FieldTextures();

  // The page holding the latest atlas, which it keeps from being drawn over.
  _Page? _page;

  /// The geometry pipeline, which renderers of one bundle share.
  @visibleForTesting
  Object get debugPipelineIdentity => _bundle._pages.first._pipelines.shapes;

  /// How many host-visible buffers the scratch every renderer shares
  /// holds for quads and uniform blocks.
  @visibleForTesting
  int get debugScratchBuffers => _scratch.debugBuffers;

  /// Number of atlases rendered.
  @visibleForTesting
  int debugRenderCount = 0;

  /// Whether [dispose] ran.
  @visibleForTesting
  bool get debugDisposed => _disposed;

  bool _disposed = false;

  // The corners of the unit square as two triangles, which every quad of
  // every atlas is an instance of.
  static gpu.BufferView? _corners;

  /// Lets go of the latest atlas: its page is drawn over once no renderer
  /// holds an atlas in it. Its images are not to be drawn with after this.
  void releaseAtlas() {
    final page = _page;
    if (page == null) return;
    _page = null;
    page.owner.release(page);
    assert(() {
      _debugActiveAtlasCount--;
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
  /// has been submitted ahead of it on the GPU queue.
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
    for (final bundle in GeometryBundle._loaded.values) {
      for (final pages in bundle._pages) {
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
      assert(
        _openPages.isEmpty,
        'An atlas was placed after the last flush of the frame: its scene was '
        'built before the atlas was drawn, so the glass shows it a frame '
        'late. Atlases are placed at paint or in the composer, which flushes '
        'before any scene is built.',
      );
      if (!RendererBinding.instance.sendFramesToEngine) return;
      _completedFrames++;
    });
  }

  /// The texture of the page holding the latest atlas, compared by identity
  /// in tests.
  @visibleForTesting
  Object? get debugPageTexture => _page?.texture;

  /// Size of the page holding the latest atlas.
  @visibleForTesting
  (int, int)? get debugPageSize => switch (_page) {
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

  /// Releases the latest atlas and the field textures and retires this
  /// renderer. Clones of its images and submitted native scenes stay valid.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    releaseAtlas();
    _fieldTextures.release();
    assert(() {
      _debugActiveRendererCount--;
      return true;
    }(), 'Track disposed geometry renderers in debug builds.');
  }
}

/// The renderer's atlas, which only the rendering library draws and reads.
extension FlutterGpuGeometryRendererAtlas on FlutterGpuGeometryRenderer {
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
  /// The lease stands until this renderer renders another atlas or releases
  /// this one. The page's images are disposed once every atlas of the page
  /// is released; a clone lives on, and [reuseAfterFrames] frames later may
  /// show other atlases.
  AtlasLease renderAtlas(
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
    final pages = _bundle._pages[AtlasLooks.of(tiling.looks).index];
    final (page, place) = pages.add(tiling, _fieldTextures);
    page.leases++;
    releaseAtlas();
    _page = page;
    assert(() {
      FlutterGpuGeometryRenderer._debugActiveAtlasCount++;
      return true;
    }(), 'Track held geometry atlases in debug builds.');
    if (FlutterGpuGeometryRenderer._deferring) {
      assert(() {
        FlutterGpuGeometryRenderer.debugDeferredPassCount++;
        return true;
      }(), 'Count deferred atlases in debug builds.');
      FlutterGpuGeometryRenderer._flushAfterFrame();
    } else {
      FlutterGpuGeometryRenderer.flush();
    }
    return AtlasLease(image: page.image, looks: page.lookImages, place: place);
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
