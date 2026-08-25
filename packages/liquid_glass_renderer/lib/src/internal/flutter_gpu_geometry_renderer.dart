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
  }) {
    _pipeline = gpu.gpuContext.createRenderPipeline(
      vertexShader,
      fragmentShader,
    );
    _bindUniformLayout(fragmentShader);
    _createVertexBuffer();
    _uniformData = ByteData(_uniformSize);
    _initCoordinateTexture();
  }

  FlutterGpuGeometryRenderer._fromShared(_SharedGeometryResources resources) {
    _pipeline = resources.pipeline;
    _uniformSlot = resources.uniformSlot;
    _uniformSize = resources.uniformSize;
    _offsetUOffset = resources.offsetUOffset;
    _offsetUTextureSize = resources.offsetUTextureSize;
    _offsetOpticalProps = resources.offsetOpticalProps;
    _offsetShapeData = resources.offsetShapeData;
    _offsetRseData = resources.offsetRseData;
    _vertexBuffer = resources.vertexBuffer;
    _vertexBufferView = resources.vertexBufferView;
    _uniformData = ByteData(_uniformSize);
    _initCoordinateTexture();
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
      if (vertexShader == null || fragmentShader == null) {
        throw StateError(
          'LiquidGlass requires Flutter GPU. Run with Flutter 3.47 or newer '
          'and enable Flutter GPU for the target platform.',
        );
      }
      return _SharedGeometryResources(
        vertexShader: vertexShader,
        fragmentShader: fragmentShader,
      );
    }();
    try {
      final resources = await resourcesFuture;
      final renderer = FlutterGpuGeometryRenderer._fromShared(resources);
      _resolvedAssetResources[assetKey] = resources;
      if (identical(_assetResources[assetKey], resourcesFuture)) {
        _assetResources.remove(assetKey);
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

  // Coordinate mappings are tiny (two affine texels), but Texture.overwrite
  // still submits a staging blit and command buffer. Keep stable rows in a
  // shared atlas and batch all registered layer mappings on the first update
  // of a frame. The final shader selects its row with a stable float uniform,
  // so ancestor motion updates texel contents without rebuilding filters.
  static final _CoordinateAtlas _coordinateAtlas = _CoordinateAtlas();

  /// One bump allocator for every geometry pass in the current frame.
  ///
  /// HostBuffer retains four device-buffer blocks. Sizing each renderer to a
  /// single uniform used to be 1 MB × 4 × N layers; a shared scratch sized for
  /// a frame of layers keeps that off the native heap.
  static gpu.HostBuffer? _sharedHostBuffer;
  static int _sharedHostBufferBlockLength = 0;
  static Duration? _sharedHostBufferFrame;

  static const int _hostBufferSlotsPerFrame = 32;

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

  @visibleForTesting
  Object get debugPipelineIdentity => _pipeline;

  @visibleForTesting
  int get debugHostBufferBlockLength => _sharedHostBufferBlockLength;

  @visibleForTesting
  Object? get debugHostBufferIdentity => _sharedHostBuffer;

  /// Number of geometry command buffers submitted by this renderer.
  @visibleForTesting
  int debugRenderCount = 0;

  // Uniform slot reflection.
  late final gpu.UniformSlot _uniformSlot;
  late final int _uniformSize;
  late final int _offsetUOffset;
  late final int _offsetUTextureSize;
  late final int _offsetOpticalProps;
  late final int _offsetShapeData;
  late final int _offsetRseData;
  late final ByteData _uniformData;
  int _writtenShapeFloats = 0;
  int _writtenRseFloats = 0;

  // Persistent render target texture — reused across frames.
  gpu.Texture? _texture;
  ui.Image? _image;
  gpu.RenderTarget? _renderTarget;
  int _textureWidth = 0;
  int _textureHeight = 0;

  _CoordinateSlot? _coordinateSlot;

  late final gpu.DeviceBuffer _vertexBuffer;
  late final gpu.BufferView _vertexBufferView;

  ui.Image? get coordinateImage => _coordinateSlot?.image;

  /// Stable normalized row used by the final shader's coordinate atlas.
  double get coordinateRow => _coordinateSlot?.row ?? 0.5;

  void registerCoordinateMappingReader(CoordinateMappingReader reader) {
    _initCoordinateTexture();
    _coordinateAtlas.registerReader(this, reader);
  }

  /// Stops the shared atlas from calling a detached render object's transform
  /// reader while another layer is being painted.
  void unregisterCoordinateMappingReader() {
    _coordinateAtlas.unregisterReader(this);
  }

  void updateCoordinateMapping({
    required double basisXX,
    required double basisYX,
    required double basisXY,
    required double basisYY,
    required double originX,
    required double originY,
  }) {
    _initCoordinateTexture();
    _coordinateAtlas.update(
      this,
      (
        basisXX: basisXX,
        basisYX: basisYX,
        basisXY: basisXY,
        basisYY: basisYY,
        originX: originX,
        originY: originY,
      ),
    );
  }

  void _initCoordinateTexture() {
    _coordinateSlot ??= _coordinateAtlas.acquire(this);
  }

  void _bindUniformLayout(gpu.Shader fragmentShader) {
    _uniformSlot = fragmentShader.getUniformSlot('GeometryUniforms');
    _uniformSize = _uniformSlot.sizeInBytes ?? 0;
    _offsetUOffset = _uniformSlot.getMemberOffsetInBytes('uOffset') ?? 0;
    _offsetUTextureSize =
        _uniformSlot.getMemberOffsetInBytes('uTextureSize') ?? 0;
    _offsetOpticalProps =
        _uniformSlot.getMemberOffsetInBytes('uOpticalProps') ?? 0;
    _offsetShapeData = _uniformSlot.getMemberOffsetInBytes('uShapeData') ?? 0;
    _offsetRseData = _uniformSlot.getMemberOffsetInBytes('uRseData') ?? 0;
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
    double refractionSpread = 0.0,
    double? displacementScale,
    required double thickness,
    required double offsetX,
    required double offsetY,
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
      geometryAaHalfWidth: _geometryAaHalfWidth,
      numShapes: numShapes.toDouble(),
      shapeData: shapeData,
      rseData: rseData,
    );

    final uniformView = _hostBufferForUniformSize(
      _uniformSize,
    ).emplace(_uniformData);

    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    commandBuffer.createRenderPass(_renderTarget!)
      ..bindPipeline(_pipeline)
      ..setPrimitiveType(gpu.PrimitiveType.triangleStrip)
      ..bindUniform(_uniformSlot, uniformView)
      ..bindVertexBuffer(_vertexBufferView)
      ..draw(4);
    commandBuffer.submit();

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
    required double geometryAaHalfWidth,
    required double numShapes,
    required List<double> shapeData,
    required List<double> rseData,
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
  }

  /// Releases the persistent textures.
  void dispose() {
    _texture = null;
    _image = null;
    _renderTarget = null;
    _coordinateAtlas.release(this);
    _coordinateSlot = null;
  }
}

