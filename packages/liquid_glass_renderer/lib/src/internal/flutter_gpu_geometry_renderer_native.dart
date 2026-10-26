import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:liquid_glass_renderer/src/liquid_glass_field.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// The edge distance stored in low-res matte texels that are far away from
/// every shape. Must match `kFarInward` in `geometry_fragment.glsl`. The
/// texture is cleared to it.
@internal
const double kLowResFarInward = -4096;

/// Renders the liquid glass low-res matte (see `geometry_fragment.glsl`)
/// using flutter_gpu.
///
/// Each output keeps a current texture and one spare. Textures grow as needed;
/// rendering uses only the top-left area, with shader UVs adjusted to match.
/// Unchanged geometry reuses the image without rendering again.
///
/// Repeated renders in one frame may need another texture. Each output keeps
/// at most three textures (current plus two spares); scenes and GC can keep
/// dropped textures alive longer.
///
/// This renderer owns the image handles returned by [gpu.Texture.asImage].
/// Replacing/disposal releases those handles; recorded scenes hold independent
/// native references. A scene rasterized more than [reuseAfterFrames] frames
/// after it was recorded may show a newer matte.
@internal
class FlutterGpuGeometryRenderer {
  FlutterGpuGeometryRenderer._fromShared(_SharedGeometryResources resources) {
    _pipeline = resources.pipeline;
    _materialGradientPipeline = resources.materialGradientPipeline;
    _materialTintGradientPipeline = resources.materialTintGradientPipeline;
    _offsetULowRes = resources.offsetULowRes;
    _fieldPipeline = resources.fieldPipeline;
    _fieldUniformSlot = resources.fieldUniformSlot;
    _fieldTextureSlot = resources.fieldTextureSlot;
    _fieldUniformSize = resources.fieldUniformSize;
    _fieldOffsets = resources.fieldOffsets;
    _fieldUniformData = ByteData(_fieldUniformSize);
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
    _vertexBufferView = resources.vertexBufferView;
    _uniformData = ByteData(_uniformSize);
    assert(() {
      _debugActiveRendererCount++;
      return true;
    }(), 'Track live geometry renderers in debug builds.');
  }

