import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

/// Renders the liquid glass geometry SDF shader using flutter_gpu.
///
/// Each changed matte gets a texture no in-flight frame reads: previously
/// submitted Flutter scenes may still sample the old matte with their old
/// coordinate uniforms, and rewriting it would mix frames. A replaced texture
/// is rendered into again only after [reuseAfterFrames] frames, which keeps
/// Impeller's cached render pass and framebuffer and skips the allocation.
/// The layer reuses the image without calling [render] when geometry is
/// unchanged (including uniform translation).
///
/// This renderer owns the image handles returned by [gpu.Texture.asImage].
/// Replacing/disposal releases those handles; recorded scenes hold independent
/// native references. Direct callers needing a handle across renders can clone
/// it and must dispose their clone; its pixels stay valid for
/// [reuseAfterFrames] frames after replacement, enough for scene submission.
@internal
class FlutterGpuGeometryRenderer {
  FlutterGpuGeometryRenderer({
    required gpu.Shader vertexShader,
    required gpu.Shader fragmentShader,
    gpu.Shader? materialGradientFragmentShader,
    gpu.Shader? materialTintGradientFragmentShader,
  }) {
    _pipeline = gpu.gpuContext.createRenderPipeline(
      vertexShader,
      fragmentShader,
    );
    _materialGradientPipeline = materialGradientFragmentShader == null
        ? null
        : gpu.gpuContext.createRenderPipeline(
            vertexShader,
            materialGradientFragmentShader,
          );
    _materialTintGradientPipeline = materialTintGradientFragmentShader == null
        ? null
        : gpu.gpuContext.createRenderPipeline(
            vertexShader,
            materialTintGradientFragmentShader,
          );
    _bindUniformLayout(fragmentShader);
    _createVertexBuffer();
    _uniformData = ByteData(_uniformSize);
    assert(() {
      _debugActiveRendererCount++;
      return true;
    }(), 'Track live geometry renderers in debug builds.');
  }

  FlutterGpuGeometryRenderer._fromShared(_SharedGeometryResources resources) {
    _pipeline = resources.pipeline;
    _materialGradientPipeline = resources.materialGradientPipeline;
    _materialTintGradientPipeline = resources.materialTintGradientPipeline;
    _uniformSlot = resources.uniformSlot;
    _uniformSize = resources.uniformSize;
    _offsetUOffset = resources.offsetUOffset;
    _offsetUTextureSize = resources.offsetUTextureSize;
    _offsetOpticalProps = resources.offsetOpticalProps;
    _offsetContourProps = resources.offsetContourProps;
    _offsetShapeData = resources.offsetShapeData;
    _offsetRseData = resources.offsetRseData;
    _offsetShapeTints = resources.offsetShapeTints;
    _offsetShapeResponses = resources.offsetShapeResponses;
    _offsetShapeBounds = resources.offsetShapeBounds;
    _vertexBuffer = resources.vertexBuffer;
    _vertexBufferView = resources.vertexBufferView;
    _uniformData = ByteData(_uniformSize);
    assert(() {
      _debugActiveRendererCount++;
      return true;
    }(), 'Track live geometry renderers in debug builds.');
  }

  // Harness-only rasterization probe. The default exactly matches Flutter's
  // centered half-pixel coverage; this is deliberately not a public material
  // parameter.
  static const double _geometryAaHalfWidth =
      int.fromEnvironment(
        'LIQUID_GLASS_GEOMETRY_AA_HALF_WIDTH',
        defaultValue: 500,
      ) /
      1000.0;

