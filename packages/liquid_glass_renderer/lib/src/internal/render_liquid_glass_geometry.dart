import 'package:equatable/equatable.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/snap_rect_to_pixels.dart';
import 'package:liquid_glass_renderer/src/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_blend_group.dart';
import 'package:liquid_glass_renderer/src/logging.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';
import 'package:meta/meta.dart';

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

/// A base class for any render object that represents liquid glass geometry.
///
/// This will paint to the screen normally, but use a [GlassGroupLink] to gather
/// shape information for the Flutter GPU geometry pass.
@internal
abstract class RenderLiquidGlassGeometry extends RenderProxyBox {
  RenderLiquidGlassGeometry({
    required GeometryRenderLink this._renderLink,
    required LiquidGlassSettings settings,
    required double devicePixelRatio,
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
  }

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

  /// Paints the contents of all shapes to the given [context] at the given
  /// [offset].
  void paintShapeContents(
    RenderObject from,
    PaintingContext context,
    Offset offset, {
    required bool insideGlass,
  });

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
        shape.renderObject.getPath(),
        Offset.zero,
        matrix4: shape.shapeToGeometry?.storage,
      );
    }
    return path;
  }

  /// Smooth-union radius for shapes owned by this geometry node.
  double get geometryBlend => 0;

  /// Should be called from within [paint] to maybe rebuild the [geometry].
  GeometryCache? maybeRebuildGeometry() {
    if (geometryState == LiquidGlassGeometryState.updated && geometry != null) {
      return geometry;
    }

    final (layerBounds, shapes, anyShapeChangedInLayer) = gatherShapeData();

    if (geometryState == LiquidGlassGeometryState.mightNeedUpdate &&
        !anyShapeChangedInLayer &&
        geometry != null) {
      logger.finer('$hashCode Skipping geometry rebuild.');
      renderLink?.markRebuilt(this);

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
    );

    // We have updated the geometry.
    _renderLink?.markRebuilt(this);
    return newGeo;
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
  });

  final Rect bounds;
  final List<ShapeGeometry> shapes;
  final Path path;
  final double blend;

  void dispose() {}
}

extension on LiquidGlassSettings {
  bool requiresGeometryRebuild(LiquidGlassSettings? other) {
    if (other == null) return false;

    return effectiveThickness != other.effectiveThickness ||
        refractiveIndex != other.refractiveIndex;
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
    required this.glassContainsChild,
    required this.shapeBounds,
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

  final RenderLiquidGlass renderObject;

  final LiquidShape shape;

  final RawShapeType rawShapeType;

  final double rawCornerRadius;

  final bool glassContainsChild;

  /// Bounds in geometry-local coordinates (for painting)
  final Rect shapeBounds;

  final Matrix4? shapeToGeometry;

  @override
  List<Object?> get props => [
    renderObject,
    shape,
    glassContainsChild,
    shapeBounds,
    shapeToGeometry,
  ];
}
