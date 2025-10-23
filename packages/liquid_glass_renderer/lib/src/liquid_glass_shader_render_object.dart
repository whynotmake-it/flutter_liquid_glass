import 'dart:math';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/glass_link.dart';
import 'package:liquid_glass_renderer/src/internal/snap_rect_to_pixels.dart';
import 'package:liquid_glass_renderer/src/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/logging.dart';
import 'package:liquid_glass_renderer/src/shape_in_layer.dart';
import 'package:meta/meta.dart';

@internal
bool debugPaintLiquidGlassGeometry = false;

enum _GeometryUpdateState {
  maybeUpdate,
  needsUpdate,
  upToDate,
}

/// Base render object for liquid glass effects.
///
/// **Coordinate Spaces**:
/// - Layer space: Coordinates relative to this render object
/// - Screen space: Global coordinates (what backdropFilter sees)
///
/// **Key Insight**: BackdropFilter captures content in screen space, so the
/// geometry image must be created in screen coordinates to align correctly
/// when the layer is transformed by parent widgets.
@internal
abstract class LiquidGlassShaderRenderObject extends RenderProxyBox {
  LiquidGlassShaderRenderObject({
    required this.renderShader,
    required this.geometryShader,
    required this.lightingShader,
    required GlassLink glassLink,
    required LiquidGlassSettings settings,
    required double devicePixelRatio,
  })  : _settings = settings,
        _glassLink = glassLink,
        _devicePixelRatio = devicePixelRatio {
    _glassLink.addListener(onLinkNotification);
    onLinkNotification();
    _updateShaderSettings();
  }

  static final logger = Logger(LgrLogNames.object);

  final FragmentShader renderShader;
  final FragmentShader geometryShader;
  final FragmentShader lightingShader;

  // === Settings and Configuration ===

  LiquidGlassSettings? _settings;
  LiquidGlassSettings get settings => _settings!;
  set settings(LiquidGlassSettings value) {
    if (_settings == value) return;

    if (value.requiresGeometryRebuild(_settings)) {
      logger.finer('$hashCode geometry rebuild due to settings change.');
      _invalidateGeometry(force: true);
    }

    _settings = value;
    _updateShaderSettings();
    markNeedsPaint();
  }