  static Future<FlutterGpuGeometryRenderer> fromAsset(String assetKey) async {
    final cachedResources = _resolvedAssetResources[assetKey];
    if (cachedResources != null) {
      try {
        return FlutterGpuGeometryRenderer._fromShared(cachedResources);
      } on Object {
        // A recreated Android surface can invalidate native resources that
        // were resolved before the context loss. Let the next layer reload
        // the immutable bundle instead of retaining a poisoned fast path.
        if (identical(_resolvedAssetResources[assetKey], cachedResources)) {
          _resolvedAssetResources.remove(assetKey);
        }
        rethrow;
      }
    }
    final resourcesFuture = _assetResources[assetKey] ??= () async {
      final library = await gpu.ShaderLibrary.fromAsset(assetKey);
      final vertexShader = library?['GeometryVertex'];
      final fragmentShader = library?['GeometryFragment'];
      final materialGradientFragmentShader =
          library?['MaterialGradientFragment'];
      final materialTintGradientFragmentShader =
          library?['MaterialTintGradientFragment'];
      if (vertexShader == null ||
          fragmentShader == null ||
          materialGradientFragmentShader == null ||
          materialTintGradientFragmentShader == null) {
        throw StateError(
          'LiquidGlass requires Flutter GPU. Run with Flutter 3.47 or newer '
          'and enable Flutter GPU for the target platform.',
        );
      }
      return _SharedGeometryResources(
        vertexShader: vertexShader,
        fragmentShader: fragmentShader,
        materialGradientFragmentShader: materialGradientFragmentShader,
        materialTintGradientFragmentShader: materialTintGradientFragmentShader,
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
      // A transiently unavailable GPU context must not poison all later layer
      // initialization attempts with the same cached failed Future.
      if (identical(_assetResources[assetKey], resourcesFuture)) {
        unawaited(_assetResources.remove(assetKey));
      }
      rethrow;
    }
  }

  /// Synchronously builds a renderer from already resolved shared resources.
  ///
  /// Returns null when [fromAsset] has not resolved [assetKey] yet, so callers
  /// can fall back to the asynchronous path. On failure the poisoned cache
  /// entry is evicted exactly like [fromAsset] does.
  static FlutterGpuGeometryRenderer? tryCreateCached(String assetKey) {
    final cachedResources = _resolvedAssetResources[assetKey];
    if (cachedResources == null) return null;
    try {
      return FlutterGpuGeometryRenderer._fromShared(cachedResources);
    } on Object {
      if (identical(_resolvedAssetResources[assetKey], cachedResources)) {
        _resolvedAssetResources.remove(assetKey);
      }
      return null;
    }
  }

  /// Completes once a Flutter GPU context can be created.
  ///
  /// On Android the Impeller context is unavailable before the first surface
  /// frame, so this initializes the widgets binding if needed — including
  /// when called before `runApp` — and waits for the first rasterized frame.
  /// On every other platform it completes immediately.
  static Future<void> waitUntilGpuContextAvailable() async {
    if (!Platform.isAndroid) return;
    await WidgetsFlutterBinding.ensureInitialized()
        .waitUntilFirstFrameRasterized;
  }

  static final Map<String, Future<_SharedGeometryResources>> _assetResources =
      {};
  static final Map<String, _SharedGeometryResources> _resolvedAssetResources =
      {};

  /// One bump allocator for every geometry pass in the current frame.
  ///
  /// HostBuffer retains four device-buffer blocks. Sizing each renderer to a
  /// single uniform used to be 1 MB × 4 × N layers; a shared scratch sized for
  /// a frame of layers keeps that off the native heap.
  static gpu.HostBuffer? _sharedHostBuffer;
  static int _sharedHostBufferBlockLength = 0;
  static Duration? _sharedHostBufferFrame;
  static int _diagnosticWrites = 0;
  static int _diagnosticMaxWrites = 0;

  static const int _hostBufferSlotsPerFrame = 32;

  // These ownership counters exclude clones held by callers and native
  // references retained by submitted scenes; they are not GPU memory metrics.
  static int _debugActiveRendererCount = 0;
  static int _debugActiveGeometryTextureCount = 0;
  static int _debugActiveMaterialTextureCount = 0;
  static int _debugTotalRenderCount = 0;

  /// Counts SDF submissions across all owners, including temporary renderers.
  @visibleForTesting
  static int get debugTotalRenderCount => _debugTotalRenderCount;

  @visibleForTesting
  static int get debugActiveRendererCount => _debugActiveRendererCount;

  @visibleForTesting
  static int get debugActiveGeometryTextureCount =>
      _debugActiveGeometryTextureCount;

  @visibleForTesting
  static int get debugActiveMaterialTextureCount =>
      _debugActiveMaterialTextureCount;

  static gpu.HostBuffer _hostBufferForUniformSize(int uniformSize) {
    final alignment = gpu.gpuContext.minimumUniformByteAlignment;
    final alignedSize =
        ((uniformSize + alignment - 1) ~/ alignment) * alignment;
    final blockLength = alignedSize * _hostBufferSlotsPerFrame;
    if (_sharedHostBuffer == null ||
        _sharedHostBufferBlockLength < blockLength) {
      _sharedHostBuffer = gpu.gpuContext.createHostBuffer(
        blockLengthInBytes: blockLength,
      );
      _sharedHostBufferBlockLength = blockLength;
    }
    // This is also defined for direct renderer callers outside
    // handleDrawFrame while still advancing once per engine frame in
    // production.
    final timestamp = SchedulerBinding.instance.currentSystemFrameTimeStamp;
    if (_sharedHostBufferFrame != timestamp) {
      _sharedHostBuffer!.reset();
      _sharedHostBufferFrame = timestamp;
      if (GpuAllocationDiagnostics.enabled) _diagnosticWrites = 0;
    }
    if (GpuAllocationDiagnostics.enabled) {
      _diagnosticWrites++;
      _diagnosticMaxWrites = math.max(_diagnosticMaxWrites, _diagnosticWrites);
    }
    return _sharedHostBuffer!;
  }

  late final gpu.RenderPipeline _pipeline;
  late final gpu.RenderPipeline? _materialGradientPipeline;
  late final gpu.RenderPipeline? _materialTintGradientPipeline;

  @visibleForTesting
  Object get debugPipelineIdentity => _pipeline;

  @visibleForTesting
  int get debugHostBufferBlockLength => _sharedHostBufferBlockLength;

  @visibleForTesting
  Object? get debugHostBufferIdentity => _sharedHostBuffer;

  /// Number of geometry command buffers submitted by this renderer.
  @visibleForTesting
  int debugRenderCount = 0;

  @visibleForTesting
  bool get debugDisposed => _disposed;

  bool _disposed = false;

  // Uniform slot reflection.
  late final gpu.UniformSlot _uniformSlot;
  late final int _uniformSize;
  late final int _offsetUOffset;
  late final int _offsetUTextureSize;
  late final int _offsetOpticalProps;
  late final int _offsetContourProps;
  late final int _offsetShapeData;
  late final int _offsetRseData;
  late final int _offsetShapeTints;
  late final int _offsetShapeResponses;
  late final int _offsetShapeBounds;
  late final ByteData _uniformData;
  int _writtenShapeFloats = 0;
  int _writtenRseFloats = 0;

  // Latest immutable matte. Older scenes retain their own native references.
  gpu.Texture? _texture;
  ui.Image? _image;
  gpu.RenderTarget? _renderTarget;
  gpu.Texture? _materialTexture;
  ui.Image? _materialImage;
  gpu.RenderTarget? _materialRenderTarget;

  // Appearance blending is decorative and only visible while shapes merge.
  // One sample per 8x8 full-resolution block makes its SDF work 64x smaller.
  static const int materialRasterScale = 8;

  late final gpu.DeviceBuffer _vertexBuffer;
  late final gpu.BufferView _vertexBufferView;

  /// Low-resolution contributor map from the latest appearance render.
  ui.Image? get materialImage => _materialImage;

  void _bindUniformLayout(gpu.Shader fragmentShader) {
    _uniformSlot = fragmentShader.getUniformSlot('GeometryUniforms');
    _uniformSize = _uniformSlot.sizeInBytes ?? 0;
    _offsetUOffset = _uniformSlot.getMemberOffsetInBytes('uOffset') ?? 0;
    _offsetUTextureSize =
        _uniformSlot.getMemberOffsetInBytes('uTextureSize') ?? 0;
    _offsetOpticalProps =
        _uniformSlot.getMemberOffsetInBytes('uOpticalProps') ?? 0;
    _offsetContourProps =
        _uniformSlot.getMemberOffsetInBytes('uContourProps') ?? 0;
    _offsetShapeData = _uniformSlot.getMemberOffsetInBytes('uShapeData') ?? 0;
    _offsetRseData = _uniformSlot.getMemberOffsetInBytes('uRseData') ?? 0;
    _offsetShapeTints = _uniformSlot.getMemberOffsetInBytes('uShapeTints') ?? 0;
    _offsetShapeResponses =
        _uniformSlot.getMemberOffsetInBytes('uShapeResponses') ?? 0;
    _offsetShapeBounds =
        _uniformSlot.getMemberOffsetInBytes('uShapeBounds') ?? 0;
  }

  void _createVertexBuffer() {
    final vertices = Float32List.fromList([
      -1.0, -1.0, 0.0, 0.0, //
      1.0, -1.0, 1.0, 0.0, //
      -1.0, 1.0, 0.0, 1.0, //
      1.0, 1.0, 1.0, 1.0, //
    ]);
    _vertexBuffer = gpu.gpuContext.createDeviceBufferWithCopy(
      ByteData.sublistView(vertices),
    );
    _vertexBufferView = gpu.BufferView(
      _vertexBuffer,
      offsetInBytes: 0,
      lengthInBytes: _vertexBuffer.sizeInBytes,
    );
  }

  /// Renders a new geometry matte and returns it as a [ui.Image].
  ///
  /// The returned image is a non-owning wrapper — do NOT dispose it. Its
  /// texture is not written again until [reuseAfterFrames] frames after a
  /// later render replaces it; a clone kept longer than that may show a newer
  /// matte.
  ({ui.Image image, int width, int height}) render({
    required int width,
    required int height,
    required List<double> shapeData,
    required int numShapes,
    required double refractionHeight,
    required double refractionAmount,
    required double offsetX,
    required double offsetY,
    double? edgeDistanceRange,
    bool refractionFitsShape = true,
    double contourExtent = 0.5,
    bool writeMaterials = false,
    bool writeTintOnly = false,
    List<double> appearanceData = const <double>[],
    List<double> rseData = const <double>[],
    List<double> boundsData = const <double>[],
  }) {
    assert(() {
      debugRenderCount++;
      _debugTotalRenderCount++;
      return true;
    }(), 'Track geometry submissions in debug builds.');
    final allocatedWidth = _bucketDimension(width);
    final allocatedHeight = _bucketDimension(height);

    _ensureFrameCounter();
    _lastRenderFrame = _completedFrames;
    if (_texture != null) {
      // Release our handle; earlier submitted scenes hold their own.
      _image?.dispose();
      _image = null;
      _retire(_retiredMattes, _texture!, _renderTarget!);
      _renderTarget = null;
      _texture = null;
      assert(() {
        _debugActiveGeometryTextureCount--;
        return true;
      }(), 'Track replaced geometry textures in debug builds.');
    }
    // The shader writes every pixel of the full-screen quad, so neither a
    // fresh nor a reused texture needs a clear or a copy of the old matte.
    final (matte, matteTarget) = _acquire(
      _retiredMattes,
      allocatedWidth,
      allocatedHeight,
    );
    _texture = matte;
    _renderTarget = matteTarget;
    _image = _texture!.asImage();
    assert(() {
      _debugActiveGeometryTextureCount++;
      return true;
    }(), 'Track live geometry textures in debug builds.');

    if (_materialTexture != null) {
      _materialImage?.dispose();
      _materialImage = null;
      _retire(_retiredMaterials, _materialTexture!, _materialRenderTarget!);
      _materialRenderTarget = null;
      _materialTexture = null;
      assert(() {
        _debugActiveMaterialTextureCount--;
        return true;
      }(), 'Track replaced material textures in debug builds.');
    }
    if (writeMaterials) {
      final materialMapWidth = math.max(
        1,
        (allocatedWidth + materialRasterScale - 1) ~/ materialRasterScale,
      );
      final materialMapHeight = math.max(
        1,
        (allocatedHeight + materialRasterScale - 1) ~/ materialRasterScale,
      );
      final materialWidth = writeTintOnly
          ? materialMapWidth
          : math.max(16, materialMapWidth);
      final materialHeight = writeTintOnly
          ? materialMapHeight
          : materialMapHeight + 2;
      final (material, materialTarget) = _acquire(
        _retiredMaterials,
        materialWidth,
        materialHeight,
      );
      _materialTexture = material;
      _materialRenderTarget = materialTarget;
      _materialImage = _materialTexture!.asImage();
      assert(() {
        _debugActiveMaterialTextureCount++;
        return true;
      }(), 'Track live material textures in debug builds.');
    }
    _trimRetired(_retiredMattes, allocatedWidth, allocatedHeight);

    _packUniformData(
      offsetX: offsetX,
      offsetY: offsetY,
      textureWidth: allocatedWidth.toDouble(),
      textureHeight: allocatedHeight.toDouble(),
      refractionHeight: refractionHeight,
      refractionAmount: refractionAmount,
      edgeDistanceRange: edgeDistanceRange ?? math.max(12, refractionHeight),
      refractionFitsShape: refractionFitsShape,
      contourExtent: contourExtent,
      materialScale: writeMaterials ? materialRasterScale.toDouble() : 1.0,
      materialMapWidth: writeMaterials
          ? math
                .max(
                  1,
                  (allocatedWidth + materialRasterScale - 1) ~/
                      materialRasterScale,
                )
                .toDouble()
          : 1.0,
      materialMapHeight: writeMaterials
          ? math
                .max(
                  1,
                  (allocatedHeight + materialRasterScale - 1) ~/
                      materialRasterScale,
                )
                .toDouble()
          : 1.0,
      geometryAaHalfWidth: _geometryAaHalfWidth,
      numShapes: numShapes.toDouble(),
      shapeData: shapeData,
      rseData: rseData,
      appearanceData: appearanceData,
      boundsData: boundsData,
    );

    final uniformView = _hostBufferForUniformSize(
      _uniformSize,
    ).emplace(_uniformData);

    final geometryCommandBuffer = gpu.gpuContext.createCommandBuffer();
    final geometryPass = geometryCommandBuffer.createRenderPass(_renderTarget!)
      ..bindPipeline(_pipeline)
      ..setPrimitiveType(gpu.PrimitiveType.triangleStrip)
      ..bindUniform(_uniformSlot, uniformView)
      ..bindVertexBuffer(_vertexBufferView)
      ..draw(4);
    _submitOrDefer(geometryCommandBuffer);
    if (GpuAllocationDiagnostics.enabled) {
      GpuAllocationDiagnostics.observe('command', geometryCommandBuffer);
      GpuAllocationDiagnostics.observe('pass', geometryPass);
      GpuAllocationDiagnostics.observe('texture', _texture!);
      GpuAllocationDiagnostics.allocations.add(
        '$allocatedWidth x $allocatedHeight ${_texture!.format}',
      );
    }
    if (writeMaterials) {
      final materialCommandBuffer = gpu.gpuContext.createCommandBuffer();
      final materialPass =
          materialCommandBuffer.createRenderPass(_materialRenderTarget!)
            ..bindPipeline(
              writeTintOnly
                  ? _materialTintGradientPipeline!
                  : _materialGradientPipeline!,
            )
            ..setPrimitiveType(gpu.PrimitiveType.triangleStrip)
            ..bindUniform(_uniformSlot, uniformView)
            ..bindVertexBuffer(_vertexBufferView)
            ..draw(4);
      _submitOrDefer(materialCommandBuffer);
      if (GpuAllocationDiagnostics.enabled) {
        GpuAllocationDiagnostics.observe('command', materialCommandBuffer);
        GpuAllocationDiagnostics.observe('pass', materialPass);
        GpuAllocationDiagnostics.observe('texture', _materialTexture!);
      }
    }

    return (image: _image!, width: allocatedWidth, height: allocatedHeight);
  }

  static int _bucketDimension(int value) => (value + 63) & ~63;

  /// Whether passes recorded during a frame are submitted together when the
  /// frame's scene is built instead of right after each pass is recorded.
  static const bool _batchSubmissions = bool.fromEnvironment(
    'LIQUID_GLASS_BATCH_GEOMETRY_SUBMISSIONS',
    defaultValue: true,
  );

  /// Submits every pass immediately, as renders outside a frame always do.
  @visibleForTesting
  static bool debugSubmitImmediately = false;

  // Every pass gets its own command buffer. Flutter GPU (3.47.1) begins the
  // backend pass in `createRenderPass` and ends it only in `submit`, so a
  // second pass on the same command buffer nests inside the first:
  //
  // - Vulkan (Pixel 10, PowerVR; also flutter_tester on SwiftShader):
  //     Fatal signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), fault addr 0x60
  //     #00 vulkan.powervr.so (CmdEndRenderPass2+188)
  //     #04 libflutter.so (InternalFlutterGpu_CommandBuffer_Submit+56)
  // - Metal (macOS, AGX G16X):
  //     -[AGXG16XFamilyCommandBuffer renderCommandEncoderWithDescriptor:]:
  //     failed assertion `A command encoder is already encoding to this
  //     command buffer'
  //       impeller::RenderPassMTL::RenderPassMTL
  //       impeller::CommandBufferMTL::OnCreateRenderPass
  //       flutter::gpu::RenderPass::Begin
  //
  // Share a command buffer across passes only once the engine ends a pass
  // before the next begins.
  static final List<gpu.CommandBuffer> _pendingCommandBuffers = [];
  static bool _postFrameFlushScheduled = false;

  /// Command buffers submitted by [flushPendingSubmissions].
  @visibleForTesting
  static int debugBatchedSubmitCount = 0;

  /// Flushes left to the post-frame safety net because no glass layer of the
  /// frame's scene flushed first.
  @visibleForTesting
  static int debugPostFrameFlushCount = 0;

  /// Passes whose submission was deferred to [flushPendingSubmissions].
  @visibleForTesting
  static int debugDeferredPassCount = 0;

  // Only the paint and compositing phases are followed by a scene build that
  // flushes before the scene reaches the raster thread.
  static bool get _deferring =>
      _batchSubmissions &&
      !debugSubmitImmediately &&
      SchedulerBinding.instance.schedulerPhase ==
          SchedulerPhase.persistentCallbacks;

  static void _submitOrDefer(gpu.CommandBuffer commandBuffer) {
    if (!_deferring) {
      commandBuffer.submit();
      return;
    }
    assert(() {
      debugDeferredPassCount++;
      return true;
    }(), 'Count deferred geometry passes in debug builds.');
    _pendingCommandBuffers.add(commandBuffer);
    if (_postFrameFlushScheduled) return;
    _postFrameFlushScheduled = true;
    // Covers passes whose layer was painted but not composited.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _postFrameFlushScheduled = false;
      if (_pendingCommandBuffers.isEmpty) return;
      assert(() {
        debugPostFrameFlushCount++;
        return true;
      }(), 'Count safety-net flushes in debug builds.');
      flushPendingSubmissions();
    });
  }

  /// Submits the passes recorded since the last flush, in recording order.
  ///
  /// Glass layers call this while the scene is built, which is before the
  /// scene is handed to the raster thread, so every matte a scene samples has
  /// been submitted ahead of it on the GPU queue. A post-frame callback
  /// flushes passes of layers that were painted but not composited.
  static void flushPendingSubmissions() {
    if (_pendingCommandBuffers.isEmpty) return;
    for (final commandBuffer in _pendingCommandBuffers) {
      commandBuffer.submit();
      assert(() {
        debugBatchedSubmitCount++;
        return true;
      }(), 'Count batched submissions in debug builds.');
    }
    _pendingCommandBuffers.clear();
  }

  /// Frames after its replacement before a texture may be rendered into
  /// again.
  ///
  /// The last scene that can sample a matte replaced during frame E is
  /// frame E - 1's. The engine keeps at most two layer trees in flight and
  /// frees a slot only after rasterizing (`Animator`'s `FramePipeline(2)`),
  /// so when the UI thread paints frame k, frame k - 2 has been rasterized.
  /// The Vulkan swapchains (KHR and AHB) wait for the GPU fence of the frame
  /// two before the one they rasterize, so the GPU has finished frame k - 4.
  /// Reuse is therefore safe from frame E + 3. Metal tracks the hazard
  /// itself and GLES submits on the raster thread in order. The extra three
  /// frames absorb frames rendered outside vsync, such as warm-up frames.
  static const int reuseAfterFrames = 6;

  /// Harness switch for A/B builds; production always reuses.
  static const bool _reuseTextures = bool.fromEnvironment(
    'LIQUID_GLASS_REUSE_GEOMETRY_TEXTURES',
    defaultValue: true,
  );

  /// Renderers stop holding retired textures after this many frames
  /// without a geometry render.
  static const int _idleFramesBeforeTrim = 30;

  static int _completedFrames = 0;
  static bool _countingFrames = false;
  static final Set<FlutterGpuGeometryRenderer> _renderersWithRetired = {};

  /// Counts frames that submit a scene, the unit [reuseAfterFrames] is in.
  ///
  /// Renders outside a frame, as in unit tests, do not advance the count,
  /// so their textures are never reused.
  static void _ensureFrameCounter() {
    if (_countingFrames || !_reuseTextures) return;
    _countingFrames = true;
    SchedulerBinding.instance.addPersistentFrameCallback((_) {
      if (!RendererBinding.instance.sendFramesToEngine) return;
      _completedFrames++;
      if (_renderersWithRetired.isEmpty) return;
      for (final renderer in _renderersWithRetired.toList()) {
        if (_completedFrames - renderer._lastRenderFrame >
            _idleFramesBeforeTrim) {
          renderer._releaseRetired();
        }
      }
    });
  }

  int _lastRenderFrame = 0;
  final List<_RetiredTarget> _retiredMattes = [];
  final List<_RetiredTarget> _retiredMaterials = [];

  /// Number of replaced textures this renderer holds for reuse.
  @visibleForTesting
  int get debugRetiredTextureCount =>
      _retiredMattes.length + _retiredMaterials.length;

  /// Renders that wrote into a reused texture instead of allocating one.
  @visibleForTesting
  static int debugReusedTextureCount = 0;

  void _retire(
    List<_RetiredTarget> retired,
    gpu.Texture texture,
    gpu.RenderTarget target,
  ) {
    if (!_reuseTextures) return;
    retired.add(_RetiredTarget(texture, target, _completedFrames));
    _renderersWithRetired.add(this);
  }

  (gpu.Texture, gpu.RenderTarget) _acquire(
    List<_RetiredTarget> retired,
    int width,
    int height,
  ) {
    for (var index = 0; index < retired.length; index++) {
      final candidate = retired[index];
      if (_completedFrames - candidate.retiredFrame < reuseAfterFrames) {
        // Retired in frame order; later entries are younger still.
        break;
      }
      if (candidate.texture.width == width &&
          candidate.texture.height == height) {
        retired.removeAt(index);
        assert(() {
          debugReusedTextureCount++;
          return true;
        }(), 'Count reused geometry textures in debug builds.');
        return (candidate.texture, candidate.renderTarget);
      }
    }
    final texture = gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      width,
      height,
    );
    return (
      texture,
      gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(
          texture: texture,
          loadAction: gpu.LoadAction.dontCare,
        ),
      ),
    );
  }

  /// Keeps enough retired mattes to cycle through [reuseAfterFrames] at the
  /// current size, and a few of other sizes for mattes that oscillate
  /// between two buckets.
  void _trimRetired(List<_RetiredTarget> retired, int width, int height) {
    retired.removeWhere(
      (entry) =>
          (entry.texture.width != width || entry.texture.height != height) &&
          _completedFrames - entry.retiredFrame > 2 * reuseAfterFrames,
    );
    const maxRetired = reuseAfterFrames + 2;
    if (retired.length > maxRetired) {
      retired.removeRange(0, retired.length - maxRetired);
    }
    if (_retiredMaterials.length > maxRetired) {
      _retiredMaterials.removeRange(
        0,
        _retiredMaterials.length - maxRetired,
      );
    }
  }

  void _releaseRetired() {
    _retiredMattes.clear();
    _retiredMaterials.clear();
    _renderersWithRetired.remove(this);
  }

  void _packUniformData({
    required double offsetX,
    required double offsetY,
    required double textureWidth,
    required double textureHeight,
    required double refractionHeight,
    required double refractionAmount,
    required double edgeDistanceRange,
    required bool refractionFitsShape,
    required double contourExtent,
    required double materialScale,
    required double materialMapWidth,
    required double materialMapHeight,
    required double geometryAaHalfWidth,
    required double numShapes,
    required List<double> shapeData,
    required List<double> rseData,
    required List<double> appearanceData,
    required List<double> boundsData,
  }) {
    final floatData = _uniformData.buffer.asFloat32List();

    final uOffsetIndex = _offsetUOffset ~/ 4;
    floatData[uOffsetIndex] = offsetX;
    floatData[uOffsetIndex + 1] = offsetY;

    final textureSizeIndex = _offsetUTextureSize ~/ 4;
    // X selects shape-fitted refraction; Y is the bevel's edge displacement,
    // which is also the codec scale.
    floatData[textureSizeIndex] = refractionFitsShape ? 1 : 0;
    floatData[textureSizeIndex + 1] = math.max(1e-3, refractionAmount);

    final opticalPropsIndex = _offsetOpticalProps ~/ 4;
    floatData[opticalPropsIndex] = math.max(0, refractionHeight);
    // The Y slot is a harness-only centered-AA half-width. It defaults to
    // 0.5, matching Flutter's one-pixel transition; keeping it in the
    // existing reserved slot avoids changing the uniform ABI.
    floatData[opticalPropsIndex + 1] = geometryAaHalfWidth.clamp(0.0, 1.0);
    floatData[opticalPropsIndex + 2] = math.max(1, edgeDistanceRange);
    floatData[opticalPropsIndex + 3] = numShapes;

    final contourPropsIndex = _offsetContourProps ~/ 4;
    floatData[contourPropsIndex] = math.max(0.5, contourExtent);
    floatData[contourPropsIndex + 1] = materialScale;
    floatData[contourPropsIndex + 2] = materialMapWidth;
    floatData[contourPropsIndex + 3] = materialMapHeight;

    final shapeDataStartIndex = _offsetShapeData ~/ 4;
    final shapeFloats = shapeData.length < 192 ? shapeData.length : 192;
    for (var i = 0; i < shapeFloats; i++) {
      floatData[shapeDataStartIndex + i] = shapeData[i];
    }
    for (var i = shapeFloats; i < _writtenShapeFloats; i++) {
      floatData[shapeDataStartIndex + i] = 0;
    }
    _writtenShapeFloats = shapeFloats;

    final rseDataStartIndex = _offsetRseData ~/ 4;
    final rseFloats = rseData.length < 192 ? rseData.length : 192;
    for (var i = 0; i < rseFloats; i++) {
      floatData[rseDataStartIndex + i] = rseData[i];
    }
    for (var i = rseFloats; i < _writtenRseFloats; i++) {
      floatData[rseDataStartIndex + i] = 0;
    }
    _writtenRseFloats = rseFloats;

    if (appearanceData.isNotEmpty && appearanceData.length != 16 * 2 * 4) {
      throw ArgumentError.value(
        appearanceData.length,
        'appearanceData.length',
        'must contain two vec4 rows for each of 16 shapes',
      );
    }
    if (appearanceData.isNotEmpty) {
      final shapeTintsStartIndex = _offsetShapeTints ~/ 4;
      final shapeResponsesStartIndex = _offsetShapeResponses ~/ 4;
      for (var i = 0; i < 16 * 4; i++) {
        floatData[shapeTintsStartIndex + i] = appearanceData[i];
        floatData[shapeResponsesStartIndex + i] = appearanceData[16 * 4 + i];
      }
    }

    // Shapes without bounds are never culled.
    final boundsStartIndex = _offsetShapeBounds ~/ 4;
    final boundsFloats = math.min(boundsData.length, 16 * 4);
    for (var i = 0; i < 16 * 4; i++) {
      floatData[boundsStartIndex + i] = i < boundsFloats
          ? boundsData[i]
          : (i % 4 < 2 ? -1e9 : 1e9);
    }
  }

  /// Releases borrowed output handles, keeping reusable rendering resources.
  ///
  /// Callers retaining an output must clone its images before calling this.
  /// Independent clones and submitted native scenes remain valid.
  void releaseOutput() {
    _releaseRetired();
    _renderTarget = null;
    _image?.dispose();
    _image = null;
    _materialRenderTarget = null;
    _materialImage?.dispose();
    _materialImage = null;
    if (_materialTexture != null) {
      assert(() {
        _debugActiveMaterialTextureCount--;
        return true;
      }(), 'Track disposed material textures in debug builds.');
    }
    _materialTexture = null;
    if (_texture != null) {
      assert(() {
        _debugActiveGeometryTextureCount--;
        return true;
      }(), 'Track disposed geometry textures in debug builds.');
    }
    _texture = null;
  }

  /// Releases the current output and retires this renderer.
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

