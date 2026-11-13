import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/rendering/geometry_render_link.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_composition_probe.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_shadow_recorder.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_shape_helpers.dart';
import 'package:liquid_glass_renderer/src/rendering/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/rendering/retained_glass_clip.dart';
import 'package:liquid_glass_renderer/src/rendering/shape_set.dart';

part 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object_frame.dart';

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
abstract class LiquidGlassRenderObject extends RenderProxyBox {
  /// Creates a layer of glass that draws the geometry [link] gathers.
  LiquidGlassRenderObject({
    required this._link,
    required this._settings,
    required this._defaultAppearance,
    required this._devicePixelRatio,
  }) {
    _link.settings = _settings;
  }

  // MARK: Configuration

  GeometryRenderLink _link;

  /// The link its glass and blend groups register their geometry on.
  GeometryRenderLink get link => _link;
  set link(GeometryRenderLink value) {
    if (_link == value) return;
    if (attached) {
      _link.onMembershipChanged = null;
      value.onMembershipChanged = markNeedsPaint;
    }
    _link = value;
    value.settings = _settings;
    markNeedsPaint();
  }

  /// The registered shapes that are painted when this layer paints (see
  /// [isGlassShapePainted]), in paint order.
  @protected
  List<RenderLiquidGlassGeometry> get paintedShapes => [
    for (final shape in link.shapes)
      if (isGlassShapePainted(shape, this)) shape,
  ];

