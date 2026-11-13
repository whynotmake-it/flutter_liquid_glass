part of 'flutter_gpu_geometry_renderer_native.dart';

/// The pipelines of an atlas pass that writes one set of looks, with their
/// uniform slots: one for shapes, one for a field. Without looks a field
/// pass reads no shapes, so it has no shape slot.
typedef _TilePipelines = ({
  gpu.RenderPipeline geometry,
  gpu.UniformSlot geometryShapes,
  gpu.RenderPipeline field,
  gpu.UniformSlot fieldUniforms,
  gpu.UniformSlot fieldTexture,
  gpu.UniformSlot? fieldShapes,
});

/// Byte offsets of GeometryUniforms' members (geometry_uniforms.glsl).
typedef _GeometryUniformOffsets = ({
  int shapeData,
  int rseData,
  int shapeBounds,
  int shapeLens,
  int lookTints,
  int lookResponses,
});

class _SharedGeometryResources {
  _SharedGeometryResources(
    gpu.Shader Function(String name) shader, {
    required bool oneTargetPerPass,
  }) {
    final vertex = shader('TileVertex');
    gpu.RenderPipeline pipeline(gpu.Shader fragment) =>
        gpu.gpuContext.createRenderPipeline(
          vertex,
          fragment,
          vertexLayout: _tileVertexLayout,
        );
    _TilePipelines of(String looks, {required bool shapes}) {
      final geometry = shader('TileGeometry${looks}Fragment');
      final field = shader('TileField${looks}Fragment');
      return (
        geometry: pipeline(geometry),
        geometryShapes: geometry.getUniformSlot('GeometryUniforms'),
        field: pipeline(field),
        fieldUniforms: field.getUniformSlot('TileFieldUniforms'),
        fieldTexture: field.getUniformSlot('uField'),
        fieldShapes: shapes ? field.getUniformSlot('GeometryUniforms') : null,
      );
    }

    pipelines = List.unmodifiable([
      for (final targets in _LookTargets.values)
        of(targets.shaderSuffix, shapes: targets != _LookTargets.none),
    ]);
    onePerTarget = oneTargetPerPass
        ? List.unmodifiable([
            for (final only in const ['Matte', 'Tint', 'Response', 'Shares'])
              of('Only$only', shapes: true),
          ])
        : null;
    final fieldSlot = pipelines.first.fieldUniforms;
    tileFieldUniformSize = fieldSlot.sizeInBytes ?? 0;
    int tileField(String name) => fieldSlot.getMemberOffsetInBytes(name) ?? 0;
    tileFieldOffsets = (
      bufferToGrid: tileField('uBufferToGrid'),
      gridShift: tileField('uGridShift'),
      fieldSize: tileField('uFieldSize'),
    );
    // The pass with looks reads every member.
    final slot = pipelines[_LookTargets.all.index].geometryShapes;
    uniformSize = slot.sizeInBytes ?? 0;
    int member(String name) => slot.getMemberOffsetInBytes(name) ?? 0;
    offsets = (
      shapeData: member('uShapeData'),
      rseData: member('uRseData'),
      shapeBounds: member('uShapeBounds'),
      shapeLens: member('uShapeLens'),
      lookTints: member('uLookTints'),
      lookResponses: member('uLookResponses'),
    );
  }

  late final List<_TilePipelines> pipelines;

  /// Where a pass draws into one color attachment alone (Impeller's OpenGL
  /// ES backend), the pipelines that write an atlas with looks a target a
  /// pass: the geometry, then the tint, the response and the shares. Null
  /// where one pass writes them all.
  late final List<_TilePipelines>? onePerTarget;
  late final int tileFieldUniformSize;
  late final _TileFieldUniformOffsets tileFieldOffsets;
  late final int uniformSize;
  late final _GeometryUniformOffsets offsets;

  /// The pages every renderer of these resources places its atlases in,
  /// by the looks they write.
  late final List<_Pages> pages = List.unmodifiable([
    for (final targets in _LookTargets.values)
      _Pages(
        pipelines: pipelines[targets.index],
        onePerTarget: onePerTarget,
        offsets: offsets,
        uniformSize: uniformSize,
        fieldOffsets: tileFieldOffsets,
        fieldUniformSize: tileFieldUniformSize,
        lookCount: targets.count,
      ),
  ]);
}

/// Byte offsets of the tile field pass's uniform members.
typedef _TileFieldUniformOffsets = ({
  int bufferToGrid,
  int gridShift,
  int fieldSize,
});

/// The float textures a renderer uploads its fields into, reused: a body
/// whose field changes every frame - a menu opening - reuses its textures
/// instead of creating one per frame. A field fills the top-left of its
/// texture; the field pass reads only that region. The samples are copied
/// in by a command recorded on the caller's command buffer, from bytes
/// staged in the caller's scratch, which holds them until the GPU has run
/// that copy. At most four textures survive; command buffers in flight
/// retain theirs.
///
/// A slot is copied into again from the frame after its last use: a pass
/// of the frame being built may still bind it, and the GPU's queue orders
/// a later copy behind the passes submitted before it.
final class _FieldTextures {
  static const int _reuseAfterFrames = 1;
  static const int _maxTextures = 4;
  static const int _bucket = 16;

  final List<_FieldTexture> _textures = [];

  static int _capacity(int nodes) => (nodes + _bucket - 1) ~/ _bucket * _bucket;

  /// The texture already holding [field], marked as used in [frame], or
  /// null.
  gpu.Texture? held(LiquidGlassField field, int frame) {
    for (final entry in _textures) {
      if (identical(entry.samples, field.samples) &&
          entry.cols == field.cols &&
          entry.rows == field.rows) {
        entry.frame = frame;
        return entry.texture;
      }
    }
    return null;
  }

  /// A texture holding [field], its samples staged by [stage] and copied
  /// into it by a command recorded on [commands]; called when no texture
  /// [held] it.
  gpu.Texture upload(
    LiquidGlassField field,
    int frame,
    gpu.CommandBuffer commands,
    gpu.BufferView Function(ByteData bytes) stage,
  ) {
    _FieldTexture? slot;
    for (final entry in _textures) {
      if (entry.texture.width >= field.cols &&
          entry.texture.height >= field.rows &&
          frame - entry.frame >= _reuseAfterFrames) {
        slot = entry;
        break;
      }
    }
    if (slot == null) {
      final width = _capacity(field.cols);
      final height = _capacity(field.rows);
      slot = _FieldTexture(
        gpu.gpuContext.createTexture(
          gpu.StorageMode.devicePrivate,
          width,
          height,
          format: gpu.PixelFormat.r32g32b32a32Float,
          enableRenderTargetUsage: false,
        ),
      );
      if (_textures.length >= _maxTextures) {
        // The one used longest ago: a field held every frame keeps its own.
        _textures.remove(
          _textures.reduce((a, b) => a.frame <= b.frame ? a : b),
        );
      }
      _textures.add(slot);
    }
    final bytes = ByteData.sublistView(
      field.samples,
      0,
      field.cols * field.rows * 4,
    );
    commands.copyBufferToTexture(
      stage(bytes),
      gpu.TextureRegion(slot.texture, width: field.cols, height: field.rows),
    );
    slot
      ..samples = field.samples
      ..cols = field.cols
      ..rows = field.rows
      ..frame = frame;
    return slot.texture;
  }

  void release() => _textures.clear();
}

final class _FieldTexture {
  _FieldTexture(this.texture);

  final gpu.Texture texture;
  Float32List? samples;
  int cols = 0;
  int rows = 0;
  int frame = 0;
}
