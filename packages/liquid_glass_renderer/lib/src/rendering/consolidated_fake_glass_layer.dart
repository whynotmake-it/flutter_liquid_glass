import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/backdrop_capture_debug.dart';
import 'package:liquid_glass_renderer/src/internal/fake_glass_color.dart';
import 'package:liquid_glass_renderer/src/internal/paint_fake_glass_surface.dart';
import 'package:liquid_glass_renderer/src/internal/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/internal/transform_tracking_repaint_boundary_mixin.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';

enum _FakeGlassPaintStage {
  shadows,
  backdrop,
  surfaces,
  contents,
}

@internal
class ConsolidatedFakeGlassLayer extends SingleChildRenderObjectWidget {
  const ConsolidatedFakeGlassLayer({
    required this.link,
    required this.settings,
    required this.defaultAppearance,
    required this.backdropKey,
    required this.surfaceShader,
    required super.child,
    super.key,
  });

  final GeometryRenderLink link;
  final LiquidGlassSettings settings;
  final LiquidGlassAppearance defaultAppearance;
  final BackdropKey? backdropKey;
  final FragmentShader? surfaceShader;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderConsolidatedFakeGlassLayer(
        devicePixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
        link: link,
        settings: settings,
        defaultAppearance: defaultAppearance,
        backdropKey: backdropKey,
        surfaceShader: surfaceShader,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderConsolidatedFakeGlassLayer renderObject,
  ) {
    renderObject
      ..devicePixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1
      ..link = link
      ..settings = settings
      ..defaultAppearance = defaultAppearance
      ..backdropKey = backdropKey
      ..surfaceShader = surfaceShader;
  }
}