  double _devicePixelRatio;
  double get devicePixelRatio => _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  GlassLink _glassLink;
  GlassLink get glassLink => _glassLink;
  set glassLink(GlassLink value) {
    if (_glassLink == value) return;
    _glassLink.removeListener(onLinkNotification);
    _glassLink = value;
    value.addListener(onLinkNotification);
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => _geometryImage != null;

  _GeometryUpdateState _geometryState = _GeometryUpdateState.needsUpdate;

  /// Pre-rendered geometry texture in screen space
  ui.Image? _geometryImage;

  /// Screen-space bounding box of all shapes (for geometry texture sizing)
  Rect? _cachedScreenShapesBounds;

  Matrix4 _lastTransformToScreen = Matrix4.identity();

  /// Computed shape information
  List<ShapeInLayerInfo> _cachedShapes = [];

  /// Layer-space bounding box (for painting)
  Rect _cachedLayerBoundingBox = Rect.zero;

  @protected
  void onLinkNotification() {
    _invalidateGeometry();
  }

  void _invalidateGeometry({bool force = false}) {
    _geometryState = force
        ? _GeometryUpdateState.needsUpdate
        : _GeometryUpdateState.maybeUpdate;
    markNeedsPaint();
  }

  // === Shader Uniform Updates ===

  void _updateShaderSettings() {
    renderShader.setFloatUniforms(initialIndex: 23, (value) {
      value
        ..setColor(settings.glassColor)
        ..setFloats([
          settings.refractiveIndex,
          settings.chromaticAberration,
          settings.thickness,
          settings.lightIntensity,
          settings.ambientStrength,
          settings.saturation,
        ])
        ..setOffset(
          Offset(
            cos(settings.lightAngle),
            sin(settings.lightAngle),
          ),
        );
    });

    geometryShader.setFloatUniforms(initialIndex: 2, (value) {
      value.setFloats([
        settings.refractiveIndex,
        settings.chromaticAberration,
        settings.thickness,
        settings.blend * devicePixelRatio,
      ]);
    });
  }

  /// Uploads shape data to geometry shader in screen space coordinates
  void _updateGeometryShaderShapes(Offset screenOrigin) {
    final shapes = _cachedShapes;

    if (shapes.length > LiquidGlass.maxShapesPerLayer) {
      throw UnsupportedError(
        'Only ${LiquidGlass.maxShapesPerLayer} shapes are supported at '
        'the moment!',
      );
    }

    geometryShader.setFloatUniforms(initialIndex: 6, (value) {
      value.setFloat(shapes.length.toDouble());
      for (final shape in shapes) {
        final center = shape.screenBounds.center;
        final size = shape.screenBounds.size;
        value
          ..setFloat(shape.rawShapeType.shaderIndex)
          ..setFloat((center.dx - screenOrigin.dx) * devicePixelRatio)
          ..setFloat((center.dy - screenOrigin.dy) * devicePixelRatio)
          ..setFloat(size.width * devicePixelRatio)
          ..setFloat(size.height * devicePixelRatio)
          ..setFloat(shape.rawCornerRadius * devicePixelRatio);
      }
    });
  }

  // === Main Rendering ===

  @override
  @nonVirtual
  void paint(PaintingContext context, Offset offset) {
    if (_geometryState == _GeometryUpdateState.needsUpdate ||
        _geometryState == _GeometryUpdateState.maybeUpdate) {
      _maybeRebuildGeometry();
    }

    final shapes = _cachedShapes;

    if (shapes.isEmpty) {
      super.paint(context, offset);
      return;
    }

    if (settings.thickness <= 0) {
      _paintShapesWithoutGlass(context, offset, shapes);
      super.paint(context, offset);
      return;
    }

    if (debugPaintLiquidGlassGeometry) {
      _debugPaintGeometry(context, offset);
    } else {
      _paintGlassEffect(context, offset);
    }

    super.paint(context, offset);

    // If we are still attached, schedule a repaint to pick up on transform
    // changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached) markNeedsPaint();
    });
  }

  void _paintShapesWithoutGlass(
    PaintingContext context,
    Offset offset,
    List<ShapeInLayerInfo> shapes,
  ) {
    paintShapeContents(context, offset, shapes, glassContainsChild: true);
    paintShapeContents(context, offset, shapes, glassContainsChild: false);
  }

  void _debugPaintGeometry(PaintingContext context, Offset offset) {
    if (_geometryImage case final geometryImage?) {
      context.canvas
        ..save()
        ..scale(1 / devicePixelRatio)
        ..drawImage(geometryImage, offset * devicePixelRatio, Paint())
        ..restore();
    }
  }

  void _paintGlassEffect(PaintingContext context, Offset offset) {
    if (_geometryImage case final geometryImage?) {
      final geometryBounds = _cachedScreenShapesBounds ?? Rect.zero;

      renderShader
        ..setFloatUniforms((value) {
          value
            ..setSize(geometryBounds.size * devicePixelRatio)
            ..setOffset(geometryBounds.topLeft * devicePixelRatio)
            ..setSize(geometryBounds.size * devicePixelRatio)
            ..setFloats(_getTransformSinceLastGeometryUpdate().storage)
            ..setFloat(devicePixelRatio);
        })
        ..setImageSampler(1, geometryImage);

      paintLiquidGlass(context, offset, _cachedShapes, _cachedLayerBoundingBox);
    }
  }

  /// Subclasses implement the actual glass rendering
  /// (e.g., with backdrop filters)
  void paintLiquidGlass(
    PaintingContext context,
    Offset offset,
    List<ShapeInLayerInfo> shapes,
    Rect boundingBox,
  );

  @protected
  void paintShapeContents(
    PaintingContext context,
    Offset offset,
    List<ShapeInLayerInfo> shapes, {
    required bool glassContainsChild,
  }) {
    for (final shapeInLayer in shapes) {
      if (shapeInLayer.glassContainsChild == glassContainsChild) {
        context.pushTransform(
          true,
          offset,
          shapeInLayer.shapeToLayer,
          shapeInLayer.renderObject.paintFromLayer,
        );
      }
    }
  }

  // === Geometry Texture Creation ===

  /// Rebuilds the geometry texture in screen space with pixel-perfect alignment
  void _maybeRebuildGeometry() {
    final (layerBounds, screenBounds, shapes, anyShapeChangedInLayer) =
        _gatherShapeData();

    if (_geometryState == _GeometryUpdateState.maybeUpdate &&
        !anyShapeChangedInLayer &&
        _geometryImage != null) {
      logger.finer('$hashCode Skipping geometry rebuild.');
      _geometryState = _GeometryUpdateState.upToDate;

      return;
    }

    logger.finer('$hashCode Rebuilding geometry');

    _lastTransformToScreen = getTransformTo(null);
    _geometryState = _GeometryUpdateState.upToDate;

    _geometryImage?.dispose();
    _geometryImage = null;

    _cachedShapes = shapes;
    _cachedLayerBoundingBox = layerBounds;
    final geometryBounds = _cachedScreenShapesBounds =
        screenBounds.inflate(settings.blend).snapToPixels(devicePixelRatio);

    if (shapes.isEmpty) {
      markNeedsCompositingBitsUpdate();
      return;
    }

    _updateGeometryShaderShapes(Offset.zero);

    final (width, height) = _getGeometryImageSize(geometryBounds);

    geometryShader
      ..setFloat(0, width.toDouble())
      ..setFloat(1, height.toDouble());

    _geometryImage = _renderGeometryToImage(geometryBounds, width, height);
    markNeedsCompositingBitsUpdate();
  }

  Matrix4 _getTransformSinceLastGeometryUpdate() {
    // Get transforms in logical pixel space
    final currentTransform = getTransformTo(null);
    final inverseCurrent = Matrix4.inverted(currentTransform);
    final deltaTransform = _lastTransformToScreen.clone()
      ..multiply(inverseCurrent);

    // Scale the transform to physical pixel space
    // We need to scale both the input and output by devicePixelRatio
    // This is equivalent to: scale^-1 * deltaTransform * scale
    // But since we're scaling uniformly, we only need to scale the translation
    // components
    final scaled = Matrix4.identity()..setFrom(deltaTransform);

    // Scale translation components (last column, rows 0-2)
    scaled[12] *= devicePixelRatio; // tx
    scaled[13] *= devicePixelRatio; // ty
    scaled[14] *= devicePixelRatio; // tz

    return scaled;
  }

  (int, int) _getGeometryImageSize(Rect bounds) {
    final width = (bounds.width * devicePixelRatio).ceil();
    final height = (bounds.height * devicePixelRatio).ceil();
    return (width, height);
  }

  ui.Image _renderGeometryToImage(Rect geometryBounds, int width, int height) {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..shader = geometryShader;

    final leftPixel = (geometryBounds.left * devicePixelRatio).roundToDouble();
    final topPixel = (geometryBounds.top * devicePixelRatio).roundToDouble();

    canvas
      ..translate(-leftPixel, -topPixel)
      ..drawRect(
        Rect.fromLTWH(leftPixel, topPixel, width.toDouble(), height.toDouble()),
        paint,
      );

    final pic = recorder.endRecording();
    return pic.toImageSync(width, height);
  }

  // === Shape Data Collection ===

  /// Gathers all shapes and computes them in both layer and screen space
  /// Returns (layerBounds, screenBounds, shapes, anyShapeChangedInLayer)
  (Rect, Rect, List<ShapeInLayerInfo>, bool) _gatherShapeData() {
    final shapes = <ShapeInLayerInfo>[];
    final cachedShapes = _cachedShapes;

    var anyShapeChangedInLayer =
        cachedShapes.length != glassLink.shapeEntries.length;

    Rect? layerBounds;
    Rect? screenBounds;

    for (final (index, entry) in glassLink.shapeEntries.indexed) {
      final renderObject = entry.key;
      final shapeInfo = entry.value;

      if (!renderObject.attached || !renderObject.hasSize) continue;

      try {
        final shapeData = _computeShapeInfo(renderObject, shapeInfo);
        shapes.add(shapeData);

        layerBounds = layerBounds?.expandToInclude(shapeData.layerBounds) ??
            shapeData.layerBounds;

        screenBounds = screenBounds?.expandToInclude(shapeData.screenBounds) ??
            shapeData.screenBounds;

        final existingShape =
            cachedShapes.length > index ? cachedShapes[index] : null;

        if (existingShape == null) {
          anyShapeChangedInLayer = true;
        } else if (existingShape.layerBounds != shapeData.layerBounds) {
          anyShapeChangedInLayer = true;
        }
      } catch (e) {
        debugPrint('Failed to compute shape info: $e');
      }
    }

    return (
      layerBounds ?? Rect.zero,
      screenBounds ?? Rect.zero,
      shapes,
      anyShapeChangedInLayer,
    );
  }

  ShapeInLayerInfo _computeShapeInfo(
    RenderLiquidGlass renderObject,
    GlassShapeInfo shapeInfo,
  ) {
    // Layer space: for painting shape contents with correct transforms
    final transformToLayer = renderObject.getTransformTo(this);
    final layerRect = MatrixUtils.transformRect(
      transformToLayer,
      Offset.zero & renderObject.size,
    );

    // Screen space: for geometry texture (backdropFilter uses screen coords)
    final transformToScreen = renderObject.getTransformTo(null);
    final screenRect = MatrixUtils.transformRect(
      transformToScreen,
      Offset.zero & renderObject.size,
    );

    return ShapeInLayerInfo(
      renderObject: renderObject,
      shape: shapeInfo.shape,
      glassContainsChild: shapeInfo.glassContainsChild,
      layerBounds: layerRect,
      screenBounds: screenRect,
      relativeLayerBounds: RelativeRect.fromLTRB(
        layerRect.left / size.width,
        layerRect.top / size.height,
        1 - layerRect.right / size.width,
        1 - layerRect.bottom / size.height,
      ),
      shapeToLayer: transformToLayer,
    );
  }

  @override
  @mustCallSuper
  void dispose() {
    _geometryImage?.dispose();
    glassLink.removeListener(onLinkNotification);
    super.dispose();
  }
}

extension on LiquidGlassSettings {
  bool requiresGeometryRebuild(LiquidGlassSettings? other) {
    if (other == null) return false;

    return thickness != other.thickness ||
        refractiveIndex != other.refractiveIndex ||
        blend != other.blend;
  }
}
