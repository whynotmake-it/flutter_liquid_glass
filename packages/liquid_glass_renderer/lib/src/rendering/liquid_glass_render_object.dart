import 'dart:math';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/internal/snap_rect_to_pixels.dart';
import 'package:liquid_glass_renderer/src/logging.dart';
import 'package:meta/meta.dart';

@internal
bool debugPaintLiquidGlassGeometry = false;

/// A render object that can assemble [RenderLiquidGlassGeometry] shapes and
/// render them to the screen with the liquid glass effect.
@internal
abstract class LiquidGlassRenderObject extends RenderProxyBox {
  LiquidGlassRenderObject({
    required GeometryRenderLink link,
    required this.renderShader,
    required LiquidGlassSettings settings,
    required double devicePixelRatio,
    required BackdropKey? backdropKey,
  })  : _settings = settings,
        _devicePixelRatio = devicePixelRatio,
        _backdropKey = backdropKey,
        _link = link {
    _updateShaderSettings();
  }

  static final logger = Logger(LgrLogNames.object);

  final FragmentShader renderShader;

  /// The size that the geometry texture should have.
  Size get desiredMatteSize;

  Matrix4 get matteTransform;

  late GeometryRenderLink _link;
  GeometryRenderLink get link => _link;
  set link(GeometryRenderLink value) {
    if (_link == value) return;
    _link.removeListener(_onLinkNotification);
    value.addListener(_onLinkNotification);
    markNeedsPaint();
    _link = value;
  }

  LiquidGlassSettings? _settings;
  LiquidGlassSettings get settings => _settings!;
  set settings(LiquidGlassSettings value) {
    if (_settings == value) return;
    _settings = value;
    _updateShaderSettings();
    markNeedsPaint();
  }

  BackdropKey? _backdropKey;
  BackdropKey? get backdropKey => _backdropKey;
  set backdropKey(BackdropKey? value) {
    if (_backdropKey == value) return;
    _backdropKey = value;
  }

  double _devicePixelRatio;
  double get devicePixelRatio => _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => _geometryImage != null;

  /// Pre-rendered geometry texture in screen space
  ui.Image? _geometryImage;

  /// The bounding box of the geometry matte in the coordinate space of the
  /// shader
  Rect _geometryMatteBounds = Rect.zero;

  @override
  @mustCallSuper
  void attach(PipelineOwner owner) {
    _link.addListener(_onLinkNotification);
    super.attach(owner);
  }

  @override
  @mustCallSuper
  void detach() {
    _link.removeListener(_onLinkNotification);
    super.detach();
  }

  @override
  void layout(Constraints constraints, {bool parentUsesSize = false}) {
    needsGeometryUpdate = true;
    super.layout(constraints, parentUsesSize: parentUsesSize);
  }

