import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:meta/meta.dart';

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
  })  : _vertexShader = vertexShader,
        _fragmentShader = fragmentShader {
    _pipeline = gpu.gpuContext.createRenderPipeline(
      _vertexShader,
      _fragmentShader,
    );
    _hostBuffer = gpu.gpuContext.createHostBuffer();

    // Cache uniform slot reflection info.
    _uniformSlot = _fragmentShader.getUniformSlot('GeometryUniforms');
    _uniformSize = _uniformSlot.sizeInBytes ?? 0;
    _offsetUSize = _uniformSlot.getMemberOffsetInBytes('uSize') ?? 0;
    _offsetUOffset = _uniformSlot.getMemberOffsetInBytes('uOffset') ?? 0;
    _offsetOpticalProps =
        _uniformSlot.getMemberOffsetInBytes('uOpticalProps') ?? 0;
    _offsetNumShapes = _uniformSlot.getMemberOffsetInBytes('uNumShapes') ?? 0;
    _offsetShapeData = _uniformSlot.getMemberOffsetInBytes('uShapeData') ?? 0;

    // Create the static full-screen quad vertex buffer.
    _createVertexBuffer();
  }

  final gpu.Shader _vertexShader;
  final gpu.Shader _fragmentShader;
  late final gpu.RenderPipeline _pipeline;
  late final gpu.HostBuffer _hostBuffer;

  // Uniform slot reflection.
  late final gpu.UniformSlot _uniformSlot;
  late final int _uniformSize;
  late final int _offsetUSize;
  late final int _offsetUOffset;
  late final int _offsetOpticalProps;
  late final int _offsetNumShapes;
  late final int _offsetShapeData;

  // Persistent render target texture — reused across frames.
  gpu.Texture? _texture;
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
  /// Returns null if rendering fails (caller should fall back to old path).
  ui.Image? render({
    required int width,
    required int height,
    required double devicePixelRatio,
    required List<double> shapeData,
    required int numShapes,
    required double refractiveIndex,
    required double chromaticAberration,
    required double thickness,
    required double blend,
    required double offsetX,
    required double offsetY,
  }) {
    // Resize texture if needed (only allocates when size changes).
    if (_texture == null ||
        _textureWidth != width ||
        _textureHeight != height) {
      _texture = gpu.gpuContext.createTexture(
        gpu.StorageMode.devicePrivate,
        width,
        height,
      );
      _textureWidth = width;
      _textureHeight = height;
    }

    final texture = _texture!;
    final renderTarget = gpu.RenderTarget.singleColor(
      gpu.ColorAttachment(texture: texture),
    );

    // Pack uniform data into a byte buffer using reflected offsets.
    _hostBuffer.reset();
    final uniformData = _packUniformData(
      width: width.toDouble(),
      height: height.toDouble(),
      offsetX: offsetX,
      offsetY: offsetY,
      refractiveIndex: refractiveIndex,
      chromaticAberration: chromaticAberration,
      thickness: thickness,
      blend: blend,
      numShapes: numShapes.toDouble(),
      shapeData: shapeData,
    );

    final uniformView = _hostBuffer.emplace(uniformData);

    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = commandBuffer.createRenderPass(renderTarget);
    renderPass
      ..bindPipeline(_pipeline)
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

    return texture.asImage();
  }

  ByteData _packUniformData({
    required double width,
    required double height,
    required double offsetX,
    required double offsetY,
    required double refractiveIndex,
    required double chromaticAberration,
    required double thickness,
    required double blend,
    required double numShapes,
    required List<double> shapeData,
  }) {
    final data = ByteData(_uniformSize);
    final floatData = data.buffer.asFloat32List();

    // uSize (vec2)
    final uSizeIndex = _offsetUSize ~/ 4;
    floatData[uSizeIndex] = width;
    floatData[uSizeIndex + 1] = height;

    // uOffset (vec2)
    final uOffsetIndex = _offsetUOffset ~/ 4;
    floatData[uOffsetIndex] = offsetX;
    floatData[uOffsetIndex + 1] = offsetY;

    // uOpticalProps (vec4)
    final opticalIndex = _offsetOpticalProps ~/ 4;
    floatData[opticalIndex] = refractiveIndex;
    floatData[opticalIndex + 1] = chromaticAberration;
    floatData[opticalIndex + 2] = thickness;
    floatData[opticalIndex + 3] = blend;

    // uNumShapes (float)
    final numShapesIndex = _offsetNumShapes ~/ 4;
    floatData[numShapesIndex] = numShapes;

    // uShapeData (float array)
    // In std140, float arrays are packed with 16-byte stride per element.
    final shapeDataStartIndex = _offsetShapeData ~/ 4;
    const stride = 16 ~/ 4; // 4 floats per array element in std140
    for (var i = 0; i < shapeData.length && i < 96; i++) {
      floatData[shapeDataStartIndex + i * stride] = shapeData[i];
    }

    return data;
  }

  /// Releases the persistent texture.
  void dispose() {
    // gpu.Texture does not have an explicit dispose method.
    // The texture is garbage collected when no longer referenced.
    _texture = null;
  }
}
