// Explicit canvas save/transform/restore sequences are easier to audit than
// cascades across nested geometry loops.
// ignore_for_file: cascade_invocations

import 'dart:collection';
import 'dart:math';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/glass_shadow.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/glass_composition_probe.dart';
import 'package:liquid_glass_renderer/src/internal/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/internal/retained_glass_clip.dart';
import 'package:liquid_glass_renderer/src/internal/rounded_superellipse_parameters.dart';
import 'package:liquid_glass_renderer/src/internal/snap_rect_to_pixels.dart';
import 'package:liquid_glass_renderer/src/internal/transform_tracking_repaint_boundary_mixin.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_settings.dart';
import 'package:liquid_glass_renderer/src/logging.dart';

@internal
abstract interface class LiquidGlassLayerRenderObject {
  /// Everything this layer paints or samples, in its own coordinates, or
  /// `null` while it has no shapes: the material plus contour, the backdrop
  /// reach of its blur and refraction, and its exterior shadows. A
  /// `LiquidGlassCapture` sizes itself to the union of these. Reads layout and
  /// cached shape data only; it never polls or rebuilds geometry.
  Rect? get effectBounds;
}

/// Grows [bounds] to include the exterior shadows of [shapes], whose
/// coordinates map into the layer through their transforms.
@internal
Rect expandForGlassShadows(
  Rect bounds,
  Iterable<(List<ShapeGeometry>, Matrix4)> shapes,
  LiquidGlassSettings settings,
) {
  var result = bounds;
  for (final (geometryShapes, geometryToLayer) in shapes) {
    for (final shape in geometryShapes) {
      final shapeVisibility = shape.appearance.visibility.clamp(0.0, 1.0);
      if (shapeVisibility <= 0) continue;
      final shapeToLayer = shape.shapeToGeometry == null
          ? geometryToLayer
          : geometryToLayer.multiplied(shape.shapeToGeometry!);
      for (final shadow in shape.shadows) {
        final extent = max(
          shadow.spreadRadius +
              glassShadowBlurSupport(
                shadow.blurRadius * shapeVisibility,
              ),
          0,
        ).toDouble();
        final localBounds = (Offset.zero & shape.renderObject.size)
            .shift(shadow.offset)
            .inflate(extent);
        result = result.expandToInclude(
          MatrixUtils.transformRect(shapeToLayer, localBounds),
        );
      }
    }
  }
  return result;
}

/// Union of the geometry bounds registered with [link], in layer space, with
/// the shapes and transforms needed to grow it. Pure: no polling, no rebuild.
@internal
(Rect, List<(List<ShapeGeometry>, Matrix4)>)? gatherGlassGeometryBounds(
  GeometryRenderLink link,
  RenderObject layer,
) {
  Rect? bounds;
  final shapes = <(List<ShapeGeometry>, Matrix4)>[];
  for (final geometryRo in link.shapes) {
    if (!geometryRo.attached || !geometryRo.hasSize) continue;
    final (geometryBounds, geometryShapes, _) = geometryRo.gatherShapeData();
    if (geometryShapes.isEmpty) continue;
    final toLayer = geometryRo.getTransformTo(layer);
    final inLayer = MatrixUtils.transformRect(toLayer, geometryBounds);
    bounds = bounds?.expandToInclude(inLayer) ?? inLayer;
    shapes.add((geometryShapes, toLayer));
  }
  if (bounds == null) return null;
  return (bounds, shapes);
}

bool _debugWarnedOpacityBetweenShapeAndLayer = false;

/// Warns once per app when an [RenderOpacity] or [RenderAnimatedOpacity] sits
/// between one of [shapes] and its glass [layer], which would fade only the
/// glass's children. Returns `true` so it can run inside an `assert`.
@internal
bool debugCheckOpacityBetweenShapesAndLayer(
  RenderObject layer,
  Iterable<RenderObject> shapes,
) {
  if (_debugWarnedOpacityBetweenShapeAndLayer) return true;
  for (final shape in shapes) {
    for (
      var ancestor = shape.parent;
      ancestor != null && !identical(ancestor, layer);
      ancestor = ancestor.parent
    ) {
      if (ancestor is RenderOpacity || ancestor is RenderAnimatedOpacity) {
        _debugWarnedOpacityBetweenShapeAndLayer = true;
        debugPrint(
          'liquid_glass_renderer: an Opacity or FadeTransition between '
          'a LiquidGlass and its LiquidGlassLayer only fades the '
          "glass's children, not the glass. Fade glass with "
          'LiquidGlassVisibility or LiquidGlassAppearance.visibility '
          'instead.',
        );
        return true;
      }
    }
  }
  return true;
}

@internal
bool hasLiquidGlassLayerAncestor(RenderObject renderObject) {
  var ancestor = renderObject.parent;
  while (ancestor != null) {
    if (ancestor is LiquidGlassLayerRenderObject) return true;
    ancestor = ancestor.parent;
  }
  return false;
}

