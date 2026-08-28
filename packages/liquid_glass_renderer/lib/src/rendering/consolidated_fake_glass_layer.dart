import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/glass_shadow.dart';
import 'package:liquid_glass_renderer/src/internal/fake_glass_color.dart';
import 'package:liquid_glass_renderer/src/internal/paint_fake_glass_surface.dart';
import 'package:liquid_glass_renderer/src/internal/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/internal/transform_tracking_repaint_boundary_mixin.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';
import 'package:meta/meta.dart';

enum _FakeGlassPaintStage {
  shadows,
  backdrop,
  insideContents,
  surfaces,
  contents,
}

@internal
class ConsolidatedFakeGlassLayer extends SingleChildRenderObjectWidget {
  const ConsolidatedFakeGlassLayer({
    required this.link,
    required this.settings,
    required this.backdropKey,
    required this.surfaceShader,
    required super.child,
    super.key,
  });

  final GeometryRenderLink link;
  final LiquidGlassSettings settings;
  final BackdropKey? backdropKey;
  final FragmentShader? surfaceShader;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderConsolidatedFakeGlassLayer(
        link: link,
        settings: settings,
        backdropKey: backdropKey,
        surfaceShader: surfaceShader,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderConsolidatedFakeGlassLayer renderObject,
  ) {
    renderObject
      ..link = link
      ..settings = settings
      ..backdropKey = backdropKey
      ..surfaceShader = surfaceShader;
  }
}

