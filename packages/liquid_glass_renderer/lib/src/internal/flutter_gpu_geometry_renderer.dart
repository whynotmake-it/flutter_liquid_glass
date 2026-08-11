import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

/// Renders the liquid glass geometry SDF shader to a persistent GPU texture
/// using flutter_gpu.
///
/// The texture is only recreated when its dimensions change, eliminating the
/// per-frame texture allocation/disposal cycle that causes memory spikes
/// (Flutter issue #138627).
///
/// The [gpu.Texture.asImage] call returns a lightweight non-owning wrapper —
/// do NOT dispose it. The underlying texture is owned by this renderer and
/// persists across frames.
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
    // Cache uniform slot reflection info.
    _uniformSlot = fragmentShader.getUniformSlot('GeometryUniforms');
    _uniformSize = _uniformSlot.sizeInBytes ?? 0;
    _offsetUOffset = _uniformSlot.getMemberOffsetInBytes('uOffset') ?? 0;
    _offsetUTextureSize =
        _uniformSlot.getMemberOffsetInBytes('uTextureSize') ?? 0;
    _offsetOpticalProps =
        _uniformSlot.getMemberOffsetInBytes('uOpticalProps') ?? 0;
    _offsetShapeData = _uniformSlot.getMemberOffsetInBytes('uShapeData') ?? 0;
    _hostBuffer = _createUniformHostBuffer(_uniformSize);

    // Create the static full-screen quad vertex buffer.
    _createVertexBuffer();
  }

  factory FlutterGpuGeometryRenderer.fromAsset(String assetKey) {
    final resources = _assetResources.putIfAbsent(assetKey, () {
      final library = gpu.ShaderLibrary.fromAsset(assetKey);
      final vertexShader = library?['GeometryVertex'];
      final fragmentShader = library?['GeometryFragment'];
      if (vertexShader == null || fragmentShader == null) {
        throw StateError(
          'LiquidGlass requires Flutter GPU. Run with Flutter 3.44 or newer and '
          'enable Flutter GPU for the target platform.',
        );
      }
      return _SharedGeometryResources(
        vertexShader: vertexShader,
        fragmentShader: fragmentShader,
      );
    });
    return FlutterGpuGeometryRenderer._fromShared(resources);
  }

  FlutterGpuGeometryRenderer._fromShared(_SharedGeometryResources resources) {
    _pipeline = resources.pipeline;
    _hostBuffer = _createUniformHostBuffer(resources.uniformSize);
    _uniformSlot = resources.uniformSlot;
    _uniformSize = resources.uniformSize;
    _offsetUOffset = resources.offsetUOffset;
    _offsetUTextureSize = resources.offsetUTextureSize;
    _offsetOpticalProps = resources.offsetOpticalProps;
    _offsetShapeData = resources.offsetShapeData;
    _vertexBuffer = resources.vertexBuffer;
  }

  static final Map<String, _SharedGeometryResources> _assetResources = {};

  static gpu.HostBuffer _createUniformHostBuffer(int uniformSize) {
    final alignment = gpu.gpuContext.minimumUniformByteAlignment;
    final alignedSize =
        ((uniformSize + alignment - 1) ~/ alignment) * alignment;
    return gpu.gpuContext.createHostBuffer(
      blockLengthInBytes: alignedSize,
    );
  }

  late final gpu.RenderPipeline _pipeline;

  @visibleForTesting
  Object get debugPipelineIdentity => _pipeline;

  @visibleForTesting
  int get debugHostBufferBlockLength => _hostBuffer.blockLengthInBytes;

  /// Number of geometry command buffers submitted by this renderer.
  @visibleForTesting
  int debugRenderCount = 0;
  late final gpu.HostBuffer _hostBuffer;

  // Uniform slot reflection.
  late final gpu.UniformSlot _uniformSlot;
  late final int _uniformSize;
  late final int _offsetUOffset;
  late final int _offsetUTextureSize;
  late final int _offsetOpticalProps;
  late final int _offsetShapeData;

  // Persistent render target texture — reused across frames.
  gpu.Texture? _texture;
  ui.Image? _image;
  int _textureWidth = 0;
  int _textureHeight = 0;

  // Static full-screen quad vertex buffer (position.xy, texCoord.xy).
  late final gpu.DeviceBuffer _vertexBuffer;

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
  }

  /// Renders geometry to the persistent texture and returns it as a [ui.Image].
  ///
  /// The returned image is a non-owning wrapper — do NOT dispose it.
  /// The underlying texture persists across frames.
  ///
  /// Returns the image view backed by the persistent render target.
  ({ui.Image image, int width, int height}) render({
    required int width,
    required int height,
    required List<double> shapeData,
    required int numShapes,
    required double refractiveIndex,
    required double thickness,
    required double offsetX,
    required double offsetY,
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
    }

    final texture = _texture!;
    final renderTarget = gpu.RenderTarget.singleColor(
      gpu.ColorAttachment(texture: texture),
    );

    // Pack uniform data into a byte buffer using reflected offsets.
    _hostBuffer.reset();
    final uniformData = _packUniformData(
      offsetX: offsetX,
      offsetY: offsetY,
      textureWidth: allocatedWidth.toDouble(),
      textureHeight: allocatedHeight.toDouble(),
      refractiveIndex: refractiveIndex,
      thickness: thickness,
      numShapes: numShapes.toDouble(),
      shapeData: shapeData,
    );

    final uniformView = _hostBuffer.emplace(uniformData);

    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    commandBuffer.createRenderPass(renderTarget)
      ..bindPipeline(_pipeline)
      ..setPrimitiveType(gpu.PrimitiveType.triangleStrip)
      ..bindUniform(_uniformSlot, uniformView)
      ..bindVertexBuffer(
        gpu.BufferView(
          _vertexBuffer,
          offsetInBytes: 0,
          lengthInBytes: _vertexBuffer.sizeInBytes,
        ),
        4,
      )
      ..draw();
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

  ByteData _packUniformData({
    required double offsetX,
    required double offsetY,
    required double textureWidth,
    required double textureHeight,
    required double refractiveIndex,
    required double thickness,
    required double numShapes,
    required List<double> shapeData,
  }) {
    final data = ByteData(_uniformSize);
    final floatData = data.buffer.asFloat32List();

    // uOffset (vec2)
    final uOffsetIndex = _offsetUOffset ~/ 4;
    floatData[uOffsetIndex] = offsetX;
    floatData[uOffsetIndex + 1] = offsetY;

    // uTextureSize (vec2), used to convert OpenGL's bottom-up fragment
    // coordinates into Flutter's top-down coordinate system.
    final textureSizeIndex = _offsetUTextureSize ~/ 4;
    floatData[textureSizeIndex] = textureWidth;
    floatData[textureSizeIndex + 1] = textureHeight;

    // uOpticalProps (vec4)
    final opticalIndex = _offsetOpticalProps ~/ 4;
    floatData[opticalIndex] = refractiveIndex;
    floatData[opticalIndex + 1] =
        defaultTargetPlatform == TargetPlatform.android ? 1 : 0;
    floatData[opticalIndex + 2] = thickness;
    floatData[opticalIndex + 3] = numShapes;

    // uShapeData (vec4 array). Packing scalar shape values into vec4s avoids
    // std140's 16-byte stride for every individual float.
    final shapeDataStartIndex = _offsetShapeData ~/ 4;
    for (var i = 0; i < shapeData.length && i < 192; i++) {
      floatData[shapeDataStartIndex + i] = shapeData[i];
    }

    return data;
  }

  /// Releases the persistent texture.
  void dispose() {
    // gpu.Texture does not have an explicit dispose method.
    // The texture is garbage collected when no longer referenced.
    _texture = null;
    _image = null;
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
    final vertices = Float32List.fromList([
      -1.0,
      -1.0,
      0.0,
      0.0,
      1.0,
      -1.0,
      1.0,
      0.0,
      -1.0,
      1.0,
      0.0,
      1.0,
      1.0,
      1.0,
      1.0,
      1.0,
    ]);
    vertexBuffer = gpu.gpuContext.createDeviceBufferWithCopy(
      ByteData.sublistView(vertices),
    );
  }

  late final gpu.RenderPipeline pipeline;
  late final gpu.UniformSlot uniformSlot;
  late final int uniformSize;
  late final int offsetUOffset;
  late final int offsetUTextureSize;
  late final int offsetOpticalProps;
  late final int offsetShapeData;
  late final gpu.DeviceBuffer vertexBuffer;
}