  // Flutter's centered half-pixel coverage transition.
  static const double _geometryAaHalfWidth = 0.5;

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
      final fieldFragmentShader = library?['GeometryFieldFragment'];
      if (vertexShader == null ||
          fragmentShader == null ||
          materialGradientFragmentShader == null ||
          materialTintGradientFragmentShader == null ||
          fieldFragmentShader == null) {
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
        fieldFragmentShader: fieldFragmentShader,
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
  late final gpu.RenderPipeline _materialGradientPipeline;
  late final gpu.RenderPipeline _materialTintGradientPipeline;
  late final int _offsetULowRes;
  late final gpu.RenderPipeline _fieldPipeline;
  late final gpu.UniformSlot _fieldUniformSlot;
  late final gpu.UniformSlot _fieldTextureSlot;
  late final int _fieldUniformSize;
  late final _FieldUniformOffsets _fieldOffsets;
  late final ByteData _fieldUniformData;
  final _FieldTextures _fieldTextures = _FieldTextures();

  @visibleForTesting
  Object get debugPipelineIdentity => _pipeline;

  @visibleForTesting
  int get debugHostBufferBlockLength => _sharedHostBufferBlockLength;

  @visibleForTesting
  Object? get debugHostBufferIdentity => _sharedHostBuffer;

  /// Number of output-update calls, including material-only updates.
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
  int _writtenRseLowerFloats = 0;

  // Latest matte. Older scenes retain their own native references.
  gpu.Texture? _texture;
  ui.Image? _image;
  gpu.RenderTarget? _renderTarget;
  gpu.RenderTarget? _clearingRenderTarget;
  gpu.Texture? _materialTexture;
  ui.Image? _materialImage;
  gpu.RenderTarget? _materialRenderTarget;

  // Appearance blending is decorative and only visible while shapes merge.
  // One sample per 8x8 full-resolution block makes its SDF work 64x smaller.
  static const int materialRasterScale = 8;

  late final gpu.BufferView _vertexBufferView;

  /// Low-resolution contributor map from the latest appearance render.
  ///
  /// The map fills the top-left sub-rect of the image; its size follows from
  /// the matte size, as in the final shader.
  ui.Image? get materialImage => _materialImage;

  // The low-res matte is RGBA16F and is cleared to "far outside" (see
  // [kLowResFarInward]); the material maps are RGBA8.
  final _TextureRing _mattes = _TextureRing(
    format: gpu.PixelFormat.r16g16b16a16Float,
    clearValue: vm.Vector4(kLowResFarInward, 0, 0, 0),
  );
  final _TextureRing _materials = _TextureRing();

  /// Actual output draws, separate from calls that only retire a material map.
  @visibleForTesting
  int debugMatteDrawCount = 0;

  @visibleForTesting
  int debugMaterialDrawCount = 0;

  /// Renders a new low-res matte and returns it as a [ui.Image].
  ///
  /// The low-res matte has one texel for every [matteScale] x [matteScale]
  /// (2 or 4) block of matte pixels, plus one extra row and column for the
  /// far edge. It fills the top-left of the image, which is `textureWidth` x
  /// `textureHeight`. `width` and `height` are the matte's size in pixels.
  /// The returned image is a non-owning wrapper — do NOT dispose it. Its
  /// texture is written again [reuseAfterFrames] frames after a later render
  /// replaces it.
  ///
  /// With [writeMatte] false, retain the current matte and only replace (or
  /// retire) the material output. The caller must verify that geometry,
  /// raster dimensions and optical settings still match the encoded matte.
  ///
  /// With a [field], the matte encodes the body the field describes instead
  /// of the shapes, at [fieldScale] device pixels per logical pixel of the
  /// field; the material output still reads the shapes.
  ({ui.Image image, int width, int height, int textureWidth, int textureHeight})
  render({
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
    bool writeMatte = true,
    bool writeMaterials = false,
    bool writeTintOnly = false,
    List<double> appearanceData = const <double>[],
    List<double> rseData = const <double>[],
    List<double> rseLowerData = const <double>[],
    List<double> boundsData = const <double>[],
    required int matteScale,
    LiquidGlassField? field,
    double fieldScale = 1,
  }) {
    assert(
      matteScale == 2 || matteScale == 4,
      'The matte scale must be 2 or 4.',
    );
    final scale = matteScale;
    assert(() {
      debugRenderCount++;
      _debugTotalRenderCount++;
      return true;
    }(), 'Track geometry submissions in debug builds.');
    final matteWidth = _bucketDimension(width);
    final matteHeight = _bucketDimension(height);
    final (viewWidth, viewHeight) = _viewCapacity();

    _ensureFrameCounter();
    assert(
      writeMatte || _texture != null,
      'A material-only update requires an existing matte.',
    );
    if (writeMatte) {
      if (_texture != null) {
        // Release our handle; earlier submitted scenes hold their own.
        _image?.dispose();
        _image = null;
        _renderTarget = null;
        _clearingRenderTarget = null;
        _texture = null;
        assert(() {
          _debugActiveGeometryTextureCount--;
          return true;
        }(), 'Track replaced geometry textures in debug builds.');
      }
      // The shader writes every texel of the sub-rect; the rest of the texture
      // is undefined and never sampled, so no clear or copy is needed.
      // The low-res matte has a texel on both edges of the matte, so it
      // needs one more texel than width / scale in each direction.
      final matte = _mattes.next(
        _completedFrames,
        width: matteWidth ~/ scale + 1,
        height: matteHeight ~/ scale + 1,
        maxWidth: viewWidth ~/ scale + 1,
        maxHeight: viewHeight ~/ scale + 1,
      );
      _texture = matte.texture;
      _renderTarget = matte.renderTarget;
      _clearingRenderTarget = matte.clearingRenderTarget;
      _image = _texture!.asImage();
      assert(() {
        _debugActiveGeometryTextureCount++;
        return true;
      }(), 'Track live geometry textures in debug builds.');
    }

    final materialMapWidth = math.max(
      1,
      (matteWidth + materialRasterScale - 1) ~/ materialRasterScale,
    );
    final materialMapHeight = math.max(
      1,
      (matteHeight + materialRasterScale - 1) ~/ materialRasterScale,
    );
    final materialWidth = writeTintOnly
        ? materialMapWidth
        : math.max(16, materialMapWidth);
    final materialHeight = writeTintOnly
        ? materialMapHeight
        : materialMapHeight + 2;
    if (_materialTexture != null) {
      _materialImage?.dispose();
      _materialImage = null;
      _materialRenderTarget = null;
      _materialTexture = null;
      assert(() {
        _debugActiveMaterialTextureCount--;
        return true;
      }(), 'Track replaced material textures in debug builds.');
    }
    if (writeMaterials) {
      final material = _materials.next(
        _completedFrames,
        width: materialWidth,
        height: materialHeight,
        maxWidth: math.max(
          16,
          (viewWidth + materialRasterScale - 1) ~/ materialRasterScale,
        ),
        maxHeight:
            (viewHeight + materialRasterScale - 1) ~/ materialRasterScale + 2,
      );
      _materialTexture = material.texture;
      _materialRenderTarget = material.renderTarget;
      _materialImage = _materialTexture!.asImage();
      assert(() {
        _debugActiveMaterialTextureCount++;
        return true;
      }(), 'Track live material textures in debug builds.');
    } else {
      _materials.releaseCurrent(_completedFrames);
    }

    _packUniformData(
      offsetX: offsetX,
      offsetY: offsetY,
      textureWidth: matteWidth.toDouble(),
      textureHeight: matteHeight.toDouble(),
      refractionHeight: refractionHeight,
      refractionAmount: refractionAmount,
      edgeDistanceRange: edgeDistanceRange ?? math.max(12, refractionHeight),
      refractionFitsShape: refractionFitsShape,
      contourExtent: contourExtent,
      materialScale: writeMaterials ? materialRasterScale.toDouble() : 1.0,
      materialMapWidth: writeMaterials ? materialMapWidth.toDouble() : 1.0,
      materialMapHeight: writeMaterials ? materialMapHeight.toDouble() : 1.0,
      geometryAaHalfWidth: _geometryAaHalfWidth,
      numShapes: numShapes.toDouble(),
      shapeData: shapeData,
      rseData: rseData,
      rseLowerData: rseLowerData,
      appearanceData: appearanceData,
      boundsData: boundsData,
      matteScale: scale,
    );

    final uniformView = _hostBufferForUniformSize(_uniformSize)
        .emplace(_uniformData);

    if (writeMatte) {
      assert(() {
        debugMatteDrawCount++;
        return true;
      }(), 'Track matte draws in debug builds.');
      final geometryCommandBuffer = gpu.gpuContext.createCommandBuffer();
      gpu.Texture? fieldTexture;
      try {
        fieldTexture = field == null
            ? null
            : _uploadField(field, geometryCommandBuffer);
      } on Object {
        geometryCommandBuffer.submit();
        rethrow;
      }
      // Only texels near a shape hold anything but "far outside". When those
      // are a small part of the low-res matte, clear the texture to "far
      // outside" and draw just that part. The clear writes the same value the
      // shader would.
      final passWidth = matteWidth ~/ scale + 1;
      final passHeight = matteHeight ~/ scale + 1;
      final drawRect = _occupiedRect(
        shapeData: shapeData,
        boundsData: boundsData,
        numShapes: numShapes,
        offsetX: offsetX,
        offsetY: offsetY,
        contourExtent: contourExtent,
        width: matteWidth,
        height: matteHeight,
        scale: scale,
      );
      final geometryPass = geometryCommandBuffer.createRenderPass(
        drawRect == null ? _renderTarget! : _clearingRenderTarget!,
      )..setPrimitiveType(gpu.PrimitiveType.triangleStrip);
      if (field != null) {
        _packFieldUniformData(field, fieldScale, fieldTexture!);
        geometryPass
          ..bindPipeline(_fieldPipeline)
          ..bindUniform(
            _fieldUniformSlot,
            _hostBufferForUniformSize(
              _fieldUniformSize,
            ).emplace(_fieldUniformData),
          )
          ..bindTexture(_fieldTextureSlot, fieldTexture);
      } else {
        geometryPass
          ..bindPipeline(_pipeline)
          ..bindUniform(_uniformSlot, uniformView);
      }
      geometryPass.bindVertexBuffer(_vertexBufferView);
      _restrictTo(geometryPass, _texture!, passWidth, passHeight);
      if (drawRect != null) {
        geometryPass.setScissor(
          gpu.Scissor(
            x: drawRect.left,
            y: drawRect.top,
            width: drawRect.width,
            height: drawRect.height,
          ),
        );
      }
      geometryPass.draw(4);
      _submitOrDefer(geometryCommandBuffer);
    }
    if (writeMaterials) {
      assert(() {
        debugMaterialDrawCount++;
        return true;
      }(), 'Track material draws in debug builds.');
      final materialCommandBuffer = gpu.gpuContext.createCommandBuffer();
      final materialPass =
          materialCommandBuffer.createRenderPass(_materialRenderTarget!)
            ..bindPipeline(
              writeTintOnly
                  ? _materialTintGradientPipeline
                  : _materialGradientPipeline,
            )
            ..setPrimitiveType(gpu.PrimitiveType.triangleStrip)
            ..bindUniform(_uniformSlot, uniformView)
            ..bindVertexBuffer(_vertexBufferView);
      _restrictTo(
        materialPass,
        _materialTexture!,
        materialWidth,
        materialHeight,
      );
      materialPass.draw(4);
      _submitOrDefer(materialCommandBuffer);
    }

    return (
      image: _image!,
      width: matteWidth,
      height: matteHeight,
      textureWidth: _texture!.width,
      textureHeight: _texture!.height,
    );
  }

  /// The low-res matte texels (for a matte of [width] x [height] pixels at
  /// [scale]) that can hold anything but "far outside", or null to draw them
  /// all.
  ///
  /// This is the same test the geometry shader uses to skip a texel, done once
  /// for a whole rectangle: a texel farther from every shape's box than the
  /// border, two texels and the blend radius is "far outside". Without shape
  /// boxes there is nothing to go on, and when the rectangle covers most of
  /// the texture, the clear isn't worth it.
  static _PixelRect? _occupiedRect({
    required List<double> shapeData,
    required List<double> boundsData,
    required int numShapes,
    required double offsetX,
    required double offsetY,
    required double contourExtent,
    required int width,
    required int height,
    required int scale,
  }) {
    final count = math.min(numShapes, 16);
    if (count <= 0 ||
        boundsData.length < count * 4 ||
        shapeData.length < count * 12) {
      return null;
    }
    var smoothing = 0.0;
    var left = double.infinity;
    var top = double.infinity;
    var right = -double.infinity;
    var bottom = -double.infinity;
    for (var i = 0; i < count; i++) {
      final marker = shapeData[i * 12 + 11];
      if (marker >= 0) smoothing += marker * 0.25;
      left = math.min(left, boundsData[i * 4]);
      top = math.min(top, boundsData[i * 4 + 1]);
      right = math.max(right, boundsData[i * 4 + 2]);
      bottom = math.max(bottom, boundsData[i * 4 + 3]);
    }
    if (!(left.isFinite && top.isFinite && right.isFinite && bottom.isFinite)) {
      return null;
    }
    // One extra pixel covers float rounding in the shader's own test. The two
    // texels of margin make sure no visible pixel blends in a cleared
    // texel.
    final reach = contourExtent + 2 * scale + 2 + smoothing + 1;
    final x0 = (left - reach - offsetX).floor().clamp(0, width);
    final y0 = (top - reach - offsetY).floor().clamp(0, height);
    final x1 = (right + reach - offsetX).ceil().clamp(0, width);
    final y1 = (bottom + reach - offsetY).ceil().clamp(0, height);
    // The texels covering matte pixels x0..x1 (inclusive), and one more on
    // each side.
    final tx0 = (x0 ~/ scale - 1).clamp(0, width ~/ scale);
    final ty0 = (y0 ~/ scale - 1).clamp(0, height ~/ scale);
    final tx1 = ((x1 + scale - 1) ~/ scale + 2).clamp(0, width ~/ scale + 1);
    final ty1 = ((y1 + scale - 1) ~/ scale + 2).clamp(0, height ~/ scale + 1);
    if (tx1 <= tx0 || ty1 <= ty0) return const _PixelRect(0, 0, 1, 1);
    // On some GPUs a clear writes the whole texture once more. The low-res
    // matte is small, so that costs little, but it only pays off when most of
    // the texture can be skipped.
    final textureWidth = width ~/ scale + 1;
    final textureHeight = height ~/ scale + 1;
    if ((tx1 - tx0) * (ty1 - ty0) > 0.9 * textureWidth * textureHeight) {
      return null;
    }
    return _PixelRect(tx0, ty0, tx1 - tx0, ty1 - ty0);
  }

  /// The texture holding [field], its copy recorded on [geometry] where a
  /// copy may precede the geometry pass on one command buffer, else on a
  /// command buffer of its own submitted ahead of it.
  gpu.Texture _uploadField(
    LiquidGlassField field,
    gpu.CommandBuffer geometry,
  ) {
    final held = _fieldTextures.held(field, _completedFrames);
    if (held != null) return held;
    if (_uploadsShareCommandBuffer) {
      return _fieldTextures.upload(field, _completedFrames, geometry);
    }
    final upload = gpu.gpuContext.createCommandBuffer();
    try {
      final texture = _fieldTextures.upload(field, _completedFrames, upload);
      _submitOrDefer(upload);
      return texture;
    } on Object {
      upload.submit();
      rethrow;
    }
  }

  // A copy recorded before a render pass on the same command buffer is
  // encoded ahead of it on Vulkan and GLES. Metal opens a blit encoder when
  // the copy is recorded and closes it only on submit, so the render pass's
  // encoder would nest: there the copy gets its own command buffer,
  // submitted first.
  static final bool _uploadsShareCommandBuffer =
      !(Platform.isIOS || Platform.isMacOS);

  /// Writes the field pass's uniforms: the matte offset and scale the shape
  /// pass packed, and the field's frame in device pixels.
  void _packFieldUniformData(
    LiquidGlassField field,
    double fieldScale,
    gpu.Texture texture,
  ) {
    final from = _uniformData.buffer.asFloat32List();
    final to = _fieldUniformData.buffer.asFloat32List();
    void copy(int fromOffset, int toOffset, int count) {
      for (var i = 0; i < count; i++) {
        to[toOffset ~/ 4 + i] = from[fromOffset ~/ 4 + i];
      }
    }

    final offsets = _fieldOffsets;
    copy(_offsetULowRes, offsets.lowRes, 4);
    copy(_offsetUOffset, offsets.offset, 2);
    final frame = offsets.fieldFrame ~/ 4;
    to[frame] = field.origin.dx * fieldScale;
    to[frame + 1] = field.origin.dy * fieldScale;
    to[frame + 2] = field.step * fieldScale;
    to[frame + 3] = fieldScale;
    final size = offsets.fieldSize ~/ 4;
    to[size] = field.cols.toDouble();
    to[size + 1] = field.rows.toDouble();
    to[size + 2] = 1 / texture.width;
    to[size + 3] = 1 / texture.height;
  }

  /// Limits [pass] to the top-left [width] x [height] of [texture].
  ///
  /// `gl_FragCoord` stays framebuffer-relative, so the shaders need no
  /// offset for a sub-rect at the origin.
  static void _restrictTo(
    gpu.RenderPass pass,
    gpu.Texture texture,
    int width,
    int height,
  ) {
    if (texture.width == width && texture.height == height) return;
    pass
      ..setViewport(gpu.Viewport(width: width, height: height))
      ..setScissor(gpu.Scissor(width: width, height: height));
  }

  /// Largest view in physical pixels, the cap for texture growth.
  static (int, int) _viewCapacity() {
    var width = 0;
    var height = 0;
    for (final view in WidgetsBinding.instance.platformDispatcher.views) {
      width = math.max(width, view.physicalSize.width.ceil());
      height = math.max(height, view.physicalSize.height.ceil());
    }
    return (_bucketDimension(width), _bucketDimension(height));
  }

  static int _bucketDimension(int value) => (value + 63) & ~63;

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

  /// Frames to wait after retirement before reusing a texture.
  ///
  /// A texture retired in frame E was last read by frame E - 1. The engine's
  /// two-frame pipeline (`Animator.FramePipeline(2)`) submits that scene before
  /// frame E + 1 paints. Flutter GPU uses the same queue, which orders the next
  /// write after those reads (Metal/Vulkan hazards; GLES posting order).
  static const int reuseAfterFrames = 1;

  static int _completedFrames = 0;
  static bool _countingFrames = false;

  /// Counts scene-submitting frames for texture reuse.
  ///
  /// Renders outside a frame, as in unit tests, do not advance the count,
  /// so their textures are never reused.
  static void _ensureFrameCounter() {
    if (_countingFrames) return;
    _countingFrames = true;
    SchedulerBinding.instance.addPersistentFrameCallback((_) {
      if (!RendererBinding.instance.sendFramesToEngine) return;
      _completedFrames++;
    });
  }

  /// Textures this renderer holds that are not in use.
  @visibleForTesting
  int get debugRetiredTextureCount =>
      _mattes.spareCount + _materials.spareCount;

  /// Matte textures this renderer holds, including the one in use.
  @visibleForTesting
  int get debugMatteTextureCount => _mattes.textureCount;

  /// The latest matte texture, compared by identity in tests.
  @visibleForTesting
  Object? get debugMatteTexture => _texture;

  /// Size of the latest matte texture.
  @visibleForTesting
  (int, int)? get debugMatteTextureSize => switch (_texture) {
    final texture? => (texture.width, texture.height),
    null => null,
  };

  /// Renders that wrote into a reused texture instead of allocating one.
  @visibleForTesting
  static int debugReusedTextureCount = 0;

  /// Textures allocated, all renderers.
  @visibleForTesting
  static int debugAllocatedTextureCount = 0;

  /// Textures dropped, all renderers. Once a texture has lived a few young
  /// GCs its wrapper is promoted, and dropping it pins its storage until an
  /// old-generation GC.
  @visibleForTesting
  static int debugDroppedTextureCount = 0;

  static void _countDropped() {
    assert(() {
      debugDroppedTextureCount++;
      return true;
    }(), 'Count dropped geometry textures in debug builds.');
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
    required List<double> rseLowerData,
    required List<double> appearanceData,
    required List<double> boundsData,
    int matteScale = 0,
  }) {
    final floatData = _uniformData.buffer.asFloat32List();

    // Only the geometry pass has this uniform. It comes after the ones the
    // material passes share.
    if (matteScale > 0) floatData[_offsetULowRes ~/ 4] = matteScale.toDouble();

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
    // uOpticalProps.y is the centered-AA half-width: 0.5 (Flutter's
    // one-pixel transition) unless the harness overrides it.
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

    // A pair's bottom half sits in the second half of uRseData.
    final lowerStartIndex = rseDataStartIndex + 192;
    final lowerFloats = rseLowerData.length < 192 ? rseLowerData.length : 192;
    for (var i = 0; i < lowerFloats; i++) {
      floatData[lowerStartIndex + i] = rseLowerData[i];
    }
    for (var i = lowerFloats; i < _writtenRseLowerFloats; i++) {
      floatData[lowerStartIndex + i] = 0;
    }
    _writtenRseLowerFloats = lowerFloats;

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
    _mattes.release();
    _materials.release();
    _fieldTextures.release();
    _renderTarget = null;
    _clearingRenderTarget = null;
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

/// An integer pixel rectangle.
final class _PixelRect {
  const _PixelRect(this.left, this.top, this.width, this.height);
  final int left;
  final int top;
  final int width;
  final int height;
}

/// A texture and its render target.
final class _RingTexture {
  _RingTexture(this.texture, {vm.Vector4? clearValue})
    : _clearValue = clearValue,
      renderTarget = gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(
          texture: texture,
          loadAction: gpu.LoadAction.dontCare,
        ),
      );

  final vm.Vector4? _clearValue;

  final gpu.Texture texture;
  final gpu.RenderTarget renderTarget;

  /// Clears the whole texture before drawing, for passes that draw only part
  /// of it. It clears to the ring's `clearValue`, or transparent black when
  /// there is none. Created on first use.
  late final gpu.RenderTarget clearingRenderTarget =
      gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(texture: texture, clearValue: _clearValue),
      );

