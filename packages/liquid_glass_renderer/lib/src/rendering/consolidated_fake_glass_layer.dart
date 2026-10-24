import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/backdrop_capture_debug.dart';
import 'package:liquid_glass_renderer/src/internal/backdrop_seed.dart';
import 'package:liquid_glass_renderer/src/internal/fake_glass_color.dart';
import 'package:liquid_glass_renderer/src/internal/paint_fake_glass_surface.dart';
import 'package:liquid_glass_renderer/src/internal/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/internal/transform_tracking_repaint_boundary_mixin.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';

enum _FakeGlassPaintStage {
  shadows,
  backdrop,
  surfaces,
  contents,
}

@internal
class ConsolidatedFakeGlassLayer extends SingleChildRenderObjectWidget {
  const ConsolidatedFakeGlassLayer({
    required this.link,
    required this.settings,
    required this.defaultAppearance,
    required this.backdropKey,
    required this.surfaceShader,
    required super.child,
    super.key,
  });

  final GeometryRenderLink link;
  final LiquidGlassSettings settings;
  final LiquidGlassAppearance defaultAppearance;
  final BackdropKey? backdropKey;
  final FragmentShader? surfaceShader;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderConsolidatedFakeGlassLayer(
        devicePixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
        link: link,
        settings: settings,
        defaultAppearance: defaultAppearance,
        backdropKey: backdropKey,
        surfaceShader: surfaceShader,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderConsolidatedFakeGlassLayer renderObject,
  ) {
    renderObject
      ..devicePixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1
      ..link = link
      ..settings = settings
      ..defaultAppearance = defaultAppearance
      ..backdropKey = backdropKey
      ..surfaceShader = surfaceShader;
  }
}

