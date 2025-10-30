import 'dart:ui';

import 'package:equatable/equatable.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/snap_rect_to_pixels.dart';
import 'package:liquid_glass_renderer/src/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_blend_group.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';
import 'package:logging/logging.dart';
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
/// shape information and generate a geometry matte using the provided
/// [geometryShader].
@internal
abstract class RenderLiquidGlassGeometry extends RenderProxyBox {
  /// Creates a new [RenderLiquidGlassGeometry] with the given
  /// [geometryShader].
  RenderLiquidGlassGeometry({
    required GeometryRenderLink renderLink,
    required this.geometryShader,
    required LiquidGlassSettings settings,
    required double devicePixelRatio,
  })  : _renderLink = renderLink,
        _settings = settings,
        _devicePixelRatio = devicePixelRatio {
    updateShaderWithSettings(settings, devicePixelRatio);
  }

  /// The logger for liquid glass geometry.
  final Logger logger = Logger('lgr.LiquidGlassGeometry');

  /// The shader that generates the geometry matte.
  final FragmentShader geometryShader;

  LiquidGlassSettings? _settings;

  /// The settings used for liquid glass rendering.
  ///
  /// If these settings change in a way that affects geometry, the geometry
  /// will be marked as needing an update.
  LiquidGlassSettings get settings => _settings!;
  set settings(LiquidGlassSettings value) {
    if (_settings == value) return;

    if (value.requiresGeometryRebuild(_settings)) {
      logger.finer('$hashCode geometry rebuild due to settings change.');
      markGeometryNeedsUpdate(force: true);
    }

    _settings = value;
    updateShaderWithSettings(value, _devicePixelRatio);
    markNeedsPaint();
  }

  double _devicePixelRatio;

  /// The device pixel ratio used for rendering.
  ///
  /// If this changes, the geometry will be marked as needing an update.
  double get devicePixelRatio => _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markGeometryNeedsUpdate(force: true);
    updateShaderWithSettings(settings, value);
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
  Geometry? geometry;

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

  /// Updates the shader with the current settings and device pixel ratio.
  void updateShaderWithSettings(
    LiquidGlassSettings settings,
    double devicePixelRatio,
  );

  /// Uploads shape data to geometry shader in screen space coordinates
  void updateGeometryShaderShapes(
    List<ShapeGeometry> shapes,
  );

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
  ) gatherShapeData();

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

  /// Should be called from within [paint] to maybe rebuild the [geometry].
  Geometry? maybeRebuildGeometry() {
    if (geometryState == LiquidGlassGeometryState.updated && geometry != null) {
      return geometry!;
    }

    final (layerBounds, shapes, anyShapeChangedInLayer) = gatherShapeData();

    if (geometryState == LiquidGlassGeometryState.mightNeedUpdate &&
        !anyShapeChangedInLayer &&
        geometry != null) {
      logger.finer('$hashCode Skipping geometry rebuild.');
      renderLink?.markRebuilt(this);
      geometryState = LiquidGlassGeometryState.updated;
      return geometry!;
    }

    logger.finer('$hashCode Rebuilding geometry');

    geometry?.dispose();
    geometry = null;
    geometryState = LiquidGlassGeometryState.updated;

    if (shapes.isEmpty) {
      return null;
    }

    final snappedBounds = layerBounds.snapToPixels(devicePixelRatio);
    final matteBounds = Rect.fromLTWH(
      snappedBounds.left * devicePixelRatio,
      snappedBounds.top * devicePixelRatio,
      snappedBounds.width * devicePixelRatio,
      snappedBounds.height * devicePixelRatio,
    ).snapToPixels(1);

    final picture = _buildGeometryPicture(snappedBounds, shapes);
    final image = picture.toImageSync(
      matteBounds.width.toInt(),
      matteBounds.height.toInt(),
    );
    picture.dispose();

    // Set the new geometry
    final newGeo = geometry = Geometry(
      matte: image,
      bounds: snappedBounds,
      matteBounds: matteBounds,
      shapes: shapes,
      path: getPath(shapes),
    );

    // We have updated the geometry.
    _renderLink?.markRebuilt(this);
    return newGeo;
  }

  Picture _buildGeometryPicture(
    Rect geometryBounds,
    List<ShapeGeometry> shapes,
  ) {
    final bounds = geometryBounds.snapToPixels(devicePixelRatio);

    final width = (bounds.width * devicePixelRatio).ceil();
    final height = (bounds.height * devicePixelRatio).ceil();

    geometryShader.setFloatUniforms((value) {
      value
        ..setFloat(width.toDouble())
        ..setFloat(height.toDouble());
    });

    updateGeometryShaderShapes(shapes);

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..shader = geometryShader;

    final leftPixel = (geometryBounds.left * devicePixelRatio).roundToDouble();
    final topPixel = (geometryBounds.top * devicePixelRatio).roundToDouble();

    canvas
      // This translation might seem redundant, but we do it to ensure pixel
      // snapping
      ..translate(-leftPixel, -topPixel)
      ..drawRect(
        Rect.fromLTWH(
          leftPixel,
          topPixel,
          width.toDouble(),
          height.toDouble(),
        ),
        paint,
      );

    return recorder.endRecording();
  }
}

/// Represents a current snapshot of the geometry used for liquid glass
/// rendering.
@immutable
@internal
class Geometry {
  const Geometry({
    required this.matte,
    required this.matteBounds,
    required this.bounds,
    required this.shapes,
    required this.path,
  });

  /// The matte image representing the geometry.
  final Image matte;

  /// The bounds of the geometry in the coordinate space of its
  /// [RenderLiquidGlassGeometry] parent.
  final Rect bounds;

  /// The bounds of the matte image in physical pixels.
  final Rect matteBounds;

  final List<ShapeGeometry> shapes;

  final Path path;

  /// Disposes of the resources used by the geometry.
  @mustCallSuper
  void dispose() {
    matte.dispose();
  }
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
  })  : rawCornerRadius = _getRadiusFromGlassShape(shape),
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
      ];
}
