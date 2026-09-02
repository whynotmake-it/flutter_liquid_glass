import 'package:equatable/equatable.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/snap_rect_to_pixels.dart';
import 'package:liquid_glass_renderer/src/logging.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';
import 'package:meta/meta.dart';

/// Refreshes source order during owner paint, walking only source ancestry.
/// Retained compositor ticks never call this traversal.
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

/// The state of liquid glass geometry, used to determine if it needs to be
/// updated.
enum LiquidGlassGeometryState {
  /// The geometry is up to date and does not need to be updated.
  updated,

  /// The geometry might need to be updated, but could potentially be reused.
  ///
  /// This happens mainly when all of the geometry itself is unchanged, but all
  /// of the geometry has been uniformly transformed.
  ///
  /// In this case, we can use the existing geometry matte and transform it to
  /// save GPU cycles.
  mightNeedUpdate,

  /// The geometry definitely needs to be updated.
  needsUpdate,
}

/// Result of checking one geometry node against its owning layer.
@internal
typedef LiquidGlassTransformPoll = ({
  bool childChanged,
  bool selfChanged,
  Matrix4? transform,
});

/// A render object that contributes one glass shape to a geometry pass.
@internal
mixin LiquidGlassShapeRenderObject on RenderBox {
  /// The shape's path in its own local coordinates.
  Path shapePath();

  /// Shadows painted by the parent layer before grouped glass shading.
  List<BoxShadow> get layerShadows;

  /// Resolved color and materialization controls for this shape.
  LiquidGlassAppearance get appearance;
}

/// A base class for any render object that represents liquid glass geometry.
///
/// Standalone shapes and blend groups both register with a
/// [GeometryRenderLink] so the parent layer can pack them into one sample.
@internal
abstract class RenderLiquidGlassGeometry extends RenderProxyBox {
  RenderLiquidGlassGeometry({
    required LiquidGlassSettings settings,
    required double devicePixelRatio,
    this._renderLink,
  }) {
    _settings = settings;
    _devicePixelRatio = devicePixelRatio;
  }

  /// The logger for liquid glass geometry.
  final Logger logger = Logger(LgrLogNames.geometry);

  late LiquidGlassSettings? _settings;

  /// The settings used for liquid glass rendering.
  ///
  /// If these settings change in a way that affects geometry, the geometry
  /// will be marked as needing an update.
  LiquidGlassSettings get settings => _settings!;
  set settings(LiquidGlassSettings value) {
    if (_settings == value) return;

    if (value.requiresGeometryRebuild(_settings)) {
      logger.finer('$hashCode rebuild ');
      markGeometryNeedsUpdate(force: true);
    }

    _settings = value;
    markNeedsPaint();
  }

  late double _devicePixelRatio;

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
  GeometryRenderLink? get renderLink => _renderLink;
  set renderLink(GeometryRenderLink? value) {
    if (_renderLink == value) return;
    _renderLink?.unregisterGeometry(this);
    _renderLink = value;
    _renderLink?.registerGeometry(this);
  }

  /// The current state of the geometry.
  @visibleForTesting
  @protected
  LiquidGlassGeometryState geometryState = LiquidGlassGeometryState.needsUpdate;

  /// The current geometry matte image.
  @visibleForTesting
  @protected
  GeometryCache? geometry;

  int _matteRevision = 0;

  /// Marks the geometry as needing an update.
  ///
  /// If [force] is true, the geometry will be marked as definitely needing an
  /// update. Otherwise, it will be marked as possibly needing an update,
  /// unless it is already marked as definitely needing an update.
  @protected
  void markGeometryNeedsUpdate({bool force = false}) {
    final newState = force
        ? LiquidGlassGeometryState.needsUpdate
        : LiquidGlassGeometryState.mightNeedUpdate;

    geometryState = switch ((geometryState, newState)) {
      (LiquidGlassGeometryState.needsUpdate, _) =>
        LiquidGlassGeometryState.needsUpdate,
      (_, LiquidGlassGeometryState.needsUpdate) =>
        LiquidGlassGeometryState.needsUpdate,
      _ => LiquidGlassGeometryState.mightNeedUpdate,
    };
    _renderLink?.markDirty();
  }

