// Explicit canvas save/transform/restore sequences are easier to audit than
// cascades across nested geometry loops.
// ignore_for_file: cascade_invocations

import 'dart:collection';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/glass_shadow.dart';
import 'package:liquid_glass_renderer/src/internal/glass_composition_probe.dart';
import 'package:liquid_glass_renderer/src/internal/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/internal/retained_glass_clip.dart';
import 'package:liquid_glass_renderer/src/internal/transform_tracking_repaint_boundary_mixin.dart';
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

/// What a glass layer's last painted frame committed to the retained layer
/// tree.
@internal
enum GlassFrameState {
  /// The frame drew no glass effect: no shapes are registered, none is
  /// visible, or none can be drawn by this effect. Foreground still retains
  /// its own paint, and the committed input snapshot lets ancestor motion
  /// stay on the compositor.
  empty,

  /// Every registered shape is hidden but drawable. The snapshot and the
  /// retained effect of the last active frame stay encoded — the GPU matte
  /// in particular — so ancestor motion stays compositor-only until a shape
  /// becomes visible again.
  idle,

  /// The frame drew the glass effect for at least one visible shape.
  active,
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

/// Shared base for render objects that assemble [RenderLiquidGlassGeometry]
/// shapes and paint one glass effect over the layer's foreground.
///
/// The base owns shape registration via [GeometryRenderLink], transform
/// polling ([FramePollMarker] and the compositor-translation poll), the
/// retained [GlassFrameState] with its encoded input snapshot, layer
/// shadows, effect bounds, retained ancestor clips ([RetainedGlassClip])
/// and compositor translation. Subclasses implement only their effect in
/// [paintFrame]: real glass renders a GPU matte plus the final shader
/// filter; fake glass draws a blur plus a surface shader.
@internal
abstract class LiquidGlassRenderObject extends RenderProxyBox
    implements LiquidGlassLayerRenderObject {
  LiquidGlassRenderObject({
    required this._link,
    required this._settings,
    required this._defaultAppearance,
    required this._backdropKey,
    required this._devicePixelRatio,
  });

  static final logger = Logger(LgrLogNames.render);

  // MARK: Configuration

  GeometryRenderLink _link;
  GeometryRenderLink get link => _link;
  set link(GeometryRenderLink value) {
    if (_link == value) return;
    _link = value;
    markNeedsPaint();
  }

  LiquidGlassSettings _settings;
  LiquidGlassSettings get settings => _settings;
  set settings(LiquidGlassSettings value) {
    if (_settings == value) return;
    final old = _settings;
    _settings = value;
    onSettingsChanged(old);
    markNeedsPaint();
  }

  /// Called after [settings] changed, before [markNeedsPaint].
  @protected
  void onSettingsChanged(LiquidGlassSettings old) {}

  LiquidGlassAppearance _defaultAppearance;
  LiquidGlassAppearance get defaultAppearance => _defaultAppearance;
  set defaultAppearance(LiquidGlassAppearance value) {
    if (_defaultAppearance == value) return;
    _defaultAppearance = value;
    onAppearanceChanged();
    markNeedsPaint();
  }

  /// Called after [defaultAppearance] changed, before [markNeedsPaint].
  @protected
  void onAppearanceChanged() {}

  BackdropKey? _backdropKey;
  BackdropKey? get backdropKey => _backdropKey;
  set backdropKey(BackdropKey? value) {
    if (_backdropKey == value) return;
    _backdropKey = value;
    markNeedsPaint();
  }

  double _devicePixelRatio;
  double get devicePixelRatio => _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    onDevicePixelRatioChanged();
    markNeedsPaint();
  }

  /// Called after [devicePixelRatio] changed, before [markNeedsPaint].
  @protected
  void onDevicePixelRatioChanged() {}

  // MARK: Retained frame state

  /// The state the last painted frame committed.
  GlassFrameState _frameState = GlassFrameState.empty;

  /// The state the last painted frame committed.
  @protected
  GlassFrameState get frameState => _frameState;

