import 'dart:collection';
import 'dart:math';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/internal/snap_rect_to_pixels.dart';
import 'package:liquid_glass_renderer/src/logging.dart';
import 'package:meta/meta.dart';

/// A render object that can assemble [RenderLiquidGlassGeometry] shapes and
/// render them to the screen with the liquid glass effect.
@internal
abstract class LiquidGlassRenderObject extends RenderProxyBox {
  LiquidGlassRenderObject({
    required this._link,
    required this.renderShader,
    required LiquidGlassSettings this._settings,
    required this._devicePixelRatio,
    required this._backdropKey,
    this._gpuGeometryRenderer,
  }) {
    _updateShaderSettings();
  }

  static final logger = Logger(LgrLogNames.render);

  final FragmentShader renderShader;

  Matrix4 get matteTransform;

  /// Maps local matte bounds into the coordinate space used by
  /// `FlutterFragCoord` in the final image-filter shader.
  Matrix4 get shaderCoordinateTransform => Matrix4.identity();

  late GeometryRenderLink _link;
  GeometryRenderLink get link => _link;
  set link(GeometryRenderLink value) {
    if (_link == value) return;
    markNeedsPaint();
    _link = value;
  }

  LiquidGlassSettings? _settings;
  LiquidGlassSettings get settings => _settings!;
  set settings(LiquidGlassSettings value) {
    if (_settings == value) return;
    final geometryInputsChanged =
        _settings?.effectiveThickness != value.effectiveThickness ||
        _settings?.refractiveIndex != value.refractiveIndex;
    _settings = value;
    _updateShaderSettings();
    if (geometryInputsChanged) needsGeometryUpdate = true;
    markNeedsPaint();
  }

  BackdropKey? _backdropKey;
  BackdropKey? get backdropKey => _backdropKey;
  set backdropKey(BackdropKey? value) {
    if (_backdropKey == value) return;
    _backdropKey = value;
    markNeedsPaint();
  }

  FlutterGpuGeometryRenderer? _gpuGeometryRenderer;
  FlutterGpuGeometryRenderer? get gpuGeometryRenderer => _gpuGeometryRenderer;
  set gpuGeometryRenderer(FlutterGpuGeometryRenderer? value) {
    if (_gpuGeometryRenderer == value) return;
    _gpuGeometryRenderer = value;
    markNeedsPaint();
  }

  double _devicePixelRatio;
  double get devicePixelRatio => _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    needsGeometryUpdate = true;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => _geometryImage != null;

  /// Pre-rendered geometry texture in screen space
  ui.Image? _geometryImage;

  /// The bounding box of the geometry matte in the coordinate space of the
  /// shader
  Rect _geometryMatteBounds = Rect.zero;

  /// The pre-rendered geometry texture in screen space.
  ///
  /// Exposed for subclasses that render additional passes (such as the separate
  /// specular layer) from the same geometry texture.
  @protected
  ui.Image? get geometryImage => _geometryImage;

  /// The bounding box of the geometry matte in screen space.
  ///
  /// Exposed for subclasses that need to map the geometry texture into their
  /// own coordinate space.
  @protected
  Rect get geometryMatteBounds => _geometryMatteBounds;

  @override
  @mustCallSuper
  void attach(PipelineOwner owner) {
    super.attach(owner);
  }

  @override
  @mustCallSuper
  void detach() {
    super.detach();
  }

  @override
  void layout(Constraints constraints, {bool parentUsesSize = false}) {
    needsGeometryUpdate = true;
    super.layout(constraints, parentUsesSize: parentUsesSize);
  }

  int _shaderSettingsRevision = 0;

