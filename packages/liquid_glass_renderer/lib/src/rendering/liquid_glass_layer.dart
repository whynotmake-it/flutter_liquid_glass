import 'dart:math';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/composer.dart';
import 'package:liquid_glass_renderer/painting.dart';
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
import 'package:liquid_glass_renderer/src/rendering/geometry_tiling.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_blur.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_composer.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_shape_helpers.dart';
import 'package:liquid_glass_renderer/src/rendering/group_matte.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';
import 'package:liquid_glass_renderer/src/rendering/read.dart';
import 'package:liquid_glass_renderer/src/rendering/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/rendering/scene_out.dart';
import 'package:liquid_glass_renderer/src/rendering/shading.dart';
import 'package:liquid_glass_renderer/src/rendering/shape_set.dart';
import 'package:liquid_glass_renderer/src/rendering/snap_rect_to_pixels.dart';
import 'package:liquid_glass_renderer/src/rendering/tiling_drift.dart';
import 'package:liquid_glass_renderer/src/rendering/transform_tracking_render_object_mixin.dart';

/// The real glass layer: renders the shapes into a GPU matte and paints the
/// final shader filter over it.
class RenderLiquidGlassLayer extends LiquidGlassRenderObject
    with TransformTrackingRenderObjectMixin {
  /// Creates a glass layer that draws with [finalShaders] and builds its
  /// geometry with [gpuGeometryRenderer].
  RenderLiquidGlassLayer({
    required this.finalShaders,
    required super.devicePixelRatio,
    required super.settings,
    required super.defaultAppearance,
    required super.link,
    this._gpuGeometryRenderer,
  });

  /// The final shaders, one per [FinalShaderVariant.all]; each draw takes
  /// the cheapest that shades it ([debugLiveShader]).
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

  // The index of the cheapest final shader that draws the glass: by where it
  // reads its geometry and appearance, and the color model family of its
  // appearances, in a group whose matte holds its tints when [groupTints],
  // beside the band that leads its read when [band]. A look that changed
  // since the read began has no band variant. [geometry] is the one drawn.
  int _variant(
    GlassGeometry geometry, {
    bool band = false,
    bool groupTints = false,
  }) {
    final kind = switch ((
      _usesShapeAppearances || groupTints,
      _usesTintOnlyAppearance || groupTints,
    )) {
      (false, _) => FinalShaderKind.single,
      (true, true) => FinalShaderKind.tint,
      (true, false) => FinalShaderKind.material,
    };
    final models = _colorModelFamily;
    return FinalShaderVariant.indexOf(
      kind,
      models,
      frost: _frostsCopies,
      band:
          band &&
          kind == FinalShaderKind.single &&
          _frostsCopies &&
          models == FinalShaderModels.ios27,
      shape: geometry is ComputedGeometry,
    );
  }

  /// The shader the live filter draws with.
  @visibleForTesting
  FragmentShader get debugLiveShader => finalShaders[_liveDraw.variant];

  GlassDraw? _debugReadDraw;

  // Whether the shader may frost the copy it draws over, which picks a
  // variant that can. Settings pick it, as they pick the color models.
  bool get _frostsCopies =>
      GlassCopyTuning.shaderFrost &&
      settings.frost > 0 &&
      settings.dispersion == 0;

  /// The color models the layer shades: the direct model alone, one iOS
  /// 27 model in the first slot, or any.
  FinalShaderModels get _colorModelFamily {
    // Only the variants that shade every model part colors.
    if (!debugShaderVariants || settings.effectiveAberration != 0) {
      return FinalShaderModels.all;
    }
    return colorModelFamily(
      _usesShapeAppearances
          ? _shapeAppearances
          : [_uniformAppearance ?? defaultAppearance],
    );
  }

  FlutterGpuGeometryRenderer? _gpuGeometryRenderer;

  /// The renderer that draws the layer's geometry, or null before it has
  /// loaded.
  FlutterGpuGeometryRenderer? get gpuGeometryRenderer => _gpuGeometryRenderer;
  set gpuGeometryRenderer(FlutterGpuGeometryRenderer? value) {
    if (_gpuGeometryRenderer == value) return;
    _gpuGeometryRenderer = value;
    markNeedsPaint();
  }

  // MARK: Shader inputs

  LiquidGlassAppearance? _uniformAppearance;
  List<LiquidGlassAppearance> _shapeAppearances = const [];
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
  List<ui.Image> get debugLookImages => switch (_geometry) {
    AtlasGeometry(:final looks) => looks,
    _ => const [],
  };

  // The material and glow the glass draws with, made again after their
  // inputs change.
  GlassFace? _face;
  List<double>? _glowUniforms;

  void _shadingChanged() {
    _face = null;
    _glowUniforms = null;
  }

  GlassFace get _glassFace {
    if (_face case final face?) return face;
    final appearance = _uniformAppearance ?? defaultAppearance;
    final slots = colorModelSlots(_shapeAppearances, defaultAppearance);
    return _face = GlassFace.of(
      settings: settings,
      appearance: appearance,
      colorModels: slots,
      devicePixelRatio: devicePixelRatio,
      blurs: blurPassSigma > 0,
    );
  }

  List<double> get _glowNow =>
      _glowUniforms ??= glowUniforms(_glow, devicePixelRatio);

  /// [smallestVisibleShortSide], measured when geometry is bound. Starts at
  /// [largestFittedShortSide] so a bounds query before the first paint
  /// over-allocates rather than clips the blur.
  double _shapeShortSide = LiquidGlassRenderObject.largestFittedShortSide;

  /// Sigma of the separate backdrop blur pass; `0` when there is none.
  ///
  /// It is the sigma at a toolbar's size; painting scales it by the size of
  /// the shapes.
  double get blurPassSigma => settings.frostSigmaAt(devicePixelRatio);

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

  // What a copy the glass draws its haze into has to be, for glass scaled
  // by [scale], or null where its frost there is one its shader cannot
  // draw. Such glass is frosted by the one blur that stands in for both.
  //
  // iOS captures what lies under glass at half of the screen's pixels and
  // reads it back between them, so a hard edge under its glass is about two
  // device pixels soft. Glass with a preset's frost reads a copy as coarse
  // on a screen that fine. Against captures of native glass 63 points high
  // over a grid of hard cells its face lies 2.0 levels off so, and 3.4 from
  // a copy at the screen's pixels (dark glass 1.1 and 4.0), for a quarter of
  // the copy's pixels.
  CopyNeed? _hazedNeed(double scale, double dpr) {
    if (debugGlassHaze == false) return null;
    final haze = settings.haze.isNone ? null : settings.haze;
    // Until the haze's programs load the one blur stands in for it.
    if (haze != null && !CopyHaze.ready) return null;
    final frost = settings.hazedFrostSigmaAt(
      dpr,
      shapeShortSide: _shapeShortSide,
    );
    final coarse = settings.frostIsPreset && dpr >= 2.5;
    if (frost <= 0) {
      return haze == null && !coarse
          ? null
          : CopyNeed(dpr, share: coarse ? 2 : 1, haze: haze);
    }
    if (!_frostsCopies) return null;
    final need = CopyNeed.glassFrost(
      frost * scale,
      devicePixelRatio: dpr,
      haze: haze,
    );
    return need != null && coarse && need.share < 2
        ? CopyNeed(dpr, share: 2, shaderFrost: need.shaderFrost, haze: haze)
        : need;
  }

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

  /// Whether the last composited frame drew the glass over the underlay's
  /// copy rather than reading the backdrop.
  @visibleForTesting
  bool debugDrewOverCopy = false;

  PageCopy? _debugPage;

  /// What the last plan has this glass do.
  @visibleForTesting
  SiteFate? get debugFate => _fate;

  /// See `LiquidGlassLayer.glow`.
  LiquidGlassGlow? get glow => _glow;
  LiquidGlassGlow? _glow;
  set glow(LiquidGlassGlow? value) {
    if (_glow == value) return;
    _glow = value;
    // Only the glow changes. A retained pass takes it in a new filter,
    // without painting the layer and its shapes.
    _glowUniforms = null;
    if (!_refreshRetainedFilter()) markNeedsPaint();
  }

  /// Hands the final pass's current uniforms to the retained filter layer
  /// and schedules a frame to composite it; false when there is no
  /// retained pass to update, so the layer has to paint.
  bool _refreshRetainedFilter() {
    if (!attached || !_canRebindFilter) return false;
    _bindFilter();
    SchedulerBinding.instance.ensureVisualUpdate();
    return true;
  }

  /// See `LiquidGlassLayer.field`.
  LiquidGlassField? get field => _field;
  LiquidGlassField? _field;
  set field(LiquidGlassField? value) {
    if (_field == value) return;
    _field = value;
    needsGeometryUpdate = true;
    markNeedsPaint();
  }

  void _setShapeAppearances(List<LiquidGlassAppearance> appearances) {
    final (:mixed, :tintOnly, :uniform) = classifyAppearances(
      appearances,
      defaultAppearance,
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

  /// Whether the committed shapes exist but none can be drawn by this effect.
  /// It reads the committed geometry, so it stays right when a retained
  /// refresh commits new shapes between paints.
  bool get drawableEmpty => _drawableEmpty ??=
      shapesWithGeometry.isNotEmpty && !hasDrawableGlass(shapesWithGeometry);

  bool? _drawableEmpty;

  @override
  void onFrameGeometryCommitted() => _drawableEmpty = null;

  /// True once geometry has been encoded, so ancestor motion can stay on the
  /// compositor without crossing this layer's repaint boundary.
  @protected
  bool get hasReusableGeometry => _geometry != null;

  // Whether the retained filter layer can take new uniforms without a paint.
  bool get _canRebindFilter =>
      _rig.filterLayer != null && !drawableEmpty && hasReusableGeometry;

  // Whether the frame shows the live filter. Glass over a copy reads through
  // a filter of its own, so moving it builds no live one: [show] brings
  // the filter up to date when the plan turns to it.
  // Glass with no slot shows its live filter whatever its fate says: no plan
  // draws it.
  bool get _readsLive => switch (_fate) {
    LeadFate(read: GlassRead(source: LiveRead())) => true,
    _ => !_rig.hasSlot,
  };

  @override
  bool get encodesMatte => true;

  @override
  void onSettingsChanged(LiquidGlassSettings old) {
    GlassReach reachOf(LiquidGlassSettings settings) => glassReach(
      settings,
      devicePixelRatio: devicePixelRatio,
      contourExtent: 0,
    );
    _shadingChanged();
    if (old.contourWidth != settings.contourWidth ||
        !reachOf(old).covers(reachOf(settings))) {
      needsGeometryUpdate = true;
    }
  }

  @override
  void onAppearanceChanged() => _shadingChanged();

  @override
  void onDevicePixelRatioChanged() {
    _shadingChanged();
    needsGeometryUpdate = true;
  }

  // MARK: Retained matte

  // The glass's geometry, once encoded. An atlas's images are its page's
  // (FlutterGpuGeometryRenderer.renderAtlas), good until the renderer draws
  // another atlas or releases this one.
  GlassGeometry? _geometry;

  /// How many times the glass's geometry was encoded, as an atlas or as one
  /// shape for the shader.
  @visibleForTesting
  int debugEncodeCount = 0;

  /// Layer-local bounds of the matte, in logical pixels. Ancestor transforms
  /// do not change them: the compositor applies those, not the shader.
  Rect _geometryMatteBounds = Rect.zero;
  Offset _materialCenterInMatte = Offset.zero;
  Size _materialSize = Size.zero;

  /// The page holding the glass's atlas, where its geometry is one.
  @visibleForTesting
  ui.Image? get debugGeometryImage => switch (_geometry) {
    AtlasGeometry(:final image) => image,
    _ => null,
  };

  /// The bounds of the last geometry matte it drew.
  @visibleForTesting
  Rect get debugGeometryMatteBounds => _geometryMatteBounds;

  // Whether [_refreshRetainedGeometry] can take the shapes as they are now
  // in place of a paint: the retained frame has a filter and a clip to
  // re-sync, or draws nothing, and the same structure. Topology changes need
  // normal painting to rebuild clip ancestry. It records nothing.
  bool get _refreshTakesFrame =>
      (_rig.filterLayer != null || drawableEmpty) &&
      _rig.hasClip &&
      (_geometry != null || drawableEmpty) &&
      frameState != GlassFrameState.idle &&
      !debugPaintLiquidGlassGeometry &&
      retainedStructureHolds();

  /// Re-encodes the committed shapes before the layer tree is built, without
  /// painting children; false when the frame needs a normal paint.
  bool _refreshRetainedGeometry() {
    if (!_refreshTakesFrame) return false;
    final candidate = <(RenderLiquidGlassGeometry, GeometryCache, Matrix4)>[];
    final bounds = collectFrameGeometry(candidate);
    // Collecting sorts the shapes into paint order, which the question above
    // read as the link held it.
    if (bounds == null || !retainedStructureHolds()) return false;
    commitFrameGeometry(candidate);
    final materialBounds = _prepareGeometryAppearance(bounds);
    // A drawable-empty refresh encodes nothing; the committed list alone
    // is the compositor-translation poll's baseline.
    if (hasDrawableGlass(shapesWithGeometry)) {
      if (!_reusesMatte(bounds, marked: needsGeometryUpdate)) {
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
  bool get _geometryStale =>
      needsGeometryUpdate || link.isDirty || _encodedLean != _leans;

  // Whether the glass's shapes may lean, now and as they were last encoded.
  bool get _leans => settings.refractionFitsShape && (debugGlassLean ?? true);
  bool _encodedLean = false;

  // The one place both marks clear once the encoded geometry holds the
  // committed shapes; the shapes rebuild their caches before the link's mark
  // clears, as a rebuild marks it again.
  void _markGeometryCurrent() {
    needsGeometryUpdate = false;
    link
      ..updateAllGeometries()
      ..markClean();
  }

  // [marked] is [needsGeometryUpdate] as it stood before the frame cleared it.
  bool _reusesMatte(Rect bounds, {required bool marked}) =>
      !marked && _geometry != null && _reuseUniformlyTranslatedGeometry(bounds);

  void _encodeGeometry(Rect bounds) {
    final result = _buildGeometry(shapesWithGeometry, bounds);
    debugEncodeCount++;
    _geometry = result.geometry;
    _geometryMatteBounds = result.matteBounds;
    _materialCenterInMatte = bounds.center;
    _materialSize = bounds.size;
    _rememberEncodedGeometry(bounds);
  }

  void _clearGeometryImage() {
    clearGlassShadows();
    // A page is drawn over only once nothing holds an atlas in it.
    _gpuGeometryRenderer?.releaseAtlas();
    _geometry = null;
    clearFrameInputs();
  }

  void _rememberEncodedGeometry(Rect bounds) {
    encodedGeometryBounds = bounds;
    rememberFrameInputs();
  }

  bool _reuseUniformlyTranslatedGeometry(Rect bounds) {
    final delta = encodedMatteDelta(bounds);
    if (delta == null) return false;
    _geometryMatteBounds = _geometryMatteBounds.shift(delta);
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
      _clearGeometryImage();
      _releaseCompositorFilter();
      releaseRetainedEffectLayer();
      return;
    }
    final materialPaintBounds = _prepareGeometryAppearance(geometryBounds);
    switch (frameState) {
      case GlassFrameState.empty:
        _clearGeometryImage();
        _releaseCompositorFilter();
        needsGeometryUpdate = false;
        link.markClean();
        paintRetainedEffect(context, offset, (effectContext, effectOffset) {
          _paintMaterialFilter(
            effectContext,
            effectOffset,
            materialPaintBounds,
          );
          if (recordGlassShadows(effectOffset) case final shadows?) {
            effectContext.addLayer(shadows);
          }
        });
      case GlassFrameState.idle:
        // Keep the last matte and its encode snapshot; ancestor motion
        // stays compositor-only while hidden because the translation poll
        // rebaselines on the committed frame, not on that snapshot. Skip
        // the backdrop filter so idle glass does not sample.
        updateIdleAncestorClips();
        _releaseCompositorFilter();
        paintRetainedEffect(context, offset, (effectContext, effectOffset) {});
      case GlassFrameState.active:
        if (_geometryStale || _geometry == null) {
          final marked = needsGeometryUpdate;
          _markGeometryCurrent();
          if (!_reusesMatte(geometryBounds, marked: marked)) {
            _clearGeometryImage();
            _encodeGeometry(geometryBounds);
          }
        }

        paintRetainedEffect(context, offset, (effectContext, effectOffset) {
          if (debugPaintLiquidGlassGeometry) {
            _debugPaintGeometry(effectContext, effectOffset);
          } else if (_geometry != null) {
            _paintMaterialFilter(
              effectContext,
              effectOffset,
              materialPaintBounds,
            );
            if (recordGlassShadows(effectOffset) case final shadows?) {
              effectContext.addLayer(shadows);
            }
          }
        });
    }
  }

  Rect _prepareGeometryAppearance(Rect boundingBox) {
    _shapeShortSide = switch (smallestVisibleShortSide()) {
      final side? => max(1, side),
      null => LiquidGlassRenderObject.largestFittedShortSide,
    };
    final usedShapeAppearances = _usesShapeAppearances;
    final usedTintOnlyAppearance = _usesTintOnlyAppearance;
    final appearances = [
      for (final (_, geometry, geometryToLayer) in shapesWithGeometry)
        for (final shape in geometry.shapes)
          if (matteShapeBasis(shape, geometryToLayer) != null) shape.appearance,
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

  MatteBinding get _ownMatte => _matteBinding(
    switch (_geometry) {
      null => AtlasGeometry.none,
      // Glass that came to look alike keeps its atlas and reads none of the
      // looks beside it.
      AtlasGeometry(:final image, :final place, looks: [_, ...])
          when !_usesShapeAppearances =>
        AtlasGeometry(image: image, place: place),
      final geometry => geometry,
    },
    bounds: _geometryMatteBounds,
  );

  // A matte this glass's draws read, its own or its group's: the bevel, the
  // material's center and the shrink's axis stay the glass's own.
  MatteBinding _matteBinding(GlassGeometry geometry, {required Rect bounds}) {
    final dpr = devicePixelRatio;
    // Along the glass's long side.
    final half =
        settings.effectiveBackdropShrinkRim *
        (_materialSize.longestSide - _materialSize.shortestSide) /
        2 *
        dpr;
    final alongX = _materialSize.width >= _materialSize.height;
    final pull = settings.effectiveBackdropPull;
    final aberration = settings.effectiveAberration;
    final line =
        (_materialSize.longestSide - _materialSize.shortestSide) / 2 * dpr;
    return MatteBinding(
      geometry: geometry,
      origin: bounds.topLeft * dpr,
      size: bounds.size * dpr,
      halfMinor: _halfMinor,
      refractionHeight: settings.effectiveRefractionHeight * dpr,
      fitsShape: settings.refractionFitsShape,
      materialCenter: _materialCenterInMatte * dpr,
      shrinkAxis: alongX ? Offset(half, 0) : Offset(0, half),
      edge: pull == 0 && aberration == 0
          ? MatteBinding.plainEdge
          : (
              pull: pull * dpr,
              pullHeight: settings.backdropPullHeight * dpr,
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

  MatteMapping _liveMapping = MatteMapping.none;
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
    if (blurPassSigma <= 0) return clip;
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

  /// The [backdropSampleBounds] the live filter last mapped.
  @visibleForTesting
  Rect? get debugBackdropSampleBounds => _backdropBounds;

  // Maps the live filter's fragments into the matte; false where the
  // mapping holds.
  bool _syncMapping() {
    // Scaled to nothing, it draws nothing: the last mapping holds.
    final toMatte = Matrix4.tryInvert(shaderCoordinateTransform);
    if (toMatte == null) return false;
    final backdropBounds = backdropSampleBounds;
    final mapping = MatteMapping.of(
      toMatte,
      devicePixelRatio: devicePixelRatio,
      backdropBounds: backdropBounds,
    );
    final changed = mapping != _liveMapping;
    _liveMapping = mapping;
    _backdropBounds = backdropBounds;
    return changed;
  }

  // MARK: Native filter

  // The live read: a filter in a clip.
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
    return bounds
        .shift(translation)
        .expandToPixelBuckets(devicePixelRatio)
        .shift(-translation);
  }

  GlassDraw get _liveDraw => GlassDraw(
    variant: _variant(_geometry ?? AtlasGeometry.none),
    face: _glassFace,
    glow: _glowNow,
    matte: _ownMatte,
    mapping: _liveMapping,
  );

  // The live filter, with the draw and the blur it was made for.
  (GlassDraw, double, ImageFilter)? _liveFilter;

  void _bindFilter() => _rig.bindFilter(_liveFilterNow());

  ImageFilter _liveFilterNow() {
    final draw = _liveDraw;
    final sigma = _frostSigmaForCurrentShapes();
    if (_liveFilter case (final held, final heldSigma, final filter)
        when heldSigma == sigma && held == draw) {
      return filter;
    }
    final filter = _frosted(_shading.filter(draw), sigma);
    _liveFilter = (draw, sigma, filter);
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

  void _dropFilterCache() => _liveFilter = null;

  // Shared by paint and the retained geometry refresh; it never paints
  // children.
  Rect _syncMaterialFilter(Rect materialBounds, Offset offset) {
    final filterBounds = materialBounds.expandToPixelBuckets(devicePixelRatio);
    _filterMaterialBounds = materialBounds;
    _filterPaintOffset = offset;
    debugFilterBounds = filterBounds;
    _rig.clipTo(filterBounds.shift(offset));
    if (drawableEmpty) {
      _rig.releaseFilter();
      _dropFilterCache();
    } else {
      _syncMapping();
      _bindFilter();
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
      shadowsUnderGlass = false;
      _paintOverSolid(context, offset, materialBounds);
      return;
    }
    final filterBounds = _syncMaterialFilter(materialBounds, offset);
    final copies = GlassCopies.enabled && !drawableEmpty;
    // Only glass over its copy can cover the shadows (see _placeShadows).
    if (!copies) shadowsUnderGlass = false;

    void paintLive(PaintingContext context, Offset offset) {
      _rig.paintLive(
        context,
        offset,
        bounds: filterBounds,
        drawsFilter: !drawableEmpty,
      );
    }

    // The live filter, or the glass painted over a copy of what lies under
    // it: compositing picks one per frame.
    _rig.paintSite(
      context,
      offset,
      site: copies ? layer : null,
      live: paintLive,
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
    final filterBounds = materialBounds.expandToPixelBuckets(devicePixelRatio);
    debugFilterBounds = filterBounds;
    final dpr = devicePixelRatio;
    final color = _solidBackdrop!.withValues(
      colorSpace: ColorSpace.extendedSRGB,
    );
    final live = _liveDraw;
    _shading.paintRect(
      context.canvas,
      filterBounds.shift(offset),
      live.copyWith(
        mapping: MatteMapping((
          dpr,
          0,
          0,
          dpr,
          -offset.dx * dpr,
          -offset.dy * dpr,
        ), live.mapping.backdropBounds),
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

  // This frame's place on the screen, for the glass's own draws: the glass's
  // transform to the screen, the logical rect the shader draws and the sigma
  // of the blur, in the screen's logical pixels, the shader frosts the copy
  // for, 0 where the copy is blurred or the glass unfrosted. Only this glass
  // reads it: the others of a read hear of it through its ask.
  _Frame? _frame;

  late final _GlassPainter _painter = _GlassPainter(this);

  // Kept while the glass rests, so its ask stays equal with no new role.
  PainterRole? _role;

  PainterRole _roleAt(Matrix4 screen) {
    final storage = screen.storage;
    final x = storage[12];
    final y = storage[13];
    final held = _role;
    if (held != null &&
        held.originOnScreen.dx == x &&
        held.originOnScreen.dy == y) {
      return held;
    }
    return _role = PainterRole(_painter, originOnScreen: Offset(x, y));
  }

  // This frame's place, where the glass draws a read. The planner joins only
  // sites that asked this frame, so a missing one is a broken plan: the read
  // then draws nothing this frame.
  _Frame? get _drawingFrame {
    final frame = _frame;
    assert(
      frame != null,
      'The glass was planned to draw a read without an ask this frame.',
    );
    return frame;
  }

  // Four answers, read in this order because each needs more of the glass
  // than the one before: none (no slot, no bounds or nothing drawn: no read),
  // turned (flipped, rotated or skewed: a copy taken in screen space cannot
  // stand for it, so the read stays live and the look is not asked), scaled
  // (the full answer kept out of every group, NoJoin.scaled) and full (the
  // copy need, the look and this frame's place for the glass's own draws).
  // Only the full answer sets [_frame]: a turned glass draws no read of a
  // copy.
  @override
  SiteAsk ask() {
    _frame = null;
    final bounds = _filterMaterialBounds;
    if (!_rig.hasSlot || bounds == null || drawableEmpty) return SiteAsk.none;
    var noJoin = _field != null || _usesShapeAppearances
        ? NoJoin.field
        : _glow != null
        ? NoJoin.glow
        : settings.effectiveBackdropShrink != 0 ||
              settings.effectiveBackdropPull != 0 ||
              settings.effectiveAberration != 0
        ? NoJoin.shrink
        : glassShadowsFade
        ? NoJoin.fadingShadows
        : _shapes.count == 0 || _geometry == null
        ? NoJoin.noMatte
        : null;
    final dpr = devicePixelRatio;
    final screen = filterPassTransform(
      this,
      seeding: false,
      devicePixelRatio: dpr,
      translation: compositorTranslation,
    );
    // The copy is taken in screen space: glass that is turned reads the
    // backdrop. A scale along the axes scales the filter's blur and reach on
    // the screen, along each axis on its own, as Impeller scales the live
    // filter's blur. Impeller blurs a scaled canvas with other taps than the
    // same blur unscaled: NEAR, at most 5 channel levels apart in the host
    // test of glass scaled 1.2 under 8 px of frost, and only while the glass
    // is scaled.
    final storage = screen.storage;
    final scaleX = storage[0];
    final scaleY = storage[5];
    // What the shader paints: the material, not the rect it is drawn in.
    final drawn = MatrixUtils.transformRect(screen, bounds);
    final reads = drawn.inflate(
      (backdropSamplingReach(bounds) + 1) * max(scaleX.abs(), scaleY.abs()),
    );
    final paints = _liveDraw;
    if (scaleX <= 0 ||
        scaleY <= 0 ||
        storage[1].abs() > 1e-6 ||
        storage[4].abs() > 1e-6) {
      return SiteAsk(
        drawn: drawn,
        reads: reads,
        role: _roleAt(screen),
        noJoin: noJoin,
        turned: true,
        paints: paints,
      );
    }
    if ((scaleX - 1).abs() > 1e-6 || (scaleY - 1).abs() > 1e-6) {
      noJoin ??= NoJoin.scaled;
    }
    final logical = MatrixUtils.transformRect(
      screen,
      bounds.expandToPixelBuckets(dpr),
    );
    // The shader frosts round and a haze is mixed in round, so glass
    // stretched past 5 % keeps the copy's blur, which follows each axis.
    final round = (scaleX / scaleY - 1).abs() <= 0.05;
    final hazed = round ? _hazedNeed(sqrt(scaleX * scaleY), dpr) : null;
    final sigma = hazed == null ? _frostSigmaForCurrentShapes() : 0.0;
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
          maxShare: GlassCopyTuning.maxCopyShare,
        );
    final frost = need.shaderFrost;
    final appearance = _uniformAppearance ?? defaultAppearance;
    _frame = (screen: screen, logical: logical, shaderFrost: frost);
    return SiteAsk(
      drawn: drawn,
      reads: reads,
      look: FilterLook(
        key: (
          settings,
          appearance.colorModel,
          appearance.visibility,
          dpr,
          need.shaderFrost,
          need.share,
          _colorModelFamily,
          // The shader's bevel asks how large a surface is only between these
          // sizes.
          (_halfMinor.clamp(
                    GlassRim.bevelShadowDepth * dpr * 3.5,
                    GlassRim.bevelShadowDepth * dpr * 5,
                  ) *
                  64)
              .round(),
        ),
        need: need,
        // A haze is mixed into all of its copy, which a scroll edge drawn
        // beside the glass would read too.
        drawsBand:
            need.haze == null &&
            frost > 0 &&
            _frostsCopies &&
            _colorModelFamily == FinalShaderModels.ios27,
        tint: appearance.tint,
        body: _body,
        page: sigma > 0 && frosted == null
            ? PageFilter(blur: (frostX, frostY))
            : null,
        anyGrid: true,
      ),
      role: _roleAt(screen),
      noJoin: noJoin,
      paints: paints,
    );
  }

  SiteFate _fate = const HiddenFate();

  GroupMatte? _groupMatte;

  // How far [_shapes] and the matte bounds moved since they were encoded.
  Offset _encodedShift = Offset.zero;

  double get _halfMinor =>
      _geometryMatteBounds.shortestSide * devicePixelRatio / 2;

  // Where the origin of the canvas the glass paints in lies on the screen,
  // with the glass's origin at [origin].
  Offset _canvasOnScreen(Offset origin) => origin - _filterPaintOffset;

  // Where the origin of the encoded shapes lies on the screen, in device
  // pixels, with the glass's origin at [origin].
  Offset _shapesOnScreen(Offset origin) =>
      (origin + _encodedShift) * devicePixelRatio;

  // What the glass is, as its geometry was last encoded.
  GlassBody get _body => _geometry == null
      ? GlassBody.none
      : GlassBody(
          shapes: _shapes.count,
          field: _drift.tiling?.field != null,
          looks: _drift.tiling?.looks != null,
          leans: _shapes.leans,
        );

  // The glass of [read], its band left out, each with the role and the rect
  // its ask holds for this frame.
  static List<(RenderLiquidGlassLayer, PainterRole, Rect)> _glassIn(
    GlassRead read,
  ) => [
    for (final member in read.members)
      if (member.ask.role
          case final PainterRole role &&
              PainterRole(painter: _GlassPainter(:final layer)))
        (layer, role, member.ask.drawn),
  ];

  static BandLook? _bandOf(GlassRead read) => switch (read.lead.ask.role) {
    BandSiteRole(:final look) => look,
    _ => null,
  };

  // Gathers the matte [read] is drawn over, where it has more glass than this.
  void _beginRead(GlassRead read) {
    if (read.geometryKind is! SharedAtlas) return;
    final glass = _glassIn(read);
    final (first, _, _) = glass.first;
    (_groupMatte ??= GroupMatte()).gather(
      [
        for (final (layer, role, drawn) in glass)
          (
            shapes: layer._shapes,
            onScreen: layer._shapesOnScreen(role.originOnScreen),
            drawn: drawn,
            appearance: layer._uniformAppearance ?? layer.defaultAppearance,
          ),
      ],
      (
        settings: first.settings,
        devicePixelRatio: first.devicePixelRatio,
        contourOutset: first._contourOutset,
      ),
    );
  }

  // From the screen's device pixels into the matte [read] is drawn over, and
  // what its shader samples of the backdrop there.
  (Matrix4, Rect?) _readMapping(GlassRead read, _Frame frame) {
    final origin = switch (read.geometryKind) {
      SharedAtlas() => _groupMatte?.origin,
      ComputedShape() || OwnAtlas() => null,
    };
    return origin == null
        ? (Matrix4.inverted(frame.screen), _backdropBounds)
        : (
            Matrix4.translationValues(-origin.dx, -origin.dy, 0),
            read.band.shift(-origin),
          );
  }

  // The draw of [read] over a copy read as [sampling], beside the band that
  // leads it, if one does and the variant draws it.
  GlassDraw _readDraw(
    GlassRead read,
    _Frame frame,
    GlassSampling sampling, {
    _BandAt? band,
  }) {
    final kind = read.geometryKind;
    assert(
      kind is SharedAtlas ||
          (kind is ComputedShape) == (_geometry is ComputedGeometry),
      'A read of one glass draws the geometry that glass encoded.',
    );
    final group = kind is SharedAtlas ? _groupMatte! : null;
    final tints = group?.tints;
    final matte = group == null
        ? _ownMatte
        : _matteBinding(
            AtlasGeometry(
              image: group.image!,
              place: group.place,
              looks: [?tints],
            ),
            bounds: group.bounds,
          );
    final variant = _variant(
      matte.geometry,
      band: band != null,
      groupTints: tints != null,
    );
    final (globalToMatte, backdropBounds) = _readMapping(read, frame);
    final holds = sampling.holds;
    final within = holds == null
        ? null
        : MatrixUtils.transformRect(globalToMatte, holds);
    final draw = GlassDraw(
      variant: variant,
      face: _glassFace,
      glow: _glowNow,
      matte: matte,
      mapping: MatteMapping.of(
        globalToMatte,
        devicePixelRatio: devicePixelRatio,
        origin: sampling.origin,
        scale: sampling.scale.toDouble(),
        backdropBounds: within == null
            ? backdropBounds
            : backdropBounds?.intersect(within) ?? within,
      ),
      reading: CopyReading(sampling),
      band: band != null && FinalShaderVariant.all[variant].band
          ? BandOverlay.of(
              band.look,
              origin: sampling.origin,
              scale: sampling.scale,
              shown: band.shown,
              whole: band.whole,
              held: band.held,
            )
          : null,
    );
    if (!kReleaseMode) _debugReadDraw = draw;
    return draw;
  }

  // What a read drawn without this frame's place shows: the backdrop as it is.
  static final ImageFilter _drawsNothing = ImageFilter.matrix(
    Matrix4.identity().storage,
  );

  static const Object _noPageKey = Object();

  ImageFilter _readFilterFor(GlassRead read, CornerRead corner) {
    final frame = _drawingFrame;
    return frame == null ? _drawsNothing : _readFilter(read, frame, corner);
  }

  ImageFilter _readFilter(GlassRead read, _Frame frame, CornerRead corner) {
    final look = _bandOf(read);
    final draw = _readDraw(
      read,
      frame,
      corner.glassSampling(frame.shaderFrost),
      band: look == null
          ? null
          : (
              look: look,
              shown: corner.fragmentsOf(look.shown) ?? Rect.zero,
              whole: corner.frostOf(look.sigma),
              held: corner.heldFrost,
            ),
    );
    for (final (held, filter) in _inSceneFilters) {
      if (held == draw) return filter;
    }
    final filter = _shading.filter(draw);
    if (_inSceneFilters.length == 2) _inSceneFilters.removeAt(0);
    _inSceneFilters.add((draw, filter));
    return filter;
  }

  // The draw of [read] over [page], and the device rect it covers.
  (GlassDraw, Rect) _pageDraw(GlassRead read, _Frame frame, PageCopy page) {
    final look = _bandOf(read);
    final draw = _readDraw(
      read,
      frame,
      page.glassSampling(frame.shaderFrost),
      band: look == null
          ? null
          : (
              look: look,
              shown: page.fragmentsOf(look.shown),
              whole: page.frostOf(look.sigma),
              held: page.heldFrost,
            ),
    );
    final dpr = devicePixelRatio;
    final logical = _glassIn(read).length == 1 && look == null
        ? frame.logical
        : read.quad.expandToPixelBuckets(dpr);
    return (draw, logical.scaled(dpr));
  }

  Object _pageKeyFor(GlassRead read, PageCopy page) {
    final frame = _drawingFrame;
    return frame == null ? _noPageKey : _pageDraw(read, frame, page);
  }

  ui.Picture _recordPageFor(
    GlassRead read,
    PageCopy page,
    Matrix4 screenToCanvas,
  ) {
    final frame = _drawingFrame;
    if (!kReleaseMode) GlassWork.pictures++;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..transform(screenToCanvas.storage);
    if (frame != null) {
      final (draw, device) = _pageDraw(read, frame, page);
      _shading.paintRect(canvas, device, draw);
    }
    return recorder.endRecording();
  }

  // From the screen's device pixels to the canvas the glass paints in.
  Matrix4 _screenToCanvas(_Frame frame) {
    final canvasToScreen = frame.screen.clone()
      ..multiply(
        Matrix4.translationValues(
          -_filterPaintOffset.dx,
          -_filterPaintOffset.dy,
          0,
        ),
      );
    return Matrix4.tryInvert(canvasToScreen)!..multiply(
      Matrix4.diagonal3Values(1 / devicePixelRatio, 1 / devicePixelRatio, 1),
    );
  }

  // The shadows of the other glass [read] draws, where they lie in this glass's
  // canvas: under its filter, which covers them inside their silhouettes.
  List<(ui.Picture, Offset)> _shadowsOfOthers(GlassRead read, _Frame frame) {
    if (_bandOf(read) != null) return const [];
    final storage = frame.screen.storage;
    final canvas = _canvasOnScreen(Offset(storage[12], storage[13]));
    return [
      for (final (glass, role, _) in _glassIn(read))
        if (!identical(glass, this))
          if (glass._shadowUnderRead() case final picture?)
            (picture, glass._canvasOnScreen(role.originOnScreen) - canvas),
    ];
  }

  ui.Picture? _shadowUnderRead() {
    _placeShadows(under: true);
    return glassShadowPicture?.picture;
  }

  // The hard edge around glass far apart, in the screen's device pixels, or
  // null where it fills most of [layer], the filter's layer on the screen: it
  // rejects the pixels of the layer no glass paints, which saved 0.6 ms of GPU
  // time over twelve buttons on the Pixel 6a.
  //
  // A pixel at two corners keeps the edge's bounds at the layer's: Impeller
  // would cut the layer, and the fragment coordinates the glass reads start
  // at the cut (see [ImpellerLayers]).
  ui.Path? _clipIn(GlassRead read, Rect layer) {
    if (read.members.length < 2 || _bandOf(read) != null) return null;
    double area(Rect rect) => rect.width * rect.height;
    var sum = 0.0;
    for (final member in read.members) {
      sum += area(member.ask.drawn);
    }
    if (area(read.quad) <= sum * 1.3) return null;
    final dpr = devicePixelRatio;
    final path = ui.Path();
    void add(Rect rect) => path.addRect(rect.scaled(dpr));
    for (final member in read.members) {
      add(member.ask.drawn.inflate(2 / dpr));
    }
    final (topLeft, bottomRight) = ImpellerLayers.pinsOf(layer, dpr);
    add(topLeft);
    add(bottomRight);
    return path;
  }

  @override
  void beginFate(SiteFate fate) {
    _fate = fate;
    _debugPage = null;
    if (!_rig.hasSlot) {
      _placeShadows(under: false);
      return;
    }
    switch (fate) {
      case HiddenFate():
        compositionSeedSuppressed = true;
        debugDrewOverCopy = false;
        _rig.hide();
        _placeShadows(under: false);
      case LeadFate(:final read) when read.source is! LiveRead:
        // Glass over its copy reads no backdrop: an opacity pass around it
        // needs no seed.
        compositionSeedSuppressed = true;
        debugDrewOverCopy = true;
        _beginRead(read);
        _placeShadows(under: !glassShadowsFade);
      case LeadFate():
        // The live read is set up as it shows.
        break;
      case FollowFate(:final read):
        compositionSeedSuppressed = true;
        debugDrewOverCopy = true;
        // The glass over a band draws it, in the band's place.
        if (_bandOf(read) != null && identical(_glassIn(read).first.$1, this)) {
          _beginRead(read);
        }
        _rig.hide();
        // Another layer draws this glass. Its shadows lie under that layer's
        // filter, or, over a band, stay cut outside the glass: a band's bar
        // spends next to nothing on them.
        if (_bandOf(read) == null) {
          _placeShadows(under: true);
          glassShadowPicture?.remove();
        } else {
          _placeShadows(under: false);
        }
    }
  }

  // Where this glass's read shows in the scene.
  late CornerRead _shownCorner;
  late ImageFilter _shownFilter;
  ui.Path? _shownClip;
  late Matrix4 _shownToCanvas;
  List<(ui.Picture, Offset)> _shownUnder = const [];
  Object? _shownKey;

  @override
  void show(GlassRead read, ReadPixels pixels) {
    switch (pixels) {
      case LiveBackdrop(:final group):
        _showLive(group);
      case InScene(:final corner):
        final frame = _drawingFrame;
        if (frame == null) {
          _rig.hide();
          return;
        }
        _showScene(read, frame, corner);
      case OnPage(:final page):
        final frame = _drawingFrame;
        if (frame == null) {
          _rig.hide();
          return;
        }
        _showPage(read, frame, page);
    }
  }

  void _showScene(GlassRead read, _Frame frame, CornerRead corner) {
    final inPlace = corner.inPlace.filter;
    final filter = _readFilter(read, frame, corner);
    final toCanvas = _screenToCanvas(frame);
    final under = _shadowsOfOthers(read, frame);
    final layer = read.geometry.layer;
    final clip = _clipIn(read, layer);
    final key = [
      filter,
      inPlace,
      toCanvas,
      layer,
      if (clip != null) ...[
        for (final member in read.members) member.ask.drawn,
      ],
      for (final (picture, offset) in under) ...[picture, offset],
    ];
    final readLayer = _rig.readLayer;
    final held = _shownKey;
    final changed =
        read.changed ||
        readLayer.parent == null ||
        held is! List<Object?> ||
        !listEquals(held, key);
    _shownCorner = corner;
    _shownFilter = filter;
    _shownClip = clip;
    _shownToCanvas = toCanvas;
    _shownUnder = under;
    _shownKey = key;
    // Shadows added beside the engine layer are not in what it retains.
    readLayer.show(_addRead, changed: changed || under.isNotEmpty);
    _rig.show(readLayer, under: glassShadowsFade ? null : glassShadowPicture);
  }

  ui.TransformEngineLayer? _addRead(ui.SceneBuilder builder) {
    for (final (picture, offset) in _shownUnder) {
      builder.addPicture(offset, picture);
    }
    return _shownCorner.addToScene(
      builder,
      _shownFilter,
      _shownToCanvas,
      _rig.readLayer.held,
      clip: _shownClip,
    );
  }

  void _showPage(GlassRead read, _Frame frame, PageCopy page) {
    _debugPage = page;
    final toCanvas = _screenToCanvas(frame);
    final under = _shadowsOfOthers(read, frame);
    final dpr = devicePixelRatio;
    final quad = read.quad;
    final bounds = MatrixUtils.transformRect(
      toCanvas,
      quad.scaled(dpr),
    ).inflate(1);
    final key = (
      page.image,
      page.placement,
      page.rect,
      _pageKeyFor(read, page),
      toCanvas,
      Object.hashAll([
        for (final (picture, offset) in under) ...[picture, offset],
      ]),
    );
    _rig.show(
      _rig.pagePicture(key, bounds, () {
        final body = _recordPageFor(read, page, toCanvas);
        if (under.isEmpty) return body;
        if (!kReleaseMode) GlassWork.pictures++;
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        for (final (shadow, offset) in under) {
          canvas
            ..save()
            ..translate(offset.dx, offset.dy)
            ..drawPicture(shadow)
            ..restore();
        }
        canvas.drawPicture(body);
        body.dispose();
        return recorder.endRecording();
      }),
      under: glassShadowsFade ? null : glassShadowPicture,
    );
  }

  void _showLive(BackdropKey? group) {
    compositionSeedSuppressed = false;
    debugDrewOverCopy = false;
    _placeShadows(under: false);
    if (_canRebindFilter) _bindFilter();
    _rig.showLive(group);
  }

  @override
  void addOutput(SceneOut out, ReadCopy outer) {
    final fate = _fate;
    if (fate is! LeadFate) return;
    final read = fate.read;
    if (glassShadowPicture?.picture case final shadow? when !glassShadowsFade) {
      out.picture(shadow);
    }
    if (read.source is ImageRead) {
      if (_rig.pageShown case final page?) out.picture(page);
      return;
    }
    final corner = outer.cornerOf(read);
    if (corner == null) return;
    final frame = _drawingFrame;
    if (frame == null) return;
    for (final (picture, offset) in _shadowsOfOthers(read, frame)) {
      out
        ..mark()
        ..at += offset
        ..picture(picture)
        ..leave();
    }
    final filter = _readFilter(read, frame, corner);
    out.settle();
    corner.addToScene(out.builder, filter, _screenToCanvas(frame), out.held);
  }

  // Glass over its copy paints its silhouettes opaquely over the slot, so
  // its shadows lie under it in the slot, whole, rather than over it cut
  // outside the silhouettes: the cut is a stencil clip of the shadow
  // groups' bounds, the dearest part of drawing them. The copy is taken
  // under the glass's own layer, so it never holds them.
  void _placeShadows({required bool under}) {
    if (under == shadowsUnderGlass) return;
    shadowsUnderGlass = under;
    if (glassShadowPicture != null) recordGlassShadows(retainedPaintOffset);
  }

  // Two: glass that leads a read and is held by a read over it draws over
  // both copies each frame.
  final List<(GlassDraw, ImageFilter)> _inSceneFilters = [];

  @override
  void onCompositorTranslated(Offset translation) {
    // Nothing to map: a shape that appears repaints.
    if (shapesWithGeometry.isEmpty) return;
    // Glass with no filter or copy to draw reads no mapping: paint maps what it
    // draws.
    if (drawableEmpty || (!_rig.hasSlot && _rig.filterLayer == null)) {
      _mappingMoved = true;
      return;
    }
    // Chrome over a scroll keeps all of it, frame after frame. Glass that moved
    // maps whatever the rest holds, so it asks for none of it.
    final inputs = _mappingMoved
        ? null
        : (
            translation,
            _filterMaterialBounds,
            _filterPaintOffset,
            compositionProbeSeeding,
            _frostSigmaForCurrentShapes(),
            devicePixelRatio,
            retainedClipBounds,
            localPaintClipAbove(this),
          );
    if (inputs != null && inputs == _mappingInputs) return;
    _mappingMoved = false;
    _mappingInputs = inputs;
    final clip = _filterClip;
    if (clip != null && _rig.hasClip) {
      _rig.clipTo(clip.shift(_filterPaintOffset));
    }
    final remapped = _syncMapping();
    if (remapped && _readsLive && _canRebindFilter) _bindFilter();
  }

  @override
  void onCompositorTranslationMissed() {
    // A pass-origin change (the opacity seed turning on, or an ancestor clip
    // moving with paint-only changes inside it) moves no tracked transform,
    // so the translation poll misses it. Where the filter cannot be rebound,
    // the retained refresh re-syncs it or the glass repaints.
    if (_syncMapping() && _canRebindFilter) _bindFilter();
    if (_refreshRetainedGeometry()) return;
    // A frame late: the composer asked [paintsLate] before paint, and
    // marked this glass when it would come here. What it could not see
    // reaches here: a shape under a follower whose leader moved this frame,
    // as the leader's offset exists only after paint.
    GlassComposer.repaint(this);
  }

  // The poll after paint would miss and the refresh could not take it: a
  // mark now paints the glass in this frame.
  @override
  bool paintsLate() => compositorPollMisses && !_refreshTakesFrame;

  // The atlas texel for texel at the geometry buffer's corner.
  void _debugPaintGeometry(PaintingContext context, Offset offset) {
    if (debugGeometryImage case final atlas?) {
      context.canvas
        ..save()
        ..translate(
          offset.dx + _geometryMatteBounds.left,
          offset.dy + _geometryMatteBounds.top,
        )
        ..scale(1 / devicePixelRatio)
        ..drawImage(atlas, Offset.zero, Paint()..blendMode = BlendMode.src)
        ..restore();
    }
  }

  @override
  void dispose() {
    _rig.dispose();
    _clearGeometryImage();
    _gpuGeometryRenderer = null;
    _groupMatte?.dispose();
    _groupMatte = null;
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
  double get materialOutset => _contourOutset;

  double get _contourOutset {
    if (settings.contourWidth <= 0) return 0;
    return max(
      0.5 / devicePixelRatio,
      settings.contourWidth + 1.0 / devicePixelRatio,
    );
  }

  /// How far outside the material the composed filter reads the backdrop:
  /// the blur kernel (3 sigma), the peak edge displacement of shapes that
  /// fit in [material] including its dispersion, and, with
  /// [LiquidGlassSettings.backdropShrink] or
  /// [LiquidGlassSettings.backdropPull], the extra content revealed on the
  /// face. A copy of the backdrop must contain this reach or the filter
  /// samples its own edge.
  double backdropSamplingReach(Rect material) {
    // The final shader's edge shift (displacementMagnitude): no wider
    // than half a shape's shorter side when refraction fits the shape, and
    // than 0.65 of it otherwise. No shape inside the material has a shorter
    // side longer than the material's.
    final amount = settings.effectiveDisplacementScale;
    final halfMinor = min(material.width, material.height) / 2;
    final shift = min(
      amount,
      settings.refractionFitsShape ? halfMinor : 1.3 * halfMinor,
    );
    final frostSigma = _frostSigmaForCurrentShapes();
    final blur = frostSigma > 0 ? frostSigma * 3 + 1 / devicePixelRatio : 0.0;
    final displacement = shift * (1 + settings.dispersion.abs() * 0.5);
    final scale = 1 - settings.effectiveBackdropShrink;
    final revealed = (1 / scale - 1) * max(material.width, material.height) / 2;
    return blur +
        displacement +
        revealed +
        settings.effectiveBackdropPull +
        settings.effectiveAberration;
  }

  // The geometry of [geometries]: worked out by the shader where they are
  // one shape of one look, else drawn into the frame's page.
  ({GlassGeometry geometry, Rect matteBounds}) _buildGeometry(
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

    final dpr = devicePixelRatio;
    final aaPadding = matteRoom(dpr, _contourOutset);
    // The geometry buffer is in this layer's local coordinates. Ancestor
    // transforms are applied once by the compositor; baking them in would
    // apply scale and rotation twice.
    final boundsInMatteSpace = bounds.inflate(aaPadding).snapToPixels(dpr);
    if (boundsInMatteSpace.isEmpty) {
      throw StateError('Cannot render empty liquid-glass geometry.');
    }

    _encodedShift = Offset.zero;
    var shapes = ShapeSet.encode(
      geometries,
      devicePixelRatio: dpr,
      turnsToCenter: _encodedLean = _leans,
    );
    if (shapes.count == 0) {
      throw StateError('No invertible liquid-glass shapes to render.');
    }
    // A field takes its looks from one draw of shapes.
    if (_usesShapeAppearances &&
        _field != null &&
        shapes.count > geometryMaxShapesPerDraw) {
      _debugWarnShapeLimitExceeded();
      shapes = shapes.take(geometryMaxShapesPerDraw);
    }
    _shapes = shapes;
    final looks = _usesShapeAppearances
        ? shapeLooks(
            shapes.appearances,
            colorModels: colorModelSlots(_shapeAppearances, defaultAppearance),
            tintOnly: _usesTintOnlyAppearance,
          )
        : null;
    final body = GlassBody(
      shapes: shapes.count,
      field: _field != null,
      looks: looks != null,
      leans: shapes.leans,
    );
    if (geometryKindOf([body]) is ComputedShape) {
      renderer.releaseAtlas();
      _drift.reset();
      return (
        geometry: ComputedGeometry(
          ShapeSet.join([(shapes, -boundsInMatteSpace.topLeft * dpr)]),
        ),
        matteBounds: Rect.fromLTWH(
          boundsInMatteSpace.left,
          boundsInMatteSpace.top,
          (boundsInMatteSpace.width * dpr).ceil() / dpr,
          (boundsInMatteSpace.height * dpr).ceil() / dpr,
        ),
      );
    }
    final reach = glassReach(
      settings,
      devicePixelRatio: dpr,
      contourExtent: aaPadding * dpr,
    );

    // Shapes that drift keep the tiling of an earlier frame while each stays
    // within its slack, in that frame's buffer: only the pass runs again.
    final tiling = _drift.advance(
      shapes,
      bounds: bounds,
      padded: boundsInMatteSpace,
      padding: aaPadding,
      devicePixelRatio: dpr,
      field: _field,
      reach: reach,
      looks: looks,
    );
    final atlas = renderer.renderAtlas(tiling);
    if (renderer.droppedShapes > 0) _debugWarnShapeLimitExceeded();
    return (
      geometry: AtlasGeometry(
        image: atlas.image,
        place: atlas.place,
        looks: atlas.looks,
      ),
      matteBounds: Rect.fromLTWH(
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
  GlassDraw? get debugReadDraw => _debugReadDraw;

  /// The page this glass reads in the last composited frame, if it reads one.
  PageCopy? get debugPage => _debugPage;

  /// What the live filter draws.
  GlassDraw get debugLiveDraw => _liveDraw;

  /// Where the shader takes the glass's geometry from.
  GlassGeometry? get debugGeometry => _geometry;

  /// Where the atlas lies in [debugGeometryImage].
  AtlasPlace get debugGeometryPlace => switch (_geometry) {
    AtlasGeometry(:final place) => place,
    _ => AtlasLayout.unplaced,
  };

  /// The tiling of the latest atlas.
  Tiling? get debugTiling => _drift.tiling;
}

// A band beside glass in a read: [shown] of it in the draw's fragments,
// frosted by [whole] device pixels, of which [held] is in what it reads.
typedef _BandAt = ({BandLook look, Rect shown, double whole, double held});

typedef _Frame = ({Matrix4 screen, Rect logical, double shaderFrost});

// The layer as the painter of the reads it leads, apart from it so the
// composer's interface stays out of the layer's public type.
final class _GlassPainter implements ReadPainter {
  _GlassPainter(this.layer);

  final RenderLiquidGlassLayer layer;

  @override
  ImageFilter readFilter(GlassRead read, CornerRead corner) =>
      layer._readFilterFor(read, corner);

  @override
  Object pageKey(GlassRead read, PageCopy page) =>
      layer._pageKeyFor(read, page);

  @override
  ui.Picture recordPage(
    GlassRead read,
    PageCopy page,
    Matrix4 screenToCanvas,
  ) => layer._recordPageFor(read, page, screenToCanvas);
}
