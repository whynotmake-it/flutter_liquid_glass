// Explicit canvas save/transform/restore sequences are easier to audit than
// cascades across nested geometry loops.
// ignore_for_file: cascade_invocations

import 'dart:collection';
import 'dart:math';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/glass_shadow.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/internal/snap_rect_to_pixels.dart';
import 'package:liquid_glass_renderer/src/logging.dart';

/// A render object that can assemble [RenderLiquidGlassGeometry] shapes and
/// render them to the screen with the liquid glass effect.
@internal
abstract class LiquidGlassRenderObject extends RenderProxyBox {
  LiquidGlassRenderObject({
    required this._link,
    required this.defaultRenderShader,
    required this.materialRenderShader,
    required LiquidGlassSettings this._settings,
    required this._defaultAppearance,
    required this._devicePixelRatio,
    required this._backdropKey,
    this._gpuGeometryRenderer,
  }) {
    _updateShaderSettings();
  }

  static final logger = Logger(LgrLogNames.render);

  final FragmentShader defaultRenderShader;
  final FragmentShader materialRenderShader;

  FragmentShader get renderShader =>
      _usesShapeAppearances ? materialRenderShader : defaultRenderShader;

  Matrix4 get matteTransform;

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
        _settings?.effectiveEdgeRefraction != value.effectiveEdgeRefraction ||
        _settings?.effectiveRefractionSpread !=
            value.effectiveRefractionSpread ||
        _settings?.effectiveContourWidth != value.effectiveContourWidth ||
        _settings?.effectiveContourOffset != value.effectiveContourOffset;
    final wasIdle = (_settings?.effectiveThickness ?? 0) <= 0;
    final isIdle = value.effectiveThickness <= 0;
    _settings = value;
    _updateShaderSettings();
    if (geometryInputsChanged) needsGeometryUpdate = true;
    if (wasIdle != isIdle) markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  LiquidGlassAppearance _defaultAppearance;
  LiquidGlassAppearance get defaultAppearance => _defaultAppearance;
  set defaultAppearance(LiquidGlassAppearance value) {
    if (_defaultAppearance == value) return;
    _defaultAppearance = value;
    _updateShaderSettings();
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
    if (_settings != null) _updateShaderSettings();
    needsGeometryUpdate = true;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing =>
      _geometryImage != null && settings.effectiveThickness > 0;

  /// Pre-rendered geometry texture in screen space
  ui.Image? _geometryImage;
  ui.Image? _materialImage;

  /// The bounding box of the geometry matte in the coordinate space of the
  /// shader
  Rect _geometryMatteBounds = Rect.zero;
  Offset _materialCenterInMatte = Offset.zero;

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
  LiquidGlassAppearance? _uniformAppearance;
  List<LiquidGlassAppearance> _shapeAppearances = const [];
  bool _usesShapeAppearances = false;

  /// Whether the latest geometry pass writes per-shape contributor data.
  @visibleForTesting
  bool get debugUsesShapeAppearances => _usesShapeAppearances;

  /// The optional contributor texture sampled by the final material pass.
  @visibleForTesting
  ui.Image? get debugMaterialImage => _materialImage;

  void _updateShaderSettings() {
    _shaderSettingsRevision++;
    final appearance = _uniformAppearance ?? defaultAppearance;
    final appearanceVisibility = appearance.visibility;
    final tint = appearance.tint.withValues(
      alpha: appearance.tint.a * appearanceVisibility,
    );
    final saturation = 1 + (appearance.saturation - 1) * appearanceVisibility;
    final transmissionGamma =
        1 + (appearance.transmissionGamma - 1) * appearanceVisibility;
    final vibrancy = appearance.vibrancy * appearanceVisibility;
    void updateCommonUniforms(FragmentShader shader) {
      shader.setFloatUniforms(initialIndex: 6, (value) {
        value
          ..setColor(tint)
          ..setFloats([
            settings.effectiveDisplacementScale * devicePixelRatio,
            settings.effectiveChromaticAberration,
            settings.effectiveThickness * devicePixelRatio,
            settings.effectiveHighlight,
            settings.effectiveBackdropScale,
            saturation,
          ])
          ..setOffset(
            const Offset(0, 1),
          )
          ..setColor(const Color.fromARGB(255, 255, 255, 255))
          ..setColor(
            Color.fromARGB(
              (settings.effectiveContourStrength.clamp(0.0, 1.0) * 255).round(),
              0,
              0,
              0,
            ),
          )
          ..setFloats([
            settings.effectiveBevelShadowDirectionality,
            settings.effectiveBevelShadowSizeResponse,
            settings.effectiveHighlightWidth * devicePixelRatio,
            settings.effectiveHighlightOppositeStrength,
          ])
          ..setFloats([
            settings.effectiveContourWidth * devicePixelRatio,
            settings.effectiveContourTransmittance,
          ])
          ..setFloats([
            settings.effectiveContourOffset * devicePixelRatio,
            _materialCenterInMatte.dx * devicePixelRatio,
            _materialCenterInMatte.dy * devicePixelRatio,
            settings.effectiveHighlightWrap,
          ])
          ..setFloats([
            transmissionGamma,
            vibrancy,
          ])
          ..setFloats([
            settings.effectiveBevelShadowStrength,
            settings.effectiveBevelShadowDepth * devicePixelRatio,
            settings.effectiveBevelShadowOffset * devicePixelRatio,
          ])
          ..setFloats([
            appearance.colorModel.shaderValue,
            appearanceVisibility,
          ]);
      });
    }

    updateCommonUniforms(defaultRenderShader);
    updateCommonUniforms(materialRenderShader);
    materialRenderShader.setFloatUniforms(initialIndex: 43, (value) {
      for (var i = 0; i < 16; i++) {
        var tint = appearance.tint;
        if (i < _shapeAppearances.length) tint = _shapeAppearances[i].tint;
        value.setColor(tint);
      }
      for (var i = 0; i < 16; i++) {
        final shapeAppearance = i < _shapeAppearances.length
            ? _shapeAppearances[i]
            : appearance;
        value.setFloats([
          shapeAppearance.saturation,
          shapeAppearance.transmissionGamma,
          shapeAppearance.vibrancy,
          shapeAppearance.visibility,
        ]);
      }
      for (var i = 0; i < 16; i++) {
        final shapeAppearance = i < _shapeAppearances.length
            ? _shapeAppearances[i]
            : appearance;
        value.setFloat(
          shapeAppearance.colorModel.shaderValue,
        );
      }
    });
  }

  void _setShapeAppearances(List<LiquidGlassAppearance> appearances) {
    final first = appearances.isEmpty ? defaultAppearance : appearances.first;
    final usesShapeAppearances = appearances.any(
      (appearance) => appearance != first,
    );
    final uniformAppearance = usesShapeAppearances ? null : first;
    if (_usesShapeAppearances == usesShapeAppearances &&
        _uniformAppearance == uniformAppearance &&
        listEquals(_shapeAppearances, appearances)) {
      return;
    }
    _usesShapeAppearances = usesShapeAppearances;
    _uniformAppearance = uniformAppearance;
    _shapeAppearances = List.unmodifiable(appearances);
    _updateShaderSettings();
  }

  ui.Rect _paintBounds = ui.Rect.zero;

  @override
  ui.Rect get paintBounds => _paintBounds;

  /// Number of times [paint] has run. Ancestor motion should not increment
  /// this once geometry has been encoded.
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
      releaseCompositorFilter();
      super.paint(context, offset);
      return;
    }

