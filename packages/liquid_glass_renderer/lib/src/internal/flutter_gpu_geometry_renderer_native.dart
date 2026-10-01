import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

/// Renders the liquid glass geometry SDF shader using flutter_gpu.
///
/// Each changed matte owns its texture: previously submitted Flutter scenes
/// may still sample the old matte with their old coordinate uniforms. Rewriting
/// that texture would mix frames. The layer reuses the image without calling
/// [render] when geometry is unchanged (including uniform translation).
///
/// This renderer owns the image handles returned by [gpu.Texture.asImage].
/// Replacing/disposal releases those handles; recorded scenes hold independent
/// native references. Direct callers needing a handle across renders can clone
/// it and must dispose their clone.
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
    _vertexBuffer = resources.vertexBuffer;
    _vertexBufferView = resources.vertexBufferView;
    _uniformData = ByteData(_uniformSize);
    assert(() {
      _debugActiveRendererCount++;
      return true;
    }(), 'Track live geometry renderers in debug builds.');
  }

  // Tuning knob for the Apple-match harness (`tool/apple_match`), not a
  // public material parameter. The default matches Flutter's centered
  // half-pixel coverage.
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
        // Drop resources that failed to build a renderer so the next layer
        // reloads the bundle instead of failing the same way.
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

  /// Completes once the Flutter GPU context exists without blocking.
  ///
  /// Workaround for Flutter 3.47.1 on Android: the engine creates the
  /// Impeller context on the raster thread after startup, off the critical
  /// path (`shell/common/shell.cc`), and reading `gpu.gpuContext` before
  /// then blocks the UI thread until it exists, which takes 100 ms or more on
  /// some Vulkan devices. The first rasterized frame needs the context, so
  /// waiting for it avoids the block. This initializes the widgets binding
  /// if needed, including before `runApp`. Remove it once the engine creates
  /// the context before the first frame or offers a non-blocking way to wait
  /// for it. On every other platform it completes immediately.
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
  /// A HostBuffer retains four device-buffer blocks, so one per renderer
  /// would cost four blocks per layer. A single scratch sized for a frame of
  /// layers keeps that off the native heap.
  static gpu.HostBuffer? _sharedHostBuffer;
  static int _sharedHostBufferBlockLength = 0;
  static Duration? _sharedHostBufferFrame;

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

  /// Renders a new immutable geometry texture and returns it as a [ui.Image].
  ///
  /// The returned image is a non-owning wrapper — do NOT dispose it.
  /// The underlying texture persists across frames.
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
  }) {
    assert(() {
      debugRenderCount++;
      _debugTotalRenderCount++;
      return true;
    }(), 'Track geometry submissions in debug builds.');
    final allocatedWidth = _bucketDimension(width);
    final allocatedHeight = _bucketDimension(height);

    if (_texture != null) {
      // Release our references, not those held by earlier submitted scenes.
      _renderTarget = null;
      _image?.dispose();
      _image = null;
      _texture = null;
      assert(() {
        _debugActiveGeometryTextureCount--;
        return true;
      }(), 'Track replaced geometry textures in debug builds.');
    }
    _texture = gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      allocatedWidth,
      allocatedHeight,
    );
    _image = _texture!.asImage();
    // The shader writes every pixel of the full-screen quad; no clear or
    // copy of the previous matte is needed.
    _renderTarget = gpu.RenderTarget.singleColor(
      gpu.ColorAttachment(
        texture: _texture!,
        loadAction: gpu.LoadAction.dontCare,
      ),
    );
    assert(() {
      _debugActiveGeometryTextureCount++;
      return true;
    }(), 'Track live geometry textures in debug builds.');

    if (!writeMaterials && _materialTexture != null) {
      _materialRenderTarget = null;
      _materialImage?.dispose();
      _materialImage = null;
      _materialTexture = null;
      assert(() {
        _debugActiveMaterialTextureCount--;
        return true;
      }(), 'Track released material textures in debug builds.');
    } else if (writeMaterials) {
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
      if (_materialTexture != null) {
        _materialRenderTarget = null;
        _materialImage?.dispose();
        _materialImage = null;
        _materialTexture = null;
        assert(() {
          _debugActiveMaterialTextureCount--;
          return true;
        }(), 'Track replaced material textures in debug builds.');
      }
      _materialTexture = gpu.gpuContext.createTexture(
        gpu.StorageMode.devicePrivate,
        materialWidth,
        materialHeight,
      );
      _materialImage = _materialTexture!.asImage();
      _materialRenderTarget = gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(
          texture: _materialTexture!,
          loadAction: gpu.LoadAction.dontCare,
        ),
      );
      assert(() {
        _debugActiveMaterialTextureCount++;
        return true;
      }(), 'Track live material textures in debug builds.');
    }

    _packUniformData(
      offsetX: offsetX,
      offsetY: offsetY,
      textureWidth: allocatedWidth.toDouble(),
      textureHeight: allocatedHeight.toDouble(),
      opticalIndex: opticalIndex,
      refractionSpread: refractionSpread,
      displacementScale:
          displacementScale ??
          math.max(
            1e-3,
            1.05 *
                8.0 *
                thickness *
                math.sqrt(math.max(0.0, opticalIndex * opticalIndex - 1.0)),
          ),
      thickness: thickness,
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
    );

    final uniformView = _hostBufferForUniformSize(
      _uniformSize,
    ).emplace(_uniformData);

    final geometryCommandBuffer = gpu.gpuContext.createCommandBuffer();
    geometryCommandBuffer.createRenderPass(_renderTarget!)
      ..bindPipeline(_pipeline)
      ..setPrimitiveType(gpu.PrimitiveType.triangleStrip)
      ..bindUniform(_uniformSlot, uniformView)
      ..bindVertexBuffer(_vertexBufferView)
      ..draw(4);
    geometryCommandBuffer.submit();
    if (writeMaterials) {
      final materialCommandBuffer = gpu.gpuContext.createCommandBuffer();
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
      materialCommandBuffer.submit();
    }

    return (image: _image!, width: allocatedWidth, height: allocatedHeight);
  }

  static int _bucketDimension(int value) => (value + 63) & ~63;

  void _packUniformData({
    required double offsetX,
    required double offsetY,
    required double textureWidth,
    required double textureHeight,
    required double opticalIndex,
    required double refractionSpread,
    required double displacementScale,
    required double thickness,
    required double contourExtent,
    required double materialScale,
    required double materialMapWidth,
    required double materialMapHeight,
    required double geometryAaHalfWidth,
    required double numShapes,
    required List<double> shapeData,
    required List<double> rseData,
    required List<double> appearanceData,
  }) {
    final floatData = _uniformData.buffer.asFloat32List();

    final uOffsetIndex = _offsetUOffset ~/ 4;
    floatData[uOffsetIndex] = offsetX;
    floatData[uOffsetIndex + 1] = offsetY;

    final textureSizeIndex = _offsetUTextureSize ~/ 4;
    // uTextureSize carries the profile spread and the codec scale.
    floatData[textureSizeIndex] = refractionSpread.clamp(0.0, 1.0);
    floatData[textureSizeIndex + 1] = math.max(1e-3, displacementScale);

    final opticalPropsIndex = _offsetOpticalProps ~/ 4;
    floatData[opticalPropsIndex] = opticalIndex;
    // uOpticalProps.y is the centered-AA half-width: 0.5 (Flutter's
    // one-pixel transition) unless the harness overrides it.
    floatData[opticalPropsIndex + 1] = geometryAaHalfWidth.clamp(0.0, 1.0);
    floatData[opticalPropsIndex + 2] = thickness;
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
  }

  /// Releases borrowed output handles, keeping reusable rendering resources.
  ///
  /// Callers retaining an output must clone its images before calling this.
  /// Independent clones and submitted native scenes remain valid.
  void releaseOutput() {
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
  late final gpu.DeviceBuffer vertexBuffer;
  late final gpu.BufferView vertexBufferView;
}