  /// Frame count when this texture was last replaced or released.
  int retiredFrame = 0;

  bool covers(int width, int height) =>
      texture.width >= width && texture.height >= height;
}

/// A current texture and up to two retired spares for one output.
///
/// Capacity grows in 1.5x steps, capped at the view unless a render needs more.
/// A second spare avoids allocations when a frame renders twice.
final class _TextureRing {
  _TextureRing({
    this.format = gpu.PixelFormat.r8g8b8a8UNormInt,
    this.clearValue,
  });

  /// Pixel format of the textures; the appearance maps are RGBA8.
  final gpu.PixelFormat format;

  /// What a clearing render target clears to; transparent black when null.
  final vm.Vector4? clearValue;

  static const int _maxSpares = 2;

  _RingTexture? _current;
  final List<_RingTexture> _spares = [];
  int _width = 0;
  int _height = 0;

  int get spareCount => _spares.length;
  int get textureCount => _spares.length + (_current == null ? 0 : 1);

  /// Replaces the texture in use with one that holds [width] x [height].
  _RingTexture next(
    int frame, {
    required int width,
    required int height,
    required int maxWidth,
    required int maxHeight,
  }) {
    if (width > _width || height > _height) {
      _width = _grow(_width, width, maxWidth);
      _height = _grow(_height, height, maxHeight);
      _spares.removeWhere((texture) {
        if (texture.covers(_width, _height)) return false;
        FlutterGpuGeometryRenderer._countDropped();
        return true;
      });
    }
    final previous = _current;
    _current = null;
    if (previous != null) {
      if (previous.covers(_width, _height)) {
        previous.retiredFrame = frame;
        _spares.add(previous);
      } else {
        FlutterGpuGeometryRenderer._countDropped();
      }
    }
    // Reuse the oldest spare only after its frame-age guard has passed.
    if (_spares.isNotEmpty &&
        frame - _spares.first.retiredFrame >=
            FlutterGpuGeometryRenderer.reuseAfterFrames) {
      assert(() {
        FlutterGpuGeometryRenderer.debugReusedTextureCount++;
        return true;
      }(), 'Count reused geometry textures in debug builds.');
      return _current = _spares.removeAt(0);
    }
    while (_spares.length > _maxSpares) {
      _spares.removeAt(0);
      FlutterGpuGeometryRenderer._countDropped();
    }
    return _current = _allocate(_width, _height);
  }

