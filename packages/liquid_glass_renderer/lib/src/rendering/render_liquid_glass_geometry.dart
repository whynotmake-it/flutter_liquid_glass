import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_shadow.dart';
import 'package:liquid_glass_renderer/src/painting/shader_constants.dart';
import 'package:liquid_glass_renderer/src/painting/view_pixels.dart';
import 'package:liquid_glass_renderer/src/rendering/appearance.dart';
import 'package:liquid_glass_renderer/src/rendering/drawn_values.dart';
import 'package:liquid_glass_renderer/src/rendering/follower_transform.dart';
import 'package:liquid_glass_renderer/src/rendering/geometry_render_link.dart';

/// Sorts [sources] into paint order under [owner], walking only their
/// ancestry; returns whether the order changed.
bool sortGlassPaintOrder<T>(
  RenderObject owner,
  List<T> sources,
  RenderObject Function(T) renderObject,
) {
  if (sources.length < 2) return false;
  final byObject = <RenderObject, T>{
    for (final source in sources) renderObject(source): source,
  };
  final ancestry = <RenderObject>{};
  for (final source in byObject.keys) {
    for (var node = source; !identical(node, owner);) {
      if (!ancestry.add(node)) break;
      final parent = node.parent;
      if (parent == null) break;
      node = parent;
    }
  }
  final ordered = <T>[];
  void visit(RenderObject node) {
    if (!ancestry.contains(node)) return;
    if (byObject.containsKey(node)) ordered.add(byObject[node] as T);
    node.visitChildren(visit);
  }

  owner.visitChildren(visit);
  if (ordered.length != sources.length) return false;
  for (var i = 0; i < sources.length; i++) {
    if (!identical(sources[i], ordered[i])) {
      sources.setAll(0, ordered);
      return true;
    }
  }
  return false;
}

/// Whether a geometry has to be built again.
enum LiquidGlassGeometryState {
  /// The geometry is up to date.
  updated,

  /// The geometry may be reused: its shapes may only have moved together,
  /// which the layer follows by moving the geometry it encoded.
  mightNeedUpdate,

  /// The geometry has to be built again.
  needsUpdate,
}

/// Result of checking one geometry node against its owning layer.
@internal
typedef LiquidGlassTransformPoll = ({
  bool childChanged,
  Matrix4? transform,
});

/// A render object that contributes one glass shape to a geometry pass.
mixin LiquidGlassShapeRenderObject on RenderBox {
  /// Shadows painted by the parent layer before grouped glass shading.
  List<LiquidGlassShadow> get layerShadows;

  List<LiquidGlassShadow>? _castFrom;
  Size? _castAt;
  List<BoxShadow> _cast = const [];

  /// [layerShadows] as the shape casts them at its [paintSize]
  /// ([castGlassShadows]).
  List<BoxShadow> get castShadows {
    final shadows = layerShadows;
    final size = paintSize;
    if (!identical(shadows, _castFrom) || size != _castAt) {
      _castFrom = shadows;
      _castAt = size;
      _cast = castGlassShadows(shadows, size);
    }
    return _cast;
  }

  /// The shape of the glass.
  LiquidShape get shape;

  /// The appearance the shape draws with on a layer whose glass wears
  /// [defaultAppearance] where it sets none, as glass of its [paintSize]
  /// wears it.
  WornAppearance appearanceOn(LiquidGlassAppearance defaultAppearance);

  /// The size the shape is drawn at, which a live frame sets apart from the
  /// layout size.
  Size get paintSize;

  /// The glow a live frame raises on the shape where it draws, else null.
  DrawnGlow? get glow;
}

/// A base class for any render object that represents liquid glass geometry.
///
/// Standalone shapes and blend groups both register with a
/// [GeometryRenderLink] so the parent layer can pack them into one sample.
abstract class RenderLiquidGlassGeometry extends RenderProxyBox {
  /// Creates a geometry that registers on [renderLink].
  RenderLiquidGlassGeometry({
    required this._devicePixelRatio,
    this._renderLink,
  });

  double _devicePixelRatio;