/// The fake glass layer: paints a clipped backdrop blur plus the surface
/// shader for the shared shape geometry. All shared machinery — shape
/// registration, transform and compositor-translation polling, retained
/// ancestor clips, shadows, bounds and the frame state — lives in
/// [LiquidGlassRenderObject]; this class implements only the effect.
@visibleForTesting
@internal
class RenderConsolidatedFakeGlassLayer extends LiquidGlassRenderObject
    with TransformTrackingRenderObjectMixin {
  RenderConsolidatedFakeGlassLayer({
    required super.devicePixelRatio,
    required super.link,
    required super.settings,
    required super.defaultAppearance,
    required super.backdropKey,
    required this._surfaceShader,
  });

  FragmentShader? _surfaceShader;
  FragmentShader? get surfaceShader => _surfaceShader;

  @visibleForTesting
  FragmentShader? get debugSurfaceShader => _surfaceShader;
  set surfaceShader(FragmentShader? value) {
    if (identical(_surfaceShader, value)) return;
    _surfaceShader = value;
    markNeedsPaint();
  }

  final _backdropLayer = LayerHandle<BackdropFilterLayer>();
  final _clipLayer = LayerHandle<ClipPathLayer>();

  /// The pass around the shared filter's clip.
  final _sharedPass = _PassSlot();

  final _retainedFrameSlot = LayerHandle<ContainerLayer>();

  /// Capture shared by this layer's own backdrop filters when the user did
  /// not provide a [backdropKey] or [BackdropGroup]. Without it, a
  /// separately served shape would sample the shared filter's output in
  /// overlapping pixels and compound both transfers; sharing one capture
  /// also collapses their backdrop readbacks into one.
  final _ownBackdropKey = BackdropKey();

  BackdropKey get _effectiveBackdropKey => backdropKey ?? _ownBackdropKey;

  /// Per-shape backdrop passes for shapes the shared union clip cannot
  /// serve: shapes that are fading (0 < visibility < 1) or whose appearance
  /// needs a different backdrop transfer than the layer's. They sit between
  /// the shared opaque-shape filter and the surfaces so a fading shape keeps
  /// its own clipped backdrop filter instead of swapping its widget subtree.
  final Map<LiquidGlassShapeRenderObject, _SeparateBackdropLayers>
  _separateBackdropLayers = {};
  FakeGlassFilterParts? _cachedFilter;
  ({double frost, double sizeProgress})? _cachedFilterInputs;

  Path? _cachedClipPath;
  Rect? _cachedClipBounds;
  List<int> _cachedClipClasses = const [];

  bool get _hasBlur => settings.effectiveFrost > 0;
  bool get _hasColorTransfer =>
      defaultAppearance.colorModel.saturation != 1 ||
      defaultAppearance.colorModel.transmissionGamma != 1 ||
      defaultAppearance.colorModel.faceTransfer() != null;
  bool get _hasBackdropEffect => _hasBlur || _hasColorTransfer;

  /// Whether [appearance] can be served by the layer's shared backdrop
  /// filter — that is, it differs from [defaultAppearance] only in fields
  /// the surface pass and opacity handle (tint and visibility).
  bool _sharesLayerBackdrop(LiquidGlassAppearance appearance) =>
      appearance.colorModel == defaultAppearance.colorModel;

  @visibleForTesting
  BackdropFilterLayer? get debugBackdropFilterLayer => _backdropLayer.layer;

  /// The retained per-shape clipped backdrop passes, keyed by shape.
  @visibleForTesting
  Iterable<BackdropFilterLayer> get debugSeparateBackdropLayers =>
      _separateBackdropLayers.values
          .map((layers) => layers.backdrop.layer)
          .nonNulls;

  @visibleForTesting
  Rect? debugClipBounds;

  @visibleForTesting
  Path? get debugClipPath => _cachedClipPath;

  final List<_FakeGlassPaintStage> _debugLastPaintStages = [];

  @visibleForTesting
  List<String> get debugLastPaintStages =>
      _debugLastPaintStages.map((stage) => stage.name).toList(growable: false);

  // MARK: Retained frame hooks

  // The fake effect encodes no matte, so a fully-hidden frame retains
  // nothing that must stay compositor-only.
  @override
  GlassFrameState get hiddenFrameState => GlassFrameState.empty;

  // Without a matte, every shape is drawable.
  @override
  bool hasDrawableGlass(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
  ) => true;

  @override
  bool isSnapshotCurrent(
    RenderLiquidGlassGeometry geometry,
    GeometryCache snapshot,
  ) => geometry.hasCurrentGeometryCache(snapshot);

  @override
  double get materialOutset => fakeGlassSurfaceOutset(settings);

  // One extra logical pixel covers the kernel's rounding at any DPR.
  @override
  double effectSamplingReach(Rect material) {
    if (!_hasBlur) return 0;
    final sigma = settings.frostSigmaAt(
      devicePixelRatio,
      shapeShortSide: _sharedShapeShortSide,
    );
    return sigma * 3 + 1;
  }

  /// Short side of the smallest shape the shared filter covers. The blur is
  /// layer-wide, like RealGlass's.
  double get _sharedShapeShortSide {
    double? shortest;
    for (final (_, geometry, geometryToLayer) in shapesWithGeometry) {
      for (final shape in geometry.shapes) {
        if (_backdropClass(shape.appearance) != 2) continue;
        // shapeBounds is already in the geometry's local space.
        final side = MatrixUtils.transformRect(
          geometryToLayer,
          shape.shapeBounds,
        ).shortestSide;
        if (side <= 0) continue;
        shortest = shortest == null ? side : math.min(shortest, side);
      }
    }
    return shortest ?? 150;
  }

  FakeGlassFilterParts _sharedBackdropFilter() {
    // Keyed on what the short side turns into (blur sigma, size progress), not
    // on the short side: an animated scale changes it every frame, but the
    // filter only when those do, and a new filter object is a new backdrop
    // saveLayer paint.
    final inputs = fakeGlassFilterInputs(
      settings,
      deviceScale: devicePixelRatio,
      shapeShortSide: _sharedShapeShortSide,
    );
    final cached = _cachedFilter;
    if (cached != null && _cachedFilterInputs == inputs) return cached;
    final filter = _buildBackdropFilter();
    _cachedFilter = filter;
    _cachedFilterInputs = inputs;
    return filter;
  }

  @override
  void onDevicePixelRatioChanged() {
    _cachedFilter = null;
    _cachedFilterInputs = null;
    markNeedsCompositingBitsUpdate();
  }

  @override
  void onSettingsChanged(LiquidGlassSettings old) {
    _cachedFilter = null;
    _cachedFilterInputs = null;
    markNeedsCompositingBitsUpdate();
  }

  @override
  void onAppearanceChanged() {
    _cachedFilter = null;
    _cachedFilterInputs = null;
    markNeedsCompositingBitsUpdate();
  }

  // MARK: Painting

  @override
  void paintFrame(
    PaintingContext context,
    Offset offset,
    Rect? geometryBounds,
  ) {
    context.pushLayer(
      _retainedFrameSlot.layer ??= ContainerLayer(),
      (slotContext, slotOffset) =>
          _paintFrame(slotContext, slotOffset, geometryBounds),
      offset,
    );
  }

  void _paintFrame(
    PaintingContext context,
    Offset offset,
    Rect? geometryBounds,
  ) {
    assert(() {
      _debugLastPaintStages.clear();
      return true;
    }(), 'Reset paint-order diagnostics.');
    if (frameState == GlassFrameState.empty && shapesWithGeometry.isEmpty) {
      debugClipBounds = null;
      effectPaintBounds = Offset.zero & size;
      _clearClipCache();
      clearFrameInputs();
      _releaseLayers();
      return;
    }

    if (!_clipInputsMatch()) {
      Rect? rebuiltBounds;
      final rebuiltPath = Path();
      final rebuiltClasses = <int>[];
      for (final (_, geometry, transform) in shapesWithGeometry) {
        for (final shape in geometry.shapes) {
          final backdropClass = _backdropClass(shape.appearance);
          rebuiltClasses.add(backdropClass);
          if (backdropClass == 0) continue;
          final shapeToLayer = shape.shapeToGeometry == null
              ? transform
              : transform.multiplied(shape.shapeToGeometry!);
          final shapeBounds = Offset.zero & shape.renderObject.size;
          final transformedBounds = MatrixUtils.transformRect(
            shapeToLayer,
            shapeBounds,
          );
          rebuiltBounds =
              rebuiltBounds?.expandToInclude(transformedBounds) ??
              transformedBounds;
          // The shared union clip covers only fully visible shapes whose
          // backdrop transfer matches the layer's; every other visible shape
          // gets its own clipped pass below.
          if (backdropClass == 2) {
            rebuiltPath.addPath(
              shape.shape.getOuterPath(shapeBounds),
              Offset.zero,
              matrix4: shapeToLayer.storage,
            );
          }
        }
      }
      _cachedClipPath = rebuiltPath;
      _cachedClipBounds = rebuiltBounds;
      _cachedClipClasses = rebuiltClasses;
      rememberFrameInputs();
    }
    final bounds = _cachedClipBounds;
    if (bounds == null) {
      debugClipBounds = null;
      effectPaintBounds = Offset.zero & size;
      _releaseLayers();
      return;
    }
    final clipPath = _cachedClipPath!;

    debugClipBounds = bounds;
    effectPaintBounds = expandEffectBounds(bounds);
    assert(() {
      _debugLastPaintStages.add(_FakeGlassPaintStage.shadows);
      return true;
    }(), 'Record shadow composition order.');
    paintRetainedEffect(context, offset, (effectContext, effectOffset) {
      if (recordGlassShadows(effectOffset) case final shadows?) {
        effectContext.addLayer(shadows);
      }

      // The shared filter only exists while a fully visible shape shares
      // the layer's backdrop transfer.
      final sharedBackdropActive =
          _hasBackdropEffect && _cachedClipClasses.contains(2);
      var paintedBackdrop = sharedBackdropActive;
      if (sharedBackdropActive) {
        final sharedFilter = _sharedBackdropFilter();
        final backdropLayer = (_backdropLayer.layer ??= BackdropFilterLayer())
          ..filter = sharedFilter.full
          ..blendMode = BlendMode.srcOver;
        assert(() {
          debugRegisterBackdropCapture(this, _effectiveBackdropKey);
          return true;
        }(), 'Count independent backdrop captures in debug builds.');
        _paintInPass(
          effectContext,
          effectOffset,
          _sharedPass,
          filter: backdropLayer,
          parts: sharedFilter,
          inner: bounds,
          reach: effectSamplingReach(bounds),
          (passContext, passOffset) => _paintPassClip(
            passContext,
            passOffset,
            _sharedPass,
            _clipLayer,
            bounds,
            clipPath,
            backdropLayer,
          ),
        );
      } else {
        _backdropLayer.layer = null;
        _clipLayer.layer = null;
        _sharedPass.clear();
      }
      paintedBackdrop =
          _paintSeparateBackdrops(
            effectContext,
            effectOffset,
            shapesWithGeometry,
          ) ||
          paintedBackdrop;
      assert(() {
        if (paintedBackdrop) {
          _debugLastPaintStages.add(_FakeGlassPaintStage.backdrop);
        }
        return true;
      }(), 'Record backdrop composition order.');

      assert(() {
        _debugLastPaintStages.add(_FakeGlassPaintStage.surfaces);
        return true;
      }(), 'Record layer-owned surface composition order.');
      _paintSurfaces(effectContext.canvas, effectOffset, shapesWithGeometry);
    });
    assert(() {
      _debugLastPaintStages.add(_FakeGlassPaintStage.contents);
      return true;
    }(), 'Record normal subtree composition order.');
  }

  void _paintSurfaces(
    Canvas canvas,
    Offset offset,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
  ) {
    final shader = surfaceShader;
    if (shader == null) return;
    for (final (_, geometry, geometryToLayer) in geometries) {
      for (final shape in geometry.shapes) {
        canvas
          ..save()
          ..translate(offset.dx, offset.dy)
          ..transform(geometryToLayer.storage);
        if (shape.shapeToGeometry case final transform?) {
          canvas.transform(transform.storage);
        }
        paintFakeGlassSurface(
          canvas,
          shader: shader,
          size: shape.renderObject.size,
          shape: shape.shape,
          settings: settings,
          appearance: shape.appearance,
          devicePixelRatio: devicePixelRatio,
        );
        if (settings.highlight * shape.appearance.visibility > 0) {
          paintFakeGlassSurface(
            canvas,
            shader: shader,
            size: shape.renderObject.size,
            shape: shape.shape,
            settings: settings,
            appearance: shape.appearance,
            devicePixelRatio: devicePixelRatio,
            highlightOnly: true,
          );
        }
        canvas.restore();
      }
    }
  }

  /// Paints each separately served shape's own clipped backdrop filter so
  /// its transfer applies independently while the shape stays registered
  /// with this layer. Layers are retained across frames keyed by the
  /// shape's render object; entries for shapes that rejoined the shared
  /// clip or hid are released. Returns whether any pass was painted.
  bool _paintSeparateBackdrops(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
  ) {
    final active = <LiquidGlassShapeRenderObject>{};
    for (final (_, geometry, geometryToLayer) in geometries) {
      for (final shape in geometry.shapes) {
        if (_backdropClass(shape.appearance) != 1) continue;
        // The shape's own appearance carries its visibility and any
        // backdrop-transfer override, so fading keeps the same transfer the
        // shared filter applied while it was fully visible.
        // One short side decides the blur the filter applies and how far the
        // pass has to reach for it.
        final shortSide = MatrixUtils.transformRect(
          geometryToLayer,
          shape.shapeBounds,
        ).shortestSide;
        final filter = fakeGlassBackdropFilterParts(
          settings,
          shape.appearance,
          deviceScale: devicePixelRatio,
          shapeShortSide: shortSide,
        );
        if (filter == null) continue;
        final renderObject = shape.renderObject;
        active.add(renderObject);
        final layers = _separateBackdropLayers.putIfAbsent(
          renderObject,
          _SeparateBackdropLayers.new,
        );
        final backdropLayer = (layers.backdrop.layer ??= BackdropFilterLayer())
          ..filter = filter.full
          ..blendMode = BlendMode.srcOver;
        assert(() {
          debugRegisterBackdropCapture(this, _effectiveBackdropKey);
          return true;
        }(), 'Count independent backdrop captures in debug builds.');
        final shapeToLayer = shape.shapeToGeometry == null
            ? geometryToLayer
            : geometryToLayer.multiplied(shape.shapeToGeometry!);
        final shapeBounds = Offset.zero & renderObject.size;
        final clipBounds = MatrixUtils.transformRect(shapeToLayer, shapeBounds);
        final sigma = settings.frostSigmaAt(
          devicePixelRatio,
          shapeShortSide: shortSide,
        );
        _paintInPass(
          context,
          offset,
          layers.pass,
          filter: backdropLayer,
          parts: filter,
          inner: clipBounds,
          reach: sigma != 0 ? sigma * 3 + 1 : 0,
          (passContext, passOffset) => _paintPassClip(
            passContext,
            passOffset,
            layers.pass,
            layers.clip,
            clipBounds,
            shape.shape
                .getOuterPath(shapeBounds)
                .transform(shapeToLayer.storage),
            backdropLayer,
          ),
        );
      }
    }
    for (final renderObject in _separateBackdropLayers.keys.toList()) {
      if (active.contains(renderObject)) continue;
      _separateBackdropLayers.remove(renderObject)!.dispose();
    }
    return active.isNotEmpty;
  }

  bool _clipInputsMatch() {
    if (!encodedInputsMatch(shapesWithGeometry)) return false;
    var shapeIndex = 0;
    for (final (_, geometry, _) in shapesWithGeometry) {
      for (final shape in geometry.shapes) {
        if (shapeIndex >= _cachedClipClasses.length ||
            _cachedClipClasses[shapeIndex] !=
                _backdropClass(shape.appearance)) {
          return false;
        }
        shapeIndex++;
      }
    }
    return shapeIndex == _cachedClipClasses.length;
  }

  /// 0: hidden, 1: needs its own clipped backdrop pass — fading visibility,
  /// or a backdrop transfer that differs from the layer's shared one,
  /// 2: fully visible and covered by the shared union clip.
  int _backdropClass(LiquidGlassAppearance appearance) {
    final visibility = appearance.visibility.clamp(0.0, 1.0);
    if (visibility <= 0) return 0;
    if (visibility >= 1 && _sharesLayerBackdrop(appearance)) return 2;
    return 1;
  }

  void _clearClipCache() {
    _cachedClipPath = null;
    _cachedClipBounds = null;
    _cachedClipClasses = const [];
  }

  FakeGlassFilterParts _buildBackdropFilter() {
    // Every shape the shared clip covers is fully visible, so the shared
    // transfer always applies at full strength.
    return fakeGlassBackdropFilterParts(
      settings,
      defaultAppearance.copyWith(visibility: 1),
      deviceScale: devicePixelRatio,
      shapeShortSide: _sharedShapeShortSide,
    )!;
  }

  // MARK: Compositing

  @override
  void onTransformChanged() {
    // The clip, backdrop filter, and analytic surface are local to this layer
    // and therefore move with the retained ancestor tree without repainting.
  }

  @override
  void onCompositing() {
    if (!attached) return;
    runCompositorPoll();
    // Where the glass is on screen decides how its passes are cut, and
    // retained motion moves it without repainting.
    _syncPassSlot(_sharedPass);
    for (final layers in _separateBackdropLayers.values) {
      _syncPassSlot(layers.pass);
    }
  }

  /// Paints a clipped backdrop [filter] with [painter]. With native seeds on
  /// (see [liquidGlassNativeSeed]) and a blur to crop, that happens inside a
  /// pass the layer holds in [slot], seeded by a small backdrop filter, and the
  /// filter reads that pass instead of the backdrop its key names; otherwise
  /// the filter keeps its key and nothing else is added to the layer tree.
  void _paintInPass(
    PaintingContext context,
    Offset offset,
    _PassSlot slot,
    PaintingContextCallback painter, {
    required BackdropFilterLayer filter,
    required FakeGlassFilterParts parts,
    required Rect inner,
    required double reach,
  }) {
    final key = _effectiveBackdropKey;
    // A glass without a blur, or that is nothing but a blur, needs no seed.
    final seeds =
        liquidGlassNativeSeed != LiquidGlassNativeSeed.none &&
        parts.sigma > 0 &&
        !identical(parts.withoutBlur, fakeGlassIdentityFilter);
    if (!seeds) {
      slot.clear();
      filter.backdropKey = key;
      painter(context, offset);
      return;
    }
    final pass = slot.handle.layer ??= SeededBackdropPassLayer()
      ..seedWhileResizing = true
      ..onActiveChanged = () => _syncChildClip(slot);
    slot
      ..inner = inner.shift(offset)
      ..offset = offset
      ..reach = reach;
    _syncPassSlot(slot);
    pass.bindFilter(
      filter,
      key,
      full: parts.full,
      blur: PassBlur(
        sigma: parts.sigma,
        withoutBlur: parts.withoutBlur,
        blurOnly: identical(parts.withoutBlur, fakeGlassIdentityFilter),
      ),
      automaticKey: backdropKey == null,
    );
    context.pushLayer(pass, painter, offset);
  }

  void _syncPassSlot(_PassSlot slot) {
    final layer = slot.handle.layer;
    final inner = slot.inner;
    if (layer == null || inner == null) return;
    layer.apply(
      planBackdropPass(inner, slot.offset, slot.reach, sizing: slot.sizing),
      inner,
    );
    _syncChildClip(slot);
  }

  /// Paints the clip around [backdrop] in [slot]'s pass: the effect's
  /// outline, [path], clipped natively like a filter without a pass.
  ///
  /// While the pass is in effect, [_syncChildClip] swaps the clip for a rect
  /// the size of the pass, and the pass cuts [path] out with its own
  /// outside-clear instead.
  void _paintPassClip(
    PaintingContext context,
    Offset offset,
    _PassSlot slot,
    LayerHandle<ClipPathLayer> handle,
    Rect bounds,
    Path path,
    BackdropFilterLayer backdrop,
  ) {
    final layer = context.pushClipPath(
      true,
      offset,
      bounds,
      path,
      (clipContext, clipOffset) {
        clipContext.pushLayer(backdrop, (_, _) {}, clipOffset);
      },
      oldLayer: handle.layer,
    );
    handle.layer = layer;
    slot
      ..clipLayer = layer
      ..outline = layer?.clipPath;
    _syncChildClip(slot);
  }

  /// Makes the pass's child clip a rect while the pass is in effect.
  ///
  /// The backdrop filter's saveLayer takes the size of its clip, and Impeller
  /// reuses an offscreen target only at exactly the same size, so a clip that
  /// is the exact outline of an animated shape allocates and frees a target
  /// every frame. The pass rect is already on pixel buckets (see
  /// [planSeededBackdropPass]) and contains the outline, so the filter paints
  /// the whole of it and the pass clears everything outside the real outline
  /// ([SeededBackdropPassLayer.silhouette]). Without a pass, the clip is the
  /// outline itself, as before.
  void _syncChildClip(_PassSlot slot) {
    final clip = slot.clipLayer;
    final outline = slot.outline;
    if (clip == null || outline == null) return;
    final pass = slot.handle.layer;
    pass?.silhouette = outline;
    final rect = pass?.passRect;
    final wanted = rect == null ? outline : slot.rectPath(rect);
    if (!identical(clip.clipPath, wanted)) clip.clipPath = wanted;
  }

  @override
  void onCompositorTranslationMissed(
    ({bool needsRepaint, Offset? translation}) motion,
  ) {
    if (motion.needsRepaint) _refreshRetainedFrame();
  }

  // The retained layers of this frame are already in the scene.
  void _refreshRetainedFrame() {
    final slot = _retainedFrameSlot.layer;
    if (slot == null) {
      markNeedsPaint();
      return;
    }
    final bounds = prepareFrameGeometry();
    slot.removeAllChildren();
    final context = PaintingContext(
      slot,
      paintBounds.shift(retainedPaintOffset),
    );
    _paintFrame(context, retainedPaintOffset, bounds);
  }

  void _releaseGlassLayers() {
    _backdropLayer.layer = null;
    _clipLayer.layer = null;
    _sharedPass.clear();
    for (final layers in _separateBackdropLayers.values) {
      layers.dispose();
    }
    _separateBackdropLayers.clear();
  }

  void _releaseLayers() {
    _releaseGlassLayers();
    releaseRetainedEffectLayer();
  }

  @override
  void dispose() {
    _retainedFrameSlot.layer = null;
    _releaseLayers();
    super.dispose();
  }
}