/// Temporary diagnostic bookkeeping; never enabled in published/default builds.
@internal
class GpuAllocationDiagnostics {
  /// Controls all instrumentation at compile time.
  static const enabled = bool.fromEnvironment('DIAG_GPU_ALLOCATION');
  static final _objects = <(String, WeakReference<Object>)>[];

  /// Geometry texture descriptors since the previous report.
  static final allocations = <String>[];

  /// Observe ownership without retaining the observed object.
  static void observe(String kind, Object value) {
    if (!enabled) return;
    if (_objects.length == 256) _objects.removeAt(0);
    _objects.add((kind, WeakReference(value)));
  }

  /// Return diagnostics without collecting garbage or waiting for GPU work.
  static Map<String, Object> snapshot() {
    final alive = <String, int>{};
    final seen = <String, int>{};
    for (final (kind, reference) in _objects) {
      seen.update(kind, (value) => value + 1, ifAbsent: () => 1);
      if (reference.target != null) {
        alive.update(kind, (value) => value + 1, ifAbsent: () => 1);
      }
    }
    final result = <String, Object>{
      'seen': seen,
      'alive': alive,
      'allocations': List<String>.of(allocations),
      'uniform_block_bytes':
          FlutterGpuGeometryRenderer._sharedHostBufferBlockLength,
      'max_uniform_writes_per_timestamp':
          FlutterGpuGeometryRenderer._diagnosticMaxWrites,
    };
    allocations.clear();
    return result;
  }
}

