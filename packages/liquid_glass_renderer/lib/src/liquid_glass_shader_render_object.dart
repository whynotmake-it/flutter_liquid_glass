import 'dart:math';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/glass_link.dart';
import 'package:liquid_glass_renderer/src/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/raw_shapes.dart';
import 'package:meta/meta.dart';

@internal
bool debugPaintLiquidGlassGeometry = false;

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

  final FragmentShader renderShader;
  final FragmentShader geometryShader;
  final FragmentShader lightingShader;

  // === Settings and Configuration ===

  LiquidGlassSettings? _settings;
  LiquidGlassSettings get settings => _settings!;
  set settings(LiquidGlassSettings value) {
    if (_settings == value) return;
    final oldSettings = _settings;
    _settings = value;
    _updateShaderSettings(oldSettings);
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

  @protected
  void onLinkNotification() {
    _invalidateGeometry();
  }

  // === Cached Geometry State ===

  /// Pre-rendered geometry texture in screen space
  ui.Image? _geometryImage;

  /// Screen-space bounding box of all shapes (for geometry texture sizing)
  Rect? _cachedScreenShapesBounds;

  /// Computed shape information
  List<ShapeInLayerInfo> _cachedShapes = [];
  List<ShapeInLayerInfo> get cachedShapes => _cachedShapes;

  /// Layer-space bounding box (for painting)
  Rect _cachedLayerBoundingBox = Rect.zero;

  bool _needsRecreateGeometryImage = true;

  void _invalidateGeometry() {
    _needsRecreateGeometryImage = true;
    _cachedScreenShapesBounds = null;
    markNeedsPaint();
  }

  // === Shader Uniform Updates ===

  void _updateShaderSettings([LiquidGlassSettings? oldSettings]) {
    renderShader.setFloatUniforms(initialIndex: 6, (value) {
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

    if (oldSettings != null && oldSettings.thickness != settings.thickness) {
      _invalidateGeometry();
    }
  }

  /// Uploads shape data to geometry shader in screen space coordinates
  void _updateGeometryShaderShapes(Offset screenOrigin) {
    final shapes = cachedShapes;
    final shapeCount = shapes.length;

    if (shapeCount > LiquidGlass.maxShapesPerLayer) {
      throw UnsupportedError(
        'Only ${LiquidGlass.maxShapesPerLayer} shapes are supported at '
        'the moment!',
      );
    }

    geometryShader.setFloatUniforms(initialIndex: 6, (value) {
      value.setFloat(shapeCount.toDouble());
      for (var i = 0; i < shapeCount; i++) {
        final shape = i < shapes.length ? shapes[i].rawShape : RawShape.none;
        value
          ..setFloat(shape.type.index.toDouble())
          ..setFloat((shape.center.dx - screenOrigin.dx) * devicePixelRatio)
          ..setFloat((shape.center.dy - screenOrigin.dy) * devicePixelRatio)
          ..setFloat(shape.size.width * devicePixelRatio)
          ..setFloat(shape.size.height * devicePixelRatio)
          ..setFloat(shape.cornerRadius * devicePixelRatio);
      }
    });
  }

  // === Main Rendering ===

  @override
  @nonVirtual
  void paint(PaintingContext context, Offset offset) {
    debugPaintLiquidGlassGeometry = false;

    if (_needsRecreateGeometryImage) {
      _rebuildGeometry();
      _needsRecreateGeometryImage = false;
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
      final geometryBounds = _getPixelAlignedGeometryBounds();

      renderShader
        ..setFloatUniforms((value) {
          value
            ..setSize(geometryBounds.size * devicePixelRatio)
            ..setOffset(geometryBounds.topLeft * devicePixelRatio)
            ..setSize(geometryBounds.size * devicePixelRatio);
        })
        ..setImageSampler(1, geometryImage);

      paintLiquidGlass(context, offset, _cachedShapes, _cachedLayerBoundingBox);
    }
  }

  Rect _getPixelAlignedGeometryBounds() {
    if (_cachedScreenShapesBounds case final bounds?) {
      return bounds.inflate(settings.thickness * 2);
    }
    return Rect.zero;
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
          shapeInLayer.transform,
          shapeInLayer.renderObject.paintFromLayer,
        );
      }
    }
  }

  // === Geometry Texture Creation ===

  /// Rebuilds the geometry texture in screen space with pixel-perfect alignment
  void _rebuildGeometry() {
    _geometryImage?.dispose();

    final (layerBounds, screenBounds, shapes) = _gatherShapeData();
    _cachedShapes = shapes;
    _cachedLayerBoundingBox = layerBounds;
    _cachedScreenShapesBounds = screenBounds;

    if (shapes.isEmpty) {
      _geometryImage = null;
      return;
    }

    final geometryBounds = _snapToPixelBoundaries(
      screenBounds.inflate(settings.thickness * 2),
    );

    _updateGeometryShaderShapes(Offset.zero);

    final (width, height) = _getGeometryImageSize(geometryBounds);

    geometryShader
      ..setFloat(0, width.toDouble())
      ..setFloat(1, height.toDouble());

    _geometryImage = _renderGeometryToImage(geometryBounds, width, height);
  }

  /// Snaps bounds to pixel boundaries to prevent sub-pixel flickering
  Rect _snapToPixelBoundaries(Rect bounds) {
    final left =
        (bounds.left * devicePixelRatio).floorToDouble() / devicePixelRatio;
    final top =
        (bounds.top * devicePixelRatio).floorToDouble() / devicePixelRatio;
    final right =
        (bounds.right * devicePixelRatio).ceilToDouble() / devicePixelRatio;
    final bottom =
        (bounds.bottom * devicePixelRatio).ceilToDouble() / devicePixelRatio;

    return Rect.fromLTRB(left, top, right, bottom);
  }

  (int, int) _getGeometryImageSize(Rect bounds) {
    final width = (bounds.width * devicePixelRatio).round();
    final height = (bounds.height * devicePixelRatio).round();
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
  /// Returns (layerBounds, screenBounds, shapes)
  (Rect, Rect, List<ShapeInLayerInfo>) _gatherShapeData() {
    final shapes = <ShapeInLayerInfo>[];
    Rect? layerBounds;
    Rect? screenBounds;

    for (final entry in glassLink.shapeEntries) {
      final renderObject = entry.key;
      final shapeInfo = entry.value;

      if (!renderObject.attached || !renderObject.hasSize) continue;

      try {
        final shapeData = _computeShapeInfo(renderObject, shapeInfo);
        shapes.add(shapeData);

        layerBounds = layerBounds?.expandToInclude(shapeData.boundsInLayer) ??
            shapeData.boundsInLayer;
        screenBounds = screenBounds?.expandToInclude(shapeData.screenBounds) ??
            shapeData.screenBounds;
      } catch (e) {
        debugPrint('Failed to compute shape info: $e');
      }
    }

    return (
      layerBounds ?? Rect.zero,
      screenBounds ?? Rect.zero,
      shapes,
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
      boundsInLayer: layerRect,
      screenBounds: screenRect,
      transform: transformToLayer,
      rawShape: RawShape.fromLiquidGlassShape(
        shapeInfo.shape,
        center: screenRect.center,
        size: screenRect.size,
      ),
    );
  }

  @override
  @mustCallSuper
  void dispose() {
    glassLink.removeListener(onLinkNotification);
    super.dispose();
  }
}

/// Shape data in both layer and screen coordinate spaces
@internal
class ShapeInLayerInfo {
  ShapeInLayerInfo({
    required this.renderObject,
    required this.shape,
    required this.glassContainsChild,
    required this.boundsInLayer,
    required this.screenBounds,
    required this.transform,
    required this.rawShape,
  });

  final RenderLiquidGlass renderObject;

  final LiquidShape shape;

  final bool glassContainsChild;

  /// Bounds in layer-local coordinates (for painting)
  final Rect boundsInLayer;

  /// Bounds in screen coordinates (for geometry texture)
  final Rect screenBounds;

  /// Transform from shape to layer (for painting contents)
  final Matrix4 transform;

  /// Shader-ready shape data (in screen coordinates)
  final RawShape rawShape;
}