  /// Retires the texture in use without replacing it.
  void releaseCurrent(int frame) {
    final previous = _current;
    if (previous == null) return;
    _current = null;
    previous.retiredFrame = frame;
    _spares.add(previous);
  }

  /// Drops every texture and resets the ring's capacity.
  void release() {
    if (_current != null) {
      FlutterGpuGeometryRenderer._countDropped();
    }
    for (final _ in _spares) {
      FlutterGpuGeometryRenderer._countDropped();
    }
    _current = null;
    _spares.clear();
    _width = 0;
    _height = 0;
  }

  static int _grow(int capacity, int needed, int limit) {
    if (needed <= capacity) return capacity;
    if (capacity == 0) return needed;
    final stepped = (capacity * 3 + 1) >> 1;
    return math.max(needed, math.min(stepped, limit));
  }

  _RingTexture _allocate(int width, int height) {
    assert(() {
      FlutterGpuGeometryRenderer.debugAllocatedTextureCount++;
      return true;
    }(), 'Count allocated geometry textures in debug builds.');
    return _RingTexture(
      gpu.gpuContext.createTexture(
        gpu.StorageMode.devicePrivate,
        width,
        height,
        format: format,
      ),
      clearValue: clearValue,
    );
  }
}

class _SharedGeometryResources {
  _SharedGeometryResources({
    required gpu.Shader vertexShader,
    required gpu.Shader fragmentShader,
    required gpu.Shader materialGradientFragmentShader,
    required gpu.Shader materialTintGradientFragmentShader,
    required gpu.Shader fieldFragmentShader,
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
    fieldPipeline = gpu.gpuContext.createRenderPipeline(
      vertexShader,
      fieldFragmentShader,
    );
    fieldUniformSlot = fieldFragmentShader.getUniformSlot('FieldUniforms');
    fieldTextureSlot = fieldFragmentShader.getUniformSlot('uField');
    fieldUniformSize = fieldUniformSlot.sizeInBytes ?? 0;
    int field(String name) =>
        fieldUniformSlot.getMemberOffsetInBytes(name) ?? 0;
    fieldOffsets = (
      lowRes: field('uLowRes'),
      offset: field('uOffset'),
      fieldFrame: field('uFieldFrame'),
      fieldSize: field('uFieldSize'),
    );
    // The material passes use the same uniforms as the geometry pass, minus
    // the last one (the matte scale), so one buffer layout works for all of
    // them.
    uniformSlot = fragmentShader.getUniformSlot('GeometryUniforms');
    uniformSize = uniformSlot.sizeInBytes ?? 0;
    offsetULowRes = uniformSlot.getMemberOffsetInBytes('uLowRes') ?? 0;
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
  late final int offsetULowRes;
  late final gpu.RenderPipeline fieldPipeline;
  late final gpu.UniformSlot fieldUniformSlot;
  late final gpu.UniformSlot fieldTextureSlot;
  late final int fieldUniformSize;
  late final _FieldUniformOffsets fieldOffsets;
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

/// Byte offsets of the field pass's uniform members.
typedef _FieldUniformOffsets = ({
  int lowRes,
  int offset,
  int fieldFrame,
  int fieldSize,
});

/// The float textures a renderer uploads its fields into, reused: a body
/// whose field changes every frame - a menu opening - reuses its textures
/// instead of creating one per frame. A field fills the top-left of its
/// texture; the field pass reads only that region. The samples are copied
/// in by a command recorded on the caller's command buffer. At most four
/// textures survive; command buffers in flight retain theirs.
///
/// A slot is rewritten only three frames after its last use: the CPU
/// overwrites its staging buffer at once, which nothing orders behind a copy
/// from it the GPU may not have run yet, and Impeller keeps up to two frames
/// in flight besides the one being built (its Vulkan swapchain's
/// kMaxFramesInFlight).
final class _FieldTextures {
  static const int _reuseAfterFrames = 3;
  static const int _maxTextures = 4;
  static const int _bucket = 16;
  static const int _bytesPerNode = 16;

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

  /// A texture holding [field], its samples copied into it by a command
  /// recorded on [commands]; called when no texture [held] it.
  gpu.Texture upload(
    LiquidGlassField field,
    int frame,
    gpu.CommandBuffer commands,
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
        gpu.gpuContext.createDeviceBuffer(
          gpu.StorageMode.hostVisible,
          width * height * _bytesPerNode,
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
    slot.buffer.overwrite(bytes);
    commands.copyBufferToTexture(
      gpu.BufferView(
        slot.buffer,
        offsetInBytes: 0,
        lengthInBytes: bytes.lengthInBytes,
      ),
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
  _FieldTexture(this.texture, this.buffer);

  final gpu.Texture texture;
  final gpu.DeviceBuffer buffer;
  Float32List? samples;
  int cols = 0;
  int rows = 0;
  int frame = 0;
}