  /// The device pixel ratio used for rendering.
  ///
  /// If this changes, the geometry will be marked as needing an update.
  double get devicePixelRatio => _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markGeometryNeedsUpdate(force: true);
    markNeedsPaint();
  }

  GeometryRenderLink? _renderLink;

  /// The link of the layer this geometry registers on, or null while it
  /// registers nowhere.
  GeometryRenderLink? get renderLink => _renderLink;
  set renderLink(GeometryRenderLink? value) {
    if (_renderLink == value) return;
    _renderLink?.unregisterGeometry(this);
    _renderLink = value;
    _renderLink?.registerGeometry(this);
  }

  LiquidGlassGeometryState _geometryState =
      LiquidGlassGeometryState.needsUpdate;

  GeometryCache? _geometry;

  int _revision = 0;

  /// Marks the geometry as needing an update.
  ///
  /// If [force] is true, the geometry will be marked as definitely needing an
  /// update. Otherwise, it will be marked as possibly needing an update,
  /// unless it is already marked as definitely needing an update.
  @protected
  void markGeometryNeedsUpdate({bool force = false}) {
    _geometryState =
        force || _geometryState == LiquidGlassGeometryState.needsUpdate
        ? LiquidGlassGeometryState.needsUpdate
        : LiquidGlassGeometryState.mightNeedUpdate;
    _renderLink?.markDirty();
  }

  Matrix4? _lastTransformToLayer;

  /// Whether the last [pollRelativeTransforms] read a follower's last frame
  /// (see [transformToNowOrLast]): the layer polls again once the follower
  /// is in the leader's tree.
  bool get transformMayLag => _transformMayLag;
  bool _transformMayLag = false;

  /// Whether the encoded geometry revision was current before compositor
  /// motion.
  bool hasCurrentRevision(int revision) =>
      _geometry?.revision == revision &&
      _geometryState == LiquidGlassGeometryState.updated;

  /// Records that a translation was applied to the retained layer instead of
  /// invalidating this node's local geometry.
  void acceptCompositorTranslation() {
    if (_geometryState == LiquidGlassGeometryState.mightNeedUpdate) {
      _geometryState = LiquidGlassGeometryState.updated;
    }
  }

  /// Detects motion of registered shapes relative to this geometry node, and
  /// takes their transforms as the next poll's baseline when [record] is
  /// true; with [record] false it only answers.
  ///
  /// Direct children can skip this: their offset changes go through layout.
  @protected
  bool pollChildShapeTransforms({required bool record}) => false;

  /// The shape render objects [gatherShapeData] would gather now, in its
  /// order, without gathering them.
  Iterable<LiquidGlassShapeRenderObject> get gatheredShapes;

  @override
  @mustCallSuper
  void attach(PipelineOwner owner) {
    _renderLink?.registerGeometry(this);
    super.attach(owner);
  }

  @override
  @mustCallSuper
  void detach() {
    _renderLink?.unregisterGeometry(this);
    super.detach();
  }

  @override
  @mustCallSuper
  void dispose() {
    _renderLink?.unregisterGeometry(this);
    _geometry = null;
    super.dispose();
  }

  /// The shapes this node draws on a layer whose default appearance is
  /// [defaultAppearance], their bounds in its own coordinates, and whether
  /// any shape changed against [geometry].
  (
    Rect bounds,
    List<ShapeGeometry> geometries,
    bool needsUpdate,
  )
  gatherShapeData(LiquidGlassAppearance defaultAppearance);

  /// Smooth-union radius for shapes owned by this geometry node.
  double get geometryBlend => 0;

  /// Sorts the shapes into paint order before the layer reads the geometry.
  void updatePaintOrder() {}

  static bool _visibilityChanged(
    List<ShapeGeometry> before,
    List<ShapeGeometry> after,
  ) {
    if (before.length != after.length) return true;
    for (var index = 0; index < before.length; index++) {
      if (before[index].appearance.shows != after[index].appearance.shows) {
        return true;
      }
    }
    return false;
  }

  // What the layer it registers on reads of its geometry: the layer's
  // collect, poll and encode call these, and nothing else may.

  /// The current state of the geometry.
  @internal
  LiquidGlassGeometryState get geometryState => _geometryState;

  /// The geometry last built, if any.
  @internal
  GeometryCache? get geometry => _geometry;

  /// Detects motion of this geometry relative to [layer].
  ///
  /// Reads the transform with [transformToNowOrLast], which sees only
  /// [RenderObject.applyPaintTransform]: a transform an ancestor pushes in
  /// paint (PaintingContext.pushTransform) is not followed.
  ///
  /// Called from the layer's paint and compositing hooks so descendant glass
  /// does not need its own always-composite tracking layers. The two change
  /// flags let the layer distinguish a uniformly translated geometry node
  /// from shapes moving inside a blend group.
  ///
  /// With [record] false it changes nothing: the transforms stay the next
  /// poll's baseline and the geometry is not marked, so it can be asked
  /// before paint, as often as needed.
  @internal
  LiquidGlassTransformPoll pollRelativeTransforms(
    RenderObject layer, {
    bool record = true,
  }) {
    if (!attached || !layer.attached || !hasSize) {
      return (childChanged: false, transform: null);
    }

    final (transform: toLayer, :last) = transformToNowOrLast(this, layer);
    final baseline = _lastTransformToLayer;
    final selfChanged =
        baseline != null && !MatrixUtils.matrixEquals(toLayer, baseline);
    final childChanged = pollChildShapeTransforms(record: record);
    if (record) {
      _transformMayLag = last;
      if (baseline == null || selfChanged) _lastTransformToLayer = toLayer;
      if (!childChanged && selfChanged) markGeometryNeedsUpdate();
    }
    return (childChanged: childChanged, transform: toLayer);
  }

  /// Tells the geometry that the default appearance of its layer changed,
  /// which its shapes that set none of their own wear.
  @internal
  void defaultAppearanceChanged() => markGeometryNeedsUpdate();

  /// Whether [candidate] was current before polling compositor motion.
  @internal
  bool hasCurrentGeometryCache(GeometryCache candidate) =>
      identical(_geometry, candidate) &&
      _geometryState == LiquidGlassGeometryState.updated;

  /// Builds the geometry again where it is stale, during the layer's paint or
  /// before a retained frame is composited. It paints no children and
  /// encodes no geometry.
  @internal
  GeometryCache? maybeRebuildGeometry(LiquidGlassAppearance defaultAppearance) {
    final cached = _geometry;
    if (cached != null && _geometryState == LiquidGlassGeometryState.updated) {
      return cached;
    }
    final (layerBounds, shapes, anyShapeChangedInLayer) = gatherShapeData(
      defaultAppearance,
    );
    final reusesGeometry =
        cached != null &&
        _geometryState == LiquidGlassGeometryState.mightNeedUpdate &&
        !anyShapeChangedInLayer &&
        !_visibilityChanged(cached.shapes, shapes);
    _geometryState = LiquidGlassGeometryState.updated;
    if (reusesGeometry) {
      _renderLink?.markDirty();
      return _geometry = GeometryCache(
        bounds: cached.bounds,
        shapes: shapes,
        blend: cached.blend,
        revision: cached.revision,
      );
    }
    if (shapes.isEmpty) return _geometry = null;
    _renderLink?.markDirty();
    return _geometry = GeometryCache(
      bounds: ViewPixels(devicePixelRatio).nearest(layerBounds),
      shapes: shapes,
      blend: geometryBlend,
      revision: ++_revision,
    );
  }
}