/// The fake glass layer: paints a clipped backdrop blur plus the surface
/// shader for the shared shape geometry. All shared machinery — shape
/// registration, transform and compositor-translation polling, retained
/// ancestor clips, shadows, bounds and the frame state — lives in
/// [LiquidGlassRenderObject]; this class implements only the effect.
@visibleForTesting
@internal
class RenderConsolidatedFakeGlassLayer extends LiquidGlassRenderObject
    with TransformTrackingRenderObjectMixin
    implements LiquidGlassLayerRenderObject {
  RenderConsolidatedFakeGlassLayer({
    required super.devicePixelRatio,
    required super.link,
    required super.settings,
    required super.defaultAppearance,
    required super.backdropKey,
    required this._surfaceShader,
  });

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

  /// Per-shape blur passes for shapes that are fading (0 < visibility < 1).
  /// They sit between the shared opaque-shape blur and the surfaces so a
  /// fading shape keeps its own clipped backdrop filter instead of swapping
  /// its widget subtree.
  final Map<LiquidGlassShapeRenderObject, _FadingShapeLayers>
  _fadingShapeLayers = {};
  ImageFilter? _cachedFilter;

  /// Shorter side of the smallest shape sharing the consolidated filter.
  double _shortSide = 10000;
  Path? _cachedClipPath;
  Rect? _cachedClipBounds;
  List<int> _cachedClipClasses = const [];
  bool _repaintAfterCompositingScheduled = false;

  bool get _hasBlur => settings.effectiveFrost > 0;
  bool get _hasColorTransfer =>
      defaultAppearance.saturation != 1 ||
      defaultAppearance.transmissionGamma != 1 ||
      defaultAppearance.colorModel.faceTransfer(_shortSide) != null;
  bool get _hasBackdropEffect => _hasBlur || _hasColorTransfer;

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

  // MARK: Retained frame hooks

  // The fake effect encodes no matte, so a fully-hidden frame retains
  // nothing that must stay compositor-only.
  @override
  GlassFrameState get hiddenFrameState => GlassFrameState.empty;

  // Without a matte, every shape is drawable.
  @override
  bool hasDrawableGlass(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
  ) => true;

  @override
  bool isSnapshotCurrent(
    RenderLiquidGlassGeometry geometry,
    GeometryCache snapshot,
  ) => geometry.hasCurrentGeometryCache(snapshot);

  @override
  double get materialOutset => fakeGlassSurfaceOutset(settings);

  // One extra logical pixel covers the kernel's rounding at any DPR.
  @override
  double effectSamplingReach(Rect material) =>
      _hasBlur ? settings.effectiveFrost * 3 + 1 : 0.0;

  @override
  void onSettingsChanged(LiquidGlassSettings old) {
    _cachedFilter = null;
    markNeedsCompositingBitsUpdate();
  }

  @override
  void onAppearanceChanged() {
    _cachedFilter = null;
    markNeedsCompositingBitsUpdate();
  }

  // MARK: Painting

  @override
  void paintFrame(
    PaintingContext context,
    Offset offset,
    Rect? geometryBounds,
  ) {
    assert(() {
      _debugLastPaintStages.clear();
      return true;
    }(), 'Reset paint-order diagnostics.');
    if (frameState == GlassFrameState.empty && shapesWithGeometry.isEmpty) {
      debugClipBounds = null;
      effectPaintBounds = Offset.zero & size;
      _clearClipCache();
      clearFrameInputs();
      _releaseLayers();
      return;
    }

    if (!_clipInputsMatch()) {
      Rect? rebuiltBounds;
      var rebuiltShortSide = double.infinity;
      final rebuiltPath = Path();
      final rebuiltClasses = <int>[];
      for (final (_, geometry, transform) in shapesWithGeometry) {
        for (final shape in geometry.shapes) {
          final visibilityClass = _visibilityClass(shape.appearance);
          rebuiltClasses.add(visibilityClass);
          if (visibilityClass == 0) continue;
          final shapeToLayer = shape.shapeToGeometry == null
              ? transform
              : transform.multiplied(shape.shapeToGeometry!);
          final shapeBounds = Offset.zero & shape.renderObject.size;
          rebuiltShortSide = math.min(
            rebuiltShortSide,
            shape.renderObject.size.shortestSide,
          );
          final transformedBounds = MatrixUtils.transformRect(
            shapeToLayer,
            shapeBounds,
          );
          rebuiltBounds =
              rebuiltBounds?.expandToInclude(transformedBounds) ??
              transformedBounds;
          // The shared union clip covers only fully visible shapes; a fading
          // shape gets its own clipped blur pass below.
          if (visibilityClass == 2) {
            rebuiltPath.addPath(
              shape.shape.getOuterPath(shapeBounds),
              Offset.zero,
              matrix4: shapeToLayer.storage,
            );
          }
        }
      }
      if (rebuiltShortSide != _shortSide) {
        _shortSide = rebuiltShortSide;
        _cachedFilter = null;
      }
      _cachedClipPath = rebuiltPath;
      _cachedClipBounds = rebuiltBounds;
      _cachedClipClasses = rebuiltClasses;
      rememberFrameInputs();
    }
    final bounds = _cachedClipBounds;
    if (bounds == null) {
      debugClipBounds = null;
      effectPaintBounds = Offset.zero & size;
      _releaseLayers();
      return;
    }
    final clipPath = _cachedClipPath!;

    debugClipBounds = bounds;
    effectPaintBounds = expandEffectBounds(bounds);
    assert(() {
      _debugLastPaintStages.add(_FakeGlassPaintStage.shadows);
      return true;
    }(), 'Record shadow composition order.');
    paintRetainedEffect(context, offset, (effectContext, effectOffset) {
      drawGlassShadows(effectContext.canvas, effectOffset);

      if (_hasBackdropEffect) {
        assert(() {
          _debugLastPaintStages.add(_FakeGlassPaintStage.backdrop);
          return true;
        }(), 'Record backdrop composition order.');
        final backdropLayer = (_backdropLayer.layer ??= BackdropFilterLayer())
          ..filter = _cachedFilter ??= _buildBackdropFilter()
          ..blendMode = BlendMode.srcOver
          ..backdropKey = backdropKey;
        assert(() {
          debugRegisterBackdropCapture(this, backdropKey);
          return true;
        }(), 'Count independent backdrop captures in debug builds.');
        _clipLayer.layer = effectContext.pushClipPath(
          true,
          effectOffset,
          bounds,
          clipPath,
          (clipContext, clipOffset) {
            clipContext.pushLayer(backdropLayer, (_, _) {}, clipOffset);
          },
          oldLayer: _clipLayer.layer,
        );
        _paintFadingBackdrops(
          effectContext,
          effectOffset,
          shapesWithGeometry,
        );
      } else {
        _releaseGlassLayers();
      }

      assert(() {
        _debugLastPaintStages.add(_FakeGlassPaintStage.surfaces);
        return true;
      }(), 'Record layer-owned surface composition order.');
      _paintSurfaces(effectContext.canvas, effectOffset, shapesWithGeometry);
    });
    assert(() {
      _debugLastPaintStages.add(_FakeGlassPaintStage.contents);
      return true;
    }(), 'Record normal subtree composition order.');
  }

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
          appearance: shape.appearance,
          devicePixelRatio: devicePixelRatio,
        );
        canvas.restore();
      }
    }
  }

  /// Paints each fading shape's own clipped backdrop filter so its blur fades
  /// independently while the shape stays registered with this layer. Layers
  /// are retained across frames keyed by the shape's render object; entries
  /// for shapes that stopped fading are released.
  void _paintFadingBackdrops(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
  ) {
    final active = <LiquidGlassShapeRenderObject>{};
    for (final (_, geometry, geometryToLayer) in geometries) {
      for (final shape in geometry.shapes) {
        if (_visibilityClass(shape.appearance) != 1) continue;
        // The shared filter of fully visible shapes applies the layer's
        // backdrop transfer, so a shape leaving it keeps that transfer.
        final filter = fakeGlassBackdropFilter(
          settings,
          defaultAppearance.copyWith(visibility: shape.appearance.visibility),
          shortSide: shape.renderObject.size.shortestSide,
        );
        if (filter == null) continue;
        final renderObject = shape.renderObject;
        active.add(renderObject);
        final layers = _fadingShapeLayers.putIfAbsent(
          renderObject,
          _FadingShapeLayers.new,
        );
        final backdropLayer = (layers.backdrop.layer ??= BackdropFilterLayer())
          ..filter = filter
          ..blendMode = BlendMode.srcOver
          ..backdropKey = backdropKey;
        assert(() {
          debugRegisterBackdropCapture(this, backdropKey);
          return true;
        }(), 'Count independent backdrop captures in debug builds.');
        final shapeToLayer = shape.shapeToGeometry == null
            ? geometryToLayer
            : geometryToLayer.multiplied(shape.shapeToGeometry!);
        final shapeBounds = Offset.zero & renderObject.size;
        layers.clip.layer = context.pushClipPath(
          true,
          offset,
          MatrixUtils.transformRect(shapeToLayer, shapeBounds),
          shape.shape.getOuterPath(shapeBounds).transform(shapeToLayer.storage),
          (clipContext, clipOffset) {
            clipContext.pushLayer(backdropLayer, (_, _) {}, clipOffset);
          },
          oldLayer: layers.clip.layer,
        );
      }
    }
    for (final renderObject in _fadingShapeLayers.keys.toList()) {
      if (active.contains(renderObject)) continue;
      _fadingShapeLayers.remove(renderObject)!.dispose();
    }
  }

  bool _clipInputsMatch() {
    if (!encodedInputsMatch(shapesWithGeometry)) return false;
    var shapeIndex = 0;
    for (final (_, geometry, _) in shapesWithGeometry) {
      for (final shape in geometry.shapes) {
        if (shapeIndex >= _cachedClipClasses.length ||
            _cachedClipClasses[shapeIndex] !=
                _visibilityClass(shape.appearance)) {
          return false;
        }
        shapeIndex++;
      }
    }
    return shapeIndex == _cachedClipClasses.length;
  }

  /// 0: hidden, 1: fading (needs its own clipped blur), 2: fully visible
  /// (covered by the shared union clip).
  static int _visibilityClass(LiquidGlassAppearance appearance) {
    final visibility = appearance.visibility.clamp(0.0, 1.0);
    return visibility <= 0 ? 0 : (visibility >= 1 ? 2 : 1);
  }

  void _clearClipCache() {
    _cachedClipPath = null;
    _cachedClipBounds = null;
    _cachedClipClasses = const [];
  }

  ImageFilter _buildBackdropFilter() {
    return fakeGlassBackdropFilter(
      settings,
      defaultAppearance,
      shortSide: _shortSide,
    )!;
  }

  // MARK: Compositing

  @override
  void onTransformChanged() {
    // The clip, backdrop filter, and analytic surface are local to this layer
    // and therefore move with the retained ancestor tree without repainting.
  }

  @override
  void onCompositing() {
    if (!attached) return;
    runCompositorPoll();
  }

  @override
  void onCompositorTranslationMissed(
    ({bool needsRepaint, Offset? translation}) motion,
  ) {
    if (motion.needsRepaint) _repaintAfterCompositing();
  }

  // The retained layers of this frame are already in the scene.
  void _repaintAfterCompositing() {
    if (_repaintAfterCompositingScheduled) return;
    _repaintAfterCompositingScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _repaintAfterCompositingScheduled = false;
      if (attached) markNeedsPaint();
    });
  }

  void _releaseGlassLayers() {
    _backdropLayer.layer = null;
    _clipLayer.layer = null;
    for (final layers in _fadingShapeLayers.values) {
      layers.dispose();
    }
    _fadingShapeLayers.clear();
  }

  void _releaseLayers() {
    _releaseGlassLayers();
    releaseRetainedEffectLayer();
  }

  @override
  void dispose() {
    _repaintAfterCompositingScheduled = false;
    _releaseLayers();
    super.dispose();
  }
}

/// Retained layer handles for one fading shape's clipped backdrop pass.
class _FadingShapeLayers {
  final clip = LayerHandle<ClipPathLayer>();
  final backdrop = LayerHandle<BackdropFilterLayer>();

  void dispose() {
    clip.layer = null;
    backdrop.layer = null;
  }
}