/// A render object that can assemble [RenderLiquidGlassGeometry] shapes and
/// render them to the screen with the liquid glass effect.
@internal
abstract class LiquidGlassRenderObject extends RenderProxyBox
    implements LiquidGlassLayerRenderObject {
  LiquidGlassRenderObject({
    required this._link,
    required this.defaultRenderShader,
    required this.materialRenderShader,
    required this.tintRenderShader,
    required LiquidGlassSettings this._settings,
    required this._defaultAppearance,
    required this._devicePixelRatio,
    required this._backdropKey,
    this._gpuGeometryRenderer,
  }) {
    _updateShaderSettings();
  }

  static final logger = Logger(LgrLogNames.render);

  final FragmentShader defaultRenderShader;
  final FragmentShader materialRenderShader;
  final FragmentShader tintRenderShader;
  FragmentShader get renderShader => switch ((
    _usesShapeAppearances,
    _usesTintOnlyAppearance,
  )) {
    (false, _) => defaultRenderShader,
    (true, true) => tintRenderShader,
    (true, false) => materialRenderShader,
  };

  Matrix4 get shaderCoordinateTransform => Matrix4.identity();

  late GeometryRenderLink _link;
  GeometryRenderLink get link => _link;
  set link(GeometryRenderLink value) {
    if (_link == value) return;
    markNeedsPaint();
    _link = value;
  }

  LiquidGlassSettings? _settings;
  LiquidGlassSettings get settings => _settings!;
  set settings(LiquidGlassSettings value) {
    if (_settings == value) return;
    final geometryInputsChanged =
        _settings?.effectiveRefractionHeight !=
            value.effectiveRefractionHeight ||
        _settings?.effectiveRefractionAmount !=
            value.effectiveRefractionAmount ||
        _settings?.refractionFitsShape != value.refractionFitsShape ||
        _settings?.contourWidth != value.contourWidth;
    _settings = value;
    _updateShaderSettings();
    if (geometryInputsChanged) needsGeometryUpdate = true;
    markNeedsPaint();
  }

  LiquidGlassAppearance _defaultAppearance;
  LiquidGlassAppearance get defaultAppearance => _defaultAppearance;
  set defaultAppearance(LiquidGlassAppearance value) {
    if (_defaultAppearance == value) return;
    _defaultAppearance = value;
    _updateShaderSettings();
    markNeedsPaint();
  }

  BackdropKey? _backdropKey;
  BackdropKey? get backdropKey => _backdropKey;
  set backdropKey(BackdropKey? value) {
    if (_backdropKey == value) return;
    _backdropKey = value;
    markNeedsPaint();
  }

  FlutterGpuGeometryRenderer? _gpuGeometryRenderer;
  FlutterGpuGeometryRenderer? get gpuGeometryRenderer => _gpuGeometryRenderer;
  set gpuGeometryRenderer(FlutterGpuGeometryRenderer? value) {
    if (_gpuGeometryRenderer == value) return;
    _gpuGeometryRenderer = value;
    markNeedsPaint();
  }

  double _devicePixelRatio;
  double get devicePixelRatio => _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    if (_settings != null) _updateShaderSettings();
    needsGeometryUpdate = true;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => _geometryImage != null;

  /// Pre-rendered geometry texture in screen space
  ui.Image? _geometryImage;
  ui.Image? _materialImage;
  bool _ownsGeometryImages = false;

  /// The bounding box of the geometry matte in the coordinate space of the
  /// shader
  Rect _geometryMatteBounds = Rect.zero;
  Offset _materialCenterInMatte = Offset.zero;
  // The matte and material map fill the top-left of textures that only grow.
  Size _geometryTextureSize = Size.zero;
  Size _materialTextureSize = const Size(1, 1);

  /// Shorter side in logical pixels of the smallest shape in this layer.
  /// Adaptive color models use it to choose the material density; it is
  /// resolved once per geometry update, never per fragment.
  double _materialShortSide = 10000;

  /// The pre-rendered geometry texture in screen space.
  ///
  /// Exposed for subclasses that render additional passes (such as the separate
  /// specular layer) from the same geometry texture.
  @protected
  ui.Image? get geometryImage => _geometryImage;

  @visibleForTesting
  ui.Image? get debugGeometryImage => _geometryImage;

  /// The bounding box of the geometry matte in screen space.
  ///
  /// Exposed for subclasses that need to map the geometry texture into their
  /// own coordinate space.
  @protected
  Rect get geometryMatteBounds => _geometryMatteBounds;

  @override
  @mustCallSuper
  void attach(PipelineOwner owner) {
    super.attach(owner);
  }

  @override
  @mustCallSuper
  void detach() {
    super.detach();
  }

  LiquidGlassAppearance? _uniformAppearance;
  List<LiquidGlassAppearance> _shapeAppearances = const [];
  bool _usesShapeAppearances = false;
  bool _usesTintOnlyAppearance = false;

  /// Whether the latest geometry pass writes per-shape contributor data.
  @visibleForTesting
  bool get debugUsesShapeAppearances => _usesShapeAppearances;

  /// Whether only tint differs, allowing one filtered appearance lookup.
  @visibleForTesting
  bool get debugUsesTintOnlyAppearance => _usesTintOnlyAppearance;

  /// The optional contributor texture sampled by the final material pass.
  @visibleForTesting
  ui.Image? get debugMaterialImage => _materialImage;

  void _updateShaderSettings() {
    _shaderInputsChanged = true;
    final appearance = _uniformAppearance ?? defaultAppearance;
    _writeCommonShaderUniforms(
      defaultRenderShader,
      appearance,
      _materialCenterInMatte,
    );
    _writeCommonShaderUniforms(
      materialRenderShader,
      appearance,
      _materialCenterInMatte,
    );
    _writeCommonShaderUniforms(
      tintRenderShader,
      appearance,
      _materialCenterInMatte,
    );
  }

  void _writeCommonShaderUniforms(
    FragmentShader shader,
    LiquidGlassAppearance appearance,
    Offset materialCenter,
  ) {
    // The final shader fades the whole material with visibility, so the
    // color factors are written at full strength.
    shader.setFloatUniforms(initialIndex: 6, (value) {
      value
        ..setColor(appearance.tint)
        ..setFloats([
          settings.effectiveDisplacementScale * devicePixelRatio,
          settings.dispersion,
          settings.effectiveEdgeDistanceRange * devicePixelRatio,
          settings.highlight,
          1 - settings.effectiveBackdropShrink,
          appearance.saturation,
        ])
        ..setOffset(
          const Offset(0, 1),
        )
        ..setColor(const Color.fromARGB(255, 255, 255, 255))
        ..setColor(
          Color.fromARGB(
            (settings.contourStrength.clamp(0.0, 1.0) * 255).round(),
            0,
            0,
            0,
          ),
        )
        // Rim geometry the presets share; see [GlassRim].
        ..setFloats([
          GlassRim.bevelShadowDirectionality,
          0, // bevel shadow size response
          GlassRim.highlightWidth * devicePixelRatio,
          GlassRim.highlightOppositeStrength,
        ])
        ..setFloats([
          settings.contourWidth * devicePixelRatio,
          0, // contour transmittance
          settings.contourDirectionality,
        ])
        ..setFloats([
          0, // contour offset
          materialCenter.dx * devicePixelRatio,
          materialCenter.dy * devicePixelRatio,
          GlassRim.highlightWrap,
        ])
        ..setFloats([
          appearance.transmissionGamma,
          appearance.vibrancy,
          settings.effectiveTintAmount,
        ])
        ..setFloats([
          settings.bevelShadowStrength,
          GlassRim.bevelShadowDepth * devicePixelRatio,
          GlassRim.bevelShadowOffset * devicePixelRatio,
        ])
        ..setFloats([
          appearance.colorModel.shaderValue,
          appearance.visibility,
          FlutterGpuGeometryRenderer.materialRasterScale.toDouble(),
          _materialShortSide,
        ]);
    });
    // Float indices 53 and 54, after the 47-float common block and the
    // 6-float filter->matte mapping: frosted glass cross-fades its blur away,
    // while unfrosted glass stays alpha-1 and cross-fades its material in the
    // shader, so both match the backdrop exactly at visibility 0.
    shader
      ..setFloat(53, blurPassSigma > 0 ? 1 : 0)
      ..setFloat(54, softensInShader ? 1 : 0);
  }

  /// Largest frost, in device pixels, folded into the final pass instead of
  /// a separate blur pass. Enabling the blur pass costs about four command
  /// buffers per frame on Metal regardless of its radius.
  static const double shaderSofteningMaxDeviceSigma = 1.25;

  /// Whether the frost is small enough for the final pass's softening kernel.
  bool get softensInShader {
    final frost = _frostSigma;
    return frost > 0 &&
        frost * devicePixelRatio <= shaderSofteningMaxDeviceSigma;
  }

  /// Sigma of the separate backdrop blur pass; `0` when there is none.
  double get blurPassSigma => softensInShader ? 0 : _frostSigma;

  double get _frostSigma => settings.effectiveFrost;

  List<double> _appearanceLookupData(
    List<LiquidGlassAppearance> appearances,
  ) {
    // This is used only for mixed frames; unused lookup rows must not depend
    // on the owner's active (possibly different) uniform frame.
    final fallback = defaultAppearance;
    LiquidGlassAppearance at(int index) =>
        index < appearances.length ? appearances[index] : fallback;
    return <double>[
      for (var i = 0; i < 16; i++) ...<double>[
        at(i).tint.r,
        at(i).tint.g,
        at(i).tint.b,
        at(i).tint.a,
      ],
      for (var i = 0; i < 16; i++) ...<double>[
        at(i).saturation / 4,
        at(i).transmissionGamma / 4,
        at(i).vibrancy / 4,
        (at(i).visibility + at(i).colorModel.shaderValue * 2) / 7,
      ],
    ];
  }

  void _setShapeAppearances(List<LiquidGlassAppearance> appearances) {
    final (usesShapeAppearances, usesTintOnlyAppearance, uniformAppearance) =
        _classifyShapeAppearances(appearances, defaultAppearance);
    if (_usesShapeAppearances == usesShapeAppearances &&
        _usesTintOnlyAppearance == usesTintOnlyAppearance &&
        _uniformAppearance == uniformAppearance &&
        listEquals(_shapeAppearances, appearances)) {
      return;
    }
    _usesShapeAppearances = usesShapeAppearances;
    _usesTintOnlyAppearance = usesTintOnlyAppearance;
    _uniformAppearance = uniformAppearance;
    _shapeAppearances = List.unmodifiable(appearances);
    _updateShaderSettings();
  }

  ui.Rect _paintBounds = ui.Rect.zero;

  @override
  ui.Rect get paintBounds => _paintBounds;

  /// Number of times [paint] has run. Ancestor motion should not increment
  /// this once geometry has been encoded.
  @visibleForTesting
  int debugPaintCount = 0;

  final List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)>
  _shapesWithGeometry = [];
  final List<_EncodedGeometryInput> _encodedGeometryInputs = [];
  List<_EncodedGeometryInput>? _idleGeometryInputs;
  List<_EncodedGeometryInput>? _emptyGeometryInputs;
  bool _drawableEmpty = false;

  @protected
  bool get drawableEmpty => _drawableEmpty;
  Rect? _encodedGeometryBounds;
  final _effectLayer = LayerHandle<OffsetLayer>();
  final _originalShadows = LayerHandle<ContainerLayer>();
  final _ancestorClips = RetainedGlassClip();
  final _idleAncestorClips = RetainedGlassClip();
  bool _idleComposition = false;
  List<Object> _retainedStructure = [];
  Offset _retainedPaintOffset = Offset.zero;

  /// Refreshes already recorded contributors before layer-tree descent.
  /// No child painting occurs here, and the unchanged/translation paths do
  /// not call this method or evaluate geometry.
  @protected
  bool refreshRetainedGeometry(
    void Function(
      List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)>,
      Rect,
      Offset,
    )
    updateMaterial,
  ) {
    if ((_geometryImage == null && !_drawableEmpty) ||
        _idleComposition ||
        debugPaintLiquidGlassGeometry) {
      return false;
    }
    final candidate = <(RenderLiquidGlassGeometry, GeometryCache, Matrix4)>[];
    final bounds = _collectFrameGeometry(candidate);
    // Topology changes need normal painting to rebuild clip ancestry.
    if (bounds == null ||
        !listEquals(_retainedStructure, _geometryStructure(candidate))) {
      return false;
    }
    _commitFrameGeometry(candidate);
    final materialBounds = _prepareGeometryAppearance(bounds);
    if (_drawableEmpty) {
      _rememberGeometryInputs(_emptyGeometryInputs ??= []);
    } else {
      // Keep old borrowed handles valid until the replacement is installed.
      if (!_ownsGeometryImages && _geometryImage != null) {
        final geometry = _geometryImage!.clone();
        ui.Image? material;
        try {
          material = _materialImage?.clone();
        } catch (_) {
          geometry.dispose();
          rethrow;
        }
        _geometryImage = geometry;
        _materialImage = material;
        _ownsGeometryImages = true;
      }
      final result = _buildGpuGeometryImage(_shapesWithGeometry, bounds);
      _releaseGeometryImageHandles();
      _geometryImage = result.image;
      _materialImage = result.materialImage;
      _geometryMatteBounds = result.matteBounds;
      _geometryTextureSize = result.textureSize;
      _materialTextureSize = result.materialTextureSize;
      _materialCenterInMatte = result.materialCenter;
      _setShapeAppearances(result.appearances);
      _rememberEncodedGeometry(bounds);
      _emptyGeometryInputs = null;
      _bindGeometryShader(result.image);
    }
    needsGeometryUpdate = false;
    link
      ..updateAllGeometries()
      .._dirty = false;
    _recordOriginalShadows(_retainedPaintOffset);
    updateMaterial(_shapesWithGeometry, materialBounds, _retainedPaintOffset);
    syncAncestorClips();
    return true;
  }

  List<Object> _geometryStructure(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
  ) => [
    for (final entry in geometries)
      for (final shape in entry.$2.shapes) ...[
        shape.renderObject,
        shape.shadows.isNotEmpty,
        for (
          var node = shape.renderObject.parent;
          node != null && !identical(node, this);
          node = node.parent
        )
          node,
      ],
  ];

  /// Bounds of the clips between this object and its shapes that are
  /// re-applied around the glass filter, in local coordinates, or `null`.
  @protected
  Rect? get retainedClipBounds =>
      _idleComposition ? null : _ancestorClips.ownerBounds;

  @protected
  void syncAncestorClips() =>
      (_idleComposition ? _idleAncestorClips : _ancestorClips).sync();
  Offset _effectTranslation = Offset.zero;

  /// Translation applied to the retained layer-owned effect since paint.
  @protected
  Offset get compositorTranslation => _effectTranslation;

  @visibleForTesting
  Offset get debugCompositorTranslation => _effectTranslation;

  /// Moves all layer-owned painting without recording it again.
  @protected
  bool setCompositorTranslation(Offset value) {
    if (_nearOffset(_effectTranslation, value)) return false;
    _effectTranslation = value;
    _effectLayer.layer?.offset = value;
    return true;
  }

  // MARK: Painting

  final _compositionProbe = GlassCompositionProbe();
  final _framePoll = FramePollMarker();

  @override
  @nonVirtual
  void paint(PaintingContext context, Offset offset) {
    _compositionProbe.paint(
      context,
      offset,
      _paintOriginal,
      owner: this,
    );
  }

  void _paintOriginal(PaintingContext context, Offset offset) {
    _retainedPaintOffset = offset;
    assert(() {
      debugPaintCount++;
      return true;
    }(), 'Track layer paints in debug builds.');
    logger.finest(
      '$hashCode Painting liquid glass with '
      '${link._shapeGeometries.length} shapes.',
    );
    final boundingBox = _gatherFrameGeometry();
    if (boundingBox == null) {
      _clearGeometryImage();
      releaseCompositorFilter();
      _effectLayer.layer = null;
      super.paint(context, offset);
      return;
    }

    final materialPaintBounds = _prepareGeometryAppearance(boundingBox);

    final hasVisibleShape = _shapesWithGeometry.any(
      (entry) => entry.$2.shapes.any(
        (shape) => shape.appearance.visibility > 0,
      ),
    );
    if (!hasVisibleShape) {
      _idleComposition = true;
      // Foreground can change while a cached matte is dormant. Poll against
      // its last paint without overwriting that matte's encoded coordinates.
      _rememberGeometryInputs(_idleGeometryInputs ??= []);
      _idleAncestorClips.update(
        this,
        _shapesWithGeometry.expand(
          (entry) => entry.$2.shapes.map((shape) => shape.renderObject),
        ),
      );
      // Keep any existing matte so ancestor motion stays compositor-only.
      // Skip the backdrop filter so idle glass does not sample.
      releaseCompositorFilter();
      _paintRetainedEffect(
        context,
        offset,
        (effectContext, effectOffset) {},
      );
      super.paint(context, offset);
      return;
    }

    _idleGeometryInputs = null;
    if (_drawableEmpty) {
      _rememberGeometryInputs(_emptyGeometryInputs ??= []);
      needsGeometryUpdate = false;
      link._dirty = false;
    } else if (_emptyGeometryInputs != null ||
        needsGeometryUpdate ||
        _geometryImage == null ||
        link._dirty) {
      link
        ..updateAllGeometries()
        .._dirty = false;

      final canReuseTranslatedGeometry =
          !needsGeometryUpdate &&
          _emptyGeometryInputs == null &&
          _geometryImage != null &&
          _reuseUniformlyTranslatedGeometry(boundingBox);
      needsGeometryUpdate = false;

      if (!canReuseTranslatedGeometry) {
        _clearGeometryImage();
        final gpuResult = _buildGpuGeometryImage(
          _shapesWithGeometry,
          boundingBox,
        );
        _geometryImage = gpuResult.image;
        _materialImage = gpuResult.materialImage;
        _geometryMatteBounds = gpuResult.matteBounds;
        _geometryTextureSize = gpuResult.textureSize;
        _materialTextureSize = gpuResult.materialTextureSize;
        _materialCenterInMatte = gpuResult.materialCenter;
        _setShapeAppearances(gpuResult.appearances);
        _rememberEncodedGeometry(boundingBox);
      }
      _emptyGeometryInputs = null;
    }

    void paintOriginalEffect(PaintingContext context, Offset offset) {
      _paintRetainedEffect(context, offset, (effectContext, effectOffset) {
        if (debugPaintLiquidGlassGeometry) {
          _debugPaintGeometry(effectContext, effectOffset);
        } else if (_drawableEmpty || _geometryImage != null) {
          if (!_drawableEmpty) _bindGeometryShader(_geometryImage!);
          _recordOriginalShadows(effectOffset);
          if (_originalShadows.layer case final shadows?) {
            effectContext.addLayer(shadows);
          }
          paintLiquidGlass(
            effectContext,
            effectOffset,
            _shapesWithGeometry,
            materialPaintBounds,
          );
        }
      });
    }

    paintOriginalEffect(context, offset);

    // Foreground always paints in its own render ancestry, above the glass.
    super.paint(context, offset);
  }

  // Geometry preparation does not record pictures or paint child objects.
  Rect? _gatherFrameGeometry() {
    final candidate = <(RenderLiquidGlassGeometry, GeometryCache, Matrix4)>[];
    final bounds = _collectFrameGeometry(candidate);
    _commitFrameGeometry(candidate);
    return bounds;
  }

  Rect? _collectFrameGeometry(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> candidate,
  ) {
    Rect? boundingBox;
    link.updatePaintOrder(this);
    _framePoll.markPolled();
    for (final geometryRo in link.shapes) {
      final transformPoll = geometryRo.pollRelativeTransforms(this);
      final geometry = geometryRo.maybeRebuildGeometry();
      final transform = transformPoll.transform;
      if (geometry == null || transform == null) continue;
      candidate.add((geometryRo, geometry, transform));
      final geoBounds = MatrixUtils.transformRect(transform, geometry.bounds);
      boundingBox = boundingBox == null
          ? geoBounds
          : boundingBox.expandToInclude(geoBounds);
    }
    assert(
      debugCheckOpacityBetweenShapesAndLayer(this, link.shapes),
      'Warns about an Opacity between a shape and its layer.',
    );
    return boundingBox;
  }

  void _commitFrameGeometry(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> candidate,
  ) {
    setCompositorTranslation(Offset.zero);
    _idleComposition = false;
    _shapesWithGeometry
      ..clear()
      ..addAll(candidate);
    _retainedStructure = _geometryStructure(candidate);
    _drawableEmpty = !candidate.any(
      (entry) => entry.$2.shapes.any(
        (shape) =>
            _matteShapeBasis(entry.$3, shape.shapeToGeometry ?? _identity) !=
            null,
      ),
    );
    _ancestorClips.update(
      this,
      _shapesWithGeometry.expand(
        (entry) => entry.$2.shapes.map((shape) => shape.renderObject),
      ),
    );
  }

  Rect _prepareGeometryAppearance(Rect boundingBox) {
    final usedShapeAppearances = _usesShapeAppearances;
    final usedTintOnlyAppearance = _usesTintOnlyAppearance;
    final appearances = [
      for (final (_, geometry, _) in _shapesWithGeometry)
        for (final shape in geometry.shapes) shape.appearance,
    ];
    final appearanceValuesChanged = !listEquals(_shapeAppearances, appearances);
    _setShapeAppearances(appearances);
    if (usedShapeAppearances != _usesShapeAppearances ||
        usedTintOnlyAppearance != _usesTintOnlyAppearance ||
        (_usesShapeAppearances && appearanceValuesChanged)) {
      // Mixed material data is encoded in the geometry render target. Only
      // uniform appearance changes can be applied with final-pass uniforms.
      needsGeometryUpdate = true;
    }
    final materialBounds = boundingBox.inflate(_contourOutset);
    _paintBounds = _expandForLayerShadows(materialBounds);
    return materialBounds;
  }

  // Resource binding is separate from recording/painting children so a
  // changed geometry frame can be prepared without invoking child paint.
  void _bindGeometryShader(ui.Image geometryImage) {
    syncCoordinateMapping();
    final activeRenderShader = renderShader;
    activeRenderShader
      ..setFloatUniforms(initialIndex: 2, (value) {
        value
          ..setOffset(_geometryMatteBounds.topLeft * devicePixelRatio)
          ..setSize(_geometryMatteBounds.size * devicePixelRatio);
      })
      ..setFloatUniforms(initialIndex: 34, (value) {
        value.setOffset(_materialCenterInMatte * devicePixelRatio);
      })
      // Float index 59, after uBackdropBounds.
      ..setFloatUniforms(initialIndex: 59, (value) {
        final matteSize = _geometryMatteBounds.size * devicePixelRatio;
        value.setFloats([
          if (_geometryTextureSize.isEmpty) ...[
            1,
            1,
          ] else ...[
            matteSize.width / _geometryTextureSize.width,
            matteSize.height / _geometryTextureSize.height,
          ],
          _materialTextureSize.width,
          _materialTextureSize.height,
        ]);
      })
      // Sampler 0 is the image-filter input. The engine replaces its texture
      // with the backdrop but keeps the sampling set here, so any bound image
      // selects bilinear or nearest backdrop sampling at no cost.
      ..setImageSampler(
        0,
        geometryImage,
        filterQuality: FilterQuality.low,
      )
      // Nearest: the matte packs 12-bit normal angle and displacement codes
      // across byte boundaries, which filtering between texels would mix.
      ..setImageSampler(1, geometryImage);
    if (_materialImage case final materialImage?) {
      if (_usesTintOnlyAppearance) {
        activeRenderShader.setImageSampler(
          2,
          materialImage,
          filterQuality: FilterQuality.low,
        );
      } else {
        activeRenderShader
          ..setImageSampler(2, materialImage)
          ..setImageSampler(3, materialImage, filterQuality: FilterQuality.low);
      }
    }
    if (!identical(geometryImage, _boundGeometryImage) ||
        !identical(_materialImage, _boundMaterialImage) ||
        _geometryMatteBounds != _boundMatteBounds) {
      _boundGeometryImage = geometryImage;
      _boundMaterialImage = _materialImage;
      _boundMatteBounds = _geometryMatteBounds;
      _shaderInputsChanged = true;
    }
  }

  ui.Image? _boundGeometryImage;
  ui.Image? _boundMaterialImage;
  Rect? _boundMatteBounds;

  /// Reconciles experimental fade composition before scene submission.
  @protected
  void syncCompositionOpacity() => _compositionProbe.syncOpacity(this);

  /// Whether this layer paints inside a seeded fractional-opacity pass.
  @protected
  bool get compositionProbeSeeding => _compositionProbe.seeding;

  void _paintRetainedEffect(
    PaintingContext context,
    Offset offset,
    PaintingContextCallback painter,
  ) {
    final layer = (_effectLayer.layer ??= OffsetLayer())
      ..offset = _effectTranslation;
    (_idleComposition ? _idleAncestorClips : _ancestorClips).pushLayer(
      context,
      layer,
      painter,
      offset,
    );
  }

  Rect _expandForLayerShadows(Rect bounds) => expandForGlassShadows(
    bounds,
    _shapesWithGeometry.map((entry) => (entry.$2.shapes, entry.$3)),
    settings,
  );

  @override
  Rect? get effectBounds {
    final gathered = gatherGlassGeometryBounds(link, this);
    if (gathered == null) return null;
    final (bounds, shapes) = gathered;
    final material = bounds.inflate(_contourOutset);
    return expandForGlassShadows(
      material.inflate(backdropSamplingReach(material)),
      shapes,
      settings,
    );
  }

  /// How far outside the material the composed filter reads the backdrop:
  /// the blur kernel (3 sigma), the peak edge displacement including its
  /// dispersion, and, with [LiquidGlassSettings.backdropShrink], the extra
  /// content revealed on the face. A `LiquidGlassCapture` must contain this
  /// reach or the filter samples its own edge.
  double backdropSamplingReach(Rect material) {
    final blur = blurPassSigma > 0
        ? blurPassSigma * 3 + 1 / devicePixelRatio
        : (softensInShader ? 1 / devicePixelRatio : 0.0);
    final displacement =
        settings.effectiveDisplacementScale *
        (1 + settings.dispersion.abs() * 0.5);
    final scale = 1 - settings.effectiveBackdropShrink;
    final revealed = (1 / scale - 1) * max(material.width, material.height) / 2;
    return blur + displacement + revealed;
  }

  // Own a replaceable picture rather than recording shadows together with
  // unrelated foreground. Geometry refresh may replace this before submission
  // without asking any child render object to paint outside the paint phase.
  void _recordOriginalShadows(Offset offset) {
    final hasShadows = _shapesWithGeometry.any(
      (entry) => entry.$2.shapes.any((shape) => shape.shadows.isNotEmpty),
    );
    if (!hasShadows) {
      _originalShadows.layer = null;
      return;
    }
    final slot = _originalShadows.layer ??= ContainerLayer();
    slot.removeAllChildren();
    if (_drawableEmpty) return;
    final recorder = ui.PictureRecorder();
    _drawLayerShadows(Canvas(recorder), offset, _shapesWithGeometry);
    final picture = PictureLayer(_paintBounds.shift(offset))
      ..picture = recorder.endRecording();
    slot.append(picture);
  }

  void _drawLayerShadows(
    Canvas canvas,
    Offset offset,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
  ) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.saveLayer(_paintBounds, Paint());

    for (final (_, geometry, geometryToLayer) in geometries) {
      for (final shape in geometry.shapes) {
        final shapeVisibility = shape.appearance.visibility.clamp(0.0, 1.0);
        if (shape.shadows.isEmpty || shapeVisibility <= 0) continue;
        canvas.save();
        canvas.transform(geometryToLayer.storage);
        if (shape.shapeToGeometry case final transform?) {
          canvas.transform(transform.storage);
        }
        final rect = Offset.zero & shape.renderObject.size;
        for (final shadow in shape.shadows) {
          final paint = shadow
              .copyWith(
                color: shadow.color.withValues(
                  alpha: shadow.color.a * shapeVisibility,
                ),
                blurRadius: shadow.blurRadius * shapeVisibility,
                blurStyle: BlurStyle.normal,
              )
              .toPaint();
          _drawLayerShadowShape(
            canvas,
            shape.shape,
            rect.shift(shadow.offset).inflate(shadow.spreadRadius),
            paint,
          );
        }
        canvas.restore();
      }
    }

    for (final (_, geometry, geometryToLayer) in geometries) {
      for (final shape in geometry.shapes) {
        final shapeVisibility = shape.appearance.visibility.clamp(0.0, 1.0);
        if (shapeVisibility <= 0) continue;
        canvas.save();
        canvas.transform(geometryToLayer.storage);
        if (shape.shapeToGeometry case final transform?) {
          canvas.transform(transform.storage);
        }
        _drawLayerShadowShape(
          canvas,
          shape.shape,
          (Offset.zero & shape.renderObject.size).deflate(.5),
          Paint()
            ..color = Color.fromRGBO(0, 0, 0, shapeVisibility)
            ..blendMode = BlendMode.dstOut,
        );
        canvas.restore();
      }
    }
    canvas.restore();
    canvas.restore();
  }

  void _drawLayerShadowShape(
    Canvas canvas,
    LiquidShape shape,
    Rect rect,
    Paint paint,
  ) {
    switch (shape) {
      case LiquidRoundedSuperellipse(:final borderRadius):
        canvas.drawRSuperellipse(
          RSuperellipse.fromRectAndRadius(
            rect,
            Radius.circular(borderRadius),
          ),
          paint,
        );
      case LiquidOval():
        canvas.drawOval(rect, paint);
      case LiquidRoundedRectangle(:final borderRadius):
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(borderRadius)),
          paint,
        );
    }
  }

  void _clearGeometryImage() {
    _originalShadows.layer = null;
    _releaseGeometryImageHandles();
    _encodedGeometryInputs.clear();
    _idleGeometryInputs = null;
    _emptyGeometryInputs = null;
    _encodedGeometryBounds = null;
  }

  void _releaseGeometryImageHandles() {
    if (_ownsGeometryImages) {
      _geometryImage?.dispose();
      _materialImage?.dispose();
      _ownsGeometryImages = false;
    }
    _geometryImage = null;
    _materialImage = null;
  }

  void _rememberEncodedGeometry(Rect bounds) {
    _encodedGeometryBounds = bounds;
    _rememberGeometryInputs(_encodedGeometryInputs);
  }

  void _rememberGeometryInputs(List<_EncodedGeometryInput> inputs) {
    final sharedLength = min(
      inputs.length,
      _shapesWithGeometry.length,
    );
    for (var index = 0; index < sharedLength; index++) {
      final current = _shapesWithGeometry[index];
      inputs[index].update(
        current.$1,
        current.$2.matteRevision,
        current.$3,
      );
    }
    if (inputs.length > _shapesWithGeometry.length) {
      inputs.removeRange(
        _shapesWithGeometry.length,
        inputs.length,
      );
    }
    for (
      var index = inputs.length;
      index < _shapesWithGeometry.length;
      index++
    ) {
      final current = _shapesWithGeometry[index];
      inputs.add(
        _EncodedGeometryInput(
          current.$1,
          current.$2.matteRevision,
          current.$3,
        ),
      );
    }
  }

  /// Polls retained geometry for a translation that can be applied directly
  /// to the layer tree before it is submitted to the engine.
  @protected
  ({bool needsRepaint, Offset? translation}) pollCompositorTranslation() {
    final current = link.shapes;
    final inputs =
        _emptyGeometryInputs ?? _idleGeometryInputs ?? _encodedGeometryInputs;
    if (_framePoll.polledThisFrame && inputs.length == current.length) {
      return (needsRepaint: false, translation: Offset.zero);
    }
    if (current.isEmpty && inputs.isEmpty) {
      return (needsRepaint: false, translation: Offset.zero);
    }
    if (inputs.isEmpty || current.length != inputs.length) {
      for (final geometry in current) {
        geometry.pollRelativeTransforms(this);
      }
      return (needsRepaint: true, translation: null);
    }

    var canTranslate = true;
    var needsRepaint = false;
    final transforms = <Matrix4>[];
    final translated = <RenderLiquidGlassGeometry>[];
    for (var index = 0; index < current.length; index++) {
      final geometry = current[index];
      final encoded = inputs[index];
      final wasCurrent = geometry.hasCurrentMatteRevision(
        encoded.matteRevision,
      );
      final poll = geometry.pollRelativeTransforms(this);
      final transform = poll.transform;
      if (poll.selfChanged || poll.childChanged) needsRepaint = true;
      if (!identical(geometry, encoded.renderObject) ||
          !wasCurrent ||
          poll.childChanged ||
          transform == null) {
        canTranslate = false;
        needsRepaint = true;
        continue;
      }
      transforms.add(transform);
      if (poll.selfChanged) translated.add(geometry);
    }

    if (!canTranslate) {
      return (needsRepaint: needsRepaint, translation: null);
    }
    final translation = _sharedTranslation(inputs, transforms);
    if (translation == null) return (needsRepaint: true, translation: null);
    for (final geometry in translated) {
      geometry.acceptCompositorTranslation();
    }
    return (needsRepaint: false, translation: translation);
  }

  /// The one translation that maps every encoded transform in [inputs] to
  /// the matching transform in [current], or `null` when there is none.
  static Offset? _sharedTranslation(
    List<_EncodedGeometryInput> inputs,
    List<Matrix4> current,
  ) {
    Offset? shared;
    for (var index = 0; index < current.length; index++) {
      final delta = _translationDelta(inputs[index].transform, current[index]);
      if (delta == null) return null;
      if (shared == null) {
        shared = delta;
      } else if (!_nearOffset(shared, delta)) {
        return null;
      }
    }
    return shared ?? Offset.zero;
  }

  bool _reuseUniformlyTranslatedGeometry(Rect bounds) {
    final oldBounds = _encodedGeometryBounds;
    if (oldBounds == null ||
        _encodedGeometryInputs.length != _shapesWithGeometry.length) {
      return false;
    }

    for (var index = 0; index < _shapesWithGeometry.length; index++) {
      final current = _shapesWithGeometry[index];
      final encoded = _encodedGeometryInputs[index];
      if (!identical(current.$1, encoded.renderObject) ||
          current.$2.matteRevision != encoded.matteRevision) {
        return false;
      }
    }
    final delta = _sharedTranslation(_encodedGeometryInputs, [
      for (final entry in _shapesWithGeometry) entry.$3,
    ]);
    if (delta == null) return false;
    if (!_nearRect(bounds, oldBounds.shift(delta))) return false;

    _geometryMatteBounds = _geometryMatteBounds.shift(delta);
    _materialCenterInMatte += delta;
    _rememberEncodedGeometry(bounds);
    return true;
  }

  static Offset? _translationDelta(Matrix4 before, Matrix4 after) {
    final a = before.storage;
    final b = after.storage;
    for (var index = 0; index < 16; index++) {
      if (index == 12 || index == 13) continue;
      if ((a[index] - b[index]).abs() > 1e-6) return null;
    }
    return Offset(b[12] - a[12], b[13] - a[13]);
  }

  static bool _nearOffset(Offset a, Offset b) =>
      (a.dx - b.dx).abs() <= 1e-6 && (a.dy - b.dy).abs() <= 1e-6;

  static bool _nearRect(Rect a, Rect b) =>
      (a.left - b.left).abs() <= 1e-6 &&
      (a.top - b.top).abs() <= 1e-6 &&
      (a.right - b.right).abs() <= 1e-6 &&
      (a.bottom - b.bottom).abs() <= 1e-6;

  /// Subclasses implement the actual glass rendering
  /// (e.g., with backdrop filters). The foreground is painted by the caller.
  void paintLiquidGlass(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> shapes,
    Rect boundingBox,
  );

  (double, double, double, double, double, double)? _coordinateMapping;
  Rect? _backdropBounds;

  /// Layer-local rect the native filter captures backdrop for, or `null`
  /// when it is unbounded. Refraction mirrors samples that would leave it:
  /// outside the clip the filter input is transparent.
  @protected
  Rect? get backdropSampleBounds => null;

  /// The [backdropSampleBounds] last written to the shader.
  @visibleForTesting
  Rect? get debugBackdropSampleBounds => _backdropBounds;

  @protected
  bool syncCoordinateMapping() {
    final mapping = _currentCoordinateMapping();
    final backdropBounds = backdropSampleBounds;
    final changed =
        mapping != _coordinateMapping || backdropBounds != _backdropBounds;
    _coordinateMapping = mapping;
    _backdropBounds = backdropBounds;
    if (changed) _shaderInputsChanged = true;
    _writeCoordinateMapping(renderShader, mapping, backdropBounds);
    return changed;
  }

  (double, double, double, double, double, double) _currentCoordinateMapping() {
    final globalToMatte = Matrix4.inverted(shaderCoordinateTransform);
    final origin = MatrixUtils.transformPoint(globalToMatte, Offset.zero);
    final axisX = MatrixUtils.transformPoint(globalToMatte, const Offset(1, 0));
    final axisY = MatrixUtils.transformPoint(globalToMatte, const Offset(0, 1));
    return (
      axisX.dx - origin.dx,
      axisY.dx - origin.dx,
      axisX.dy - origin.dy,
      axisY.dy - origin.dy,
      origin.dx * devicePixelRatio,
      origin.dy * devicePixelRatio,
    );
  }

  void _writeCoordinateMapping(
    FragmentShader shader,
    (double, double, double, double, double, double) mapping,
    Rect? backdropBounds,
  ) {
    shader.setFloatUniforms(initialIndex: 47, (value) {
      value.setFloats([
        mapping.$1,
        mapping.$2,
        mapping.$3,
        mapping.$4,
        mapping.$5,
        mapping.$6,
      ]);
    });
    // Float index 55, after the frost flags.
    final matteBounds = backdropBounds ?? Rect.largest;
    shader.setFloatUniforms(initialIndex: 55, (value) {
      value.setFloats([
        matteBounds.left * devicePixelRatio,
        matteBounds.top * devicePixelRatio,
        matteBounds.right * devicePixelRatio,
        matteBounds.bottom * devicePixelRatio,
      ]);
    });
  }

  /// True once geometry has been encoded, so ancestor motion can stay on the
  /// compositor without crossing this layer's repaint boundary.
  @protected
  bool get hasReusableGeometry => _geometryImage != null;

  /// Idle foreground has retained paint even if no GPU matte was ever needed.
  @protected
  bool get hasReusableIdleContents =>
      _idleGeometryInputs != null || _emptyGeometryInputs != null;

  /// Drops native backdrop-filter state while this sample is idle.
  @protected
  void releaseCompositorFilter() {}

  /// Layer-local bounds of the geometry matte. Ancestor transforms must not
  /// change this: they are applied by the compositor, not the shader.
  @visibleForTesting
  Rect get debugGeometryMatteBounds => _geometryMatteBounds;

  bool _shaderInputsChanged = true;

  /// Whether a uniform or sampler of [renderShader] changed since the last
  /// call, which also resets it.
  ///
  /// The engine copies a shader's uniforms into the native image filter when
  /// that filter is first converted (see
  /// `ReusableFragmentShader::as_image_filter`), so a filter wrapping this
  /// shader may only be reused while this stays false.
  @protected
  bool takeShaderInputsChanged() {
    final changed = _shaderInputsChanged;
    _shaderInputsChanged = false;
    return changed;
  }

  void _debugPaintGeometry(PaintingContext context, Offset offset) {
    if (_geometryImage case final geometryImage?) {
      final bounds = _geometryMatteBounds;
      context.canvas
        ..save()
        ..translate(
          bounds.left,
          bounds.top,
        )
        ..scale(1 / devicePixelRatio)
        ..drawImageRect(
          geometryImage,
          Offset.zero & bounds.size * devicePixelRatio,
          (offset * devicePixelRatio) & bounds.size * devicePixelRatio,
          Paint()..blendMode = BlendMode.src,
        )
        ..restore();
    }
  }

  @override
  @mustCallSuper
  void dispose() {
    _compositionProbe.dispose();
    _ancestorClips.dispose();
    _idleAncestorClips.dispose();
    _clearGeometryImage();
    _gpuGeometryRenderer = null;
    _effectLayer.layer = null;
    _originalShadows.layer = null;
    super.dispose();
  }

  // MARK: Geometry

  @protected
  bool needsGeometryUpdate = true;

  final List<double> _shapeData = [];
  final List<double> _rseData = [];
  final List<double> _boundsData = [];
  static final Matrix4 _identity = Matrix4.identity();

  double get _contourOutset {
    if (settings.contourWidth <= 0) return 0;
    return max(
      0.5 / devicePixelRatio,
      settings.contourWidth + 1.0 / devicePixelRatio,
    );
  }

  /// Half-extents along the matte axes of a shape with local half-size
  /// [halfSize] mapped by the affine basis ([axisX], [axisY]). The geometry
  /// shader culls with these boxes instead of mapping every pixel into each
  /// shape's local space. Ellipses and rounded rectangles are exact;
  /// continuous corners extend further into the corner than a circular arc of
  /// the same radius, so they use their box.
  static Size _matteHalfExtents(
    RawShapeType type,
    Size halfSize,
    double cornerRadius,
    Offset axisX,
    Offset axisY,
  ) {
    double extent(double x, double y) {
      switch (type) {
        case RawShapeType.ellipse:
          return sqrt(
            pow(x * halfSize.width, 2) + pow(y * halfSize.height, 2),
          );
        case RawShapeType.roundedRectangle:
          final radius = min(cornerRadius, halfSize.shortestSide);
          return x.abs() * (halfSize.width - radius) +
              y.abs() * (halfSize.height - radius) +
              radius * sqrt(x * x + y * y);
        case RawShapeType.squircle:
          return x.abs() * halfSize.width + y.abs() * halfSize.height;
      }
    }

    return Size(extent(axisX.dx, axisY.dx), extent(axisX.dy, axisY.dy));
  }

  // The encoder's drawable-shape decision. Called only while preparing
  // geometry, never during retained compositing sync.
  ({Offset axisX, Offset axisY, double determinant})? _matteShapeBasis(
    Matrix4 geometryToLayer,
    Matrix4 shapeToGeometry,
  ) {
    Offset toMatte(Offset point) => MatrixUtils.transformPoint(
      geometryToLayer,
      MatrixUtils.transformPoint(shapeToGeometry, point),
    );
    final origin = toMatte(Offset.zero);
    final axisX = toMatte(const Offset(1, 0)) - origin;
    final axisY = toMatte(const Offset(0, 1)) - origin;
    final determinant = axisX.dx * axisY.dy - axisY.dx * axisX.dy;
    if (determinant.abs() < 1e-8) return null;
    return (axisX: axisX, axisY: axisY, determinant: determinant);
  }

  _GpuGeometryFrame _buildGpuGeometryImage(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
    Rect bounds,
  ) {
    final renderer = _gpuGeometryRenderer;
    if (renderer == null) {
      throw StateError(
        'Flutter GPU is required for LiquidGlass. Enable it in the platform '
        'manifest or with --enable-flutter-gpu.',
      );
    }

    try {
      // Centered SDF antialiasing needs half a physical pixel outside the
      // mathematical shape. Keep that margin in the persistent geometry
      // texture so the positive side of the fade is not clipped at the matte
      // edge.
      final aaPadding = max(0.5 / devicePixelRatio, _contourOutset);
      // The matte is in this layer's local coordinates. Ancestor transforms
      // are applied once by the compositor; baking them in would apply scale
      // and rotation twice.
      final boundsInMatteSpace = bounds
          .inflate(aaPadding)
          .snapToPixels(devicePixelRatio);
      final materialCenter = bounds.center;

      final textureWidth = (boundsInMatteSpace.width * devicePixelRatio).ceil();
      final textureHeight = (boundsInMatteSpace.height * devicePixelRatio)
          .ceil();

      if (textureWidth <= 0 || textureHeight <= 0) {
        throw StateError('Cannot render empty liquid-glass geometry.');
      }

      // Gather shapes in cache order. A negative blend marker starts a new
      // group; this preserves smooth unions within a group without blending
      // unrelated standalone glass widgets together.
      _shapeData.clear();
      _rseData.clear();
      _boundsData.clear();
      final appearances = <LiquidGlassAppearance>[];
      var numShapes = 0;
      var shortSide = double.infinity;

      for (final (_, geometry, geometryToLayer) in geometries) {
        var firstInGroup = true;
        for (final shape in geometry.shapes) {
          if (numShapes >= 16) break; // MAX_SHAPES limit

          final shapeToGeometry = shape.shapeToGeometry ?? _identity;
          final basis = _matteShapeBasis(geometryToLayer, shapeToGeometry);
          if (basis == null) continue;
          final (:axisX, :axisY, :determinant) = basis;

          // Inverse 2D affine basis maps matte-space physical pixels back to
          // the shape's own physical-pixel coordinate system.
          final inverse00 = axisY.dy / determinant;
          final inverse01 = -axisY.dx / determinant;
          final inverse10 = -axisX.dy / determinant;
          final inverse11 = axisX.dx / determinant;

          // The minimum singular value conservatively converts local SDF
          // distances back to screen pixels under non-uniform scaling.
          final trace =
              axisX.dx * axisX.dx +
              axisX.dy * axisX.dy +
              axisY.dx * axisY.dx +
              axisY.dy * axisY.dy;
          final discriminant = max(
            0,
            trace * trace - 4 * determinant * determinant,
          );
          final distanceScale = sqrt(
            max(0.0, (trace - sqrt(discriminant)) * 0.5),
          );

          final centerInGeometry = MatrixUtils.transformPoint(
            shapeToGeometry,
            Offset(
              shape.renderObject.size.width / 2,
              shape.renderObject.size.height / 2,
            ),
          );
          final centerInLayer = MatrixUtils.transformPoint(
            geometryToLayer,
            centerInGeometry,
          );
          final centerInMatte = centerInLayer;

          // The inverse affine basis above already maps matte coordinates back
          // into the shape's local coordinate system. Using the transformed
          // AABB here would apply scale a second time (and turn rotations into
          // oversized primitives), which is especially visible for stretched
          // shapes in a blend group.
          final size = shape.renderObject.size;
          final rseParameters = roundedSuperellipseParameters(
            size,
            shape.rawCornerRadius,
            scale: devicePixelRatio,
          );
          // The geometry shader tests each cap's angular span as
          // 1 - cos(span); FakeGlass reads the spans themselves.
          rseParameters[2] = 1.0 - cos(rseParameters[2]);
          rseParameters[3] = 1.0 - cos(rseParameters[3]);
          _rseData.addAll(rseParameters);
          final center = centerInMatte * devicePixelRatio;
          final halfExtents = _matteHalfExtents(
            shape.rawShapeType,
            size * devicePixelRatio / 2,
            shape.rawCornerRadius * devicePixelRatio,
            axisX,
            axisY,
          );
          _boundsData
            ..add(center.dx - halfExtents.width)
            ..add(center.dy - halfExtents.height)
            ..add(center.dx + halfExtents.width)
            ..add(center.dy + halfExtents.height);
          final blendMarker = firstInGroup
              ? -(geometry.blend * devicePixelRatio + 1)
              : geometry.blend * devicePixelRatio;

          _shapeData
            // vec4 0: primitive parameters.
            ..add(
              shape.appearance.visibility <= 0
                  ? 0
                  : shape.rawShapeType.shaderIndex,
            )
            ..add(size.width * devicePixelRatio)
            ..add(size.height * devicePixelRatio)
            ..add(shape.rawCornerRadius * devicePixelRatio)
            // vec4 1: inverse affine basis.
            ..add(inverse00)
            ..add(inverse01)
            ..add(inverse10)
            ..add(inverse11)
            // vec4 2: transformed center, distance scale, group marker.
            ..add(centerInMatte.dx * devicePixelRatio)
            ..add(centerInMatte.dy * devicePixelRatio)
            ..add(distanceScale)
            ..add(blendMarker);
          appearances.add(shape.appearance);
          shortSide = min(shortSide, size.shortestSide);
          numShapes++;
          firstInGroup = false;
        }
      }

      if (numShapes == 0) {
        throw StateError('No invertible liquid-glass shapes to render.');
      }
      if (shortSide != _materialShortSide) {
        _materialShortSide = shortSide;
        _updateShaderSettings();
      }
      final (usesShapeAppearances, usesTintOnlyAppearance, _) =
          _classifyShapeAppearances(appearances, defaultAppearance);

      final result = renderer.render(
        width: textureWidth,
        height: textureHeight,
        shapeData: _shapeData,
        rseData: _rseData,
        boundsData: _boundsData,
        numShapes: numShapes,
        refractionHeight: settings.effectiveRefractionHeight * devicePixelRatio,
        refractionAmount: settings.effectiveRefractionAmount * devicePixelRatio,
        edgeDistanceRange:
            settings.effectiveEdgeDistanceRange * devicePixelRatio,
        refractionFitsShape: settings.refractionFitsShape,
        contourExtent: aaPadding * devicePixelRatio,
        writeMaterials: usesShapeAppearances,
        writeTintOnly: usesTintOnlyAppearance,
        appearanceData: usesShapeAppearances
            ? _appearanceLookupData(appearances)
            : const <double>[],
        offsetX: boundsInMatteSpace.left * devicePixelRatio,
        offsetY: boundsInMatteSpace.top * devicePixelRatio,
      );
      return (
        image: result.image,
        materialImage: renderer.materialImage,
        materialCenter: materialCenter,
        textureSize: Size(
          result.textureWidth.toDouble(),
          result.textureHeight.toDouble(),
        ),
        materialTextureSize: switch (renderer.materialImage) {
          final image? => Size(image.width.toDouble(), image.height.toDouble()),
          null => const Size(1, 1),
        },
        appearances: appearances,
        matteBounds: Rect.fromLTWH(
          boundsInMatteSpace.left,
          boundsInMatteSpace.top,
          result.width / devicePixelRatio,
          result.height / devicePixelRatio,
        ),
      );
    } catch (e) {
      throw StateError('Flutter GPU geometry render failed: $e');
    }
  }
}