/// A replaced texture and its render target, stamped with the frame count at
/// replacement.
final class _RetiredTarget {
  _RetiredTarget(this.texture, this.renderTarget, this.retiredFrame);

  final gpu.Texture texture;
  final gpu.RenderTarget renderTarget;
  final int retiredFrame;
}

class _SharedGeometryResources {
  _SharedGeometryResources({
    required gpu.Shader vertexShader,
    required gpu.Shader fragmentShader,
    required gpu.Shader materialGradientFragmentShader,
    required gpu.Shader materialTintGradientFragmentShader,
  }) {
    pipeline = gpu.gpuContext.createRenderPipeline(
      vertexShader,
      fragmentShader,
    );
    materialGradientPipeline = gpu.gpuContext.createRenderPipeline(
      vertexShader,
      materialGradientFragmentShader,
    );
    materialTintGradientPipeline = gpu.gpuContext.createRenderPipeline(
      vertexShader,
      materialTintGradientFragmentShader,
    );
    uniformSlot = fragmentShader.getUniformSlot('GeometryUniforms');
    uniformSize = uniformSlot.sizeInBytes ?? 0;
    offsetUOffset = uniformSlot.getMemberOffsetInBytes('uOffset') ?? 0;
    offsetUTextureSize =
        uniformSlot.getMemberOffsetInBytes('uTextureSize') ?? 0;
    offsetOpticalProps =
        uniformSlot.getMemberOffsetInBytes('uOpticalProps') ?? 0;
    offsetContourProps =
        uniformSlot.getMemberOffsetInBytes('uContourProps') ?? 0;
    offsetShapeData = uniformSlot.getMemberOffsetInBytes('uShapeData') ?? 0;
    offsetRseData = uniformSlot.getMemberOffsetInBytes('uRseData') ?? 0;
    offsetShapeTints = uniformSlot.getMemberOffsetInBytes('uShapeTints') ?? 0;
    offsetShapeResponses =
        uniformSlot.getMemberOffsetInBytes('uShapeResponses') ?? 0;
    offsetShapeBounds = uniformSlot.getMemberOffsetInBytes('uShapeBounds') ?? 0;
    final vertices = Float32List.fromList([
      -1.0, -1.0, 0.0, 0.0, //
      1.0, -1.0, 1.0, 0.0, //
      -1.0, 1.0, 0.0, 1.0, //
      1.0, 1.0, 1.0, 1.0, //
    ]);
    vertexBuffer = gpu.gpuContext.createDeviceBufferWithCopy(
      ByteData.sublistView(vertices),
    );
    vertexBufferView = gpu.BufferView(
      vertexBuffer,
      offsetInBytes: 0,
      lengthInBytes: vertexBuffer.sizeInBytes,
    );
  }

  late final gpu.RenderPipeline pipeline;
  late final gpu.RenderPipeline materialGradientPipeline;
  late final gpu.RenderPipeline materialTintGradientPipeline;
  late final gpu.UniformSlot uniformSlot;
  late final int uniformSize;
  late final int offsetUOffset;
  late final int offsetUTextureSize;
  late final int offsetOpticalProps;
  late final int offsetContourProps;
  late final int offsetShapeData;
  late final int offsetRseData;
  late final int offsetShapeTints;
  late final int offsetShapeResponses;
  late final int offsetShapeBounds;
  late final gpu.DeviceBuffer vertexBuffer;
  late final gpu.BufferView vertexBufferView;
}