typedef CoordinateMapping = ({
  double basisXX,
  double basisYX,
  double basisXY,
  double basisYY,
  double originX,
  double originY,
});

typedef CoordinateMappingReader = CoordinateMapping Function();

class _CoordinateSlot {
  _CoordinateSlot(this.page, this.rowIndex);

  final _CoordinateAtlasPage page;
  final int rowIndex;

  double get row => (rowIndex + 0.5) / _CoordinateAtlasPage.rowsPerPage;
  ui.Image get image => page.image;
}

class _CoordinateAtlasPage {
  static const int rowsPerPage = 64;

  _CoordinateAtlasPage() {
    _data = ByteData(2 * rowsPerPage * 16);
    _freeRows.addAll(List<int>.generate(rowsPerPage, (index) => index));
  }

  late final ByteData _data;
  final List<int> _freeRows = <int>[];
  final Set<int> _dirtyRows = <int>{};
  gpu.Texture? _texture;
  ui.Image? _image;

  ui.Image get image {
    _ensureTexture();
    return _image!;
  }

  int? acquireRow() => _freeRows.isEmpty ? null : _freeRows.removeLast();

  void releaseRow(int row) {
    _freeRows.add(row);
    _dirtyRows.remove(row);
  }

  bool write(int row, CoordinateMapping mapping) {
    final floats = _data.buffer.asFloat32List();
    final first = row * 8;
    if (floats[first] == mapping.basisXX &&
        floats[first + 1] == mapping.basisYX &&
        floats[first + 2] == mapping.basisXY &&
        floats[first + 3] == mapping.basisYY &&
        floats[first + 4] == mapping.originX &&
        floats[first + 5] == mapping.originY) {
      return false;
    }
    floats
      ..[first] = mapping.basisXX
      ..[first + 1] = mapping.basisYX
      ..[first + 2] = mapping.basisXY
      ..[first + 3] = mapping.basisYY
      ..[first + 4] = mapping.originX
      ..[first + 5] = mapping.originY
      ..[first + 6] = 0
      ..[first + 7] = 0;
    _dirtyRows.add(row);
    return true;
  }

  void flush() {
    _ensureTexture();
    if (_dirtyRows.isEmpty) return;
    _texture!.overwrite(_data);
    _dirtyRows.clear();
  }