    final materialPaintBounds = boundingBox.inflate(_contourOutset);
    _paintBounds = _expandForLayerShadows(materialPaintBounds);

    final hasVisibleShape = _shapesWithGeometry.any(
      (entry) => entry.$2.shapes.any(
        (shape) => shape.appearance.visibility > 0,
      ),
    );
    if (settings.effectiveThickness <= 0 || !hasVisibleShape) {
      // Keep any existing matte so ancestor motion stays compositor-only.
      // Skip the backdrop filter so idle glass does not sample.
      releaseCompositorFilter();
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

      _clearGeometryImage();
      final gpuResult = _buildGpuGeometryImage(
        _shapesWithGeometry,
        boundingBox,
      );
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
        final activeRenderShader = renderShader;
        activeRenderShader
          ..setFloatUniforms(initialIndex: 2, (value) {
            value
              ..setOffset(_geometryMatteBounds.topLeft * devicePixelRatio)
              ..setSize(_geometryMatteBounds.size * devicePixelRatio);
          })
          ..setFloatUniforms(initialIndex: 33, (value) {
            value.setOffset(_materialCenterInMatte * devicePixelRatio);
          })
          ..setImageSampler(1, geometryImage)
          ..setImageSampler(2, coordinateImage);
        if (_materialImage case final materialImage?) {
          activeRenderShader.setImageSampler(3, materialImage);
        }
        _shaderInputSnapshot = _ShaderInputSnapshot(
          geometryImage: geometryImage,
          materialImage: _materialImage,
          coordinateImage: coordinateImage,
          matteBounds: _geometryMatteBounds,
          devicePixelRatio: devicePixelRatio,
          settingsRevision: _shaderSettingsRevision,
        );
        _paintLayerShadows(context, offset, _shapesWithGeometry);
        paintLiquidGlass(
          context,
          offset,
          _shapesWithGeometry,
          materialPaintBounds,
        );
      }
    }

    super.paint(context, offset);
  }

  Rect _expandForLayerShadows(Rect bounds) {
    var result = bounds;
    for (final (_, geometry, geometryToLayer) in _shapesWithGeometry) {
      for (final shape in geometry.shapes) {
        final shapeVisibility = shape.appearance.visibility.clamp(0.0, 1.0);
        if (shapeVisibility <= 0) continue;
        final shadowScale = liquidGlassShadowScale(
          shape.renderObject.size,
          settings.effectiveExteriorShadowSizeResponse,
        );
        final shapeToLayer = shape.shapeToGeometry == null
            ? geometryToLayer
            : geometryToLayer.multiplied(shape.shapeToGeometry!);
        for (final shadow in shape.shadows) {
          final extent = max(
            shadow.spreadRadius +
                glassShadowBlurSupport(
                  shadow.blurRadius * shapeVisibility * shadowScale.blur,
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

  void _paintLayerShadows(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
  ) {
    final hasShadows = geometries.any(
      (entry) => entry.$2.shapes.any((shape) => shape.shadows.isNotEmpty),
    );
    if (!hasShadows) return;

    final canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.saveLayer(_paintBounds, Paint());

    for (final (_, geometry, geometryToLayer) in geometries) {
      for (final shape in geometry.shapes) {
        final shapeVisibility = shape.appearance.visibility.clamp(0.0, 1.0);
        if (shape.shadows.isEmpty || shapeVisibility <= 0) continue;
        canvas.save();
        canvas.transform(geometryToLayer.storage);
        if (shape.shapeToGeometry case final transform?) {
          canvas.transform(transform.storage);
        }
        final rect = Offset.zero & shape.renderObject.size;
        final shadowScale = liquidGlassShadowScale(
          shape.renderObject.size,
          settings.effectiveExteriorShadowSizeResponse,
        );
        for (final shadow in shape.shadows) {
          final paint = shadow
              .copyWith(
                color: shadow.color.withValues(
                  alpha: shadow.color.a * shapeVisibility * shadowScale.energy,
                ),
                blurRadius:
                    shadow.blurRadius * shapeVisibility * shadowScale.blur,
                blurStyle: BlurStyle.normal,
              )
              .toPaint();
          _drawLayerShadowShape(
            canvas,
            shape.shape,
            rect.shift(shadow.offset).inflate(shadow.spreadRadius),
            paint,
          );
        }
        canvas.restore();
      }
    }

    for (final (_, geometry, geometryToLayer) in geometries) {
      for (final shape in geometry.shapes) {
        final shapeVisibility = shape.appearance.visibility.clamp(0.0, 1.0);
        if (shapeVisibility <= 0) continue;
        canvas.save();
        canvas.transform(geometryToLayer.storage);
        if (shape.shapeToGeometry case final transform?) {
          canvas.transform(transform.storage);
        }
        _drawLayerShadowShape(
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

  void _drawLayerShadowShape(
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

  void _clearGeometryImage() {
    _geometryImage = null;
    _materialImage = null;
  }

  /// Subclasses implement the actual glass rendering
  /// (e.g., with backdrop filters)
  void paintLiquidGlass(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> shapes,
    Rect boundingBox,
  );

  @protected
  ui.Image syncCoordinateMapping() {
    final renderer = _gpuGeometryRenderer;
    if (renderer == null) {
      throw StateError('Flutter GPU coordinate renderer is unavailable.');
    }
    final globalToMatte = Matrix4.inverted(shaderCoordinateTransform);
    final origin = MatrixUtils.transformPoint(globalToMatte, Offset.zero);
    final axisX = MatrixUtils.transformPoint(globalToMatte, const Offset(1, 0));
    final axisY = MatrixUtils.transformPoint(globalToMatte, const Offset(0, 1));
    renderer.updateCoordinateMapping(
      basisXX: axisX.dx - origin.dx,
      basisYX: axisY.dx - origin.dx,
      basisXY: axisX.dy - origin.dy,
      basisYY: axisY.dy - origin.dy,
      originX: origin.dx * devicePixelRatio,
      originY: origin.dy * devicePixelRatio,
    );
    return renderer.coordinateImage!;
  }

  /// True once geometry has been encoded, so ancestor motion can stay on the
  /// compositor without crossing this layer's repaint boundary.
  @protected
  bool get hasReusableGeometry =>
      _geometryImage != null && _gpuGeometryRenderer?.coordinateImage != null;

  /// Drops native backdrop-filter state while this sample is idle.
  @protected
  void releaseCompositorFilter() {}

  /// Layer-local bounds of the geometry matte. Ancestor transforms must not
  /// change this: they are applied by the compositor, not the shader.
  @visibleForTesting
  Rect get debugGeometryMatteBounds => _geometryMatteBounds;

  /// Value identity of everything [renderShader] has captured for the current
  /// paint: float uniforms and the geometry sampler.
  ///
  /// The engine copies a shader's uniforms into the native image filter when
  /// that filter is first converted (see
  /// `ReusableFragmentShader::as_image_filter`), so a filter wrapping this
  /// shader may only be reused across paints while this snapshot compares
  /// equal.
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
  final List<double> _rseData = [];
  static final Matrix4 _identity = Matrix4.identity();

  double get _contourOutset {
    if (settings.effectiveContourWidth <= 0) return 0;
    return max(
      0.5 / devicePixelRatio,
      settings.effectiveContourOffset +
          settings.effectiveContourWidth * 0.5 +
          1.0 / devicePixelRatio,
    );
  }

  // Flutter 3.47 computes these RSE parameters when its geometry changes and
  // uploads them to the symmetric RSE shader. Mirror that construction here
  // so lookup-table interpolation and circle fitting are not repeated per
  // fragment.
  static (double, double) _rseNAndXj(double ratio) {
    const table = <(double, double)>[
      (2.00000000, 1.13276676),
      (2.18349805, 1.20311921),
      (2.33888662, 1.28698796),
      (2.48660575, 1.36351941),
      (2.62226596, 1.44717976),
      (2.75148990, 1.53385819),
      (3.36298265, 1.98288283),
      (4.08649929, 2.23811846),
      (4.85481134, 2.47563463),
      (5.62945551, 2.72948597),
      (6.43023796, 2.98020421),
    ];
    if (ratio > 5.0) {
      final n = 1.559599389 * (ratio - 5.0) + table.last.$1;
      final kXj = 0.522807185 * (ratio - 5.0) + table.last.$2;
      return (n, 1.0 - 1.0 / kXj);
    }
    final clampedRatio = ratio.clamp(2.0, 5.0);
    final steps = clampedRatio < 2.5
        ? (clampedRatio - 2.0) * 10.0
        : (clampedRatio - 2.5) * 2.0 + 5.0;
    final left = steps.floor().clamp(0, table.length - 2);
    final fraction = steps - left;
    final a = table[left];
    final b = table[left + 1];
    final n = a.$1 + (b.$1 - a.$1) * fraction;
    final kXj = a.$2 + (b.$2 - a.$2) * fraction;
    return (n, 1.0 - 1.0 / kXj);
  }

  static (double, double, Offset, double) _rseOctant(
    double axis,
    double radius,
  ) {
    if (radius <= 1e-3) return (0.0, 0.0, Offset.zero, 0.0);
    final (n, xJOverA) = _rseNAndXj(2.0 * axis / radius);
    final xJ = xJOverA * axis;
    final yJ =
        pow(
          max(1.0 - pow(xJOverA, n).toDouble(), 0.0),
          1.0 / n,
        ).toDouble() *
        axis;
    final tanPhi = pow(xJ / max(yJ, 1e-6), n - 1.0).toDouble();
    final d = (xJ - tanPhi * yJ) / (1.0 - tanPhi);
    final gap = (1.0 - cos(pi / 4.0)) * radius;
    final circleRadius = (axis - d - gap) * sqrt2;
    final pointJ = Offset(xJ, yJ);
    final pointM = Offset(axis - gap, axis - gap);
    final chord = pointM - pointJ;
    final midpoint = (pointJ + pointM) / 2.0;
    final perpendicular = Offset(-chord.dy, chord.dx);
    final perpendicularLength = perpendicular.distance;
    final halfChord = chord.distance / 2.0;
    final centerDistance = sqrt(
      max(circleRadius * circleRadius - halfChord * halfChord, 0.0),
    );
    final circleCenter = perpendicularLength <= 1e-6
        ? midpoint
        : midpoint - perpendicular * (centerDistance / perpendicularLength);
    final fromM = pointM - circleCenter;
    final fromJ = pointJ - circleCenter;
    final span = atan2(
      fromM.dx * fromJ.dy - fromM.dy * fromJ.dx,
      fromM.dx * fromJ.dx + fromM.dy * fromJ.dy,
    ).abs();
    return (n, span, circleCenter, circleRadius);
  }

  static List<double> _rseParameters(
    Size size,
    double rawCornerRadius,
    double devicePixelRatio,
  ) {
    final halfWidth = size.width * devicePixelRatio / 2.0;
    final halfHeight = size.height * devicePixelRatio / 2.0;
    final radius = min(
      rawCornerRadius * devicePixelRatio,
      min(halfWidth, halfHeight),
    );
    final (topN, topSpan, topCenter, topRadius) = _rseOctant(
      halfWidth,
      radius,
    );
    final (rightN, rightSpan, rightCenter, rightRadius) = _rseOctant(
      halfHeight,
      radius,
    );
    return <double>[
      topN,
      rightN,
      topSpan,
      rightSpan,
      topCenter.dx,
      topCenter.dy,
      rightCenter.dx,
      rightCenter.dy,
      halfWidth,
      halfHeight,
      topRadius,
      rightRadius,
    ];
  }

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
      // Centered SDF antialiasing needs half a physical pixel outside the
      // mathematical shape. Keep that margin in the persistent geometry
      // texture so the positive side of the fade is not clipped at the matte
      // edge.
      final aaPadding = max(0.5 / devicePixelRatio, _contourOutset);
      final boundsInMatteSpace = MatrixUtils.transformRect(
        matteTransform,
        bounds.inflate(aaPadding),
      ).snapToPixels(devicePixelRatio);
      _materialCenterInMatte = MatrixUtils.transformRect(
        matteTransform,
        bounds,
      ).center;

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
      _rseData.clear();
      final appearances = <LiquidGlassAppearance>[];
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
          _rseData.addAll(
            _rseParameters(size, shape.rawCornerRadius, devicePixelRatio),
          );
          final blendMarker = firstInGroup
              ? -(geometry.blend * devicePixelRatio + 1)
              : geometry.blend * devicePixelRatio;

          _shapeData
            // vec4 0: primitive parameters.
            ..add(
              shape.appearance.visibility <= 0
                  ? 0
                  : shape.rawShapeType.shaderIndex,
            )
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
          appearances.add(shape.appearance);
          numShapes++;
          firstInGroup = false;
        }
      }

      if (numShapes == 0) {
        throw StateError('No invertible liquid-glass shapes to render.');
      }
      _setShapeAppearances(appearances);

      final result = renderer.render(
        width: textureWidth,
        height: textureHeight,
        shapeData: _shapeData,
        rseData: _rseData,
        numShapes: numShapes,
        opticalIndex: settings.effectiveOpticalIndex,
        refractionSpread: settings.effectiveRefractionSpread,
        displacementScale:
            settings.effectiveDisplacementScale * devicePixelRatio,
        thickness: settings.effectiveThickness * devicePixelRatio,
        contourExtent: aaPadding * devicePixelRatio,
        writeMaterials: _usesShapeAppearances,
        offsetX: boundsInMatteSpace.left * devicePixelRatio,
        offsetY: boundsInMatteSpace.top * devicePixelRatio,
      );
      _materialImage = renderer.materialImage;

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
/// Geometry images are persistent GPU textures whose wrappers stay stable
/// while the contents are updated in place. Ancestor transforms are not part
/// of this key: they are applied by the compositor, not the shader.
@immutable
class _ShaderInputSnapshot {
  const _ShaderInputSnapshot({
    required this.geometryImage,
    required this.materialImage,
    required this.coordinateImage,
    required this.matteBounds,
    required this.devicePixelRatio,
    required this.settingsRevision,
  });

  final ui.Image geometryImage;
  final ui.Image? materialImage;
  final ui.Image coordinateImage;
  final Rect matteBounds;
  final double devicePixelRatio;
  final int settingsRevision;

  @override
  bool operator ==(Object other) {
    return other is _ShaderInputSnapshot &&
        other.geometryImage == geometryImage &&
        other.materialImage == materialImage &&
        other.coordinateImage == coordinateImage &&
        other.matteBounds == matteBounds &&
        other.devicePixelRatio == devicePixelRatio &&
        other.settingsRevision == settingsRevision;
  }

  @override
  int get hashCode => Object.hash(
    geometryImage,
    materialImage,
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

  late final UnmodifiableListView<RenderLiquidGlassGeometry> shapes =
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
