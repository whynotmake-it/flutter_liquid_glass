import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

/// Renders the liquid glass geometry SDF shader to a persistent GPU texture
/// using flutter_gpu.
///
/// The geometry texture is only recreated when its dimensions change,
/// eliminating the per-frame allocation/disposal cycle (Flutter issue #138627).
///
/// [gpu.Texture.asImage] returns a lightweight non-owning wrapper — do NOT
/// dispose it. The underlying texture is owned by this renderer.
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
    _initCoordinateTexture();
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
    _initCoordinateTexture();
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

  static const int _hostBufferSlotsPerFrame = 32;

  static int _debugActiveRendererCount = 0;
  static int _debugActiveGeometryTextureCount = 0;
  static int _debugActiveMaterialTextureCount = 0;
  static int _debugActiveCoordinateTextureCount = 0;

  @visibleForTesting
  static int get debugActiveRendererCount => _debugActiveRendererCount;

  @visibleForTesting
  static int get debugActiveGeometryTextureCount =>
      _debugActiveGeometryTextureCount;

  @visibleForTesting
  static int get debugActiveMaterialTextureCount =>
      _debugActiveMaterialTextureCount;

  @visibleForTesting
  static int get debugActiveCoordinateTextureCount =>
      _debugActiveCoordinateTextureCount;

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

  // Persistent render target texture — reused across frames.
  gpu.Texture? _texture;
  ui.Image? _image;
  gpu.RenderTarget? _renderTarget;
  int _textureWidth = 0;
  int _textureHeight = 0;
  gpu.Texture? _materialTexture;
  ui.Image? _materialImage;
  gpu.RenderTarget? _materialRenderTarget;
  int _materialTextureWidth = 0;
  int _materialTextureHeight = 0;

  // Appearance blending is decorative and only visible while shapes merge.
  // One sample per 8x8 full-resolution block makes its SDF work 64x smaller.
  static const int materialRasterScale = 8;

  gpu.Texture? _coordinateTexture;
  ui.Image? _coordinateImage;
  final ByteData _coordinateData = ByteData(32);

  late final gpu.DeviceBuffer _vertexBuffer;
  late final gpu.BufferView _vertexBufferView;

  ui.Image? get coordinateImage => _coordinateImage;

  /// Low-resolution contributor map from the latest appearance render.
  ui.Image? get materialImage => _materialImage;

  void updateCoordinateMapping({
    required double basisXX,
    required double basisYX,
    required double basisXY,
    required double basisYY,
    required double originX,
    required double originY,
  }) {
    _initCoordinateTexture();
    final floats = _coordinateData.buffer.asFloat32List();
    if (floats[0] == basisXX &&
        floats[1] == basisYX &&
        floats[2] == basisXY &&
        floats[3] == basisYY &&
        floats[4] == originX &&
        floats[5] == originY) {
      return;
    }
    floats
      ..[0] = basisXX
      ..[1] = basisYX
      ..[2] = basisXY
      ..[3] = basisYY
      ..[4] = originX
      ..[5] = originY
      ..[6] = 0
      ..[7] = 0;
    _coordinateTexture!.overwrite(_coordinateData);
  }

  void _initCoordinateTexture() {
    if (_coordinateTexture != null) return;
    _coordinateTexture = gpu.gpuContext.createTexture(
      gpu.StorageMode.hostVisible,
      2,
      1,
      format: gpu.PixelFormat.r32g32b32a32Float,
      enableRenderTargetUsage: false,
    );
    if (_coordinateTexture!.isValid != true) {
      throw StateError('LiquidGlass coordinate mapping texture is invalid.');
    }
    _coordinateImage = _coordinateTexture!.asImage();
    assert(() {
      _debugActiveCoordinateTextureCount++;
      return true;
    }(), 'Track live coordinate textures in debug builds.');
  }

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

  /// Renders geometry to the persistent texture and returns it as a [ui.Image].
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
      return true;
    }(), 'Track geometry submissions in debug builds.');
    final allocatedWidth = _grownDimension(
      _textureWidth,
      _bucketDimension(width),
    );
    final allocatedHeight = _grownDimension(
      _textureHeight,
      _bucketDimension(height),
    );

    if (_texture == null ||
        allocatedWidth != _textureWidth ||
        allocatedHeight != _textureHeight) {
      if (_texture != null) {
        // Drop every wrapper which can retain the old texture before replacing
        // it. Metal may keep an in-flight command-buffer reference briefly,
        // but this renderer no longer owns the old allocation afterwards.
        _renderTarget = null;
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
      _textureWidth = allocatedWidth;
      _textureHeight = allocatedHeight;
      // The shader writes every pixel of the full-screen quad, so a clear is
      // wasted bandwidth on a persistent target.
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
    }

    if (!writeMaterials && _materialTexture != null) {
      _materialRenderTarget = null;
      _materialImage = null;
      _materialTexture = null;
      _materialTextureWidth = 0;
      _materialTextureHeight = 0;
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
      if (_materialTexture == null ||
          materialWidth != _materialTextureWidth ||
          materialHeight != _materialTextureHeight) {
        if (_materialTexture != null) {
          _materialRenderTarget = null;
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
        _materialTextureWidth = materialWidth;
        _materialTextureHeight = materialHeight;
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

  static int _grownDimension(int current, int requested) {
    if (requested <= current) return current;
    if (current == 0) return requested;
    final geometricGrowth = _bucketDimension((current * 1.5).ceil());
    return requested > geometricGrowth ? requested : geometricGrowth;
  }

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
    // Reuse the existing vec2 slot for profile spread and codec scale.
    floatData[textureSizeIndex] = refractionSpread.clamp(0.0, 1.0);
    floatData[textureSizeIndex + 1] = math.max(1e-3, displacementScale);

    final opticalPropsIndex = _offsetOpticalProps ~/ 4;
    floatData[opticalPropsIndex] = opticalIndex;
    // The Y slot is a harness-only centered-AA half-width. It defaults to
    // 0.5, matching Flutter's one-pixel transition; keeping it in the
    // existing reserved slot avoids changing the uniform ABI.
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

  /// Releases the persistent textures.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _renderTarget = null;
    _image = null;
    _materialRenderTarget = null;
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
    _coordinateImage = null;
    if (_coordinateTexture != null) {
      assert(() {
        _debugActiveCoordinateTextureCount--;
        return true;
      }(), 'Track disposed coordinate textures in debug builds.');
    }
    _coordinateTexture = null;
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
