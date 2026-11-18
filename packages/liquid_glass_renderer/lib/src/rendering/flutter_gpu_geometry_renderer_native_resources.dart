part of 'flutter_gpu_geometry_renderer_native.dart';

/// The pipelines of an atlas pass that writes one set of looks, with their
/// uniform slots: one for shapes, one for a field. Without looks a field
/// pass reads no shapes, so it has no shape slot.
typedef _TilePipelines = ({
  gpu.RenderPipeline shapes,
  gpu.UniformSlot shapesUniforms,
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

/// The geometry shader bundle, loaded once ([load]): the pipelines and the
/// pages every renderer on it ([FlutterGpuGeometryRenderer.new]) places its
/// atlases in.
@internal
final class GeometryBundle {
  GeometryBundle._(this._pages);

  factory GeometryBundle._compile(
    gpu.Shader Function(String name) shader, {
    required bool oneTargetPerPass,
  }) {
    final vertex = shader(AtlasShader.vertex);
    gpu.RenderPipeline pipeline(gpu.Shader fragment) =>
        gpu.gpuContext.createRenderPipeline(
          vertex,
          fragment,
          vertexLayout: _tileVertexLayout,
        );
    _TilePipelines of(AtlasLooks looks, {AtlasTarget? only}) {
      final shapes = shader(
        AtlasShader(AtlasBody.shapes, looks, only: only).name,
      );
      final field = shader(
        AtlasShader(AtlasBody.field, looks, only: only).name,
      );
      final hasLooks = looks != AtlasLooks.none;
      return (
        shapes: pipeline(shapes),
        shapesUniforms: shapes.getUniformSlot('GeometryUniforms'),
        field: pipeline(field),
        fieldUniforms: field.getUniformSlot('TileFieldUniforms'),
        fieldTexture: field.getUniformSlot('uField'),
        fieldShapes: hasLooks ? field.getUniformSlot('GeometryUniforms') : null,
      );
    }

    final pipelines = [for (final looks in AtlasLooks.values) of(looks)];
    final onePerTarget = oneTargetPerPass
        ? List<_TilePipelines>.unmodifiable([
            for (final target in AtlasTarget.values)
              of(AtlasLooks.all, only: target),
          ])
        : null;
    final fieldSlot = pipelines.first.fieldUniforms;
    int tileField(String name) => fieldSlot.getMemberOffsetInBytes(name) ?? 0;
    final fieldOffsets = (
      bufferToGrid: tileField('uBufferToGrid'),
      gridShift: tileField('uGridShift'),
      fieldSize: tileField('uFieldSize'),
    );
    // The pass with looks reads every member.
    final slot = pipelines[AtlasLooks.all.index].shapesUniforms;
    int member(String name) => slot.getMemberOffsetInBytes(name) ?? 0;
    final offsets = (
      shapeData: member('uShapeData'),
      rseData: member('uRseData'),
      shapeBounds: member('uShapeBounds'),
      shapeLens: member('uShapeLens'),
      lookTints: member('uLookTints'),
      lookResponses: member('uLookResponses'),
    );
    return GeometryBundle._(
      List.unmodifiable([
        for (final targets in AtlasLooks.values)
          _Pages(
            pipelines: pipelines[targets.index],
            onePerTarget: onePerTarget,
            offsets: offsets,
            uniformSize: slot.sizeInBytes ?? 0,
            fieldOffsets: fieldOffsets,
            fieldUniformSize: fieldSlot.sizeInBytes ?? 0,
            lookCount: targets.count,
          ),
      ]),
    );
  }

  /// Loads the bundle at [assetKey]; a later call for the same bundle gives
  /// back what the first one loaded.
  static Future<GeometryBundle> load(String assetKey) async {
    if (_loaded[assetKey] case final bundle?) return bundle;
    final loading = _loading[assetKey] ??= () async {
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
      return GeometryBundle._compile(
        shader,
        oneTargetPerPass: _GpuBackend.oneColorAttachmentPerPass,
      );
    }();
    try {
      return _loaded[assetKey] = await loading;
    } finally {
      if (identical(_loading[assetKey], loading)) {
        unawaited(_loading.remove(assetKey));
      }
    }
  }

  static final Map<String, Future<GeometryBundle>> _loading = {};
  static final Map<String, GeometryBundle> _loaded = {};

  final List<_Pages> _pages;

  /// The class of the GPU the Flutter GPU context runs on, read from its
  /// capabilities: the backend as [_GpuBackend] tells it, and ASTC HDR,
  /// which starts at the A13 (Apple6).
  LiquidGlassDeviceClass get deviceClass {
    final context = gpu.gpuContext;
    if (_GpuBackend.openGLES) {
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
          entry.cols == field.columns &&
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
      if (entry.texture.width >= field.columns &&
          entry.texture.height >= field.rows &&
          frame - entry.frame >= _reuseAfterFrames) {
        slot = entry;
        break;
      }
    }
    if (slot == null) {
      final width = _capacity(field.columns);
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
      field.columns * field.rows * 4,
    );
    commands.copyBufferToTexture(
      stage(bytes),
      gpu.TextureRegion(slot.texture, width: field.columns, height: field.rows),
    );
    slot
      ..samples = field.samples
      ..cols = field.columns
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