  void _updateShaderSettings() {
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
        );
    });
  }

  ui.Rect _paintBounds = ui.Rect.zero;

  @override
  ui.Rect get paintBounds => _paintBounds;

  // MARK: Painting

  @override
  @nonVirtual
  void paint(PaintingContext context, Offset offset) {
    logger.finer('$hashCode Painting liquid glass with '
        '${link.shapeGeometries.length} shapes.');
    if (link.shapeGeometries.isEmpty) {
      _geometryImage?.dispose();
      _geometryImage = null;

      super.paint(context, offset);
      return;
    }

    final shapesWithGeometry =
        <(RenderLiquidGlassGeometry, Geometry, Matrix4)>[];

    Rect? boundingBox;

    for (final MapEntry(key: geometryRo, value: geometry)
        in link.shapeGeometries.entries) {
      final transform = geometryRo.getTransformTo(this);

      shapesWithGeometry.add((geometryRo, geometry, transform));

      final geoBounds = MatrixUtils.transformRect(
        transform,
        geometry.bounds,
      );
      boundingBox = boundingBox == null
          ? geoBounds
          : boundingBox.expandToInclude(geoBounds);
    }

    _paintBounds = boundingBox ?? ui.Rect.zero;

    if (settings.effectiveThickness <= 0) {
      paintShapeContents(
        context,
        offset,
        shapesWithGeometry,
        insideGlass: true,
      );
      paintShapeContents(
        context,
        offset,
        shapesWithGeometry,
        insideGlass: false,
      );
      _geometryImage?.dispose();
      _geometryImage = null;
      super.paint(context, offset);
      return;
    }

    if (needsGeometryUpdate || _geometryImage == null) {
      _geometryImage?.dispose();
      needsGeometryUpdate = false;

      final (image, matteBounds) = _buildGeometryImage(
        shapesWithGeometry,
        boundingBox!,
      );

      _geometryImage = image;
      _geometryMatteBounds = matteBounds;
    }

    if (debugPaintLiquidGlassGeometry) {
      _debugPaintGeometry(context, offset);
      paintShapeContents(
        context,
        offset,
        shapesWithGeometry,
        insideGlass: true,
      );
      paintShapeContents(
        context,
        offset,
        shapesWithGeometry,
        insideGlass: false,
      );
    } else {
      if (_geometryImage case final geometryImage?) {
        renderShader
          ..setFloatUniforms(initialIndex: 2, (value) {
            value
              ..setOffset(_geometryMatteBounds.topLeft * devicePixelRatio)
              ..setSize(_geometryMatteBounds.size * devicePixelRatio);
          })
          ..setImageSampler(1, geometryImage);
        paintLiquidGlass(
          context,
          offset,
          shapesWithGeometry,
          _paintBounds,
        );
      }
    }

    super.paint(context, offset);
  }

  /// Subclasses implement the actual glass rendering
  /// (e.g., with backdrop filters)
  void paintLiquidGlass(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlassGeometry, Geometry, Matrix4)> shapes,
    Rect boundingBox,
  );

  @protected
  void paintShapeContents(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlassGeometry, Geometry, Matrix4)> shapes, {
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
        ..drawImage(geometryImage, offset * devicePixelRatio, Paint())
        ..restore();
    }
  }

  @override
  @mustCallSuper
  void dispose() {
    _geometryImage?.dispose();
    super.dispose();
  }

  // MARK: Geometry

  @protected
  bool needsGeometryUpdate = true;

  void _onLinkNotification() {
    needsGeometryUpdate = true;
    logger.finer('$hashCode Marking layer for repaint due to link change with '
        '${link.shapeGeometries.length} shapes.');
    markNeedsPaint();
  }

  (ui.Image, Rect) _buildGeometryImage(
    List<(RenderLiquidGlassGeometry, Geometry, Matrix4)> geometries,
    Rect bounds,
  ) {
    final boundsInMatteSpace = MatrixUtils.transformRect(
      matteTransform,
      bounds,
    ).snapToPixels(devicePixelRatio);

    final size = boundsInMatteSpace.size * devicePixelRatio;
    logger.fine('$hashCode Building geometry image with '
        '${geometries.length} shapes at size ${size.width}x${size.height}');
    final recorder = ui.PictureRecorder();

    final canvas = Canvas(recorder);
    for (final (_, geometry, transform) in geometries) {
      canvas
        ..save()
        ..scale(devicePixelRatio)
        ..translate(
          -boundsInMatteSpace.left,
          -boundsInMatteSpace.top,
        )
        ..transform(transform.storage)
        ..transform(matteTransform.storage)
        ..scale(1 / devicePixelRatio)
        ..translate(
          geometry.matteBounds.topLeft.dx,
          geometry.matteBounds.topLeft.dy,
        )
        ..drawPicture(geometry.matte)
        ..restore();
    }

    final picture = recorder.endRecording();
    final image = picture.toImageSync(
      size.width.ceil(),
      size.height.ceil(),
    );
    picture.dispose();
    return (image, boundsInMatteSpace);
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

@internal
class GeometryRenderLink with ChangeNotifier {
  Map<RenderLiquidGlassGeometry, Geometry> shapeGeometries = {};

  void setGeometry(
    RenderLiquidGlassGeometry renderObject,
    Geometry geometry,
  ) {
    shapeGeometries[renderObject] = geometry;
    notifyListeners();
  }

  void unregisterGeometry(RenderLiquidGlassGeometry renderObject) {
    shapeGeometries.remove(renderObject);
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (super.hasListeners) super.notifyListeners();
      });
      return;
    }
    super.notifyListeners();
  }
}
