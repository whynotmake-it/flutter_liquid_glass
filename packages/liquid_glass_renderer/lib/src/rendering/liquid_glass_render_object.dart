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
import 'package:flutter/scheduler.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/glass_shadow.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/glass_composition_probe.dart';
import 'package:liquid_glass_renderer/src/internal/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/internal/retained_glass_clip.dart';
import 'package:liquid_glass_renderer/src/internal/retained_glass_opacity_probe.dart';
import 'package:liquid_glass_renderer/src/internal/snap_rect_to_pixels.dart';
import 'package:liquid_glass_renderer/src/logging.dart';

part 'independent_real_glass_opacity.dart';

@internal
abstract interface class LiquidGlassLayerRenderObject {}

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
    this.independentOpacityPrograms,
  }) {
    _updateShaderSettings();
  }

  static final logger = Logger(LgrLogNames.render);

  final FragmentShader defaultRenderShader;
  final FragmentShader materialRenderShader;
  final FragmentShader tintRenderShader;
  final List<FragmentProgram>? independentOpacityPrograms;
  FragmentShader get renderShader => switch ((
    _usesShapeAppearances,
    _usesTintOnlyAppearance,
  )) {
    (false, _) => defaultRenderShader,
    (true, true) => tintRenderShader,
    (true, false) => materialRenderShader,
  };

  Matrix4 get matteTransform;

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
        _settings?.effectiveThickness != value.effectiveThickness ||
        _settings?.effectiveEdgeRefraction != value.effectiveEdgeRefraction ||
        _settings?.effectiveRefractionSpread !=
            value.effectiveRefractionSpread ||
        _settings?.effectiveContourWidth != value.effectiveContourWidth ||
        _settings?.effectiveContourOffset != value.effectiveContourOffset;
    final wasIdle = (_settings?.effectiveThickness ?? 0) <= 0;
    final isIdle = value.effectiveThickness <= 0;
    _settings = value;
    _updateShaderSettings();
    if (geometryInputsChanged) needsGeometryUpdate = true;
    if (wasIdle != isIdle) markNeedsCompositingBitsUpdate();
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
  bool get alwaysNeedsCompositing =>
      _geometryImage != null && settings.effectiveThickness > 0;

  /// Pre-rendered geometry texture in screen space
  ui.Image? _geometryImage;
  ui.Image? _materialImage;
  bool _ownsGeometryImages = false;

  /// The bounding box of the geometry matte in the coordinate space of the
  /// shader
  Rect _geometryMatteBounds = Rect.zero;
  Offset _materialCenterInMatte = Offset.zero;

  /// The pre-rendered geometry texture in screen space.
  ///
  /// Exposed for subclasses that render additional passes (such as the separate
  /// specular layer) from the same geometry texture.
  @protected
  ui.Image? get geometryImage => _geometryImage;

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

  int _shaderSettingsRevision = 0;
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
    _shaderSettingsRevision++;
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
    final appearanceVisibility = appearance.visibility;
    final tint = appearance.tint.withValues(
      alpha: appearance.tint.a * appearanceVisibility,
    );
    final saturation = 1 + (appearance.saturation - 1) * appearanceVisibility;
    final transmissionGamma =
        1 + (appearance.transmissionGamma - 1) * appearanceVisibility;
    final vibrancy = appearance.vibrancy * appearanceVisibility;
    shader.setFloatUniforms(initialIndex: 6, (value) {
      value
        ..setColor(tint)
        ..setFloats([
          settings.effectiveDisplacementScale * devicePixelRatio,
          settings.effectiveChromaticAberration,
          settings.effectiveThickness * devicePixelRatio,
          settings.effectiveHighlight,
          settings.effectiveBackdropScale,
          saturation,
        ])
        ..setOffset(
          const Offset(0, 1),
        )
        ..setColor(const Color.fromARGB(255, 255, 255, 255))
        ..setColor(
          Color.fromARGB(
            (settings.effectiveContourStrength.clamp(0.0, 1.0) * 255).round(),
            0,
            0,
            0,
          ),
        )
        ..setFloats([
          settings.effectiveBevelShadowDirectionality,
          settings.effectiveBevelShadowSizeResponse,
          settings.effectiveHighlightWidth * devicePixelRatio,
          settings.effectiveHighlightOppositeStrength,
        ])
        ..setFloats([
          settings.effectiveContourWidth * devicePixelRatio,
          settings.effectiveContourTransmittance,
        ])
        ..setFloats([
          settings.effectiveContourOffset * devicePixelRatio,
          materialCenter.dx * devicePixelRatio,
          materialCenter.dy * devicePixelRatio,
          settings.effectiveHighlightWrap,
        ])
        ..setFloats([
          transmissionGamma,
          vibrancy,
        ])
        ..setFloats([
          settings.effectiveBevelShadowStrength,
          settings.effectiveBevelShadowDepth * devicePixelRatio,
          settings.effectiveBevelShadowOffset * devicePixelRatio,
        ])
        ..setFloats([
          appearance.colorModel.shaderValue,
          appearanceVisibility,
          FlutterGpuGeometryRenderer.materialRasterScale.toDouble(),
        ]);
    });
  }

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
        (at(i).visibility + at(i).colorModel.shaderValue * 2) / 5,
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

  @visibleForTesting
  int get debugIndependentPassCount =>
      _independentOpacity.layer?._passes.length ?? 0;

  @visibleForTesting
  List<BackdropKey?> get debugIndependentCaptureBackdropKeys => [
    for (final pass
        in _independentOpacity.layer?._passes ?? <_RealOpacityPass>[])
      if (pass.capturesRefraction) pass.backdrop.layer?.backdropKey,
  ];

  @visibleForTesting
  List<(int, bool, bool)> get debugIndependentMaterialKinds => [
    for (final pass
        in _independentOpacity.layer?._passes ?? <_RealOpacityPass>[])
      (() {
        final (mixed, tintOnly, _) = _classifyShapeAppearances([
          for (final entry in pass.subset)
            for (final shape in entry.$2.shapes) shape.appearance,
        ], defaultAppearance);
        return (pass.shapes.length, mixed, tintOnly);
      })(),
  ];

  final List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)>
  _shapesWithGeometry = [];
  List<Object> _retainedStructure = [];
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
  final _idleAncestorClips = RetainedGlassClip(includeOpacity: false);
  bool _idleComposition = false;
  final _independentOpacity = LayerHandle<_IndependentRealOpacityLayer>();

  /// Test-only effective bounds; computed on demand, never during rendering.
  @visibleForTesting
  List<Object?> get debugOpacityPlacement => [
    _paintBounds.shift(_effectTranslation),
    for (final pass
        in _independentOpacity.layer?._passes ?? <_RealOpacityPass>[])
      (
        pass.bounds.shift(_effectTranslation),
        pass.filterClip.layer?.clipRect?.shift(_effectTranslation),
        pass.layer.seedBounds,
        pass._mapping,
      ),
  ];

  @protected
  void syncIndependentOpacity() {
    _independentOpacity.layer?.sync(_effectTranslation);
  }

  bool _hiddenPassCleanupPending = false;

  @protected
  void scheduleHiddenPassCleanup(OffsetLayer tracker) {
    final selector = _independentOpacity.layer;
    if (selector == null ||
        selector._passes.isEmpty ||
        _hiddenPassCleanupPending) {
      return;
    }
    _hiddenPassCleanupPending = true;
    // Repainting detaches and reattaches layers too. Inspect the settled tree,
    // not that transient state, and never run geometry/paint work here.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _hiddenPassCleanupPending = false;
      if (!attached ||
          tracker.attached ||
          !identical(tracker, layer) ||
          !identical(selector, _independentOpacity.layer)) {
        return;
      }
      for (
        var ancestor = parent;
        ancestor != null;
        ancestor = ancestor.parent
      ) {
        if (isSettledTransparentGlassScope(ancestor)) {
          selector.releaseHiddenPasses();
          return;
        }
      }
    });
  }

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
    final selector = _independentOpacity.layer;
    if (selector == null ||
        (_geometryImage == null && !_drawableEmpty) ||
        _idleComposition ||
        debugPaintLiquidGlassGeometry ||
        settings.effectiveThickness <= 0) {
      return false;
    }
    final candidate = <(RenderLiquidGlassGeometry, GeometryCache, Matrix4)>[];
    final bounds = _collectFrameGeometry(candidate);
    // Topology changes need normal painting to rebuild opacity ancestry.
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
    final offset = selector._offset;
    _recordOriginalShadows(offset);
    updateMaterial(_shapesWithGeometry, materialBounds, offset);
    selector.prepare(this, _shapesWithGeometry, offset);
    syncAncestorClips();
    syncIndependentOpacity();
    return true;
  }

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
    if (settings.effectiveThickness <= 0 || !hasVisibleShape) {
      _independentOpacity.layer = null;
      _idleComposition =
          const bool.fromEnvironment(
            'INDEPENDENT_GLASS_OPACITY',
            defaultValue: true,
          ) &&
          !const bool.fromEnvironment('NEST_GLASS_CONTENTS');
      if (_idleComposition) {
        // Foreground can change while a cached matte is dormant. Poll against
        // its last paint without overwriting that matte's encoded coordinates.
        _rememberGeometryInputs(_idleGeometryInputs ??= []);
        _idleAncestorClips.update(
          this,
          _shapesWithGeometry.expand(
            (entry) => entry.$2.shapes.map((shape) => shape.renderObject),
          ),
        );
      }
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
        _materialCenterInMatte = gpuResult.materialCenter;
        _setShapeAppearances(gpuResult.appearances);
        _rememberEncodedGeometry(boundingBox);
      }
      _emptyGeometryInputs = null;
    }

    var foregroundPainted = false;
    void paintOriginalEffect(PaintingContext context, Offset offset) {
      _paintRetainedEffect(context, offset, (effectContext, effectOffset) {
        if (debugPaintLiquidGlassGeometry) {
          _debugPaintGeometry(effectContext, effectOffset);
        } else if (_drawableEmpty || _geometryImage != null) {
          if (!_drawableEmpty) _bindGeometryShader(_geometryImage!);
          if (const bool.fromEnvironment(
            'INDEPENDENT_GLASS_OPACITY',
            defaultValue: true,
          )) {
            _recordOriginalShadows(effectOffset);
            if (_originalShadows.layer case final shadows?) {
              effectContext.addLayer(shadows);
            }
          } else if (!_drawableEmpty) {
            _paintLayerShadows(
              effectContext,
              effectOffset,
              _shapesWithGeometry,
            );
          }
          foregroundPainted = paintLiquidGlass(
            effectContext,
            effectOffset,
            _shapesWithGeometry,
            materialPaintBounds,
            super.paint,
          );
        }
      });
    }

    if (const bool.fromEnvironment(
          'INDEPENDENT_GLASS_OPACITY',
          defaultValue: true,
        ) &&
        independentOpacityPrograms != null &&
        !debugPaintLiquidGlassGeometry &&
        !const bool.fromEnvironment('NEST_GLASS_CONTENTS')) {
      final selector = _independentOpacity.layer ??=
          _IndependentRealOpacityLayer();
      selector.prepare(this, _shapesWithGeometry, offset);
      context.pushLayer(selector, (context, offset) {
        // Common opacity replay belongs to this branch only. Temporary
        // branches own alpha and opt out of RetainedGlassClip's opacity.
        context.pushLayer(selector.original, paintOriginalEffect, offset);
      }, offset);
    } else {
      _independentOpacity.layer = null;
      paintOriginalEffect(context, offset);
    }

    if (!foregroundPainted) super.paint(context, offset);
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
    return boundingBox;
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
      ..setFloatUniforms(initialIndex: 33, (value) {
        value.setOffset(_materialCenterInMatte * devicePixelRatio);
      })
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
    _shaderInputSnapshot = _ShaderInputSnapshot(
      geometryImage: geometryImage,
      materialImage: _materialImage,
      matteBounds: _geometryMatteBounds,
      devicePixelRatio: devicePixelRatio,
      settingsRevision: _shaderSettingsRevision,
    );
  }

  /// Reconciles experimental fade composition before scene submission.
  @protected
  void syncCompositionOpacity() => _compositionProbe.syncOpacity(this);

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

  Rect _expandForLayerShadows(Rect bounds) {
    var result = bounds;
    for (final (_, geometry, geometryToLayer) in _shapesWithGeometry) {
      for (final shape in geometry.shapes) {
        final shapeVisibility = shape.appearance.visibility.clamp(0.0, 1.0);
        if (shapeVisibility <= 0) continue;
        final shadowScale = liquidGlassShadowScale(
          shape.renderObject.size,
          settings.effectiveExteriorShadowSizeResponse,
        );
        final shapeToLayer = shape.shapeToGeometry == null
            ? geometryToLayer
            : geometryToLayer.multiplied(shape.shapeToGeometry!);
        for (final shadow in shape.shadows) {
          final extent = max(
            shadow.spreadRadius +
                glassShadowBlurSupport(
                  shadow.blurRadius * shapeVisibility * shadowScale.blur,
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

  void _paintLayerShadows(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
  ) {
    final hasShadows = geometries.any(
      (entry) => entry.$2.shapes.any((shape) => shape.shadows.isNotEmpty),
    );
    if (!hasShadows) return;

    _drawLayerShadows(context.canvas, offset, geometries);
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
        final shadowScale = liquidGlassShadowScale(
          shape.renderObject.size,
          settings.effectiveExteriorShadowSizeResponse,
        );
        for (final shadow in shape.shadows) {
          final paint = shadow
              .copyWith(
                color: shadow.color.withValues(
                  alpha: shadow.color.a * shapeVisibility * shadowScale.energy,
                ),
                blurRadius:
                    shadow.blurRadius * shapeVisibility * shadowScale.blur,
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
    _independentOpacity.layer = null;
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
    if (current.isEmpty && inputs.isEmpty) {
      return (needsRepaint: false, translation: Offset.zero);
    }
    if (inputs.isEmpty || current.length != inputs.length) {
      for (final geometry in current) {
        geometry.pollRelativeTransforms(this);
      }
      return (needsRepaint: true, translation: null);
    }

    Offset? sharedTranslation;
    var canTranslate = true;
    var needsRepaint = false;
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

      final translation = _translationDelta(encoded.transform, transform);
      if (translation == null) {
        canTranslate = false;
        needsRepaint = true;
        continue;
      }
      if (sharedTranslation == null) {
        sharedTranslation = translation;
      } else if (!_nearOffset(sharedTranslation, translation)) {
        canTranslate = false;
        needsRepaint = true;
      }
      if (poll.selfChanged) translated.add(geometry);
    }

    if (!canTranslate) {
      return (needsRepaint: needsRepaint, translation: null);
    }
    for (final geometry in translated) {
      geometry.acceptCompositorTranslation();
    }
    return (
      needsRepaint: false,
      translation: sharedTranslation ?? Offset.zero,
    );
  }

  bool _reuseUniformlyTranslatedGeometry(Rect bounds) {
    final oldBounds = _encodedGeometryBounds;
    if (oldBounds == null ||
        _encodedGeometryInputs.length != _shapesWithGeometry.length) {
      return false;
    }

    Offset? sharedDelta;
    for (var index = 0; index < _shapesWithGeometry.length; index++) {
      final current = _shapesWithGeometry[index];
      final encoded = _encodedGeometryInputs[index];
      if (!identical(current.$1, encoded.renderObject) ||
          current.$2.matteRevision != encoded.matteRevision) {
        return false;
      }

      final delta = _translationDelta(encoded.transform, current.$3);
      if (delta == null) return false;
      if (sharedDelta == null) {
        sharedDelta = delta;
      } else if (!_nearOffset(sharedDelta, delta)) {
        return false;
      }
    }

    final delta = sharedDelta ?? Offset.zero;
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
  /// (e.g., with backdrop filters)
  bool paintLiquidGlass(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> shapes,
    Rect boundingBox,
    PaintingContextCallback paintForeground,
  );

  (double, double, double, double, double, double)? _coordinateMapping;

  @protected
  bool syncCoordinateMapping() {
    final mapping = _currentCoordinateMapping();
    final changed = mapping != _coordinateMapping;
    _coordinateMapping = mapping;
    _writeCoordinateMapping(renderShader, mapping);
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
  ) {
    shader.setFloatUniforms(initialIndex: 44, (value) {
      value.setFloats([
        mapping.$1,
        mapping.$2,
        mapping.$3,
        mapping.$4,
        mapping.$5,
        mapping.$6,
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

  /// Value identity of everything [renderShader] has captured for the current
  /// paint: float uniforms and the geometry sampler.
  ///
  /// The engine copies a shader's uniforms into the native image filter when
  /// that filter is first converted (see
  /// `ReusableFragmentShader::as_image_filter`), so a filter wrapping this
  /// shader may only be reused across paints while this snapshot compares
  /// equal.
  @protected
  Object get shaderInputSnapshot => (_shaderInputSnapshot, _coordinateMapping);
  late Object _shaderInputSnapshot;

  void _debugPaintGeometry(PaintingContext context, Offset offset) {
    if (_geometryImage case final geometryImage?) {
      final backToThis = Matrix4.inverted(matteTransform).storage;
      final bounds = _geometryMatteBounds;
      context.canvas
        ..save()
        ..transform(backToThis)
        ..translate(
          bounds.left,
          bounds.top,
        )
        ..scale(1 / devicePixelRatio)
        ..drawImage(
          geometryImage,
          offset * devicePixelRatio,
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
  static final Matrix4 _identity = Matrix4.identity();

  double get _contourOutset {
    if (settings.effectiveContourWidth <= 0) return 0;
    return max(
      0.5 / devicePixelRatio,
      settings.effectiveContourOffset +
          settings.effectiveContourWidth * 0.5 +
          1.0 / devicePixelRatio,
    );
  }

  // Flutter 3.47 computes these RSE parameters when its geometry changes and
  // uploads them to the symmetric RSE shader. Mirror that construction here
  // so lookup-table interpolation and circle fitting are not repeated per
  // fragment.
  static (double, double) _rseNAndXj(double ratio) {
    const table = <(double, double)>[
      (2.00000000, 1.13276676),
      (2.18349805, 1.20311921),
      (2.33888662, 1.28698796),
      (2.48660575, 1.36351941),
      (2.62226596, 1.44717976),
      (2.75148990, 1.53385819),
      (3.36298265, 1.98288283),
      (4.08649929, 2.23811846),
      (4.85481134, 2.47563463),
      (5.62945551, 2.72948597),
      (6.43023796, 2.98020421),
    ];
    if (ratio > 5.0) {
      final n = 1.559599389 * (ratio - 5.0) + table.last.$1;
      final kXj = 0.522807185 * (ratio - 5.0) + table.last.$2;
      return (n, 1.0 - 1.0 / kXj);
    }
    final clampedRatio = ratio.clamp(2.0, 5.0);
    final steps = clampedRatio < 2.5
        ? (clampedRatio - 2.0) * 10.0
        : (clampedRatio - 2.5) * 2.0 + 5.0;
    final left = steps.floor().clamp(0, table.length - 2);
    final fraction = steps - left;
    final a = table[left];
    final b = table[left + 1];
    final n = a.$1 + (b.$1 - a.$1) * fraction;
    final kXj = a.$2 + (b.$2 - a.$2) * fraction;
    return (n, 1.0 - 1.0 / kXj);
  }

  static (double, double, Offset, double) _rseOctant(
    double axis,
    double radius,
  ) {
    if (radius <= 1e-3) return (0.0, 0.0, Offset.zero, 0.0);
    final (n, xJOverA) = _rseNAndXj(2.0 * axis / radius);
    final xJ = xJOverA * axis;
    final yJ =
        pow(
          max(1.0 - pow(xJOverA, n).toDouble(), 0.0),
          1.0 / n,
        ).toDouble() *
        axis;
    final tanPhi = pow(xJ / max(yJ, 1e-6), n - 1.0).toDouble();
    final d = (xJ - tanPhi * yJ) / (1.0 - tanPhi);
    final gap = (1.0 - cos(pi / 4.0)) * radius;
    final circleRadius = (axis - d - gap) * sqrt2;
    final pointJ = Offset(xJ, yJ);
    final pointM = Offset(axis - gap, axis - gap);
    final chord = pointM - pointJ;
    final midpoint = (pointJ + pointM) / 2.0;
    final perpendicular = Offset(-chord.dy, chord.dx);
    final perpendicularLength = perpendicular.distance;
    final halfChord = chord.distance / 2.0;
    final centerDistance = sqrt(
      max(circleRadius * circleRadius - halfChord * halfChord, 0.0),
    );
    final circleCenter = perpendicularLength <= 1e-6
        ? midpoint
        : midpoint - perpendicular * (centerDistance / perpendicularLength);
    final fromM = pointM - circleCenter;
    final fromJ = pointJ - circleCenter;
    final span = atan2(
      fromM.dx * fromJ.dy - fromM.dy * fromJ.dx,
      fromM.dx * fromJ.dx + fromM.dy * fromJ.dy,
    ).abs();
    return (n, span, circleCenter, circleRadius);
  }

  static List<double> _rseParameters(
    Size size,
    double rawCornerRadius,
    double devicePixelRatio,
  ) {
    final halfWidth = size.width * devicePixelRatio / 2.0;
    final halfHeight = size.height * devicePixelRatio / 2.0;
    final radius = min(
      rawCornerRadius * devicePixelRatio,
      min(halfWidth, halfHeight),
    );
    final (topN, topSpan, topCenter, topRadius) = _rseOctant(
      halfWidth,
      radius,
    );
    final (rightN, rightSpan, rightCenter, rightRadius) = _rseOctant(
      halfHeight,
      radius,
    );
    return <double>[
      topN,
      rightN,
      topSpan,
      rightSpan,
      topCenter.dx,
      topCenter.dy,
      rightCenter.dx,
      rightCenter.dy,
      halfWidth,
      halfHeight,
      topRadius,
      rightRadius,
    ];
  }

  // Share the encoder's drawable-shape decision with opacity partitioning.
  // Called only while preparing geometry, never during retained opacity sync.
  ({Offset axisX, Offset axisY, double determinant})? _matteShapeBasis(
    Matrix4 geometryToLayer,
    Matrix4 shapeToGeometry,
  ) {
    Offset toMatte(Offset point) => MatrixUtils.transformPoint(
      matteTransform,
      MatrixUtils.transformPoint(
        geometryToLayer,
        MatrixUtils.transformPoint(shapeToGeometry, point),
      ),
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
      final boundsInMatteSpace = MatrixUtils.transformRect(
        matteTransform,
        bounds.inflate(aaPadding),
      ).snapToPixels(devicePixelRatio);
      final materialCenter = MatrixUtils.transformRect(
        matteTransform,
        bounds,
      ).center;

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
      final appearances = <LiquidGlassAppearance>[];
      var numShapes = 0;

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
          final centerInMatte = MatrixUtils.transformPoint(
            matteTransform,
            centerInLayer,
          );

          // The inverse affine basis above already maps matte coordinates back
          // into the shape's local coordinate system. Using the transformed
          // AABB here would apply scale a second time (and turn rotations into
          // oversized primitives), which is especially visible for stretched
          // shapes in a blend group.
          final size = shape.renderObject.size;
          _rseData.addAll(
            _rseParameters(size, shape.rawCornerRadius, devicePixelRatio),
          );
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
          numShapes++;
          firstInGroup = false;
        }
      }

      if (numShapes == 0) {
        throw StateError('No invertible liquid-glass shapes to render.');
      }
      final (usesShapeAppearances, usesTintOnlyAppearance, _) =
          _classifyShapeAppearances(appearances, defaultAppearance);

      final result = renderer.render(
        width: textureWidth,
        height: textureHeight,
        shapeData: _shapeData,
        rseData: _rseData,
        numShapes: numShapes,
        opticalIndex: settings.effectiveOpticalIndex,
        refractionSpread: settings.effectiveRefractionSpread,
        displacementScale:
            settings.effectiveDisplacementScale * devicePixelRatio,
        thickness: settings.effectiveThickness * devicePixelRatio,
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

/// Value key describing the uniform and sampler state a [FragmentShader]
/// image filter snapshots at creation time.
///
/// Geometry images are immutable GPU textures, reused until geometry changes.
/// The frame's coordinate mapping
/// is paired with this key by [LiquidGlassRenderObject.shaderInputSnapshot].
@immutable
class _ShaderInputSnapshot {
  const _ShaderInputSnapshot({
    required this.geometryImage,
    required this.materialImage,
    required this.matteBounds,
    required this.devicePixelRatio,
    required this.settingsRevision,
  });

  final ui.Image geometryImage;
  final ui.Image? materialImage;
  final Rect matteBounds;
  final double devicePixelRatio;
  final int settingsRevision;

  @override
  bool operator ==(Object other) {
    return other is _ShaderInputSnapshot &&
        other.geometryImage == geometryImage &&
        other.materialImage == materialImage &&
        other.matteBounds == matteBounds &&
        other.devicePixelRatio == devicePixelRatio &&
        other.settingsRevision == settingsRevision;
  }

  @override
  int get hashCode => Object.hash(
    geometryImage,
    materialImage,
    matteBounds,
    devicePixelRatio,
    settingsRevision,
  );

  @override
  String toString() {
    return '_ShaderInputSnapshot(image: ${identityHashCode(geometryImage)}, '
        'matteBounds: $matteBounds, dpr: $devicePixelRatio, '
        'settingsRevision: $settingsRevision)';
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