  void _ensureTexture() {
    if (_texture?.isValid == true && _image != null) return;
    _texture = gpu.gpuContext.createTexture(
      gpu.StorageMode.hostVisible,
      2,
      rowsPerPage,
      format: gpu.PixelFormat.r32g32b32a32Float,
      enableRenderTargetUsage: false,
    );
    if (_texture!.isValid != true) {
      throw StateError('LiquidGlass coordinate atlas texture is invalid.');
    }
    _image = _texture!.asImage();
    // A context recreation invalidates the old native texture but not the
    // CPU rows. Upload the full page when the replacement is first used.
    _dirtyRows.addAll(List<int>.generate(rowsPerPage, (index) => index));
  }
}

class _CoordinateAtlas {
  final List<_CoordinateAtlasPage> _pages = <_CoordinateAtlasPage>[];
  final Map<FlutterGpuGeometryRenderer, _CoordinateSlot> _slots =
      <FlutterGpuGeometryRenderer, _CoordinateSlot>{};
  final Map<FlutterGpuGeometryRenderer, CoordinateMappingReader> _readers =
      <FlutterGpuGeometryRenderer, CoordinateMappingReader>{};
  final Set<FlutterGpuGeometryRenderer> _preparedReaders =
      <FlutterGpuGeometryRenderer>{};
  Duration? _preparedFrame;

  _CoordinateSlot acquire(FlutterGpuGeometryRenderer renderer) {
    for (final page in _pages) {
      final row = page.acquireRow();
      if (row != null) {
        final slot = _CoordinateSlot(page, row);
        _slots[renderer] = slot;
        return slot;
      }
    }
    final page = _CoordinateAtlasPage();
    _pages.add(page);
    final row = page.acquireRow()!;
    final slot = _CoordinateSlot(page, row);
    _slots[renderer] = slot;
    return slot;
  }

  void registerReader(
    FlutterGpuGeometryRenderer renderer,
    CoordinateMappingReader reader,
  ) {
    _readers[renderer] = reader;
  }

  void unregisterReader(FlutterGpuGeometryRenderer renderer) {
    _readers.remove(renderer);
    _preparedReaders.remove(renderer);
  }

  void update(FlutterGpuGeometryRenderer renderer, CoordinateMapping mapping) {
    final slot = _slots[renderer];
    if (slot == null) return;
    final frame = SchedulerBinding.instance.currentSystemFrameTimeStamp;
    if (_preparedFrame != frame) {
      _preparedFrame = frame;
      _prepareFrame();
    }
    // A renderer can first appear after the initial frame preparation (for
    // example, a newly mounted independent layer). Upload its row once so it
    // never displays an uninitialized atlas entry.
    if (!_preparedReaders.contains(renderer)) {
      slot.page.write(slot.rowIndex, mapping);
      slot.page.flush();
      _preparedReaders.add(renderer);
    }
  }

  void _prepareFrame() {
    _preparedReaders.clear();
    for (final entry in _readers.entries) {
      final slot = _slots[entry.key];
      if (slot == null) continue;
      slot.page.write(slot.rowIndex, entry.value());
      _preparedReaders.add(entry.key);
    }
    for (final page in _pages) {
      page.flush();
    }
  }

  void release(FlutterGpuGeometryRenderer renderer) {
    final slot = _slots.remove(renderer);
    _readers.remove(renderer);
    _preparedReaders.remove(renderer);
    slot?.page.releaseRow(slot.rowIndex);
  }
}

class _SharedGeometryResources {
  _SharedGeometryResources({
    required gpu.Shader vertexShader,
    required gpu.Shader fragmentShader,
  }) {
    pipeline = gpu.gpuContext.createRenderPipeline(
      vertexShader,
      fragmentShader,
    );
    uniformSlot = fragmentShader.getUniformSlot('GeometryUniforms');
    uniformSize = uniformSlot.sizeInBytes ?? 0;
    offsetUOffset = uniformSlot.getMemberOffsetInBytes('uOffset') ?? 0;
    offsetUTextureSize =
        uniformSlot.getMemberOffsetInBytes('uTextureSize') ?? 0;
    offsetOpticalProps =
        uniformSlot.getMemberOffsetInBytes('uOpticalProps') ?? 0;
    offsetShapeData = uniformSlot.getMemberOffsetInBytes('uShapeData') ?? 0;
    offsetRseData = uniformSlot.getMemberOffsetInBytes('uRseData') ?? 0;
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
  late final gpu.UniformSlot uniformSlot;
  late final int uniformSize;
  late final int offsetUOffset;
  late final int offsetUTextureSize;
  late final int offsetOpticalProps;
  late final int offsetShapeData;
  late final int offsetRseData;
  late final gpu.DeviceBuffer vertexBuffer;
  late final gpu.BufferView vertexBufferView;
}