/// Retained layer handles for one shape's own clipped backdrop pass.
class _SeparateBackdropLayers {
  final pass = _PassSlot();
  final clip = LayerHandle<ClipPathLayer>();
  final backdrop = LayerHandle<BackdropFilterLayer>();

  void dispose() {
    pass.clear();
    clip.layer = null;
    backdrop.layer = null;
  }
}

/// A retained seeded pass layer and what it was last painted with, so its
/// placement can be refreshed without repainting.
class _PassSlot {
  final handle = LayerHandle<SeededBackdropPassLayer>();

  /// Keeps this slot's pass from resizing on every bucket step.
  final sizing = BackdropPassSizing();

  /// The clip around the backdrop filter, in the pass layer's parent's
  /// coordinates.
  Rect? inner;
  Offset offset = Offset.zero;

  /// How far the blur reads past [inner].
  double reach = 0;

  /// The clip layer around the backdrop filter, and the outline it has
  /// without a pass.
  ClipPathLayer? clipLayer;
  Path? outline;

  Rect? _rectPathRect;
  Path? _rectPath;

  /// A path of exactly [rect], the same object for the same rect.
  Path rectPath(Rect rect) {
    if (_rectPath == null || _rectPathRect != rect) {
      _rectPath = Path()..addRect(rect);
      _rectPathRect = rect;
    }
    return _rectPath!;
  }

  void clear() {
    handle.layer?.onActiveChanged = null;
    handle.layer = null;
    inner = null;
    clipLayer = null;
    outline = null;
  }
}