/// CPU-side geometry metadata consumed by the Flutter GPU pass.
@immutable
@internal
class GeometryCache {
  const GeometryCache({
    required this.bounds,
    required this.shapes,
    required this.blend,
    required this.revision,
  });

  final Rect bounds;
  final List<ShapeGeometry> shapes;
  final double blend;

  /// Monotonically identifies the inputs encoded into the geometry.
  ///
  /// Paint-only metadata refreshes retain this value, allowing a parent layer
  /// to validate translation reuse without deeply comparing every shape.
  final int revision;
}

/// The geometry of a single shape.
///
/// Can be part of multiple blended shapes in [RenderLiquidGlassGeometry], or on
/// its own.
@immutable
class ShapeGeometry {
  /// Describes one shape as its layer draws it.
  ShapeGeometry({
    required this.renderObject,
    required this.shape,
    required this.shapeBounds,
    required this.appearance,
    this.shadows = const [],
    this.shapeToGeometry,
  }) : _rawCornerRadius = shape.cornerRadius,
       _rawBottomRadius = shape.bottomCornerRadius,
       _rawShapeType = shape.rawType;

  /// The render object of the shape.
  final LiquidGlassShapeRenderObject renderObject;

  /// The shape.
  final LiquidShape shape;

  final RawShapeType _rawShapeType;
  final double _rawCornerRadius;
  final double _rawBottomRadius;

  /// The appearance of the shape, as glass of its size wears it.
  final WornAppearance appearance;

  /// The shape's bounds in its geometry's coordinates.
  final Rect shapeBounds;

  /// The shadows the shape casts.
  final List<BoxShadow> shadows;

  /// The transform from the shape to its geometry, or null when they share
  /// coordinates.
  final Matrix4? shapeToGeometry;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is ShapeGeometry &&
          other.renderObject == renderObject &&
          other.shape == shape &&
          other.appearance == appearance &&
          other.shapeBounds == shapeBounds &&
          listEquals(other.shadows, shadows) &&
          other.shapeToGeometry == shapeToGeometry;

  @override
  int get hashCode => Object.hash(
    renderObject,
    shape,
    appearance,
    shapeBounds,
    Object.hashAll(shadows),
    shapeToGeometry,
  );

  // What the shape set encodes for the geometry shaders, which only it
  // reads.

  /// The kind of the shape, as the geometry shaders tell it.
  @internal
  RawShapeType get encodedShapeType => _rawShapeType;

  /// The corner radius the geometry shaders draw the shape with.
  @internal
  double get encodedCornerRadius => _rawCornerRadius;

  /// The radius of the two bottom corners: [encodedCornerRadius] except for a
  /// [RawShapeType.squirclePair].
  @internal
  double get encodedBottomRadius => _rawBottomRadius;

  @override
  String toString() =>
      'ShapeGeometry($renderObject, $shape, $appearance, $shapeBounds, '
      '$shadows, $shapeToGeometry)';
}