@visibleForTesting
@internal
class RenderConsolidatedFakeGlassLayer extends RenderProxyBox
    with TransformTrackingRenderObjectMixin {
  RenderConsolidatedFakeGlassLayer({
    required this._link,
    required this._settings,
    required this._backdropKey,
    required this._surfaceShader,
  });

  GeometryRenderLink _link;
  GeometryRenderLink get link => _link;
  set link(GeometryRenderLink value) {
    if (_link == value) return;
    _link = value;
    markNeedsPaint();
  }

  LiquidGlassSettings _settings;
  LiquidGlassSettings get settings => _settings;
  set settings(LiquidGlassSettings value) {
    if (_settings == value) return;
    _settings = value;
    _cachedFilter = null;
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  BackdropKey? _backdropKey;
  BackdropKey? get backdropKey => _backdropKey;
  set backdropKey(BackdropKey? value) {
    if (_backdropKey == value) return;
    _backdropKey = value;
    markNeedsPaint();
  }

  FragmentShader? _surfaceShader;
  FragmentShader? get surfaceShader => _surfaceShader;

  @visibleForTesting
  FragmentShader? get debugSurfaceShader => _surfaceShader;
  set surfaceShader(FragmentShader? value) {
    if (identical(_surfaceShader, value)) return;
    _surfaceShader = value;
    markNeedsPaint();
  }

  final _backdropLayer = LayerHandle<BackdropFilterLayer>();
  final _clipLayer = LayerHandle<ClipPathLayer>();
  ImageFilter? _cachedFilter;
  Path? _cachedClipPath;
  Rect? _cachedClipBounds;
  final List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)>
  _cachedClipInputs = [];
  Rect _paintBounds = Rect.zero;
  bool _repaintAfterCompositingScheduled = false;

  bool get _hasBlur => settings.effectiveFrost > 0;
  bool get _hasColorTransfer =>
      settings.effectiveSaturation != 1 ||
      settings.effectiveTransmissionGamma != 1;
  bool get _hasBackdropEffect => _hasBlur || _hasColorTransfer;

  @override
  Rect get paintBounds =>
      _paintBounds.isEmpty ? super.paintBounds : _paintBounds;

  @visibleForTesting
  BackdropFilterLayer? get debugBackdropFilterLayer => _backdropLayer.layer;

  @visibleForTesting
  Rect? debugClipBounds;

  @visibleForTesting
  Path? get debugClipPath => _cachedClipPath;

  final List<_FakeGlassPaintStage> _debugLastPaintStages = [];

  @visibleForTesting
  List<String> get debugLastPaintStages =>
      _debugLastPaintStages.map((stage) => stage.name).toList(growable: false);

  // Keep the always-composited tracker as a sibling of the retained glass
  // content, matching the full renderer. Its callback can invalidate the
  // content for the following frame when a descendant transform moves.
  @override
  // ignore: must_call_super
  void paint(PaintingContext context, Offset offset) {
    context.pushLayer(setUpLayer(offset), (_, _) {}, offset);
    _paintLayer(context, offset);
  }

  @override
  void onTransformChanged() {}

  @override
  void onCompositing() {
    if (!attached) return;
    var changed = false;
    for (final geometry in link.shapes) {
      if (geometry.pollRelativeTransforms(this)) changed = true;
    }
    if (!changed || _repaintAfterCompositingScheduled) return;
    _repaintAfterCompositingScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _repaintAfterCompositingScheduled = false;
      if (attached) markNeedsPaint();
    });
  }

  void _paintLayer(PaintingContext context, Offset offset) {
    assert(() {
      _debugLastPaintStages.clear();
      return true;
    }(), 'Reset paint-order diagnostics.');
    final geometries = <(RenderLiquidGlassGeometry, GeometryCache, Matrix4)>[];

    for (final geometryRenderObject in link.shapes) {
      geometryRenderObject.pollRelativeTransforms(this);
      final geometry = geometryRenderObject.maybeRebuildGeometry();
      if (geometry == null) continue;
      final transform = geometryRenderObject.getTransformTo(this);
      geometries.add((geometryRenderObject, geometry, transform));
    }

    if (geometries.isEmpty) {
      debugClipBounds = null;
      _paintBounds = super.paintBounds;
      _clearClipCache();
      _releaseLayers();
      super.paint(context, offset);
      return;
    }

    if (!_clipInputsMatch(geometries)) {
      Rect? rebuiltBounds;
      final rebuiltPath = Path();
      for (final (_, geometry, transform) in geometries) {
        final transformedBounds = MatrixUtils.transformRect(
          transform,
          geometry.bounds,
        );
        rebuiltBounds =
            rebuiltBounds?.expandToInclude(transformedBounds) ??
            transformedBounds;
        rebuiltPath.addPath(
          geometry.path,
          Offset.zero,
          matrix4: transform.storage,
        );
      }
      _cachedClipPath = rebuiltPath;
      _cachedClipBounds = rebuiltBounds;
      _cachedClipInputs
        ..clear()
        ..addAll(
          geometries.map(
            (entry) => (entry.$1, entry.$2, entry.$3.clone()),
          ),
        );
    }
    final bounds = _cachedClipBounds!;
    final clipPath = _cachedClipPath!;

    debugClipBounds = bounds;
    _paintBounds = _expandForEffects(bounds, geometries);
    assert(() {
      _debugLastPaintStages.add(_FakeGlassPaintStage.shadows);
      return true;
    }(), 'Record shadow composition order.');
    _paintShadows(context, offset, geometries);

    if (_hasBackdropEffect) {
      assert(() {
        _debugLastPaintStages.add(_FakeGlassPaintStage.backdrop);
        return true;
      }(), 'Record backdrop composition order.');
      final filter = _cachedFilter ??= _buildBackdropFilter();
      final backdropLayer = (_backdropLayer.layer ??= BackdropFilterLayer())
        ..filter = filter
        ..blendMode = BlendMode.srcOver
        ..backdropKey = backdropKey;
      _clipLayer.layer = context.pushClipPath(
        true,
        offset,
        bounds,
        clipPath,
        (context, offset) {
          context.pushLayer(backdropLayer, (_, _) {}, offset);
          if (_hasShapeContents(geometries, insideGlass: true)) {
            assert(() {
              _debugLastPaintStages.add(_FakeGlassPaintStage.insideContents);
              return true;
            }(), 'Record contained subtree composition order.');
            _paintShapeContents(context, offset, geometries, insideGlass: true);
          }
        },
        oldLayer: _clipLayer.layer,
      );
    } else {
      _releaseLayers();
      if (_hasShapeContents(geometries, insideGlass: true)) {
        assert(() {
          _debugLastPaintStages.add(_FakeGlassPaintStage.insideContents);
          return true;
        }(), 'Record contained subtree composition order.');
        _paintShapeContents(context, offset, geometries, insideGlass: true);
      }
    }

    assert(() {
      _debugLastPaintStages.add(_FakeGlassPaintStage.surfaces);
      return true;
    }(), 'Record layer-owned surface composition order.');
    _paintSurfaces(context.canvas, offset, geometries);
    assert(() {
      _debugLastPaintStages.add(_FakeGlassPaintStage.contents);
      return true;
    }(), 'Record normal subtree composition order.');
    super.paint(context, offset);
  }

  void _paintShapeContents(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries, {
    required bool insideGlass,
  }) {
    for (final (renderObject, _, _) in geometries) {
      renderObject.paintShapeContents(
        this,
        context,
        offset,
        insideGlass: insideGlass,
      );
    }
  }

  bool _hasShapeContents(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries, {
    required bool insideGlass,
  }) => geometries.any(
    (entry) => entry.$2.shapes.any(
      (shape) => shape.glassContainsChild == insideGlass,
    ),
  );

  void _paintSurfaces(
    Canvas canvas,
    Offset offset,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
  ) {
    final shader = surfaceShader;
    if (shader == null) return;
    for (final (_, geometry, geometryToLayer) in geometries) {
      for (final shape in geometry.shapes) {
        canvas
          ..save()
          ..translate(offset.dx, offset.dy)
          ..transform(geometryToLayer.storage);
        if (shape.shapeToGeometry case final transform?) {
          canvas.transform(transform.storage);
        }
        paintFakeGlassSurface(
          canvas,
          shader: shader,
          size: shape.renderObject.size,
          shape: shape.shape,
          settings: settings,
        );
        canvas.restore();
      }
    }
  }

  bool _clipInputsMatch(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> current,
  ) {
    if (current.length != _cachedClipInputs.length) return false;
    for (var index = 0; index < current.length; index++) {
      final value = current[index];
      final cached = _cachedClipInputs[index];
      if (!identical(value.$1, cached.$1) ||
          !identical(value.$2, cached.$2) ||
          !_sameTransform(value.$3, cached.$3)) {
        return false;
      }
    }
    return true;
  }

  bool _sameTransform(Matrix4 a, Matrix4 b) {
    final aStorage = a.storage;
    final bStorage = b.storage;
    for (var index = 0; index < 16; index++) {
      if (aStorage[index] != bStorage[index]) return false;
    }
    return true;
  }

  void _clearClipCache() {
    _cachedClipPath = null;
    _cachedClipBounds = null;
    _cachedClipInputs.clear();
  }

  ImageFilter _buildBackdropFilter() {
    return fakeGlassBackdropFilter(settings)!;
  }

  Rect _expandForEffects(
    Rect bounds,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
  ) {
    // Real glass carries the SDF contour just outside its material silhouette.
    // Keep that small support region in this layer's bounds too; otherwise the
    // fallback loses the dark edge precisely where it matters on white.
    var result = bounds.inflate(_surfaceOutset);
    for (final (_, geometry, geometryToLayer) in geometries) {
      for (final shape in geometry.shapes) {
        final scale = liquidGlassShadowScale(
          shape.renderObject.size,
          settings.effectiveExteriorShadowSizeResponse,
        );
        final shapeToLayer = shape.shapeToGeometry == null
            ? geometryToLayer
            : geometryToLayer.multiplied(shape.shapeToGeometry!);
        for (final shadow in shape.shadows) {
          final extent = math
              .max(
                shadow.spreadRadius +
                    glassShadowBlurSupport(
                      shadow.blurRadius * settings.visibility * scale.blur,
                    ),
                0,
              )
              .toDouble();
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

  double get _surfaceOutset => math.max(
    settings.effectiveContourOffset + settings.effectiveContourWidth * 0.5 + 1,
    0,
  );

  void _paintShadows(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
  ) {
    if (!geometries.any(
      (entry) => entry.$2.shapes.any((shape) => shape.shadows.isNotEmpty),
    )) {
      return;
    }
    final canvas = context.canvas
      ..save()
      ..translate(offset.dx, offset.dy)
      ..saveLayer(_paintBounds, Paint());
    for (final (_, geometry, geometryToLayer) in geometries) {
      for (final shape in geometry.shapes) {
        if (shape.shadows.isEmpty) continue;
        canvas
          ..save()
          ..transform(geometryToLayer.storage);
        if (shape.shapeToGeometry case final transform?) {
          canvas.transform(transform.storage);
        }
        final rect = Offset.zero & shape.renderObject.size;
        final scale = liquidGlassShadowScale(
          shape.renderObject.size,
          settings.effectiveExteriorShadowSizeResponse,
        );
        for (final shadow in shape.shadows) {
          _drawShape(
            canvas,
            shape.shape,
            rect.shift(shadow.offset).inflate(shadow.spreadRadius),
            shadow
                .copyWith(
                  color: shadow.color.withValues(
                    alpha: shadow.color.a * settings.visibility * scale.energy,
                  ),
                  blurRadius:
                      shadow.blurRadius * settings.visibility * scale.blur,
                  blurStyle: BlurStyle.normal,
                )
                .toPaint(),
          );
        }
        canvas.restore();
      }
    }
    final cutout = Paint()..blendMode = BlendMode.dstOut;
    for (final (_, geometry, geometryToLayer) in geometries) {
      for (final shape in geometry.shapes) {
        canvas
          ..save()
          ..transform(geometryToLayer.storage);
        if (shape.shapeToGeometry case final transform?) {
          canvas.transform(transform.storage);
        }
        _drawShape(
          canvas,
          shape.shape,
          (Offset.zero & shape.renderObject.size).deflate(.5),
          cutout,
        );
        canvas.restore();
      }
    }
    canvas
      ..restore()
      ..restore();
  }

  void _drawShape(Canvas canvas, LiquidShape shape, Rect rect, Paint paint) {
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

  void _releaseLayers() {
    _backdropLayer.layer = null;
    _clipLayer.layer = null;
  }

  @override
  void dispose() {
    _repaintAfterCompositingScheduled = false;
    _releaseLayers();
    super.dispose();
  }
}