  /// The shapes the last frame committed, in paint order.
  @protected
  final List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)>
  shapesWithGeometry = [];

  /// Encoded snapshot of the inputs the last non-idle frame was committed
  /// with: each shape's render object, geometry cache and transform into
  /// this layer. Idle frames preserve it, keeping the encoded snapshot of
  /// the last active frame so ancestor motion stays compositor-only when
  /// the glass becomes visible again.
  final List<_EncodedGeometryInput> _encodedGeometryInputs = [];

  /// Layer-local bounds the retained frame was encoded for. Only effects
  /// that encode geometry (the GPU matte) read them.
  @protected
  Rect? encodedGeometryBounds;

  /// Bounds the current frame's effect occupies, in local coordinates;
  /// [paintFrame] implementations set it.
  @protected
  Rect effectPaintBounds = Rect.zero;

  @override
  Rect get paintBounds =>
      effectPaintBounds.isEmpty ? super.paintBounds : effectPaintBounds;

  /// Number of times [paint] has run. Ancestor motion should not increment
  /// this once the frame has been encoded.
  @visibleForTesting
  int debugPaintCount = 0;

  final _compositionProbe = GlassCompositionProbe();
  final _framePoll = FramePollMarker();
  final _effectLayer = LayerHandle<OffsetLayer>();
  final _ancestorClips = RetainedGlassClip();
  final _idleAncestorClips = RetainedGlassClip();
  List<Object> _retainedStructure = [];

  /// The offset this layer last painted at; retained updates reuse it.
  @protected
  Offset retainedPaintOffset = Offset.zero;
  Offset _effectTranslation = Offset.zero;

  /// The structural identity of the last committed frame: render objects,
  /// whether they carry shadows, and their ancestry to this layer.
  @protected
  List<Object> get retainedStructure => _retainedStructure;

  /// Idle foreground has retained paint even if no effect was ever drawn.
  @protected
  bool get hasReusableIdleContents =>
      _frameState != GlassFrameState.active && shapesWithGeometry.isNotEmpty;

  /// Bounds of the clips between this object and its shapes that are
  /// re-applied around the glass filter, in local coordinates, or `null`.
  @protected
  Rect? get retainedClipBounds =>
      _frameState == GlassFrameState.idle ? null : _ancestorClips.ownerBounds;

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

  /// Reconciles experimental fade composition before scene submission.
  @protected
  void syncCompositionOpacity() => _compositionProbe.syncOpacity(this);

  /// Whether this layer paints inside a seeded fractional-opacity pass.
  @protected
  bool get compositionProbeSeeding => _compositionProbe.seeding;

  // MARK: Painting

  @override
  @nonVirtual
  void paint(PaintingContext context, Offset offset) {
    _compositionProbe.paint(
      context,
      offset,
      _paintGlass,
      owner: this,
    );
  }

  void _paintGlass(PaintingContext context, Offset offset) {
    retainedPaintOffset = offset;
    assert(() {
      debugPaintCount++;
      return true;
    }(), 'Track layer paints in debug builds.');
    logger.finest(
      '$hashCode Painting glass with ${link._shapeGeometries.length} shapes.',
    );
    final candidate =
        <(RenderLiquidGlassGeometry, GeometryCache, Matrix4)>[];
    final bounds = collectFrameGeometry(candidate);
    commitFrameGeometry(candidate);
    _frameState = classifyFrame(candidate);
    paintFrame(context, offset, bounds);
    // Foreground always paints in its own render ancestry, above the glass.
    super.paint(context, offset);
  }

  /// Paints this layer's effect for the just-committed [frameState].
  ///
  /// [geometryBounds] is the union of the committed shapes' geometry bounds
  /// in this layer's coordinates, or `null` when no shape collected geometry
  /// this frame. The foreground is painted by the caller afterwards.
  @protected
  void paintFrame(
    PaintingContext context,
    Offset offset,
    Rect? geometryBounds,
  );

  // Geometry preparation does not record pictures or paint child objects.
  @protected
  Rect? collectFrameGeometry(
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

  /// Commits the collected [candidate] to the retained frame state without
  /// deciding the frame's [GlassFrameState], so retained compositor ticks
  /// can refresh contributors without crossing an idle boundary.
  @protected
  void commitFrameGeometry(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> candidate,
  ) {
    setCompositorTranslation(Offset.zero);
    shapesWithGeometry
      ..clear()
      ..addAll(candidate);
    _retainedStructure = geometryStructure(candidate);
    _ancestorClips.update(this, shapeRenderObjects);
  }

  /// The structural identity of a frame's geometry: render objects, whether
  /// they carry shadows, and their ancestry to this layer. Retained updates
  /// compare it to detect topology changes that need a normal paint.
  @protected
  List<Object> geometryStructure(
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

  /// The state a frame that collected [geometries] commits: empty when
  /// nothing drawable remains, [hiddenFrameState] when every shape is
  /// invisible, and active otherwise.
  @protected
  GlassFrameState classifyFrame(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
  ) {
    if (geometries.isEmpty) return GlassFrameState.empty;
    if (!hasVisibleShape(geometries)) return hiddenFrameState;
    return hasDrawableGlass(geometries)
        ? GlassFrameState.active
        : GlassFrameState.empty;
  }

  /// Whether [geometries] contains a shape whose appearance is visible.
  @protected
  bool hasVisibleShape(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
  ) => geometries.any(
    (entry) => entry.$2.shapes.any(
      (shape) => shape.appearance.visibility > 0,
    ),
  );

  /// The state a fully-hidden frame commits: idle for effects that retain
  /// an encoded matte, empty for effects that cannot reuse one.
  @protected
  GlassFrameState get hiddenFrameState;

  /// Whether [geometries] contains at least one shape this effect can draw:
  /// a shape whose transform into this layer is invertible for the matte,
  /// or unconditionally true for effects that need no matte.
  @protected
  bool hasDrawableGlass(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
  );

  /// The render objects of all committed shapes, in frame order.
  @protected
  Iterable<RenderBox> get shapeRenderObjects => shapesWithGeometry.expand(
    (entry) => entry.$2.shapes.map((shape) => shape.renderObject),
  );

  /// Snapshots the committed shapes' identities, caches and transforms into
  /// the encoded inputs, reusing entries where possible.
  @protected
  void rememberFrameInputs() {
    final inputs = _encodedGeometryInputs;
    final sharedLength = min(
      inputs.length,
      shapesWithGeometry.length,
    );
    for (var index = 0; index < sharedLength; index++) {
      final current = shapesWithGeometry[index];
      inputs[index].update(
        current.$1,
        current.$2,
        current.$3,
      );
    }
    if (inputs.length > shapesWithGeometry.length) {
      inputs.removeRange(
        shapesWithGeometry.length,
        inputs.length,
      );
    }
    for (
      var index = inputs.length;
      index < shapesWithGeometry.length;
      index++
    ) {
      final current = shapesWithGeometry[index];
      inputs.add(
        _EncodedGeometryInput(
          current.$1,
          current.$2,
          current.$3,
        ),
      );
    }
  }

  /// Drops the encoded input snapshot together with its bounds.
  @protected
  void clearFrameInputs() {
    _encodedGeometryInputs.clear();
    encodedGeometryBounds = null;
  }

  /// Whether [geometries] still matches the encoded inputs exactly: same
  /// render objects, same geometry caches, same transforms.
  @protected
  bool encodedInputsMatch(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
  ) {
    if (geometries.length != _encodedGeometryInputs.length) return false;
    for (var index = 0; index < geometries.length; index++) {
      final (renderObject, cache, transform) = geometries[index];
      final encoded = _encodedGeometryInputs[index];
      if (!identical(renderObject, encoded.renderObject) ||
          !identical(cache, encoded.cache) ||
          !_sameTransform(transform, encoded.transform)) {
        return false;
      }
    }
    return true;
  }

  /// Polls retained geometry for a translation that can be applied directly
  /// to the layer tree before it is submitted to the engine.
  @protected
  ({bool needsRepaint, Offset? translation}) pollCompositorTranslation() {
    final current = link.shapes;
    final inputs = _encodedGeometryInputs;
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
      final wasCurrent = isSnapshotCurrent(geometry, encoded.cache);
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

  /// Whether [geometry]'s inputs still match the snapshot it was encoded
  /// with: the encoded matte revision for real glass, the geometry cache
  /// identity for effects that paint from the cache directly.
  @protected
  bool isSnapshotCurrent(
    RenderLiquidGlassGeometry geometry,
    GeometryCache snapshot,
  );

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

  static Offset? _translationDelta(Matrix4 before, Matrix4 after) {
    final a = before.storage;
    final b = after.storage;
    for (var index = 0; index < 16; index++) {
      if (index == 12 || index == 13) continue;
      if ((a[index] - b[index]).abs() > 1e-6) return null;
    }
    return Offset(b[12] - a[12], b[13] - a[13]);
  }

  static bool _sameTransform(Matrix4 a, Matrix4 b) {
    final aStorage = a.storage;
    final bStorage = b.storage;
    for (var index = 0; index < 16; index++) {
      if (aStorage[index] != bStorage[index]) return false;
    }
    return true;
  }

  static bool _nearOffset(Offset a, Offset b) =>
      (a.dx - b.dx).abs() <= 1e-6 && (a.dy - b.dy).abs() <= 1e-6;

  static bool _nearRect(Rect a, Rect b) =>
      (a.left - b.left).abs() <= 1e-6 &&
      (a.top - b.top).abs() <= 1e-6 &&
      (a.right - b.right).abs() <= 1e-6 &&
      (a.bottom - b.bottom).abs() <= 1e-6;

  /// The translation that maps the encoded inputs onto [bounds] when every
  /// committed shape still matches its snapshot and moved uniformly, or
  /// `null` otherwise.
  @protected
  Offset? encodedMatteDelta(Rect bounds) {
    final oldBounds = encodedGeometryBounds;
    if (oldBounds == null ||
        _encodedGeometryInputs.length != shapesWithGeometry.length) {
      return null;
    }
    for (var index = 0; index < shapesWithGeometry.length; index++) {
      final current = shapesWithGeometry[index];
      final encoded = _encodedGeometryInputs[index];
      if (!identical(current.$1, encoded.renderObject) ||
          current.$2.matteRevision != encoded.cache.matteRevision) {
        return null;
      }
    }
    final delta = _sharedTranslation(_encodedGeometryInputs, [
      for (final entry in shapesWithGeometry) entry.$3,
    ]);
    if (delta == null) return null;
    if (!_nearRect(bounds, oldBounds.shift(delta))) return null;
    return delta;
  }

  // MARK: Compositing

  /// Runs the per-frame compositing update: opacity seeding, clip sync, and
  /// the compositor-translation poll. Subclasses react through
  /// [onCompositorTranslated] and [onCompositorTranslationMissed].
  @protected
  void runCompositorPoll() {
    syncCompositionOpacity();
    syncAncestorClips();
    final motion = pollCompositorTranslation();
    if (motion.translation case final translation?) {
      setCompositorTranslation(translation);
      onCompositorTranslated(translation);
      return;
    }
    onCompositorTranslationMissed(motion);
  }

  /// A shared translation was applied to the retained effect.
  @protected
  void onCompositorTranslated(Offset translation) {}

  /// No shared translation applies to the retained effect this frame.
  @protected
  void onCompositorTranslationMissed(
    ({bool needsRepaint, Offset? translation}) motion,
  );

  /// Pushes the retained effect layer under the clips that are active for
  /// the current [frameState], then runs [painter] inside it.
  @protected
  void paintRetainedEffect(
    PaintingContext context,
    Offset offset,
    PaintingContextCallback painter,
  ) {
    final layer = (_effectLayer.layer ??= OffsetLayer())
      ..offset = _effectTranslation;
    (_frameState == GlassFrameState.idle ? _idleAncestorClips : _ancestorClips)
        .pushLayer(
      context,
      layer,
      painter,
      offset,
    );
  }

  /// Drops the retained effect layer.
  @protected
  void releaseRetainedEffectLayer() => _effectLayer.layer = null;

  /// Synchronizes the retained clips that are active for [frameState].
  @protected
  void syncAncestorClips() => (_frameState == GlassFrameState.idle
          ? _idleAncestorClips
          : _ancestorClips)
      .sync();

  /// Updates the dormant-frame clip ancestry from the committed shapes.
  @protected
  void updateIdleAncestorClips() =>
      _idleAncestorClips.update(this, shapeRenderObjects);

  // MARK: Effect bounds and shadows

  /// Logical outset the effect paints around the geometry bounds: the SDF
  /// contour support for real glass, the surface outset for the fallback.
  @protected
  double get materialOutset;

  /// How far outside the material the composed effect reads the backdrop.
  @protected
  double effectSamplingReach(Rect material);

  /// Grows [bounds] by this layer's [materialOutset] and the committed
  /// shapes' exterior shadows, in layer coordinates.
  @protected
  Rect expandEffectBounds(Rect bounds) => expandForGlassShadows(
    bounds.inflate(materialOutset),
    _shadowSources(),
    settings,
  );

  /// Grows [bounds] by the committed shapes' exterior shadows only.
  @protected
  Rect expandBoundsForShadows(Rect bounds) => expandForGlassShadows(
    bounds,
    _shadowSources(),
    settings,
  );

  Iterable<(List<ShapeGeometry>, Matrix4)> _shadowSources() =>
      shapesWithGeometry.map((entry) => (entry.$2.shapes, entry.$3));

  @override
  Rect? get effectBounds {
    final gathered = gatherGlassGeometryBounds(link, this);
    if (gathered == null) return null;
    final (bounds, shapes) = gathered;
    final material = bounds.inflate(materialOutset);
    return expandForGlassShadows(
      material.inflate(effectSamplingReach(material)),
      shapes,
      settings,
    );
  }

  /// Draws every committed shape's exterior shadows into [canvas] at
  /// [offset], then cuts the shape silhouettes back out so interior fills
  /// do not darken the glass. Both passes scale with shape visibility.
  @protected
  void drawGlassShadows(Canvas canvas, Offset offset) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.saveLayer(effectPaintBounds, Paint());

    for (final (_, geometry, geometryToLayer) in shapesWithGeometry) {
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
          _drawGlassShape(
            canvas,
            shape.shape,
            rect.shift(shadow.offset).inflate(shadow.spreadRadius),
            paint,
          );
        }
        canvas.restore();
      }
    }

    for (final (_, geometry, geometryToLayer) in shapesWithGeometry) {
      for (final shape in geometry.shapes) {
        final shapeVisibility = shape.appearance.visibility.clamp(0.0, 1.0);
        if (shapeVisibility <= 0) continue;
        canvas.save();
        canvas.transform(geometryToLayer.storage);
        if (shape.shapeToGeometry case final transform?) {
          canvas.transform(transform.storage);
        }
        _drawGlassShape(
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

  void _drawGlassShape(
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

  @override
  @mustCallSuper
  void dispose() {
    _compositionProbe.dispose();
    _ancestorClips.dispose();
    _idleAncestorClips.dispose();
    clearFrameInputs();
    _effectLayer.layer = null;
    super.dispose();
  }
}

final class _EncodedGeometryInput {
  _EncodedGeometryInput(
    this.renderObject,
    this.cache,
    Matrix4 transform,
  ) : transform = transform.clone();

  RenderLiquidGlassGeometry renderObject;
  GeometryCache cache;
  final Matrix4 transform;

  void update(
    RenderLiquidGlassGeometry newRenderObject,
    GeometryCache newCache,
    Matrix4 newTransform,
  ) {
    renderObject = newRenderObject;
    cache = newCache;
    transform.setFrom(newTransform);
  }
}

@internal
class GeometryRenderLink {
  final List<RenderLiquidGlassGeometry> _shapeGeometries = [];

  late final UnmodifiableListView<RenderLiquidGlassGeometry> shapes =
      UnmodifiableListView(_shapeGeometries);

  bool _dirty = false;

  /// Whether geometry changed since the layer last consumed the flag.
  bool get isDirty => _dirty;

  /// Consumes the dirty flag after the layer rebuilt its frame.
  void markClean() => _dirty = false;

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