  void _updateShaderSettings() {
    _shaderSettingsRevision++;
    renderShader.setFloatUniforms(initialIndex: 6, (value) {
      value
        ..setColor(settings.effectiveGlassColor)
        ..setFloats([
          settings.refractiveIndex,
          settings.effectiveChromaticAberration,
          settings.effectiveThickness,
          settings.effectiveLightIntensity,
          settings.effectiveAmbientStrength,
          settings.effectiveSaturation,
        ])
        ..setOffset(
          Offset(
            cos(settings.lightAngle),
            sin(settings.lightAngle),
          ),
        )
        ..setColor(settings.effectiveHighlightColor)
        ..setColor(settings.effectiveEdgeColor)
        ..setFloats([
          settings.effectiveEdgeWidth,
          settings.edgeInset,
          settings.effectiveBleedStrength,
          settings.specularWrap,
        ]);
    });
  }

  ui.Rect _paintBounds = ui.Rect.zero;

  @override
  ui.Rect get paintBounds => _paintBounds;

  /// Number of times [paint] has run. Ancestor motion should not increment
  /// this once live coordinate mapping is active.
  @visibleForTesting
  int debugPaintCount = 0;

  final List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)>
  _shapesWithGeometry = [];

  void _pollRegisteredGeometryTransforms() {
    for (final geometryRo in link.shapes) {
      geometryRo.pollRelativeTransforms(this);
    }
  }

  // MARK: Painting

  @override
  @nonVirtual
  void paint(PaintingContext context, Offset offset) {
    assert(() {
      debugPaintCount++;
      return true;
    }(), 'Track layer paints in debug builds.');
    logger.finest(
      '$hashCode Painting liquid glass with '
      '${link._shapeGeometries.length} shapes.',
    );

    _pollRegisteredGeometryTransforms();

    _shapesWithGeometry.clear();

    Rect? boundingBox;

    for (final geometryRo in link.shapes) {
      final geometry = geometryRo.maybeRebuildGeometry();

      if (geometry == null) continue;

      final transform = geometryRo.getTransformTo(this);
      _shapesWithGeometry.add((geometryRo, geometry, transform));

      final geoBounds = MatrixUtils.transformRect(
        transform,
        geometry.bounds,
      );
      boundingBox = boundingBox == null
          ? geoBounds
          : boundingBox.expandToInclude(geoBounds);
    }

    if (boundingBox == null) {
      _clearGeometryImage();

      super.paint(context, offset);
      return;
    }

    _paintBounds = boundingBox;

    if (settings.effectiveThickness <= 0) {
      _clearGeometryImage();
      paintShapeContents(
        context,
        offset,
        _shapesWithGeometry,
        insideGlass: true,
      );
      paintShapeContents(
        context,
        offset,
        _shapesWithGeometry,
        insideGlass: false,
      );
      super.paint(context, offset);
      return;
    }

    if (needsGeometryUpdate || _geometryImage == null || link._dirty) {
      link
        ..updateAllGeometries()
        .._dirty = false;

      needsGeometryUpdate = false;

      final gpuResult = _buildGpuGeometryImage(
        _shapesWithGeometry,
        boundingBox,
      );
      _clearGeometryImage();
      _geometryImage = gpuResult.$1;
      _geometryMatteBounds = gpuResult.$2;
    }

    if (debugPaintLiquidGlassGeometry) {
      _debugPaintGeometry(context, offset);
      paintShapeContents(
        context,
        offset,
        _shapesWithGeometry,
        insideGlass: true,
      );
      paintShapeContents(
        context,
        offset,
        _shapesWithGeometry,
        insideGlass: false,
      );
    } else {
      if (_geometryImage case final geometryImage?) {
        final coordinateImage = syncCoordinateMapping();
        renderShader
          ..setFloatUniforms(initialIndex: 2, (value) {
            value
              ..setOffset(_geometryMatteBounds.topLeft * devicePixelRatio)
              ..setSize(_geometryMatteBounds.size * devicePixelRatio);
          })
          ..setImageSampler(1, geometryImage)
          ..setImageSampler(2, coordinateImage);
        _shaderInputSnapshot = _ShaderInputSnapshot(
          geometryImage: geometryImage,
          coordinateImage: coordinateImage,
          matteBounds: _geometryMatteBounds,
          devicePixelRatio: devicePixelRatio,
          settingsRevision: _shaderSettingsRevision,
        );
        paintLiquidGlass(
          context,
          offset,
          _shapesWithGeometry,
          _paintBounds,
        );
      }
    }

    super.paint(context, offset);
  }

  void _clearGeometryImage() {
    _geometryImage = null;
  }

  /// Subclasses implement the actual glass rendering
  /// (e.g., with backdrop filters)
  void paintLiquidGlass(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> shapes,
    Rect boundingBox,
  );

  /// Writes the live filter-to-matte mapping and returns the persistent
  /// coordinate image.
  ///
  /// ImageFilter.shader copies float uniforms at creation, so this mapping
  /// cannot live in uniforms without allocating a new native filter whenever
  /// an ancestor moves. Sampler bindings stay live, which is why the mapping
  /// is a 2×1 float texture. Safe to call from compositing as well as paint.
  @protected
  ui.Image syncCoordinateMapping() {
    final renderer = _gpuGeometryRenderer;
    if (renderer == null) {
      throw StateError(
        'Flutter GPU is required for LiquidGlass. Enable it in the platform '
        'manifest or with --enable-flutter-gpu.',
      );
    }

    final globalToMatte = Matrix4.inverted(shaderCoordinateTransform);
    final inverseOrigin = MatrixUtils.transformPoint(
      globalToMatte,
      Offset.zero,
    );
    final inverseX = MatrixUtils.transformPoint(
      globalToMatte,
      const Offset(1, 0),
    );
    final inverseY = MatrixUtils.transformPoint(
      globalToMatte,
      const Offset(0, 1),
    );
    final inverseAxisX = inverseX - inverseOrigin;
    final inverseAxisY = inverseY - inverseOrigin;
    renderer.updateCoordinateMapping(
      basisXX: inverseAxisX.dx,
      basisYX: inverseAxisY.dx,
      basisXY: inverseAxisX.dy,
      basisYY: inverseAxisY.dy,
      originX: inverseOrigin.dx * devicePixelRatio,
      originY: inverseOrigin.dy * devicePixelRatio,
    );
    final image = renderer.coordinateImage;
    if (image == null) {
      throw StateError('LiquidGlass coordinate mapping texture is missing.');
    }
    return image;
  }

  /// True once the geometry matte and live coordinate texture both exist, so
  /// ancestor motion can update mapping without crossing a repaint boundary.
  @protected
  bool get hasLiveCoordinateMapping =>
      _geometryImage != null &&
      _gpuGeometryRenderer?.coordinateImage != null;

  /// Value identity of everything [renderShader] has captured for the current
  /// paint: float uniforms and the geometry/coordinate samplers.
  ///
  /// The engine copies a shader's uniforms into the native image filter when
  /// that filter is first converted (see
  /// `ReusableFragmentShader::as_image_filter`), so a filter wrapping this
  /// shader may only be reused across paints while this snapshot compares
  /// equal. Coordinate mapping is a live sampler and is not part of this key.
  @protected
  Object get shaderInputSnapshot => _shaderInputSnapshot;
  late Object _shaderInputSnapshot;

  @protected
  void paintShapeContents(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> shapes, {
    required bool insideGlass,
  }) {
    for (final (geometryRenderObject, _, _) in shapes) {
      geometryRenderObject.paintShapeContents(
        this,
        context,
        offset,
        insideGlass: insideGlass,
      );
    }
  }

  void _debugPaintGeometry(PaintingContext context, Offset offset) {
    if (_geometryImage case final geometryImage?) {
      final backToThis = Matrix4.inverted(matteTransform).storage;
      final bounds = MatrixUtils.transformRect(
        matteTransform,
        paintBounds,
      ).snapToPixels(devicePixelRatio);
      context.canvas
        ..save()
        ..transform(backToThis)
        ..translate(
          bounds.left,
          bounds.top,
        )
        ..scale(1 / devicePixelRatio)
        ..drawImage(
          geometryImage,
          offset * devicePixelRatio,
          Paint()..blendMode = BlendMode.src,
        )
        ..restore();
    }
  }

  @override
  @mustCallSuper
  void dispose() {
    _clearGeometryImage();
    _gpuGeometryRenderer = null;
    super.dispose();
  }

  // MARK: Geometry

  @protected
  bool needsGeometryUpdate = true;

  final List<double> _shapeData = [];
  static final Matrix4 _identity = Matrix4.identity();

  (ui.Image, Rect) _buildGpuGeometryImage(
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

    try {
      final boundsInMatteSpace = MatrixUtils.transformRect(
        matteTransform,
        bounds,
      ).snapToPixels(devicePixelRatio);

      final textureWidth = (boundsInMatteSpace.width * devicePixelRatio).ceil();
      final textureHeight = (boundsInMatteSpace.height * devicePixelRatio)
          .ceil();

      if (textureWidth <= 0 || textureHeight <= 0) {
        throw StateError('Cannot render empty liquid-glass geometry.');
      }

      // Gather shapes in cache order. A negative blend marker starts a new
      // group; this preserves smooth unions within a group without blending
      // unrelated standalone glass widgets together.
      _shapeData.clear();
      var numShapes = 0;

      for (final (_, geometry, geometryToLayer) in geometries) {
        var firstInGroup = true;
        for (final shape in geometry.shapes) {
          if (numShapes >= 16) break; // MAX_SHAPES limit

          final shapeToGeometry = shape.shapeToGeometry ?? _identity;
          final shapeOriginInGeometry = MatrixUtils.transformPoint(
            shapeToGeometry,
            Offset.zero,
          );
          final shapeXInGeometry = MatrixUtils.transformPoint(
            shapeToGeometry,
            const Offset(1, 0),
          );
          final shapeYInGeometry = MatrixUtils.transformPoint(
            shapeToGeometry,
            const Offset(0, 1),
          );

          Offset toMatte(Offset point) => MatrixUtils.transformPoint(
            matteTransform,
            MatrixUtils.transformPoint(geometryToLayer, point),
          );

          final origin = toMatte(shapeOriginInGeometry);
          final xPoint = toMatte(shapeXInGeometry);
          final yPoint = toMatte(shapeYInGeometry);
          final axisX = xPoint - origin;
          final axisY = yPoint - origin;
          final determinant = axisX.dx * axisY.dy - axisY.dx * axisX.dy;
          if (determinant.abs() < 1e-8) continue;

          // Inverse 2D affine basis maps matte-space physical pixels back to
          // the shape's own physical-pixel coordinate system.
          final inverse00 = axisY.dy / determinant;
          final inverse01 = -axisY.dx / determinant;
          final inverse10 = -axisX.dy / determinant;
          final inverse11 = axisX.dx / determinant;

          // The minimum singular value conservatively converts local SDF
          // distances back to screen pixels under non-uniform scaling.
          final trace =
              axisX.dx * axisX.dx +
              axisX.dy * axisX.dy +
              axisY.dx * axisY.dx +
              axisY.dy * axisY.dy;
          final discriminant = max(
            0,
            trace * trace - 4 * determinant * determinant,
          );
          final distanceScale = sqrt(
            max(0.0, (trace - sqrt(discriminant)) * 0.5),
          );

          final centerInGeometry = MatrixUtils.transformPoint(
            shapeToGeometry,
            Offset(
              shape.renderObject.size.width / 2,
              shape.renderObject.size.height / 2,
            ),
          );
          final centerInLayer = MatrixUtils.transformPoint(
            geometryToLayer,
            centerInGeometry,
          );
          final centerInMatte = MatrixUtils.transformPoint(
            matteTransform,
            centerInLayer,
          );

          // The inverse affine basis above already maps matte coordinates back
          // into the shape's local coordinate system. Using the transformed
          // AABB here would apply scale a second time (and turn rotations into
          // oversized primitives), which is especially visible for stretched
          // shapes in a blend group.
          final size = shape.renderObject.size;
          final blendMarker = firstInGroup
              ? -(geometry.blend * devicePixelRatio + 1)
              : geometry.blend * devicePixelRatio;

          _shapeData
            // vec4 0: primitive parameters.
            ..add(shape.rawShapeType.shaderIndex)
            ..add(size.width * devicePixelRatio)
            ..add(size.height * devicePixelRatio)
            ..add(shape.rawCornerRadius * devicePixelRatio)
            // vec4 1: inverse affine basis.
            ..add(inverse00)
            ..add(inverse01)
            ..add(inverse10)
            ..add(inverse11)
            // vec4 2: transformed center, distance scale, group marker.
            ..add(centerInMatte.dx * devicePixelRatio)
            ..add(centerInMatte.dy * devicePixelRatio)
            ..add(distanceScale)
            ..add(blendMarker);
          numShapes++;
          firstInGroup = false;
        }
      }

      if (numShapes == 0) {
        throw StateError('No invertible liquid-glass shapes to render.');
      }

      final result = renderer.render(
        width: textureWidth,
        height: textureHeight,
        shapeData: _shapeData,
        numShapes: numShapes,
        refractiveIndex: settings.refractiveIndex,
        thickness: settings.effectiveThickness,
        offsetX: boundsInMatteSpace.left * devicePixelRatio,
        offsetY: boundsInMatteSpace.top * devicePixelRatio,
      );

      return (
        result.image,
        Rect.fromLTWH(
          boundsInMatteSpace.left,
          boundsInMatteSpace.top,
          result.width / devicePixelRatio,
          result.height / devicePixelRatio,
        ),
      );
    } catch (e) {
      throw StateError('Flutter GPU geometry render failed: $e');
    }
  }
}