// Images here borrow the renderer's handles. A retained temporary frame must
// clone both images before another render can dispose those borrowed handles.
typedef _GpuGeometryFrame = ({
  Size textureSize,
  Size materialTextureSize,
  ui.Image image,
  ui.Image? materialImage,
  Rect matteBounds,
  Offset materialCenter,
  List<LiquidGlassAppearance> appearances,
});

(bool, bool, LiquidGlassAppearance?) _classifyShapeAppearances(
  List<LiquidGlassAppearance> appearances,
  LiquidGlassAppearance fallback,
) {
  final first = appearances.isEmpty ? fallback : appearances.first;
  final mixed = appearances.any((appearance) => appearance != first);
  final tintOnly =
      mixed &&
      appearances.every(
        (appearance) =>
            appearance.saturation == first.saturation &&
            appearance.transmissionGamma == first.transmissionGamma &&
            appearance.vibrancy == first.vibrancy &&
            appearance.visibility == first.visibility &&
            appearance.colorModel == first.colorModel,
      );
  return (mixed, tintOnly, tintOnly || !mixed ? first : null);
}

final class _EncodedGeometryInput {
  _EncodedGeometryInput(
    this.renderObject,
    this.matteRevision,
    Matrix4 transform,
  ) : transform = transform.clone();