  List<RenderLiquidGlassGeometry> _lastPaintedShapes = const [];

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    // A glass or blend group that joins or leaves under a repaint boundary of
    // its own repaints only that boundary. Real glass would otherwise learn of
    // it in its compositing poll and draw it a frame late.
    _link.onMembershipChanged = markNeedsPaint;
  }

  @override
  void detach() {
    _link.onMembershipChanged = null;
    super.detach();
  }

  LiquidGlassSettings _settings;

  /// The settings its glass draws with, which every geometry on [link]
  /// takes in the same call.
  LiquidGlassSettings get settings => _settings;
  set settings(LiquidGlassSettings value) {
    if (_settings == value) return;
    final old = _settings;
    _settings = value;
    _link.settings = value;
    onSettingsChanged(old);
    markNeedsPaint();
  }

  /// Called after [settings] changed, before [markNeedsPaint].
  @protected
  void onSettingsChanged(LiquidGlassSettings old) {}

  LiquidGlassAppearance _defaultAppearance;

  /// The appearance of glass that sets none of its own.
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

  double _devicePixelRatio;

  /// The device pixels per logical pixel it draws at.
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

  GlassFrameState _frameState = GlassFrameState.empty;

  final List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)>
  _shapesWithGeometry = [];

  /// The inputs the effect last encoded: each shape's render object,
  /// geometry cache and transform into this layer. The compositor-translation
  /// poll compares [shapesWithGeometry] instead, so this may stay stale while
  /// an idle frame keeps the last encode.
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
  late final _shadows = GlassShadowRecorder(
    _shapesWithGeometry,
    _ancestorClips,
  );
  final _idleAncestorClips = RetainedGlassClip();
  List<Object> _retainedStructure = [];

  /// The offset this layer last painted at; retained updates reuse it.
  @protected
  Offset retainedPaintOffset = Offset.zero;
  Offset _effectTranslation = Offset.zero;

  /// Whether the committed frame holds shapes but drew no active effect, so
  /// ancestor motion moves its retained layers without a repaint.
  @protected
  bool get hasReusableIdleContents =>
      _frameState != GlassFrameState.active && _shapesWithGeometry.isNotEmpty;

  /// Bounds of the clips between this object and its shapes that are
  /// re-applied around the glass filter, in local coordinates, or `null`.
  @protected
  Rect? get retainedClipBounds =>
      _frameState == GlassFrameState.idle ? null : _ancestorClips.ownerBounds;

  /// Translation applied to the retained layer-owned effect since paint.
  @protected
  Offset get compositorTranslation => _effectTranslation;

  /// The translation its effect layer last composited at.
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

  /// Decides whether the opacity pass around this glass is seeded, before
  /// the update pass.
  @protected
  void syncCompositionOpacity() => _compositionProbe.syncOpacity(this);

  /// Whether this layer paints inside a fractional-opacity pass that a live
  /// backdrop read needs seeded.
  @protected
  bool get compositionProbeSeeding => _compositionProbe.seeding;

  /// Leaves the fractional-opacity pass unseeded while this layer reads no
  /// backdrop.
  @protected
  bool get compositionSeedSuppressed => _compositionProbe.suppressed;
  @protected
  set compositionSeedSuppressed(bool value) =>
      _compositionProbe.suppressed = value;

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
    final bounds = prepareFrameGeometry();
    paintFrame(context, offset, bounds);
    // Foreground always paints in its own render ancestry, above the glass.
    super.paint(context, offset);
  }

  /// Brings every registered geometry up to date for this frame and returns the
  /// bounds of the shapes it draws, or null when it draws none.
  @protected
  Rect? prepareFrameGeometry() {
    final candidate = <(RenderLiquidGlassGeometry, GeometryCache, Matrix4)>[];
    final bounds = collectFrameGeometry(candidate);
    commitFrameGeometry(candidate);
    _frameState = _classifyFrame(candidate);
    return bounds;
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

  // The state a frame that collected [geometries] commits: empty when nothing
  // drawable remains, idle when every shape is invisible and the effect keeps
  // its matte, and active otherwise.
  GlassFrameState _classifyFrame(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
  ) {
    if (geometries.isEmpty) return GlassFrameState.empty;
    if (!_hasVisibleShape(geometries)) {
      return encodesMatte ? GlassFrameState.idle : GlassFrameState.empty;
    }
    return hasDrawableGlass(geometries)
        ? GlassFrameState.active
        : GlassFrameState.empty;
  }

  static bool _hasVisibleShape(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
  ) => geometries.any(
    (entry) => entry.$2.shapes.any(
      (shape) => shape.appearance.visibility > 0,
    ),
  );

  /// Logical short side of the smallest visible committed shape, which sizes
  /// the layer-wide blur; null without one.
  @protected
  double? smallestVisibleShortSide() {
    double? shortest;
    for (final (_, geometry, geometryToLayer) in _shapesWithGeometry) {
      for (final shape in geometry.shapes) {
        if (shape.appearance.visibility <= 0) continue;
        // shapeBounds is already in the geometry's local space.
        final side = MatrixUtils.transformRect(
          geometryToLayer,
          shape.shapeBounds,
        ).shortestSide;
        if (side <= 0) continue;
        shortest = shortest == null ? side : min(shortest, side);
      }
    }
    return shortest;
  }

  /// The short side past which [LiquidGlassSettings.frostSigmaAt] no longer
  /// grows the blur.
  static const largestFittedShortSide = 150.0;

  /// Whether the effect encodes its shapes into a matte, as real glass does.
  ///
  /// A frame whose shapes are all hidden then idles and keeps the matte,
  /// a shape draws only where the matte can hold it, and a shape's encode is
  /// current while its matte revision holds. Without a matte every shape
  /// draws, a hidden frame is empty, and an encode is current while the
  /// shape's geometry is the one painted from.
  @protected
  bool get encodesMatte;

  /// The render objects of all committed shapes, in frame order.
  @protected
  Iterable<RenderBox> get shapeRenderObjects => _shapesWithGeometry.expand(
    (entry) => entry.$2.shapes.map((shape) => shape.renderObject),
  );

  /// Snapshots the committed shapes into the encoded inputs.
  @protected
  void rememberFrameInputs() {
    final inputs = _encodedGeometryInputs;
    final shapes = _shapesWithGeometry;
    if (inputs.length > shapes.length) {
      inputs.removeRange(shapes.length, inputs.length);
    }
    for (var index = 0; index < shapes.length; index++) {
      final (renderObject, cache, transform) = shapes[index];
      if (index < inputs.length) {
        inputs[index].update(renderObject, cache, transform);
      } else {
        inputs.add(_EncodedGeometryInput(renderObject, cache, transform));
      }
    }
  }

  /// Drops the encoded input snapshot together with its bounds.
  @protected
  void clearFrameInputs() {
    _encodedGeometryInputs.clear();
    encodedGeometryBounds = null;
  }

  /// Polls the committed shapes ([shapesWithGeometry]) for one translation
  /// the compositor can apply without a repaint, or null when there is none
  /// and the frame needs a repaint.
  @protected
  Offset? pollCompositorTranslation() => _compareShapes(record: true);

  /// Whether [pollCompositorTranslation] would find no translation if it ran
  /// now. It records nothing: the poll's baseline stays where it is, so it
  /// can be asked before paint, as often as needed.
  @protected
  bool get compositorPollMisses => _compareShapes(record: false) == null;

  // The one comparison of the painted shapes with the committed ones. With
  // [record] it moves the poll's baseline as the frame's poll does; without,
  // it only answers.
  Offset? _compareShapes({required bool record}) {
    // A shape going offstage or onstage changes this list, which repaints.
    final current = paintedShapes;
    final committed = _shapesWithGeometry;
    if (_framePoll.polledThisFrame && committed.length == current.length) {
      return Offset.zero;
    }
    if (current.isEmpty && committed.isEmpty) return Offset.zero;
    if (committed.isEmpty || current.length != committed.length) {
      if (record) {
        for (final geometry in current) {
          geometry.pollRelativeTransforms(this);
        }
      }
      return null;
    }

    Offset? shared;
    var canTranslate = true;
    for (var index = 0; index < current.length; index++) {
      final geometry = current[index];
      final encoded = committed[index];
      final wasCurrent = _isSnapshotCurrent(geometry, encoded.$2);
      final poll = geometry.pollRelativeTransforms(this, record: record);
      final transform = poll.transform;
      final delta =
          !identical(geometry, encoded.$1) ||
              !wasCurrent ||
              poll.childChanged ||
              transform == null
          ? null
          : _translationDelta(encoded.$3, transform);
      if (delta == null || (shared != null && !_nearOffset(shared, delta))) {
        // Polling goes on: every shape takes its baseline.
        if (!record) return null;
        canTranslate = false;
        continue;
      }
      shared ??= delta;
    }
    if (!canTranslate) return null;
    if (record) {
      // A shape that moved by the shared translation keeps its geometry.
      for (final geometry in current) {
        geometry.acceptCompositorTranslation();
      }
    }
    return shared ?? Offset.zero;
  }

  // Whether [geometry]'s inputs still match the snapshot it was encoded with
  // (see [encodesMatte]).
  bool _isSnapshotCurrent(
    RenderLiquidGlassGeometry geometry,
    GeometryCache snapshot,
  ) => encodesMatte
      ? geometry.hasCurrentMatteRevision(snapshot.matteRevision)
      : geometry.hasCurrentGeometryCache(snapshot);

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

  /// The translation that maps the encoded inputs onto [bounds] when every
  /// committed shape still matches its snapshot and moved uniformly, or
  /// `null` otherwise.
  @protected
  Offset? encodedMatteDelta(Rect bounds) {
    final oldBounds = encodedGeometryBounds;
    if (oldBounds == null ||
        _encodedGeometryInputs.length != _shapesWithGeometry.length) {
      return null;
    }
    Offset? shared;
    for (var index = 0; index < _shapesWithGeometry.length; index++) {
      final (renderObject, cache, transform) = _shapesWithGeometry[index];
      final encoded = _encodedGeometryInputs[index];
      if (!identical(renderObject, encoded.renderObject) ||
          cache.matteRevision != encoded.cache.matteRevision) {
        return null;
      }
      final delta = _translationDelta(encoded.transform, transform);
      if (delta == null || (shared != null && !_nearOffset(shared, delta))) {
        return null;
      }
      shared ??= delta;
    }
    final delta = shared ?? Offset.zero;
    return _nearRect(bounds, oldBounds.shift(delta)) ? delta : null;
  }

  // MARK: Compositing

  /// Runs the per-frame compositing update: opacity seeding, clip sync, and
  /// the compositor-translation poll. Subclasses react through
  /// [onCompositorTranslated] and [onCompositorTranslationMissed].
  @protected
  void runCompositorPoll() {
    syncCompositionOpacity();
    syncAncestorClips();
    if (pollCompositorTranslation() case final translation?) {
      setCompositorTranslation(translation);
      onCompositorTranslated(translation);
      if (_frameState == GlassFrameState.active &&
          _shadows.slot != null &&
          _ancestorClips.hasIndividualClips &&
          !_framePoll.polledThisFrame) {
        recordGlassShadows(retainedPaintOffset);
      }
      return;
    }
    onCompositorTranslationMissed();
  }

  /// A shared translation was applied to the retained effect.
  @protected
  void onCompositorTranslated(Offset translation) {}

  /// No shared translation applies to the retained effect this frame: what
  /// it painted no longer matches its shapes.
  @protected
  void onCompositorTranslationMissed();

  /// Pushes the retained effect layer under the clips that are active for
  /// the current [frameState], then runs [painter] inside it.
  @protected
  void paintRetainedEffect(
    PaintingContext context,
    Offset offset,
    PaintingContextCallback painter,
  ) {
    final layer = (_effectLayer.layer ??= ThinOffsetLayer())
      ..offset = _effectTranslation;
    _activeClips.pushLayer(context, layer, painter, offset);
  }

  /// Drops the retained effect layer.
  @protected
  void releaseRetainedEffectLayer() {
    _effectLayer.layer = null;
    clearGlassShadows();
  }

  /// Synchronizes the retained clips that are active for [frameState].
  @protected
  void syncAncestorClips() => _activeClips.sync();

  RetainedGlassClip get _activeClips =>
      _frameState == GlassFrameState.idle ? _idleAncestorClips : _ancestorClips;

  /// Updates the dormant-frame clip ancestry from the committed shapes.
  @protected
  void updateIdleAncestorClips() =>
      _idleAncestorClips.update(this, shapeRenderObjects);

  // MARK: Effect bounds and shadows

  /// Logical outset the effect paints around the geometry bounds: the SDF
  /// contour support for real glass, the surface outset for the fallback.
  @protected
  double get materialOutset;

  /// Grows [bounds] by this layer's [materialOutset] and the committed
  /// shapes' exterior shadows, in layer coordinates.
  @protected
  Rect expandEffectBounds(Rect bounds) => expandForGlassShadows(
    bounds.inflate(materialOutset),
    _shapesWithGeometry.map((entry) => (entry.$2.shapes, entry.$3)),
  );

  /// Whether [recordGlassShadows] records the shadows for a place under the
  /// glass, where the glass covers them inside its silhouettes, instead of
  /// over it, cut outside them. Only glass that paints every pixel of its
  /// silhouettes opaquely over what lies under it may set it, and only while
  /// no shape fades ([glassShadowsFade]).
  ///
  /// NEAR: over the glass the cut lets the shadow half a pixel into the
  /// glass's edge, so that no seam shows between them; under it the glass
  /// covers its edge pixels by their coverage and needs no reach. The two
  /// differ only along the edge: by up to 57 levels under a shadow of alpha
  /// 0.25 in the host test, and by up to 23 on the Pixel 6a's glass bench
  /// under the 0.08 to 0.1 of glass controls, in a line two device pixels
  /// wide and at corners, where the cut's path and the shader's shape part;
  /// elsewhere by at most 3 levels, as copies without shadows do.
  @protected
  bool shadowsUnderGlass = false;

  /// [shadowsUnderGlass], for tests.
  @visibleForTesting
  bool get debugShadowsUnderGlass => shadowsUnderGlass;

  /// Whether a committed shape is partly visible, which makes the shadows
  /// show through it by the part it has yet to fade in.
  @protected
  bool get glassShadowsFade => _shadows.fading;

  /// The picture [recordGlassShadows] last recorded, wherever it lies now.
  @protected
  PictureLayer? get glassShadowPicture => _shadows.picture;

  /// Draws every committed shape's exterior shadows into [canvas] at
  /// [offset], kept outside the silhouette of every shape above zero
  /// visibility so they do not darken the glass, or whole for the glass to
  /// cover with [shadowsUnderGlass]. Shadow color, blur and the cut-out
  /// silhouette scale with shape visibility.
  @protected
  void drawGlassShadows(Canvas canvas, Offset offset) => _shadows.draw(
    canvas,
    offset,
    under: shadowsUnderGlass,
    translation: compositorTranslation,
    bounds: effectPaintBounds,
    devicePixelRatio: devicePixelRatio,
  );

  /// Records the shadows of its shapes at [offset] into a layer of their own,
  /// or returns null when no shape casts one.
  @protected
  ContainerLayer? recordGlassShadows(Offset offset) {
    final slot = _shadows.begin();
    if (slot == null || !hasDrawableGlass(_shapesWithGeometry)) return slot;
    _shadows.record(
      slot,
      offset,
      under: shadowsUnderGlass,
      translation: compositorTranslation,
      bounds: effectPaintBounds,
      devicePixelRatio: devicePixelRatio,
    );
    return slot;
  }

  /// Drops the layer [recordGlassShadows] recorded.
  @protected
  void clearGlassShadows() => _shadows.clear();

  /// Forgets every registered geometry.
  @override
  @mustCallSuper
  void dispose() {
    _shadows.dispose();
    _compositionProbe.dispose();
    _ancestorClips.dispose();
    _idleAncestorClips.dispose();
    clearFrameInputs();
    releaseRetainedEffectLayer();
    super.dispose();
  }

  /// Runs after a frame's shapes are committed to [shapesWithGeometry],
  /// before the frame's state is decided.
  @protected
  void onFrameGeometryCommitted() {}
}