  Matrix4? _lastTransformToLayer;

  /// Detects motion of this geometry relative to [layer].
  ///
  /// Called from the layer's paint and compositing hooks so descendant glass
  /// does not need its own always-composite tracking layers. The two change
  /// flags let the layer distinguish a uniformly translated geometry node
  /// from shapes moving inside a blend group.
  LiquidGlassTransformPoll pollRelativeTransforms(RenderObject layer) {
    if (!attached || !layer.attached || !hasSize) {
      return (childChanged: false, selfChanged: false, transform: null);
    }

    final toLayer = getTransformTo(layer);
    var selfChanged = false;
    if (_lastTransformToLayer == null) {
      _lastTransformToLayer = toLayer;
    } else if (!MatrixUtils.matrixEquals(toLayer, _lastTransformToLayer)) {
      _lastTransformToLayer = toLayer;
      selfChanged = true;
    }

    final childChanged = pollChildShapeTransforms();
    if (!childChanged && selfChanged) {
      markGeometryNeedsUpdate();
    }
    return (
      childChanged: childChanged,
      selfChanged: selfChanged,
      transform: toLayer,
    );
  }

  /// Whether [candidate] was current before polling compositor motion.
  bool hasCurrentGeometryCache(GeometryCache candidate) =>
      identical(geometry, candidate) &&
      geometryState == LiquidGlassGeometryState.updated;

  /// Whether the encoded matte revision was current before compositor motion.
  bool hasCurrentMatteRevision(int revision) =>
      geometry?.matteRevision == revision &&
      geometryState == LiquidGlassGeometryState.updated;

  /// Records that a translation was applied to the retained layer instead of
  /// invalidating this node's local geometry.
  void acceptCompositorTranslation() {
    if (geometryState == LiquidGlassGeometryState.mightNeedUpdate) {
      geometryState = LiquidGlassGeometryState.updated;
    }
  }

  /// Detects motion of registered shapes relative to this geometry node.
  ///
  /// Direct children can skip this: their offset changes go through layout.
  @protected
  bool pollChildShapeTransforms() => false;

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
    geometry?.dispose();
    geometry = null;
    super.dispose();
  }

  /// Gathers all shapes and computes them in both layer and screen space
  /// Returns (layerBounds, shapes, anyShapeChangedInLayer)
  (
    Rect bounds,
    List<ShapeGeometry> geometries,
    bool needsUpdate,
  )
  gatherShapeData();

  Path getPath(
    List<ShapeGeometry> geometries,
  ) {
    final path = Path();
    for (final shape in geometries) {
      path.addPath(
        shape.renderObject.shapePath(),
        Offset.zero,
        matrix4: shape.shapeToGeometry?.storage,
      );
    }
    return path;
  }

  /// Smooth-union radius for shapes owned by this geometry node.
  double get geometryBlend => 0;

  /// Refresh source ordering before owner paint consumes cached geometry.
  void updatePaintOrder() {}

  /// Refreshes CPU geometry during owner paint or pre-submission preparation.
  /// This advances cache state but does not paint children or encode a matte.
  GeometryCache? maybeRebuildGeometry() {
    if (geometryState == LiquidGlassGeometryState.updated && geometry != null) {
      return geometry;
    }

    final (layerBounds, shapes, anyShapeChangedInLayer) = gatherShapeData();

    if (geometryState == LiquidGlassGeometryState.mightNeedUpdate &&
        !anyShapeChangedInLayer &&
        geometry != null &&
        !_matteVisibilityChanged(geometry!.shapes, shapes)) {
      logger.finer('$hashCode Skipping geometry rebuild.');
      // Paint-only shape metadata (currently grouped shadows) must still
      // refresh even when the SDF inputs and cached vector path are reusable.
      // This keeps interactive shadow controls live without re-encoding the
      // Flutter-GPU geometry texture.
      geometry = GeometryCache(
        bounds: geometry!.bounds,
        shapes: shapes,
        path: geometry!.path,
        blend: geometry!.blend,
        matteRevision: geometry!.matteRevision,
      );
      renderLink?.markDirty();

      geometryState = LiquidGlassGeometryState.updated;
      return geometry;
    }

    logger.finer('$hashCode Rebuilding geometry');

    geometry?.dispose();
    geometry = null;
    geometryState = LiquidGlassGeometryState.updated;

    if (shapes.isEmpty) {
      return null;
    }

    final snappedBounds = layerBounds.snapToPixels(devicePixelRatio);
    final newGeo = geometry = GeometryCache(
      bounds: snappedBounds,
      shapes: shapes,
      path: getPath(shapes),
      blend: geometryBlend,
      matteRevision: ++_matteRevision,
    );

    // We have updated the geometry.
    _renderLink?.markDirty();
    return newGeo;
  }

  static bool _matteVisibilityChanged(
    List<ShapeGeometry> before,
    List<ShapeGeometry> after,
  ) {
    if (before.length != after.length) return true;
    for (var index = 0; index < before.length; index++) {
      if ((before[index].appearance.visibility > 0) !=
          (after[index].appearance.visibility > 0)) {
        return true;
      }
    }
    return false;
  }
}