  RenderLiquidGlassGeometry renderObject;
  int matteRevision;
  final Matrix4 transform;

  void update(
    RenderLiquidGlassGeometry newRenderObject,
    int newMatteRevision,
    Matrix4 newTransform,
  ) {
    renderObject = newRenderObject;
    matteRevision = newMatteRevision;
    transform.setFrom(newTransform);
  }
}

@internal
class GeometryRenderLink {
  final List<RenderLiquidGlassGeometry> _shapeGeometries = [];

  late final UnmodifiableListView<RenderLiquidGlassGeometry> shapes =
      UnmodifiableListView(_shapeGeometries);

  bool _dirty = false;

  void updatePaintOrder(RenderObject owner) {
    if (sortGlassPaintOrder(owner, _shapeGeometries, (source) => source)) {
      _dirty = true;
    }
    for (final geometry in _shapeGeometries) {
      geometry.updatePaintOrder();
    }
  }

  void updateAllGeometries() {
    for (final renderObject in _shapeGeometries) {
      renderObject.maybeRebuildGeometry();
    }
  }

  void registerGeometry(
    RenderLiquidGlassGeometry renderObject,
  ) {
    if (_shapeGeometries.contains(renderObject)) return;
    _dirty = true;
    _shapeGeometries.add(renderObject);
  }

  void markDirty() {
    _dirty = true;
  }

  void unregisterGeometry(RenderLiquidGlassGeometry renderObject) {
    if (_shapeGeometries.remove(renderObject)) {
      _dirty = true;
    }
  }

  void dispose() {
    _shapeGeometries.clear();
  }
}

@internal
class InheritedGeometryRenderLink extends InheritedWidget {
  const InheritedGeometryRenderLink({
    required this.link,
    required super.child,
    super.key,
  });

  final GeometryRenderLink link;

  static GeometryRenderLink? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<InheritedGeometryRenderLink>()
        ?.link;
  }

  @override
  bool updateShouldNotify(covariant InheritedGeometryRenderLink oldWidget) {
    return oldWidget.link != link;
  }
}
