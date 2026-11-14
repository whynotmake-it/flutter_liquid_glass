import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/composer.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/rendering/backdrop_rig.dart';
import 'package:liquid_glass_renderer/src/rendering/drawn_values.dart';
import 'package:liquid_glass_renderer/src/rendering/fake_glass_color.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_blur.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_composer.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_shape_helpers.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';
import 'package:liquid_glass_renderer/src/rendering/paint_fake_glass_surface.dart';
import 'package:liquid_glass_renderer/src/rendering/read.dart';
import 'package:liquid_glass_renderer/src/rendering/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/rendering/scene_out.dart';
import 'package:liquid_glass_renderer/src/rendering/transform_tracking_render_object_mixin.dart';

enum _FakeGlassPaintStage {
  shadows,
  backdrop,
  surfaces,
  contents,
}

/// The fake glass layer: paints a clipped backdrop blur plus the surface
/// shader for the shared shape geometry. Where it can, the shared blur is
/// drawn over a copy of what lies under the glass instead of reading the
/// backdrop (see [BackdropRig]). NEAR: over a copy, a blur that Impeller
/// downsamples takes other taps than over the whole backdrop, at most 20
/// channel levels apart in the host test of white text under 6 px of frost
/// and 24 at the edges of buttons over photos on the Pixel 6a; at 2 px the
/// two do not differ.
class RenderConsolidatedFakeGlassLayer extends LiquidGlassRenderObject
    with TransformTrackingRenderObjectMixin {
  /// Creates a fake glass layer that draws the shapes [link] gathers.
  RenderConsolidatedFakeGlassLayer({
    required super.devicePixelRatio,
    required super.link,
    required super.settings,
    required super.defaultAppearance,
    required this._surfaceShader,
  });

  FragmentShader? _surfaceShader;

  /// The surface shader of fake glass, or null before it has loaded.
  FragmentShader? get surfaceShader => _surfaceShader;
  set surfaceShader(FragmentShader? value) {
    if (identical(_surfaceShader, value)) return;
    _surfaceShader = value;
    markNeedsPaint();
  }

  /// The surface shader it draws with.
  @visibleForTesting
  FragmentShader? get debugSurfaceShader => _surfaceShader;

  final _surfaceShaders = FakeGlassSurfaceShaders();

  /// Capture shared by this layer's own backdrop reads. Without it, a
  /// separately served shape would sample the shared filter's output in
  /// overlapping pixels and compound both transfers; sharing one capture
  /// also collapses their backdrop readbacks into one.
  final _share = BackdropKey();

  /// The read under the shared union clip.
  late final _sharedRig = _rig();

  BackdropRig _rig() => BackdropRig(key: _share);

  final _retainedFrameSlot = LayerHandle<ContainerLayer>();

  /// Per-shape backdrop reads for shapes the shared union clip cannot
  /// serve: shapes that are fading (0 < visibility < 1) or whose appearance
  /// needs a different backdrop transfer than the layer's. They sit between
  /// the shared opaque-shape filter and the surfaces so a fading shape keeps
  /// its own clipped backdrop filter.
  final Map<LiquidGlassShapeRenderObject, BackdropRig> _separateRigs = {};
  FakeGlassFilterParts? _cachedFilter;
  double? _cachedFilterSigma;
  LiquidGlassColorModel? _cachedFilterModel;

  // The color model of the shared filter: the layer's own as its smallest
  // visible shape wears it, so the shapes of that size share the filter.
  late LiquidGlassColorModel _sharedModel = defaultAppearance.colorModel;

  // The same under a grey tint: it differs in the tones of the tint alone,
  // which the surface pass draws, not the filter.
  late LiquidGlassColorModel _sharedGreyModel = defaultAppearance.colorModel;

  Path? _cachedClipPath;
  Rect? _cachedClipBounds;
  List<_BackdropClass> _cachedClipClasses = const [];

  bool get _hasBlur => settings.effectiveFrost > 0;
  bool get _hasColorTransfer =>
      defaultAppearance.colorModel.saturation != 1 ||
      defaultAppearance.colorModel.transmissionGamma != 1 ||
      defaultAppearance.colorModel.parameters != null;
  bool get _hasBackdropEffect => _hasBlur || _hasColorTransfer;

  /// Whether [appearance] can use the layer's shared backdrop filter: it
  /// differs from [defaultAppearance], as the smallest visible shape wears
  /// it, only in tint and visibility, which the surface pass and opacity
  /// handle.
  bool _sharesLayerBackdrop(LiquidGlassAppearance appearance) =>
      appearance.colorModel == _sharedModel ||
      appearance.colorModel == _sharedGreyModel;

  /// The backdrop filter layer it last drew through.
  @visibleForTesting
  BackdropFilterLayer? get debugBackdropFilterLayer => _sharedRig.filterLayer;

  /// The retained per-shape clipped backdrop filters.
  @visibleForTesting
  Iterable<BackdropFilterLayer> get debugSeparateBackdropLayers =>
      _separateRigs.values.map((rig) => rig.filterLayer).nonNulls;

  /// The bounds of the clip it last drew its backdrop in.
  @visibleForTesting
  Rect? debugClipBounds;

  /// Whether the last composited frame drew the shared filter over a copy
  /// rather than reading the backdrop.
  @visibleForTesting
  bool debugDrewOverCopy = false;

  /// The clip path it last drew its backdrop in.
  @visibleForTesting
  Path? get debugClipPath => _cachedClipPath;

  final List<_FakeGlassPaintStage> _debugLastPaintStages = [];

  /// The stages of its last paint, in order.
  @visibleForTesting
  List<String> get debugLastPaintStages =>
      _debugLastPaintStages.map((stage) => stage.name).toList(growable: false);

  // The fake effect paints its shapes straight from their geometry, so a
  // fully hidden frame retains nothing that must stay compositor-only.
  @override
  bool get encodesMatte => false;

  @override
  double get materialOutset => fakeGlassSurfaceOutset(settings);

  FakeGlassFilterParts _sharedBackdropFilter(double shortSide) {
    // Keyed on the blur sigma the short side turns into, not on the short
    // side: an animated scale changes it every frame, but the filter only
    // when the sigma does, and a new filter object is a new backdrop saveLayer
    // paint.
    final sigma = settings.frostSigmaAt(
      devicePixelRatio,
      shapeShortSide: shortSide,
    );
    final cached = _cachedFilter;
    if (cached != null &&
        _cachedFilterSigma == sigma &&
        _cachedFilterModel == _sharedModel) {
      return cached;
    }
    // Every shape the shared clip covers is fully visible, so the shared
    // transfer always applies at full strength.
    final filter = fakeGlassBackdropFilterParts(
      settings,
      defaultAppearance.copyWith(visibility: 1, colorModel: _sharedModel),
      deviceScale: devicePixelRatio,
      shapeShortSide: shortSide,
    )!;
    _cachedFilter = filter;
    _cachedFilterSigma = sigma;
    _cachedFilterModel = _sharedModel;
    return filter;
  }

  void _dropFilterCache() {
    _cachedFilter = null;
    _cachedFilterSigma = null;
  }

  @override
  void onDevicePixelRatioChanged() => _dropFilterCache();

  @override
  void onSettingsChanged(LiquidGlassSettings old) => _dropFilterCache();

  @override
  void onAppearanceChanged() => _dropFilterCache();

  @override
  void paintFrame(
    PaintingContext context,
    Offset offset,
    Rect? geometryBounds,
  ) {
    context.pushLayer(
      _retainedFrameSlot.layer ??= ContainerLayer(),
      _paintFrame,
      offset,
    );
  }

  void _paintFrame(PaintingContext context, Offset offset) {
    assert(() {
      _debugLastPaintStages.clear();
      return true;
    }(), 'Reset paint-order diagnostics.');
    if (shapesWithGeometry.isEmpty) {
      debugClipBounds = null;
      effectPaintBounds = Offset.zero & size;
      _clearClipCache();
      clearFrameInputs();
      _releaseLayers();
      return;
    }

    final smallest = smallestVisibleShortSide() ?? double.infinity;
    _sharedModel = defaultAppearance.colorModel.at(smallest);
    _sharedGreyModel = defaultAppearance.colorModel.at(
      smallest,
      tint: const Color(0xFF808080),
    );
    if (!_clipInputsMatch()) {
      Rect? rebuiltBounds;
      final rebuiltPath = Path();
      final rebuiltClasses = <_BackdropClass>[];
      for (final (_, geometry, transform) in shapesWithGeometry) {
        for (final shape in geometry.shapes) {
          final backdropClass = _backdropClass(shape.appearance);
          rebuiltClasses.add(backdropClass);
          if (backdropClass == .hidden) continue;
          final shapeToLayer = shapeTransformToLayer(shape, transform);
          final shapeBounds = Offset.zero & shape.renderObject.paintSize;
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
          if (backdropClass == .shared) {
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
          _hasBackdropEffect &&
          _cachedClipClasses.contains(_BackdropClass.shared);
      var paintedBackdrop = sharedBackdropActive;
      // Fading shapes count: a shape that leaves the shared filter for one of
      // its own keeps the blur it had.
      final shortSide =
          smallestVisibleShortSide() ??
          LiquidGlassRenderObject.largestFittedShortSide;
      if (sharedBackdropActive) {
        final sharedFilter = _sharedBackdropFilter(shortSide);
        _sharedRig.paint(
          effectContext,
          effectOffset,
          filter: sharedFilter.full,
          frost: sharedFilter.frost,
          bounds: bounds,
          outline: clipPath,
          reach: glassBlurReach(sharedFilter.sigma),
          devicePixelRatio: devicePixelRatio,
          // Separate shapes read live under the shared key. A shared filter
          // drawn from a copy would leave them no shared read, so they would
          // filter its output where they overlap: while one paints, the
          // shared filter reads live too.
          site:
              GlassCopies.enabled &&
                  !_cachedClipClasses.contains(_BackdropClass.separate)
              ? layer
              : null,
        );
      } else {
        _sharedRig.clear();
      }
      paintedBackdrop =
          _paintSeparateBackdrops(effectContext, effectOffset, shortSide) ||
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
    _surfaceShaders.begin(shader);
    for (final (_, geometry, geometryToLayer) in geometries) {
      for (final shape in geometry.shapes) {
        canvas
          ..save()
          ..translate(offset.dx, offset.dy)
          ..transform(geometryToLayer.storage);
        if (shape.shapeToGeometry case final transform?) {
          canvas.transform(transform.storage);
        }
        paintFakeGlassSurfaceWithHighlight(
          canvas,
          shaders: _surfaceShaders,
          size: shape.renderObject.paintSize,
          shape: shape.shape,
          settings: settings,
          appearance: shape.appearance,
          devicePixelRatio: devicePixelRatio,
        );
        canvas.restore();
      }
    }
  }

  /// Paints a clipped backdrop filter of its own for each separately served
  /// shape; returns whether any was painted.
  bool _paintSeparateBackdrops(
    PaintingContext context,
    Offset offset,
    double shortSide,
  ) {
    final active = <LiquidGlassShapeRenderObject>{};
    for (final (_, geometry, geometryToLayer) in shapesWithGeometry) {
      for (final shape in geometry.shapes) {
        if (_backdropClass(shape.appearance) != .separate) continue;
        // The shape's own appearance carries its visibility and any
        // backdrop-transfer override, so fading keeps the same transfer the
        // shared filter applied while it was fully visible.
        final filter = fakeGlassBackdropFilterParts(
          settings,
          shape.appearance,
          deviceScale: devicePixelRatio,
          shapeShortSide: shortSide,
        );
        if (filter == null) continue;
        final renderObject = shape.renderObject;
        active.add(renderObject);
        final rig = _separateRigs.putIfAbsent(renderObject, _rig);
        final shapeToLayer = shapeTransformToLayer(shape, geometryToLayer);
        final shapeBounds = Offset.zero & renderObject.paintSize;
        final clipBounds = MatrixUtils.transformRect(shapeToLayer, shapeBounds);
        rig.paint(
          context,
          offset,
          filter: filter.full,
          bounds: clipBounds,
          outline: shape.shape
              .getOuterPath(shapeBounds)
              .transform(shapeToLayer.storage),
          reach: glassBlurReach(filter.sigma),
          devicePixelRatio: devicePixelRatio,
        );
      }
    }
    for (final renderObject in _separateRigs.keys.toList()) {
      if (active.contains(renderObject)) continue;
      _separateRigs.remove(renderObject)!.dispose();
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

  _BackdropClass _backdropClass(LiquidGlassAppearance appearance) {
    final visibility = appearance.visibility.clamp(0.0, 1.0);
    if (visibility <= 0) return .hidden;
    if (visibility >= 1 && _sharesLayerBackdrop(appearance)) return .shared;
    return .separate;
  }

  void _clearClipCache() {
    _cachedClipPath = null;
    _cachedClipBounds = null;
    _cachedClipClasses = const [];
  }

  @override
  void onTransformChanged() {
    // The clip, backdrop filter, and analytic surface are local to this layer
    // and therefore move with the retained ancestor tree without repainting.
  }

  @override
  void onPreparing() {
    runCompositorPoll();
  }

  @override
  SiteAsk ask() => _sharedRig.ask();

  @override
  void beginFate(SiteFate fate) {
    _fate = fate;
    if (fate is! HiddenFate) return;
    if (_sharedRig.hasSlot) {
      compositionSeedSuppressed = true;
      debugDrewOverCopy = false;
      _sharedRig.hide();
    } else {
      // Without a slot it is the live read.
      compositionSeedSuppressed = false;
    }
  }

  SiteFate _fate = const HiddenFate();

  @override
  void show(GlassRead read, ReadPixels pixels) {
    switch (pixels) {
      case OnPage(:final page):
        // Glass over its copy reads no backdrop: an opacity pass around it
        // needs no seed, and a seeded one would stand in the copy's way.
        compositionSeedSuppressed = true;
        debugDrewOverCopy = true;
        _sharedRig.showPage(page);
      case LiveBackdrop(:final group):
        compositionSeedSuppressed = false;
        debugDrewOverCopy = false;
        if (_sharedRig.hasSlot) _sharedRig.showLive(group);
      // Its look reads a page: compile gives it no copy in the frame.
      case InScene():
        break;
    }
  }

  @override
  void addOutput(SceneOut out, ReadCopy outer) {
    if (_fate case LeadFate(read: GlassRead(source: ImageRead()))) {
      if (_sharedRig.pageShown case final page?) out.picture(page);
    }
  }

  @override
  void onCompositorTranslationMissed() => _refreshRetainedFrame();

  // Paint is over for this frame: draws the retained slot again in place.
  void _refreshRetainedFrame() {
    final slot = _retainedFrameSlot.layer;
    assert(
      slot != null,
      'Every paint makes the retained slot and only dispose drops it, and a '
      'site is asked only after it painted.',
    );
    GlassComposer.sitePainted(owner!);
    prepareFrameGeometry();
    slot!.removeAllChildren();
    final context = PaintingContext(
      slot,
      paintBounds.shift(retainedPaintOffset),
    );
    _paintFrame(context, retainedPaintOffset);
  }

  void _releaseLayers() {
    _sharedRig.clear();
    for (final rig in _separateRigs.values) {
      rig.dispose();
    }
    _separateRigs.clear();
    releaseRetainedEffectLayer();
  }

  @override
  void dispose() {
    _retainedFrameSlot.layer = null;
    _releaseLayers();
    _sharedRig.dispose();
    _surfaceShaders.dispose();
    super.dispose();
  }
}

enum _BackdropClass {
  hidden,

  /// Fading, or a backdrop transfer other than the layer's: a clipped
  /// backdrop pass of its own.
  separate,

  /// Fully visible and covered by the shared union clip.
  shared,
}
