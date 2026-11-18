import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_color_model.dart';
import 'package:liquid_glass_renderer/src/painting/view_pixels.dart';
import 'package:liquid_glass_renderer/src/plan/plan_result.dart';
import 'package:liquid_glass_renderer/src/plan/plan_site.dart';
import 'package:liquid_glass_renderer/src/rendering/appearance.dart';
import 'package:liquid_glass_renderer/src/rendering/backdrop_rig.dart';
import 'package:liquid_glass_renderer/src/rendering/fake_glass_color.dart';
import 'package:liquid_glass_renderer/src/rendering/fake_glass_field_image.dart';
import 'package:liquid_glass_renderer/src/rendering/frame_shapes.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_composer.dart';
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
/// shader for the shared shape geometry, or for the one body its field
/// describes. Where it can, the shared blur is
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
    required this._fieldShader,
  });

  FragmentShader? _surfaceShader;

  /// The surface shader of fake glass, or null before it has loaded.
  FragmentShader? get surfaceShader => _surfaceShader;
  set surfaceShader(FragmentShader? value) {
    if (identical(_surfaceShader, value)) return;
    _surfaceShader = value;
    markNeedsPaint();
  }

  FragmentShader? _fieldShader;

  /// The surface shader of a body its [field] describes, or null before it
  /// has loaded.
  FragmentShader? get fieldShader => _fieldShader;
  set fieldShader(FragmentShader? value) {
    if (identical(_fieldShader, value)) return;
    _fieldShader = value;
    if (field != null) markNeedsPaint();
  }

  /// The surface shader it draws with.
  @visibleForTesting
  FragmentShader? get debugSurfaceShader => _surfaceShader;

  final _surfaceShaders = FakeGlassSurfaceShaders();
  final _fieldShaders = FakeGlassSurfaceShaders.field();
  final _fieldImage = FakeGlassFieldImage();

  /// Capture shared by this layer's own backdrop reads. Without it, a
  /// separately served shape would sample the shared filter's output in
  /// overlapping pixels and compound both transfers; sharing one capture
  /// also collapses their backdrop readbacks into one.
  final _backdropKey = BackdropKey();

  /// The read under the shared union clip.
  late final _sharedRig = _rig();

  FakeBackdropRig _rig() => FakeBackdropRig(key: _backdropKey);

  final _retainedFrameSlot = LayerHandle<ContainerLayer>();

  /// Backdrop reads of their own for bodies the shared union clip cannot
  /// serve: bodies that are fading (0 < visibility < 1) or whose appearance
  /// needs a different backdrop transfer than the layer's. They sit between
  /// the shared opaque-shape filter and the surfaces so a fading shape keeps
  /// its own clipped backdrop filter.
  final Map<LiquidGlassShapeRenderObject, FakeBackdropRig> _separateRigs = {};
  FakeGlassFilterParts? _cachedFilter;
  double? _cachedFilterSigma;
  FakeGlassTransfer? _cachedFilterTransfer;

  // The color model of the shared filter: the layer's own as its smallest
  // visible shape wears it, so the shapes of that size share the filter.
  late WornColorModel _sharedModel;
  FakeGlassTransfer? _sharedTransfer;

  Path? _cachedClipPath;
  Rect? _cachedClipBounds;
  List<_BackdropClass> _cachedClipClasses = const [];

  bool get _sharedFilterMayReadCopy =>
      glassReadsCopies && !_cachedClipClasses.contains(_BackdropClass.separate);

  bool _sharesLayerBackdrop(WornAppearance appearance) =>
      fakeGlassTransfer(_look, appearance.colorModel) == _sharedTransfer;

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
  bool get encodesGeometry => false;

  @override
  double get materialOutset => fakeGlassSurfaceOutset(_look);

  late FakeGlassLook _look = FakeGlassLook.of(settings);

  FakeGlassFilterParts? _sharedBackdropFilter(double shortSide) {
    // Keyed on the blur sigma the short side turns into, not on the short
    // side: an animated scale changes it every frame, but the filter only
    // when the sigma does, and a new filter object is a new backdrop saveLayer
    // paint.
    final sigma = _look.frostSigmaAt(
      devicePixelRatio,
      shapeShortSide: shortSide,
    );
    if (_cachedFilterSigma == sigma &&
        _cachedFilterTransfer == _sharedTransfer) {
      return _cachedFilter;
    }
    // Every shape the shared clip covers is fully visible, so the shared
    // transfer always applies at full strength.
    final filter = fakeGlassBackdropFilterParts(
      _look,
      WornAppearance(
        tint: defaultAppearance.tint,
        visibility: 1,
        colorModel: _sharedModel,
      ),
      devicePixelRatio: devicePixelRatio,
      shapeShortSide: shortSide,
    );
    _cachedFilter = filter;
    _cachedFilterSigma = sigma;
    _cachedFilterTransfer = _sharedTransfer;
    return filter;
  }

  void _dropFilterCache() {
    _cachedFilter = null;
    _cachedFilterSigma = null;
  }

  @override
  void onDevicePixelRatioChanged() => _dropFilterCache();

  @override
  bool drawsAlike(LiquidGlassSettings a, LiquidGlassSettings b) =>
      FakeGlassLook.of(a) == FakeGlassLook.of(b);

  @override
  void onSettingsChanged(LiquidGlassSettings old) {
    _look = FakeGlassLook.of(settings);
    _dropFilterCache();
  }

  @override
  void onFieldChanged() => _clearClipCache();

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
    if (frameShapes.geometries.isEmpty) {
      debugClipBounds = null;
      effectPaintBounds = Offset.zero & size;
      _clearClipCache();
      clearFrameInputs();
      _releaseLayers();
      return;
    }

    final shortSide = frameShapes.wornShortSide;
    _sharedModel = defaultAppearance.colorModel.wornAt(shortSide);
    _sharedTransfer = fakeGlassTransfer(_look, _sharedModel);
    final classes = [
      for (final body in _bodies) _backdropClass(body.shape.appearance),
    ];
    if (!encodedInputsMatch(frameShapes.geometries) ||
        !listEquals(_cachedClipClasses, classes)) {
      final field = this.field;
      Rect? rebuiltBounds;
      final rebuiltPath = field?.edge ?? Path();
      for (final (i, drawn) in frameShapes.drawn.indexed) {
        final shape = drawn.shape;
        final shapeBounds = Offset.zero & shape.renderObject.paintSize;
        final transformedBounds = MatrixUtils.transformRect(
          drawn.toLayer,
          shapeBounds,
        );
        rebuiltBounds =
            rebuiltBounds?.expandToInclude(transformedBounds) ??
            transformedBounds;
        if (field == null && classes[i] == .shared) {
          rebuiltPath.addPath(
            shape.shape.getOuterPath(shapeBounds),
            Offset.zero,
            matrix4: drawn.toLayer.storage,
          );
        }
      }
      _cachedClipPath = rebuiltPath;
      _cachedClipBounds = rebuiltBounds;
      _cachedClipClasses = classes;
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

      final sharedFilter = _cachedClipClasses.contains(_BackdropClass.shared)
          ? _sharedBackdropFilter(shortSide)
          : null;
      var paintedBackdrop = sharedFilter != null;
      if (sharedFilter != null) {
        _sharedRig.paint(
          effectContext,
          effectOffset,
          filter: sharedFilter.full,
          frost: sharedFilter.frost,
          bounds: bounds,
          outline: clipPath,
          site: _sharedFilterMayReadCopy ? layer : null,
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
      _paintSurfaces(effectContext.canvas, effectOffset);
    });
    assert(() {
      _debugLastPaintStages.add(_FakeGlassPaintStage.contents);
      return true;
    }(), 'Record normal subtree composition order.');
  }

  void _paintSurfaces(Canvas canvas, Offset offset) {
    if (field case final field?) {
      _paintFieldBody(canvas, offset, field);
      return;
    }
    final shader = surfaceShader;
    final lit = link.lit;
    if (shader == null && lit == null) return;
    if (shader != null) _surfaceShaders.begin(shader);
    for (final drawn in frameShapes.drawn) {
      final shape = drawn.shape;
      final glow = identical(shape.renderObject, lit) ? drawn.glow : null;
      if (shader == null && glow == null) continue;
      canvas
        ..save()
        ..translate(offset.dx, offset.dy)
        ..transform(drawn.toLayer.storage);
      final size = shape.renderObject.paintSize;
      if (glow != null) {
        canvas
          ..save()
          ..clipPath(shape.shape.getOuterPath(Offset.zero & size));
        paintFakeGlassGlow(
          canvas,
          glow,
          appearance: shape.appearance,
        );
        canvas.restore();
      }
      if (shader != null) {
        paintFakeGlassSurfaceWithGlint(
          canvas,
          shaders: _surfaceShaders,
          size: size,
          shape: shape.shape,
          look: _look,
          appearance: shape.appearance,
          devicePixelRatio: devicePixelRatio,
        );
      }
      canvas.restore();
    }
  }

  Iterable<FrameShape> get _bodies =>
      field == null ? frameShapes.drawn : frameShapes.drawn.take(1);

  void _paintFieldBody(Canvas canvas, Offset offset, LiquidGlassField field) {
    canvas
      ..save()
      ..translate(offset.dx, offset.dy);
    if (frameShapes.drawnOf(link.lit) case final lit? when lit.glow != null) {
      canvas
        ..save()
        ..clipPath(field.edge)
        ..transform(lit.toLayer.storage);
      paintFakeGlassGlow(
        canvas,
        lit.glow!,
        appearance: lit.shape.appearance,
      );
      canvas.restore();
    }
    if (fieldShader case final shader?) {
      _fieldShaders.begin(shader);
      paintFakeGlassFieldBody(
        canvas,
        shaders: _fieldShaders,
        nodes: _fieldImage.of(field),
        field: field,
        look: _look,
        appearance: _bodies.first.shape.appearance,
        devicePixelRatio: devicePixelRatio,
      );
    }
    canvas.restore();
  }

  /// Paints a clipped backdrop filter of its own for each separately served
  /// body.
  bool _paintSeparateBackdrops(
    PaintingContext context,
    Offset offset,
    double shortSide,
  ) {
    final active = <LiquidGlassShapeRenderObject>{};
    final field = this.field;
    for (final (i, drawn) in _bodies.indexed) {
      if (_cachedClipClasses[i] != .separate) continue;
      final shape = drawn.shape;
      final filter = fakeGlassBackdropFilterParts(
        _look,
        shape.appearance,
        devicePixelRatio: devicePixelRatio,
        shapeShortSide: shortSide,
      );
      if (filter == null) continue;
      final renderObject = shape.renderObject;
      active.add(renderObject);
      final rig = _separateRigs.putIfAbsent(renderObject, _rig);
      final shapeToLayer = drawn.toLayer;
      final shapeBounds = Offset.zero & renderObject.paintSize;
      final outline =
          field?.edge ??
          shape.shape.getOuterPath(shapeBounds).transform(shapeToLayer.storage);
      rig.paint(
        context,
        offset,
        filter: filter.full,
        bounds: field == null
            ? MatrixUtils.transformRect(shapeToLayer, shapeBounds)
            : outline.getBounds(),
        outline: outline,
      );
    }
    for (final renderObject in _separateRigs.keys.toList()) {
      if (active.contains(renderObject)) continue;
      _separateRigs.remove(renderObject)!.dispose();
    }
    return active.isNotEmpty;
  }

  _BackdropClass _backdropClass(WornAppearance appearance) =>
      appearance.visibility >= 1 && _sharesLayerBackdrop(appearance)
      ? .shared
      : .separate;

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
  SiteAsk ask(ViewPixels view) => _sharedRig.ask(view);

  @override
  void beginFate(SiteFate fate) {
    _fate = fate;
    if (fate is! HiddenFate) return;
    if (_sharedRig.hasSlot) {
      compositionSeedSuppressed = true;
      debugDrewOverCopy = false;
      _sharedRig.hide();
    } else {
      compositionSeedSuppressed = false;
    }
  }

  SiteFate _fate = const HiddenFate();

  @override
  void show(GlassRead read, ReadPixels pixels) {
    switch (pixels) {
      case ImagePixels(:final copy):
        // Glass over its copy reads no backdrop: an opacity pass around it
        // needs no seed, and a seeded one would stand in the copy's way.
        compositionSeedSuppressed = true;
        debugDrewOverCopy = true;
        _sharedRig.showImage(copy);
      case BackdropPixels(:final group):
        compositionSeedSuppressed = false;
        debugDrewOverCopy = false;
        if (_sharedRig.hasSlot) _sharedRig.showBackdrop(group);
      case ScenePixels():
        assert(false, 'Fake glass reads an image, never a copy in the scene.');
    }
  }

  @override
  void addOutput(SceneOut out, ReadCopy outer) {
    if (_fate case LeadFate(read: GlassRead(source: ImageRead()))) {
      if (_sharedRig.imageShown case final picture?) out.picture(picture);
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
    _fieldShaders.dispose();
    _fieldImage.dispose();
    super.dispose();
  }
}

enum _BackdropClass {
  /// Fading, or a backdrop transfer other than the layer's: a clipped
  /// backdrop pass of its own.
  separate,

  /// Fully visible and covered by the shared union clip.
  shared,
}