/// Value key describing the uniform and sampler state a [FragmentShader]
/// image filter snapshots at creation time.
///
/// Geometry and coordinate images are persistent GPU textures whose wrappers
/// stay stable while the contents are updated in place. Transform mapping is
/// not part of this key: it lives in [coordinateImage], which ImageFilter
/// samples live instead of copying.
@immutable
class _ShaderInputSnapshot {
  const _ShaderInputSnapshot({
    required this.geometryImage,
    required this.coordinateImage,
    required this.matteBounds,
    required this.devicePixelRatio,
    required this.settingsRevision,
  });

  final ui.Image geometryImage;
  final ui.Image coordinateImage;
  final Rect matteBounds;
  final double devicePixelRatio;
  final int settingsRevision;

  @override
  bool operator ==(Object other) {
    return other is _ShaderInputSnapshot &&
        other.geometryImage == geometryImage &&
        other.coordinateImage == coordinateImage &&
        other.matteBounds == matteBounds &&
        other.devicePixelRatio == devicePixelRatio &&
        other.settingsRevision == settingsRevision;
  }

  @override
  int get hashCode => Object.hash(
    geometryImage,
    coordinateImage,
    matteBounds,
    devicePixelRatio,
    settingsRevision,
  );

  @override
  String toString() {
    return '_ShaderInputSnapshot(image: ${identityHashCode(geometryImage)}, '
        'coordinates: ${identityHashCode(coordinateImage)}, '
        'matteBounds: $matteBounds, dpr: $devicePixelRatio, '
        'settingsRevision: $settingsRevision)';
  }
}

@internal
class GeometryRenderLink {
  final List<RenderLiquidGlassGeometry> _shapeGeometries = [];

  UnmodifiableListView<RenderLiquidGlassGeometry> get shapes =>
      UnmodifiableListView(_shapeGeometries);

  bool _dirty = false;

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

  void markRebuilt(RenderLiquidGlassGeometry renderObject) {
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
