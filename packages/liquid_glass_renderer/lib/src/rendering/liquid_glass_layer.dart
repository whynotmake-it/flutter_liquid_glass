import 'dart:math';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/painting/glass_work.dart';
import 'package:liquid_glass_renderer/src/painting/impeller_blur.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_settings.dart';
import 'package:liquid_glass_renderer/src/painting/rect_scaling.dart';
import 'package:liquid_glass_renderer/src/painting/screen_place.dart';
import 'package:liquid_glass_renderer/src/painting/shader_constants.dart';
import 'package:liquid_glass_renderer/src/painting/view_pixels.dart';
import 'package:liquid_glass_renderer/src/plan/band_look.dart';
import 'package:liquid_glass_renderer/src/plan/impeller.dart';
import 'package:liquid_glass_renderer/src/plan/plan_result.dart';
import 'package:liquid_glass_renderer/src/plan/plan_scenery.dart';
import 'package:liquid_glass_renderer/src/plan/plan_site.dart';
import 'package:liquid_glass_renderer/src/plan/read_layout.dart';
import 'package:liquid_glass_renderer/src/rendering/ancestor_clip.dart';
import 'package:liquid_glass_renderer/src/rendering/appearance.dart';
import 'package:liquid_glass_renderer/src/rendering/backdrop_rig.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_haze.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_read.dart';
import 'package:liquid_glass_renderer/src/rendering/debug.dart';
import 'package:liquid_glass_renderer/src/rendering/drawn_values.dart';
import 'package:liquid_glass_renderer/src/rendering/filter_pass_transform.dart';
import 'package:liquid_glass_renderer/src/rendering/final_shader_variant.dart';
import 'package:liquid_glass_renderer/src/rendering/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/frame_shapes.dart';
import 'package:liquid_glass_renderer/src/rendering/full_glass.dart';
import 'package:liquid_glass_renderer/src/rendering/geometry_tiling.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_blur.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_composer.dart';
import 'package:liquid_glass_renderer/src/rendering/group_atlas.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';
import 'package:liquid_glass_renderer/src/rendering/read.dart';
import 'package:liquid_glass_renderer/src/rendering/scene_out.dart';
import 'package:liquid_glass_renderer/src/rendering/shading.dart';
import 'package:liquid_glass_renderer/src/rendering/shape_set.dart';
import 'package:liquid_glass_renderer/src/rendering/tiling_drift.dart';
import 'package:liquid_glass_renderer/src/rendering/transform_tracking_render_object_mixin.dart';