/// An [OffsetLayer] that holds no layer of the scene while it does not shift:
/// glass over a scroll adds its layers again every frame, and each one the
/// scene holds costs both threads.
@internal
class ThinOffsetLayer extends OffsetLayer {
  @override
  void addToScene(ui.SceneBuilder builder) {
    if (offset != Offset.zero) {
      super.addToScene(builder);
      return;
    }
    engineLayer = null;
    addChildrenToScene(builder);
  }
}

/// Remembers whether a glass layer polled its shapes' transforms while the
/// current frame painted, so its compositing hook can skip a second poll.
///
/// Nothing between paint and compositing in one frame moves a render object,
/// so that poll would only find the transforms paint just recorded.
@internal
class FramePollMarker {
  bool _polled = false;

  /// Whether this frame's paint already polled.
  bool get polledThisFrame => _polled;

  /// Records a poll made during the current frame's paint. Polls outside a
  /// frame, such as `toImage` captures, are not recorded.
  void markPolled() {
    if (_polled ||
        SchedulerBinding.instance.schedulerPhase !=
            SchedulerPhase.persistentCallbacks) {
      return;
    }
    _polled = true;
    // After the frame: the flag holds for one frame's paint and scene.
    SchedulerBinding.instance.addPostFrameCallback((_) => _polled = false);
  }
}