/// CPU-side geometry metadata consumed by the Flutter GPU pass.
@immutable
@internal
class GeometryCache {
  const GeometryCache({
    required this.bounds,
    required this.shapes,
    required this.path,
    required this.blend,
    required this.matteRevision,
  });

  final Rect bounds;
  final List<ShapeGeometry> shapes;
  final Path path;
  final double blend;

  /// Monotonically identifies the inputs encoded into the SDF matte.
  ///
  /// Paint-only metadata refreshes retain this value, allowing a parent layer
  /// to validate translation reuse without deeply comparing every shape.
  final int matteRevision;

  void dispose() {}
}

extension on LiquidGlassSettings {
  bool requiresGeometryRebuild(LiquidGlassSettings? other) {
    if (other == null) return false;

    return effectiveThickness != other.effectiveThickness ||
        edgeRefraction != other.edgeRefraction ||
        refractionSpread != other.refractionSpread ||
        contourWidth != other.contourWidth ||
        contourOffset != other.contourOffset;
  }
}

@internal
enum RawShapeType {
  // none(0), unused in CPU code
  squircle(1),
  ellipse(2),
  roundedRectangle(3);

  const RawShapeType(this.shaderIndex);

  final double shaderIndex;

  static RawShapeType fromLiquidGlassShape(LiquidShape shape) {
    switch (shape) {
      case LiquidRoundedSuperellipse():
        return RawShapeType.squircle;
      case LiquidOval():
        return RawShapeType.ellipse;
      case LiquidRoundedRectangle():
        return RawShapeType.roundedRectangle;
    }
  }
}

/// The geometry of a single shape.
///
/// Can be part of multiple blended shapes in [RenderLiquidGlassGeometry], or on
/// its own.
@internal
class ShapeGeometry extends Equatable {
  ShapeGeometry({
    required this.renderObject,
    required this.shape,
    required this.shapeBounds,
    required this.appearance,
    this.shadows = const [],
    this.shapeToGeometry,
  }) : rawCornerRadius = _getRadiusFromGlassShape(shape),
       rawShapeType = RawShapeType.fromLiquidGlassShape(shape);

  static double _getRadiusFromGlassShape(LiquidShape shape) {
    switch (shape) {
      case LiquidRoundedSuperellipse():
        return shape.borderRadius;
      case LiquidRoundedRectangle():
        return shape.borderRadius;
      case LiquidOval():
        return 0;
    }
  }

  final LiquidGlassShapeRenderObject renderObject;

  final LiquidShape shape;

  final RawShapeType rawShapeType;

  final double rawCornerRadius;

  final LiquidGlassAppearance appearance;

  /// Bounds in geometry-local coordinates (for painting)
  final Rect shapeBounds;

  final List<BoxShadow> shadows;

  final Matrix4? shapeToGeometry;

  @override
  List<Object?> get props => [
    renderObject,
    shape,
    appearance,
    shapeBounds,
    shadows,
    shapeToGeometry,
  ];
}