/// The real glass layer: encodes its shapes' geometry (an atlas, or one
/// shape the final shader works out) and paints the final shader filter
/// over it.
class RenderLiquidGlassLayer extends LiquidGlassRenderObject
    with TransformTrackingRenderObjectMixin {
  /// Creates a glass layer that draws with the final shaders and builds its
  /// geometry with a renderer [glass] gives it, which it owns.
  RenderLiquidGlassLayer({
    required FullGlassReady glass,
    required super.devicePixelRatio,
    required super.settings,
    required super.defaultAppearance,
    required super.link,
  }) : _glass = glass,
       finalShaders = glass.finalShaders(),
       _gpuGeometryRenderer = glass.geometryRenderer();

  final FullGlassReady _glass;

  /// The final shaders, one per [FinalShaderVariant.all]; each draw takes
  /// the cheapest that shades it ([debugBackdropShader]).
  final List<FragmentShader> finalShaders;

  late final GlassShading _shading = GlassShading(finalShaders);

  /// Whether a layer draws with the variant of its color model family;
  /// false always draws with the general one.
  @visibleForTesting
  static bool debugShaderVariants = true;

  bool _debugWarnedShapeLimit = false;

  void _debugWarnShapeLimitExceeded() {
    if (!kDebugMode || _debugWarnedShapeLimit) return;
    _debugWarnedShapeLimit = true;
    const message =
        'a LiquidGlassLayer has more than '
        '$geometryMaxShapesPerDraw glass shapes that '
        'blend, lie within reach of each other, or carry their own '
        'appearances; the extra shapes are not drawn. Split the glass across '
        'several layers.';
    debugPrint('liquid_glass_renderer: $message');
  }

  FinalShaderKind _kind({bool groupTints = false}) => switch ((
    _usesShapeAppearances || groupTints,
    _usesTintOnlyAppearance || groupTints,
  )) {
    (false, _) => FinalShaderKind.single,
    (true, true) => FinalShaderKind.tint,
    (true, false) => FinalShaderKind.material,
  };

  int _variant(
    GlassGeometry geometry, {
    bool band = false,
    bool groupTints = false,
  }) {
    final kind = _kind(groupTints: groupTints);
    final models = _colorModelFamily;
    final shape = geometry is ComputedGeometry;
    if (band) {
      final index = FinalShaderVariant.bandIndexOf(
        kind,
        models,
        frost: _frostsCopies,
        shape: shape,
        aberrates: _aberrates,
      );
      assert(index != null, 'Glass joined a band it has no shader to draw.');
      if (index != null) return index;
    }
    return FinalShaderVariant.indexOf(
      kind,
      models,
      frost: _frostsCopies,
      shape: shape,
      aberrates: _aberrates,
    );
  }

  bool get _aberrates => settings.effectiveAberration != 0;

  /// The shader the backdrop filter draws with.
  @visibleForTesting
  FragmentShader get debugBackdropShader =>
      finalShaders[debugBackdropDraw.variant];

  // What the fitted frost and haze of the settings come to, worked out once
  // per settings.
  ({LiquidGlassSettings of, bool frosts, LiquidGlassFixedHaze? haze})
  get _drawn {
    final held = _heldDrawn;
    if (held != null && identical(held.of, settings)) return held;
    return _heldDrawn = (
      of: settings,
      frosts: settings.frostBase > 0,
      haze: settings.drawnHaze,
    );
  }

  ({LiquidGlassSettings of, bool frosts, LiquidGlassFixedHaze? haze})?
  _heldDrawn;

  /// The color models the layer shades: the direct model alone, one iOS
  /// 27 model in the first slot, or any.
  FinalShaderModels get _colorModelFamily {
    if (!debugShaderVariants) return FinalShaderModels.all;
    return colorModelFamily(
      _usesShapeAppearances
          ? _shapeAppearances
          : [_uniformAppearance ?? defaultWornByNone],
    );
  }

  final FlutterGpuGeometryRenderer _gpuGeometryRenderer;

  /// The renderer that draws the layer's geometry.
  @visibleForTesting
  FlutterGpuGeometryRenderer get gpuGeometryRenderer => _gpuGeometryRenderer;

  // MARK: Shader inputs

  WornAppearance? _uniformAppearance;
  List<WornAppearance> _shapeAppearances = const [];
  bool _usesShapeAppearances = false;
  bool _usesTintOnlyAppearance = false;

  /// Whether the shapes' appearances differ, so the atlas carries their
  /// looks.
  @visibleForTesting
  bool get debugUsesShapeAppearances => _usesShapeAppearances;

  /// Whether only the shapes' tints differ, so the atlas carries the tint
  /// alone.
  @visibleForTesting
  bool get debugUsesTintOnlyAppearance => _usesTintOnlyAppearance;

  /// The looks beside the atlas, where the shapes' appearances differ.
  @visibleForTesting
  List<ui.Image> get debugLookImages => switch (debugGeometry) {
    AtlasGeometry(:final lease) => lease.looks,
    _ => const [],
  };

  // The material and glow the glass draws with, made again after their
  // inputs change.
  GlassFace? _face;
  GlassFace? _hazedFace;
  GlowUniforms? _glowUniforms;

  void _shadingChanged() {
    _face = null;
    _hazedFace = null;
  }

  GlassFace get _glassFace {
    if (_face case final face?) return face;
    final appearance = _uniformAppearance ?? defaultWornByNone;
    final slots = colorModelSlots(_shapeAppearances, defaultWornByNone);
    return _face = GlassFace.of(
      settings: settings,
      appearance: appearance,
      colorModels: slots,
      devicePixelRatio: devicePixelRatio,
      blurs: _drawn.frosts,
    );
  }

  GlowUniforms get _glowNow => _glowUniforms ??= _litGlow();

  bool get _glows => !identical(_glowNow, noGlowUniforms);

  GlowUniforms _litGlow() {
    if (frameShapes.drawnOf(link.lit)
        case FrameShape(:final glow?) && final lit) {
      final fencesNeighbors = frameShapes.drawn.length > 1;
      return glowUniforms(
        glow,
        toLayer: lit.toLayer,
        box: fencesNeighbors
            ? Offset.zero & lit.shape.renderObject.paintSize
            : null,
        devicePixelRatio: devicePixelRatio,
      );
    }
    return noGlowUniforms;
  }

  static void _keepsRetainedEffect(PaintingContext _, Offset _) {}

  double _shapeShortSide = frostFitShortSides.largest;

  double _frostSigmaForCurrentShapes() {
    final inputs = (settings, devicePixelRatio, _shapeShortSide);
    if (inputs == _frostInputs) return _frostSigma;
    _frostInputs = inputs;
    return _frostSigma = settings.frostSigmaAt(
      devicePixelRatio,
      shapeShortSide: _shapeShortSide,
    );
  }

  (LiquidGlassSettings, double, double)? _frostInputs;
  double _frostSigma = 0;

  double _hazedFrostSigmaAt(double dpr) {
    final inputs = (settings, dpr, _shapeShortSide);
    if (inputs == _hazedFrostInputs) return _hazedFrostSigma;
    _hazedFrostInputs = inputs;
    return _hazedFrostSigma = settings.hazedFrostSigmaAt(
      dpr,
      shapeShortSide: _shapeShortSide,
    );
  }

  (LiquidGlassSettings, double, double)? _hazedFrostInputs;
  double _hazedFrostSigma = 0;

  // iOS captures what lies under glass at half the screen's pixels, which a
  // screen of 2.5 device pixels per point or more shows that soft. Against
  // native glass 63 points high over hard cells, glass with a fitted frost
  // lies 2.0 levels off so and 3.4 at the screen's pixels (dark glass 1.1
  // and 4.0).
  static const int _coarseCopyShare = 2;
  static const double _coarseCopyMinRatio = 2.5;

  /// The color of a [LiquidGlassBackdrop.solid], or null to read the
  /// backdrop; only an opaque color is painted over.
  Color? get solidBackdrop => _solidBackdrop;
  Color? _solidBackdrop;
  set solidBackdrop(Color? value) {
    if (_solidBackdrop == value) return;
    _solidBackdrop = value;
    markNeedsPaint();
  }

  bool get _drawsOverSolid => (_solidBackdrop?.a ?? 0) == 1;

  @override
  void glowChanged() {
    _glowUniforms = null;
    if (!_refreshRetainedFilter()) markNeedsPaint();
  }

  /// Hands the final pass's current uniforms to the retained filter layer
  /// and schedules a frame to composite it; false when there is no
  /// retained pass to update, so the layer has to paint.
  bool _refreshRetainedFilter() {
    if (!attached || drawableEmpty || !hasReusableGeometry) return false;
    if (_readsBackdrop) {
      if (!_rebindsBackdropFilter) return false;
      _bindFilter();
    } else if (!_rig.hasSlot) {
      return false;
    }
    SchedulerBinding.instance.ensureVisualUpdate();
    return true;
  }

  @override
  void onFieldChanged() => needsGeometryUpdate = true;

  void _setShapeAppearances(List<WornAppearance> appearances) {
    final (:mixed, :tintOnly, :uniform) = classifyAppearances(
      appearances,
      defaultWornByNone,
    );
    if (_usesShapeAppearances == mixed &&
        _usesTintOnlyAppearance == tintOnly &&
        _uniformAppearance == uniform &&
        listEquals(_shapeAppearances, appearances)) {
      return;
    }
    _usesShapeAppearances = mixed;
    _usesTintOnlyAppearance = tintOnly;
    _uniformAppearance = uniform;
    _shapeAppearances = List.unmodifiable(appearances);
    _shadingChanged();
  }

  // MARK: Retained frame hooks

  /// Whether the committed shapes exist but none is drawn.
  bool get drawableEmpty =>
      frameShapes.geometries.isNotEmpty && frameShapes.drawn.isEmpty;

  @override
  void onFrameGeometryCommitted() => _glowUniforms = null;

  /// True once geometry has been encoded, so ancestor motion can stay on the
  /// compositor without crossing this layer's repaint boundary.
  @protected
  bool get hasReusableGeometry => _geometry != null;

  bool get _bindsBackdropFilter =>
      _readsBackdrop && !drawableEmpty && hasReusableGeometry;

  bool get _rebindsBackdropFilter =>
      _bindsBackdropFilter && _rig.filterLayer != null;

  @override
  bool get encodesGeometry => true;

  @override
  void onSettingsChanged(LiquidGlassSettings old) {
    _shadingChanged();
    if (_encodedNeed case final encoded? when !encoded.covers(_need)) {
      needsGeometryUpdate = true;
    }
  }

  GeometryNeed get _need =>
      GeometryNeed.of(settings, devicePixelRatio: devicePixelRatio);
  GeometryNeed? _encodedNeed;

  @override
  void onAppearanceChanged() => _shadingChanged();

  @override
  void onDevicePixelRatioChanged() {
    _shadingChanged();
    _glowUniforms = null;
    needsGeometryUpdate = true;
  }

  GlassGeometry? _geometry;

  Tiling? _atlasToPlace;
  int _encodes = 0;

  void _placeAtlas() {
    final tiling = _atlasToPlace;
    if (tiling == null) return;
    _atlasToPlace = null;
    _geometry = AtlasGeometry(_gpuGeometryRenderer.renderAtlas(tiling));
  }

  /// How many times the glass's geometry was encoded, as an atlas or as one
  /// shape for the shader.
  @visibleForTesting
  int debugEncodeCount = 0;

  Rect _bufferBounds = Rect.zero;
  Offset _materialCenterInMatte = Offset.zero;
  Size _materialSize = Size.zero;

  /// The page holding the glass's atlas, where its geometry is one.
  @visibleForTesting
  ui.Image? get debugPageImage => switch (debugGeometry) {
    AtlasGeometry(:final lease) => lease.image,
    _ => null,
  };

  /// The bounds of the last buffer it drew.
  @visibleForTesting
  Rect get debugBufferBounds => _bufferBounds;

  // Whether [_refreshRetainedGeometry] can take the shapes as they are now
  // in place of a paint: the retained frame has a clip and a filter to
  // re-sync or a slot the plan fills (the ask changes with what the glass
  // paints), or draws nothing, and the same structure. Topology changes need
  // normal painting to rebuild clip ancestry. It records nothing.
  bool get _refreshTakesFrame =>
      (_rig.filterLayer != null || _rig.hasSlot || drawableEmpty) &&
      _rig.hasClip &&
      (_geometry != null || drawableEmpty) &&
      frameState != GlassFrameState.idle &&
      !debugPaintLiquidGlassGeometry &&
      retainedStructureHolds();

  /// Re-encodes the committed shapes before the layer tree is built, without
  /// painting children; false when the frame needs a normal paint.
  bool _refreshRetainedGeometry() {
    if (!_refreshTakesFrame) return false;
    final candidate = <CommittedGeometry>[];
    final bounds = collectFrameGeometry(candidate);
    // Collecting sorts the shapes into paint order, which the question above
    // read as the link held it.
    if (bounds == null || !retainedStructureHolds()) return false;
    commitFrameGeometry(candidate);
    final materialBounds = _prepareGeometryAppearance(bounds);
    // A drawable-empty refresh encodes nothing; the committed list alone
    // is the compositor-translation poll's baseline.
    if (frameShapes.drawn.isNotEmpty) {
      if (!_reusesGeometry(bounds, marked: needsGeometryUpdate)) {
        _encodeGeometry(bounds);
      }
    }
    _markGeometryCurrent();
    recordGlassShadows(retainedPaintOffset);
    _syncMaterialFilter(materialBounds, retainedPaintOffset);
    syncAncestorClips();
    return true;
  }

  // Whether the shapes or what is encoded beside them changed since the
  // geometry was last encoded.
  bool get _geometryStale => needsGeometryUpdate || link.isDirty;

  // The one place both marks clear once the encoded geometry holds the
  // committed shapes; the shapes rebuild their caches before the link's mark
  // clears, as a rebuild marks it again.
  void _markGeometryCurrent() {
    needsGeometryUpdate = false;
    link
      ..updateAllGeometries(defaultAppearance)
      ..markClean();
  }

  // [marked] is [needsGeometryUpdate] as it stood before the frame cleared it.
  bool _reusesGeometry(Rect bounds, {required bool marked}) =>
      !marked && _geometry != null && _reuseUniformlyTranslatedGeometry(bounds);

  void _encodeGeometry(Rect bounds) {
    final result = _buildGeometry(frameShapes.drawn, bounds);
    _encodes++;
    debugEncodeCount++;
    _geometry = result.geometry;
    _bufferBounds = result.bufferBounds;
    _materialCenterInMatte = bounds.center;
    _materialSize = bounds.size;
    _rememberEncodedGeometry(bounds);
  }

  void _clearGeometry() {
    clearGlassShadows();
    // A page is drawn over only once nothing holds an atlas in it.
    _gpuGeometryRenderer.releaseAtlas();
    _geometry = null;
    _atlasToPlace = null;
    clearFrameInputs();
  }

  void _rememberEncodedGeometry(Rect bounds) {
    encodedGeometryBounds = bounds;
    rememberFrameInputs();
  }

  bool _reuseUniformlyTranslatedGeometry(Rect bounds) {
    final delta = encodedGeometryDelta(bounds);
    if (delta == null) return false;
    _bufferBounds = _bufferBounds.shift(delta);
    _materialCenterInMatte += delta;
    _encodedShift += delta;
    _rememberEncodedGeometry(bounds);
    return true;
  }

  // MARK: Painting

  @override
  void paintFrame(
    PaintingContext context,
    Offset offset,
    Rect? geometryBounds,
  ) {
    // Set again where the frame paints its material.
    _rig.releaseSlot();
    if (geometryBounds == null) {
      _clearGeometry();
      _releaseCompositorFilter();
      releaseRetainedEffectLayer();
      return;
    }
    final materialPaintBounds = _prepareGeometryAppearance(geometryBounds);
    if (frameState == GlassFrameState.idle) {
      updateIdleAncestorClips();
      _releaseCompositorFilter();
      paintRetainedEffect(context, offset, _keepsRetainedEffect);
      return;
    }
    if (_geometryStale || _geometry == null) {
      final marked = needsGeometryUpdate;
      _markGeometryCurrent();
      if (!_reusesGeometry(geometryBounds, marked: marked)) {
        _clearGeometry();
        _encodeGeometry(geometryBounds);
      }
    }

    paintRetainedEffect(context, offset, (effectContext, effectOffset) {
      if (debugPaintLiquidGlassGeometry) {
        _debugPaintGeometry(effectContext, effectOffset);
      } else if (_geometry != null) {
        _paintMaterialFilter(effectContext, effectOffset, materialPaintBounds);
        if (recordGlassShadows(effectOffset) case final shadows?) {
          effectContext.addLayer(shadows);
        }
      }
    });
  }

  Rect _prepareGeometryAppearance(Rect boundingBox) {
    _shapeShortSide = frameShapes.wornShortSide;
    final usedShapeAppearances = _usesShapeAppearances;
    final usedTintOnlyAppearance = _usesTintOnlyAppearance;
    final appearances = [
      for (final drawn in frameShapes.drawn) drawn.shape.appearance,
    ];
    final appearanceValuesChanged = !listEquals(
      _shapeAppearances,
      appearances,
    );
    _setShapeAppearances(appearances);
    if (_usesShapeAppearances &&
        (!usedShapeAppearances ||
            usedTintOnlyAppearance != _usesTintOnlyAppearance ||
            appearanceValuesChanged)) {
      // The atlas pass writes the looks beside the geometry.
      needsGeometryUpdate = true;
    }
    effectPaintBounds = expandEffectBounds(boundingBox);
    return boundingBox.inflate(materialOutset);
  }

  GeometryBinding get _ownBinding {
    assert(
      _atlasToPlace == null,
      "A draw of the glass's own geometry comes after its atlas is placed.",
    );
    return _bindingOf(
      switch (_geometry) {
        null => AtlasGeometry.none,
        AtlasGeometry(:final lease) when !_usesShapeAppearances =>
          AtlasGeometry(lease.withoutLooks),
        final geometry => geometry,
      },
      bounds: _bufferBounds,
    );
  }

  GeometryBinding _bindingOf(GlassGeometry geometry, {required Rect bounds}) {
    final dpr = devicePixelRatio;
    final alongX = _materialSize.width >= _materialSize.height;
    final pull = settings.effectiveBackdropPull;
    final aberration = settings.effectiveAberration;
    final line =
        (_materialSize.longestSide - _materialSize.shortestSide) / 2 * dpr;
    return GeometryBinding(
      source: geometry,
      origin: bounds.topLeft * dpr,
      size: bounds.size * dpr,
      refractionHeight: settings.effectiveRefractionHeight * dpr,
      fitsShape: settings.refractionFitsShape,
      materialCenter: _materialCenterInMatte * dpr,
      edge: pull == 0 && aberration == 0
          ? GeometryBinding.plainEdge
          : (
              pull: pull * dpr,
              pullHeight: settings.backdropPullDepth * dpr,
              // A square's line is a point, and either sign keeps it one.
              line: alongX ? line : -line,
              halfMinor: _materialSize.shortestSide / 2 * dpr,
              aberration: aberration * dpr,
              aberrationDepth: settings.aberrationDepth * dpr,
            ),
    );
  }

  // MARK: Coordinate mapping

  /// The transform from the layer's coordinates to those its final shader draws
  /// in.
  Matrix4 get shaderCoordinateTransform => filterPassTransform(
    this,
    seeding: compositionProbeSeeding,
    devicePixelRatio: devicePixelRatio,
    translation: compositorTranslation,
  );

  MatteMapping _backdropMapping = MatteMapping.none;
  Rect? _backdropBounds;
  bool _mappingMoved = true;
  Object? _mappingInputs;

  /// Layer-local rect the native filter captures backdrop for, or `null`
  /// when it is unbounded. Refraction mirrors samples that would leave it:
  /// outside the clip the filter input is transparent.
  @protected
  Rect? get backdropSampleBounds {
    final clip = _filterClip;
    if (clip == null) return null;
    final translation = compositorTranslation;
    // Unblurred, the filter input is the backdrop inside the filter's own
    // clip. With a blur pass, Impeller re-rasterizes the blurred input into
    // the filter's coverage, which every clip around the filter narrows: the
    // retained clips between this layer and its shapes, and the clips above
    // this layer up to its pass. The texture is transparent outside it.
    if (!_drawn.frosts) return clip;
    var captured = clip.shift(translation);
    final ancestorClips = [
      retainedClipBounds,
      localPaintClipAbove(this),
    ];
    for (final ancestorClip in ancestorClips) {
      if (ancestorClip != null) captured = captured.intersect(ancestorClip);
    }
    return captured.shift(-translation);
  }

  /// The [backdropSampleBounds] the backdrop filter last mapped.
  @visibleForTesting
  Rect? get debugBackdropSampleBounds => _backdropBounds;

  bool _remap() {
    // Scaled to nothing, it draws nothing: the last mapping holds.
    final toMatte = Matrix4.tryInvert(shaderCoordinateTransform);
    if (toMatte == null) return false;
    final backdropBounds = backdropSampleBounds;
    final mapping = MatteMapping.of(
      toMatte,
      devicePixelRatio: devicePixelRatio,
      backdropBounds: backdropBounds,
    );
    final changed = mapping != _backdropMapping;
    _backdropMapping = mapping;
    _backdropBounds = backdropBounds;
    return changed;
  }

  // MARK: Native filter

  final _rig = BackdropRig();

  /// The backdrop filter layer it last drew through.
  @visibleForTesting
  BackdropFilterLayer? get debugBackdropFilterLayer => _rig.filterLayer;

  /// The layer-local clip of the native glass filter, without the exterior
  /// shadows.
  @visibleForTesting
  Rect? debugFilterBounds;
  Rect? _filterMaterialBounds;
  Offset _filterPaintOffset = Offset.zero;

  // The native filter clip, kept on stable pixel buckets in the translated
  // frame so retained compositor motion does not resize its render target.
  Rect? get _filterClip {
    final bounds = _filterMaterialBounds;
    if (bounds == null) return null;
    final translation = compositorTranslation;
    return ViewPixels(
      devicePixelRatio,
    ).bucket(bounds.shift(translation)).shift(-translation);
  }

  GlassDraw get _backdropDraw => _backdropDrawOver(_ownBinding);

  GlassDraw _backdropDrawOver(GeometryBinding binding) => GlassDraw(
    variant: _variant(_geometry ?? AtlasGeometry.none),
    face: _glassFace,
    glow: _glowNow,
    geometry: binding,
    mapping: _backdropMapping,
  );

  (GlassDraw, double, ImageFilter)? _backdropFilter;

  void _bindFilter() {
    _placeAtlas();
    _rig.bindFilter(_backdropFilterNow());
  }

  ImageFilter _backdropFilterNow() {
    final draw = _backdropDraw;
    final sigma = _frostSigmaForCurrentShapes();
    if (_backdropFilter case (final held, final heldSigma, final filter)
        when heldSigma == sigma && held == draw) {
      return filter;
    }
    final filter = _frosted(_shading.filter(draw), sigma);
    _backdropFilter = (draw, sigma, filter);
    return filter;
  }

  static ImageFilter _frosted(ImageFilter shader, double sigma) => sigma > 0
      ? ImageFilter.compose(
          inner: ImageFilter.blur(
            tileMode: glassBlurTileMode,
            sigmaX: sigma,
            sigmaY: sigma,
          ),
          outer: shader,
        )
      : shader;

  void _dropFilterCache() => _backdropFilter = null;

  // Shared by paint and the retained geometry refresh; it never paints
  // children.
  Rect _syncMaterialFilter(Rect materialBounds, Offset offset) {
    final filterBounds = ViewPixels(devicePixelRatio).bucket(materialBounds);
    _filterMaterialBounds = materialBounds;
    _filterPaintOffset = offset;
    debugFilterBounds = filterBounds;
    _rig.clipTo(filterBounds.shift(offset));
    if (drawableEmpty) {
      _rig.releaseFilter();
      _dropFilterCache();
    } else {
      _remap();
      if (_bindsBackdropFilter) _bindFilter();
    }
    return filterBounds;
  }

  void _paintMaterialFilter(
    PaintingContext context,
    Offset offset,
    Rect materialBounds,
  ) {
    if (!attached) return;
    if (_drawsOverSolid) {
      _placeShadows(under: false);
      _paintOverSolid(context, offset, materialBounds);
      return;
    }
    final filterBounds = _syncMaterialFilter(materialBounds, offset);
    final copies = glassReadsCopies && !drawableEmpty;
    if (!copies) _placeShadows(under: false);

    void paintBackdrop(PaintingContext context, Offset offset) {
      _rig.paintBackdrop(
        context,
        offset,
        bounds: filterBounds,
        drawsFilter: !drawableEmpty,
      );
    }

    _rig.paintSite(
      context,
      offset,
      site: copies ? layer : null,
      backdrop: paintBackdrop,
    );
  }

  // Over a solid backdrop the glass is a rect painted with the final shader.
  // A paint's fragment coordinates are the logical canvas coordinates it is
  // recorded in: the layer's own shifted by [offset]. The matte is the
  // layer's own coordinates in device pixels, so neither the pass nor any
  // ancestor transform enters the mapping.
  void _paintOverSolid(
    PaintingContext context,
    Offset offset,
    Rect materialBounds,
  ) {
    _releaseCompositorFilter();
    _filterMaterialBounds = materialBounds;
    _filterPaintOffset = offset;
    if (drawableEmpty) return;
    final filterBounds = ViewPixels(devicePixelRatio).bucket(materialBounds);
    debugFilterBounds = filterBounds;
    final dpr = devicePixelRatio;
    final color = _solidBackdrop!.withValues(
      colorSpace: ColorSpace.extendedSRGB,
    );
    _placeAtlas();
    final backdrop = _backdropDraw;
    _shading.paintRect(
      context.canvas,
      filterBounds.shift(offset),
      backdrop.copyWith(
        mapping: MatteMapping((
          dpr,
          0,
          0,
          dpr,
          -offset.dx * dpr,
          -offset.dy * dpr,
        ), backdrop.mapping.backdropBounds),
        reading: SolidReading(
          color,
          Size(
            max(filterBounds.width * dpr, 1),
            max(filterBounds.height * dpr, 1),
          ),
        ),
      ),
    );
  }

  /// Drops the native backdrop filter and its clip.
  void _releaseCompositorFilter() {
    _rig.clear();
    _dropFilterCache();
  }

  // MARK: Compositing

  @override
  void onTransformChanged() {
    _mappingMoved = true;
    // Retained geometry follows the move in onPreparing.
    if (repaintsOnMove) GlassComposer.repaint(this);
  }

  // Glass with nothing to reuse repaints.
  @override
  bool get repaintsOnMove => !hasReusableGeometry && !hasReusableIdleContents;

  @override
  void onPreparing() => runCompositorPoll();

  // Nothing around it changed: what it read of its place holds.
  @override
  void onResting() {}

  // A pass that changes size counts the frames it holds still in the poll. A
  // shape under the glass's own repaint boundary changes nothing around it.
  // Hidden glass paints nothing that clears either mark, and has nothing a
  // poll could move.
  @override
  bool get mayRest => frameState == GlassFrameState.idle || !_geometryStale;

  (SiteAsk, _Frame?) _answer(ViewPixels view) {
    final bounds = _filterMaterialBounds;
    if (!_rig.hasSlot || bounds == null || drawableEmpty) {
      return (SiteAsk.none, null);
    }
    final hasGeometry = _shapes.count != 0 && _geometry != null;
    var noJoin = field != null || _usesShapeAppearances
        ? NoJoin.field
        : _glows
        ? NoJoin.glow
        : settings.effectiveBackdropShrink != 0 ||
              settings.effectiveBackdropPull != 0 ||
              _aberrates
        ? NoJoin.ownCenter
        : glassShadowsFade
        ? NoJoin.fadingShadows
        : !hasGeometry
        ? NoJoin.noGeometry
        : null;
    final dpr = view.devicePixelRatio;
    final screen = filterPassTransform(
      this,
      seeding: false,
      devicePixelRatio: dpr,
      translation: compositorTranslation,
    );
    // A scale along the axes scales the filter's blur and reach on the
    // screen, along each axis on its own, as Impeller scales the backdrop
    // filter's blur. Impeller blurs a scaled canvas with other taps than the
    // same blur unscaled: NEAR, at most 5 channel levels apart in the host
    // test of glass scaled 1.2 under 8 px of frost, and only while the glass
    // is scaled.
    final storage = screen.storage;
    final stretch = max(storage[0].abs(), storage[5].abs());
    // What the shader paints: the material, not the rect it is drawn in.
    final drawn = MatrixUtils.transformRect(screen, bounds);
    final shifted = drawn.inflate((_shiftReach(bounds) + 1) * stretch);
    final frostSigma = _frostSigmaForCurrentShapes();
    double backdropBlurReach(double sigma) =>
        sigma > 0 ? ImpellerBlur.reach(sigma, dpr, stretch: stretch) : 0;
    final paints = _paints;
    final place = ScreenPlace.of(screen);
    if (place is Turned) {
      final answer = SiteAsk(
        drawn: drawn,
        reads: shifted.inflate(backdropBlurReach(frostSigma)),
        role: _roleAt(screen),
        noJoin: noJoin,
        groupsBackdrop: hasGeometry,
        place: place,
        paints: paints,
      );
      return (answer, null);
    }
    final (scaleX, scaleY) = place is Scaled ? (place.x, place.y) : (1.0, 1.0);
    if (place is Scaled) noJoin ??= NoJoin.scaled;
    final logical = MatrixUtils.transformRect(
      screen,
      view.bucket(bounds),
    );
    // The shader frosts round and a haze is mixed in round, so glass
    // stretched past 5 % keeps the copy's blur, which follows each axis.
    final round = (scaleX / scaleY - 1).abs() <= 0.05;
    final hazed = round ? _hazedNeed(sqrt(scaleX * scaleY), dpr) : null;
    final sigma = hazed == null ? frostSigma : 0.0;
    final frostX = sigma * scaleX;
    final frostY = sigma * scaleY;
    // Frost the final shader can draw is drawn there, over an unblurred
    // copy: the copy's blur passes become its taps.
    final frosted =
        hazed ??
        (sigma > 0 && _frostsCopies && round
            ? CopyNeed.glassFrost(
                sigma * sqrt(scaleX * scaleY),
                devicePixelRatio: dpr,
              )
            : null);
    final need =
        frosted ??
        CopyNeed.blurred(
          min(frostX, frostY),
          devicePixelRatio: dpr,
          maxShare: glassPolicy.maxCopyShare,
        );
    final frost = need.shaderFrost;
    final appearance = _uniformAppearance ?? defaultWornByNone;
    final answer = SiteAsk(
      drawn: drawn,
      reads: shifted.inflate(
        frosted == null ? backdropBlurReach(sigma) : need.reachAt(dpr),
      ),
      clip: switch (retainedClipBounds) {
        final clip? => MatrixUtils.transformRect(
          screen,
          clip.shift(-compositorTranslation),
        ),
        null => null,
      },
      look: FilterLook(
        key: (
          settings,
          appearance.colorModel,
          appearance.visibility,
          dpr,
          need.shaderFrost,
          need.share,
          _colorModelFamily,
        ),
        need: need,
        // A haze is mixed into all of its copy, which a scroll edge drawn
        // beside the glass would read too.
        drawsBand:
            need.haze == null &&
            frost > 0 &&
            FinalShaderVariant.bandIndexOf(
                  _kind(),
                  _colorModelFamily,
                  frost: _frostsCopies,
                  aberrates: _aberrates,
                ) !=
                null,
        tint: appearance.tint,
        census: _census,
        imageRead: sigma > 0 && frosted == null
            ? ImageReadFilter(blur: (frostX, frostY))
            : null,
        anyGrid: true,
      ),
      role: _roleAt(screen),
      noJoin: noJoin,
      groupsBackdrop: hasGeometry,
      place: place,
      paints: paints,
    );
    return (answer, (screen: screen, logical: logical, shaderFrost: frost));
  }

  // The atlas texel for texel at the geometry buffer's corner.
  void _debugPaintGeometry(PaintingContext context, Offset offset) {
    if (debugPageImage case final atlas?) {
      context.canvas
        ..save()
        ..translate(
          offset.dx + _bufferBounds.left,
          offset.dy + _bufferBounds.top,
        )
        ..scale(1 / devicePixelRatio)
        ..drawImage(atlas, Offset.zero, Paint()..blendMode = BlendMode.src)
        ..restore();
    }
  }

  @override
  void dispose() {
    _rig.dispose();
    _clearGeometry();
    _gpuGeometryRenderer.dispose();
    for (final shader in finalShaders) {
      shader.dispose();
    }
    _painter.dispose();
    super.dispose();
  }

  // MARK: Geometry

  /// Whether its geometry changed since it last drew it.
  @protected
  bool needsGeometryUpdate = true;

  // The shapes of the latest encode.
  ShapeSet _shapes = ShapeSet.empty;

  final _drift = TilingDrift();

  @override
  double get materialOutset => _need.contourOutset;

  double _shiftReach(Rect material) {
    // The final shader's edge shift (displacementMagnitude): no wider
    // than half a shape's shorter side when refraction fits the shape, and
    // than its clear share of it otherwise.
    final amount = settings.effectiveDisplacementScale;
    final halfMinor = min(material.width, material.height) / 2;
    final shift = min(
      amount,
      settings.refractionFitsShape
          ? halfMinor
          : GlassShift.clearRatio * halfMinor,
    );
    final displacement =
        shift * (1 + settings.dispersion.abs() * GlassShift.dispersionSpread);
    final backdropScale = 1 - settings.effectiveBackdropShrink;
    final revealed =
        (1 / backdropScale - 1) * max(material.width, material.height) / 2;
    return displacement +
        revealed +
        settings.effectiveBackdropPull +
        settings.effectiveAberration;
  }

  ({GlassGeometry geometry, Rect bufferBounds}) _buildGeometry(
    List<FrameShape> drawn,
    Rect bounds,
  ) {
    final renderer = _gpuGeometryRenderer;
    final dpr = devicePixelRatio;
    final need = _encodedNeed = _need;
    final aaPadding = need.room;
    // The geometry buffer is in this layer's local coordinates. Ancestor
    // transforms are applied once by the compositor; baking them in would
    // apply scale and rotation twice.
    final boundsInMatteSpace = ViewPixels(dpr)
        .nearest(bounds.inflate(aaPadding));
    if (boundsInMatteSpace.isEmpty) {
      throw StateError('Cannot render empty liquid-glass geometry.');
    }

    _encodedShift = Offset.zero;
    var shapes = ShapeSet.encode(
      drawn,
      devicePixelRatio: dpr,
      turnsToCenter: need.leans,
    );
    if (shapes.count == 0) {
      throw StateError('No invertible liquid-glass shapes to render.');
    }
    // A field takes its looks from one draw of shapes.
    if (_usesShapeAppearances &&
        field != null &&
        shapes.count > geometryMaxShapesPerDraw) {
      _debugWarnShapeLimitExceeded();
      shapes = shapes.take(geometryMaxShapesPerDraw);
    }
    _shapes = shapes;
    final looks = _usesShapeAppearances
        ? shapeLooks(
            shapes.appearances,
            colorModels: colorModelSlots(_shapeAppearances, defaultWornByNone),
            tintOnly: _usesTintOnlyAppearance,
          )
        : null;
    final census = ShapeCensus(
      shapes: shapes.count,
      field: field != null,
      looks: looks != null,
      leans: shapes.leans,
    );
    renderer.releaseAtlas();
    if (geometryKindOf([census]) is ComputedShape) {
      _atlasToPlace = null;
      _drift.reset();
      return (
        geometry: ComputedGeometry(
          ShapeSet.join([(shapes, -boundsInMatteSpace.topLeft * dpr)]),
        ),
        bufferBounds:
            boundsInMatteSpace.topLeft &
            ViewPixels(dpr).whole(boundsInMatteSpace.size),
      );
    }
    // Shapes that drift keep the tiling of an earlier frame while each stays
    // within its slack, in that frame's buffer: only the pass runs again.
    final tiling = _drift.advance(
      shapes,
      bounds: bounds,
      padded: boundsInMatteSpace,
      padding: aaPadding,
      devicePixelRatio: dpr,
      field: field,
      reach: need.reach,
      looks: looks,
    );
    _atlasToPlace = tiling;
    if (tiling.droppedShapes > 0) _debugWarnShapeLimitExceeded();
    return (
      geometry: AtlasGeometry.none,
      bufferBounds: Rect.fromLTWH(
        _drift.bounds.left,
        _drift.bounds.top,
        _drift.width / dpr,
        _drift.height / dpr,
      ),
    );
  }
}

/// What a [RenderLiquidGlassLayer] drew, for the package's tests.
extension RenderLiquidGlassLayerDebug on RenderLiquidGlassLayer {
  /// What the glass last drew over a copy of a read.
  GlassDraw? get debugReadDraw => _painter._debugDraw;

  /// The image copy this glass reads in the last composited frame, if it reads
  /// one.
  ImageCopy? get debugImageCopy => _debugImageCopy;

  /// What the backdrop filter draws, its atlas placed if no draw placed it.
  GlassDraw get debugBackdropDraw {
    _placeAtlas();
    return _backdropDraw;
  }

  /// Where the shader takes the glass's geometry from, its atlas placed if no
  /// draw placed it.
  GlassGeometry? get debugGeometry {
    _placeAtlas();
    return _geometry;
  }

  /// Where the atlas lies in [debugPageImage].
  AtlasPlace get debugAtlasPlace => switch (debugGeometry) {
    AtlasGeometry(:final lease) => lease.place,
    _ => AtlasLayout.unplaced,
  };

  /// The tiling of the latest atlas.
  Tiling? get debugTiling => _drift.tiling;
}
