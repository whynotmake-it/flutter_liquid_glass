import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/glass_shadow.dart';
import 'package:liquid_glass_renderer/src/internal/backdrop_capture_debug.dart';
import 'package:liquid_glass_renderer/src/internal/fake_glass_color.dart';
import 'package:liquid_glass_renderer/src/internal/filter_pass_transform.dart';
import 'package:liquid_glass_renderer/src/internal/glass_composition_probe.dart';
import 'package:liquid_glass_renderer/src/internal/paint_fake_glass_surface.dart';
import 'package:liquid_glass_renderer/src/internal/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/internal/retained_glass_clip.dart';
import 'package:liquid_glass_renderer/src/internal/rounded_superellipse_parameters.dart';
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
    this.backdropEdgeShader,
    super.key,
  });

  final GeometryRenderLink link;
  final LiquidGlassSettings settings;
  final LiquidGlassAppearance defaultAppearance;
  final BackdropKey? backdropKey;
  final FragmentShader? surfaceShader;

  /// Anti-aliases the filtered backdrop's silhouette on Impeller; `null`
  /// where the backend has no shader image filters.
  final FragmentShader? backdropEdgeShader;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderConsolidatedFakeGlassLayer(
        devicePixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
        link: link,
        settings: settings,
        defaultAppearance: defaultAppearance,
        backdropKey: backdropKey,
        surfaceShader: surfaceShader,
        backdropEdgeShader: backdropEdgeShader,
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
      ..surfaceShader = surfaceShader
      ..backdropEdgeShader = backdropEdgeShader;
  }
}

@visibleForTesting
@internal
class RenderConsolidatedFakeGlassLayer extends RenderProxyBox
    with TransformTrackingRenderObjectMixin
    implements LiquidGlassLayerRenderObject {
  RenderConsolidatedFakeGlassLayer({
    required this._devicePixelRatio,
    required this._link,
    required this._settings,
    required this._defaultAppearance,
    required this._backdropKey,
    required this._surfaceShader,
    this._backdropEdgeShader,
  });

  double _devicePixelRatio;
  double get devicePixelRatio => _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

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

  LiquidGlassAppearance _defaultAppearance;
  LiquidGlassAppearance get defaultAppearance => _defaultAppearance;
  set defaultAppearance(LiquidGlassAppearance value) {
    if (_defaultAppearance == value) return;
    _defaultAppearance = value;
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

  FragmentShader? _backdropEdgeShader;
  FragmentShader? get backdropEdgeShader => _backdropEdgeShader;
  set backdropEdgeShader(FragmentShader? value) {
    if (identical(_backdropEdgeShader, value)) return;
    _backdropEdgeShader = value;
    _edgeFilter = null;
    markNeedsPaint();
  }

  final _backdropLayer = LayerHandle<BackdropFilterLayer>();
  final _clipLayer = LayerHandle<ClipPathLayer>();
  final _edgeClipLayer = LayerHandle<ClipPathLayer>();
  final _edgeLayer = LayerHandle<BackdropFilterLayer>();

  /// Shares one snapshot between the filtered pass and the edge pass when
  /// the layer has no [backdropKey] of its own.
  final _edgeBackdropKey = BackdropKey();

  /// Fully visible shapes for the edge pass, [_edgeFloatsPerShape] floats
  /// each, or `null` when it cannot express them and the backdrop is clipped
  /// to their path instead.
  List<double>? _edgeShapes;

  /// The filtered pass's clip, just outside the shapes, and the band around
  /// their silhouette that the edge pass restores; in layer coordinates.
  Path? _edgeOutsetPath;
  Path? _edgeInsetPath;
  Path? _edgeBandPath;
  ImageFilter? _edgeFilter;
  List<double>? _edgeFilterMapping;
  final _effectLayer = LayerHandle<OffsetLayer>();
  final _ancestorClips = RetainedGlassClip();

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
  final List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)>
  _cachedClipInputs = [];
  List<int> _cachedClipClasses = const [];
  Rect _paintBounds = Rect.zero;
  bool _repaintAfterCompositingScheduled = false;
  Offset _effectTranslation = Offset.zero;

  @visibleForTesting
  int debugPaintCount = 0;

  @visibleForTesting
  Offset get debugCompositorTranslation => _effectTranslation;

  bool get _hasBlur => settings.effectiveFrost > 0;
  bool get _hasColorTransfer =>
      defaultAppearance.saturation != 1 ||
      defaultAppearance.transmissionGamma != 1 ||
      defaultAppearance.colorModel.faceTransfer(_shortSide) != null;
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

  /// Whether the shared backdrop's silhouette is anti-aliased by the edge
  /// pass instead of the clip path.
  @visibleForTesting
  bool get debugUsesBackdropEdgePass => _edgeLayer.layer != null;

  final List<_FakeGlassPaintStage> _debugLastPaintStages = [];

  @visibleForTesting
  List<String> get debugLastPaintStages =>
      _debugLastPaintStages.map((stage) => stage.name).toList(growable: false);

  // Keep the always-composited tracker as a sibling of the retained glass
  // content, matching the full renderer. Its callback can invalidate the
  // content for the following frame when a descendant transform moves.
  final _compositionProbe = GlassCompositionProbe();
  final _framePoll = FramePollMarker();

  @override
  // ignore: must_call_super
  void paint(PaintingContext context, Offset offset) {
    assert(() {
      debugPaintCount++;
      return true;
    }(), 'Track consolidated fallback paints in debug builds.');
    _setEffectTranslation(Offset.zero);
    context.pushLayer(setUpLayer(offset), (_, _) {}, offset);
    _compositionProbe.paint(
      context,
      offset,
      _paintLayer,
      owner: this,
    );
  }

  @override
  void onTransformChanged() {
    // The clip, backdrop filter, and analytic surface are local to this layer
    // and therefore move with the retained ancestor tree without repainting.
  }

  @override
  void onCompositing() {
    if (!attached) return;
    _compositionProbe.syncOpacity(this);
    _ancestorClips.sync();
    final motion = _pollCompositorTranslation();
    if (motion.translation case final translation?) {
      _setEffectTranslation(translation);
      _syncBackdropEdge();
      return;
    }
    _syncBackdropEdge();
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

  bool _setEffectTranslation(Offset value) {
    if (_sameOffset(_effectTranslation, value)) return false;
    _effectTranslation = value;
    _effectLayer.layer?.offset = value;
    return true;
  }

  void _paintLayer(PaintingContext context, Offset offset) {
    assert(() {
      _debugLastPaintStages.clear();
      return true;
    }(), 'Reset paint-order diagnostics.');
    final geometries = <(RenderLiquidGlassGeometry, GeometryCache, Matrix4)>[];

    link.updatePaintOrder(this);
    _framePoll.markPolled();
    for (final geometryRenderObject in link.shapes) {
      final transformPoll = geometryRenderObject.pollRelativeTransforms(this);
      final geometry = geometryRenderObject.maybeRebuildGeometry();
      final transform = transformPoll.transform;
      if (geometry == null || transform == null) continue;
      geometries.add((geometryRenderObject, geometry, transform));
    }
    assert(
      debugCheckOpacityBetweenShapesAndLayer(this, link.shapes),
      'Warns about an Opacity between a shape and its layer.',
    );

    _ancestorClips.update(
      this,
      geometries.expand(
        (entry) => entry.$2.shapes.map((shape) => shape.renderObject),
      ),
    );
    if (geometries.isEmpty) {
      debugClipBounds = null;
      _paintBounds = super.paintBounds;
      _clearClipCache();
      _releaseLayers();
      paintTrackedChild(context, offset);
      return;
    }

    if (!_clipInputsMatch(geometries)) {
      Rect? rebuiltBounds;
      var rebuiltShortSide = double.infinity;
      final rebuiltPath = Path();
      final rebuiltClasses = <int>[];
      List<double>? rebuiltEdgeShapes = <double>[];
      final rebuiltOutset = Path();
      final rebuiltInset = Path();
      final edgeReach = _edgeReachPixels / devicePixelRatio;
      for (final (_, geometry, transform) in geometries) {
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
            rebuiltEdgeShapes = _appendEdgeShape(
              rebuiltEdgeShapes,
              shape.shape,
              shape.renderObject.size,
              shapeToLayer,
            );
            rebuiltOutset.addPath(
              _edgePath(shape.shape, shapeBounds, edgeReach),
              Offset.zero,
              matrix4: shapeToLayer.storage,
            );
            if (shapeBounds.shortestSide > 2 * edgeReach) {
              rebuiltInset.addPath(
                _edgePath(shape.shape, shapeBounds, -edgeReach),
                Offset.zero,
                matrix4: shapeToLayer.storage,
              );
            }
          }
        }
      }
      if (rebuiltShortSide != _shortSide) {
        _shortSide = rebuiltShortSide;
        _cachedFilter = null;
      }
      _cachedClipPath = rebuiltPath;
      _cachedClipBounds = rebuiltBounds;
      _edgeShapes = rebuiltEdgeShapes;
      _edgeOutsetPath = rebuiltOutset;
      _edgeInsetPath = rebuiltInset;
      _edgeBandPath = null;
      _edgeFilter = null;
      _cachedClipClasses = rebuiltClasses;
      _cachedClipInputs
        ..clear()
        ..addAll(
          geometries.map(
            (entry) => (entry.$1, entry.$2, entry.$3.clone()),
          ),
        );
    }
    final bounds = _cachedClipBounds;
    if (bounds == null) {
      debugClipBounds = null;
      _paintBounds = super.paintBounds;
      _releaseLayers();
      paintTrackedChild(context, offset);
      return;
    }
    final clipPath = _cachedClipPath!;

    debugClipBounds = bounds;
    _paintBounds = _expandForEffects(bounds, geometries);
    assert(() {
      _debugLastPaintStages.add(_FakeGlassPaintStage.shadows);
      return true;
    }(), 'Record shadow composition order.');
    final effectLayer = (_effectLayer.layer ??= OffsetLayer())
      ..offset = _effectTranslation;
    void paintOriginalEffect(PaintingContext context, Offset offset) {
      _ancestorClips.pushLayer(
        context,
        effectLayer,
        (effectContext, effectOffset) {
          _paintShadows(effectContext, effectOffset, geometries);

          if (_hasBackdropEffect) {
            assert(() {
              _debugLastPaintStages.add(_FakeGlassPaintStage.backdrop);
              return true;
            }(), 'Record backdrop composition order.');
            final edgeFilter = _backdropEdgeFilter();
            final key = edgeFilter == null
                ? backdropKey
                : backdropKey ?? _edgeBackdropKey;
            final backdropLayer =
                (_backdropLayer.layer ??= BackdropFilterLayer())
                  ..filter = _cachedFilter ??= _buildBackdropFilter()
                  ..blendMode = BlendMode.srcOver
                  ..backdropKey = key;
            assert(() {
              debugRegisterBackdropCapture(this, key);
              return true;
            }(), 'Count independent backdrop captures in debug builds.');
            final edgeBounds = bounds.inflate(
              _edgeReachPixels / devicePixelRatio,
            );
            _clipLayer.layer = effectContext.pushClipPath(
              true,
              effectOffset,
              edgeFilter == null ? bounds : edgeBounds,
              edgeFilter == null ? clipPath : _edgeOutsetPath!,
              (clipContext, clipOffset) {
                clipContext.pushLayer(backdropLayer, (_, _) {}, clipOffset);
              },
              oldLayer: _clipLayer.layer,
            );
            if (edgeFilter != null) {
              final edgeLayer = (_edgeLayer.layer ??= BackdropFilterLayer())
                ..filter = edgeFilter
                ..blendMode = BlendMode.srcOver
                ..backdropKey = key;
              _edgeClipLayer.layer = effectContext.pushClipPath(
                true,
                effectOffset,
                edgeBounds,
                _edgeBandPath ??= Path.combine(
                  PathOperation.difference,
                  _edgeOutsetPath!,
                  _edgeInsetPath!,
                ),
                (clipContext, clipOffset) {
                  clipContext.pushLayer(edgeLayer, (_, _) {}, clipOffset);
                },
                oldLayer: _edgeClipLayer.layer,
              );
            } else {
              _edgeClipLayer.layer = null;
              _edgeLayer.layer = null;
            }
            _paintFadingBackdrops(effectContext, effectOffset, geometries);
          } else {
            _releaseGlassLayers();
          }

          assert(() {
            _debugLastPaintStages.add(_FakeGlassPaintStage.surfaces);
            return true;
          }(), 'Record layer-owned surface composition order.');
          _paintSurfaces(effectContext.canvas, effectOffset, geometries);
        },
        offset,
      );
    }

    // Foreground remains in its existing render ancestry.
    paintOriginalEffect(context, offset);
    assert(() {
      _debugLastPaintStages.add(_FakeGlassPaintStage.contents);
      return true;
    }(), 'Record normal subtree composition order.');
    paintTrackedChild(context, offset);
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

  bool _clipInputsMatch(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> current,
  ) {
    if (current.length != _cachedClipInputs.length) return false;
    var shapeIndex = 0;
    for (var index = 0; index < current.length; index++) {
      final value = current[index];
      final cached = _cachedClipInputs[index];
      if (!identical(value.$1, cached.$1) ||
          !identical(value.$2, cached.$2) ||
          !_sameTransform(value.$3, cached.$3)) {
        return false;
      }
      for (final shape in value.$2.shapes) {
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

  ({bool needsRepaint, Offset? translation}) _pollCompositorTranslation() {
    final current = link.shapes;
    if (current.isEmpty && _cachedClipInputs.isEmpty) {
      return (needsRepaint: false, translation: Offset.zero);
    }
    if (_framePoll.polledThisFrame &&
        _cachedClipInputs.length == current.length) {
      return (needsRepaint: false, translation: Offset.zero);
    }
    if (_cachedClipInputs.isEmpty ||
        current.length != _cachedClipInputs.length) {
      for (final geometry in current) {
        geometry.pollRelativeTransforms(this);
      }
      return (needsRepaint: true, translation: null);
    }

    Offset? sharedTranslation;
    var canTranslate = true;
    var needsRepaint = false;
    final translated = <RenderLiquidGlassGeometry>[];
    for (var index = 0; index < current.length; index++) {
      final geometry = current[index];
      final cached = _cachedClipInputs[index];
      final wasCurrent = geometry.hasCurrentGeometryCache(cached.$2);
      final poll = geometry.pollRelativeTransforms(this);
      final transform = poll.transform;
      if (poll.selfChanged || poll.childChanged) needsRepaint = true;
      if (!identical(geometry, cached.$1) ||
          !wasCurrent ||
          poll.childChanged ||
          transform == null) {
        canTranslate = false;
        needsRepaint = true;
        continue;
      }

      final translation = _translationDelta(cached.$3, transform);
      if (translation == null) {
        canTranslate = false;
        needsRepaint = true;
        continue;
      }
      if (sharedTranslation == null) {
        sharedTranslation = translation;
      } else if (!_sameOffset(sharedTranslation, translation)) {
        canTranslate = false;
        needsRepaint = true;
      }
      if (poll.selfChanged) translated.add(geometry);
    }

    if (!canTranslate) {
      return (needsRepaint: needsRepaint, translation: null);
    }
    for (final geometry in translated) {
      geometry.acceptCompositorTranslation();
    }
    return (
      needsRepaint: false,
      translation: sharedTranslation ?? Offset.zero,
    );
  }

  static Offset? _translationDelta(Matrix4 before, Matrix4 after) {
    final a = before.storage;
    final b = after.storage;
    for (var index = 0; index < 16; index++) {
      if (index == 12 || index == 13) continue;
      if ((a[index] - b[index]).abs() > 1e-6) return null;
    }
    return Offset(b[12] - a[12], b[13] - a[13]);
  }

  static bool _sameOffset(Offset a, Offset b) =>
      (a.dx - b.dx).abs() <= 1e-6 && (a.dy - b.dy).abs() <= 1e-6;

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
    _edgeShapes = null;
    _edgeOutsetPath = null;
    _edgeInsetPath = null;
    _edgeBandPath = null;
    _edgeFilter = null;
    _cachedClipInputs.clear();
    _cachedClipClasses = const [];
  }

  static const _maxEdgeShapes = 16;
  static const _edgeFloatsPerShape = 24;

  /// Physical pixels between the silhouette and the edge pass's clips. The
  /// coverage ramp spans half a pixel on either side.
  static const _edgeReachPixels = 2.0;

  /// [shape] grown by [outset] logical pixels; the edge pass's two pixels of
  /// slack absorb the difference from an exact offset curve.
  static Path _edgePath(LiquidShape shape, Rect rect, double outset) {
    final grown = rect.inflate(outset);
    Radius grownRadius(double radius) => Radius.circular(
      math.max(math.min(radius, rect.shortestSide / 2) + outset, 0),
    );
    return switch (shape) {
      LiquidOval() => Path()..addOval(grown),
      LiquidRoundedRectangle(:final borderRadius) =>
        Path()
          ..addRRect(RRect.fromRectAndRadius(grown, grownRadius(borderRadius))),
      LiquidRoundedSuperellipse(:final borderRadius) =>
        Path()..addRSuperellipse(
          RSuperellipse.fromRectAndRadius(grown, grownRadius(borderRadius)),
        ),
    };
  }

  /// Appends [shape] to the edge pass's shape data, or returns `null` when
  /// the pass cannot express it.
  static List<double>? _appendEdgeShape(
    List<double>? data,
    LiquidShape shape,
    Size size,
    Matrix4 shapeToLayer,
  ) {
    if (data == null || data.length >= _maxEdgeShapes * _edgeFloatsPerShape) {
      return null;
    }
    final m = shapeToLayer.storage;
    // Only 2D affine placements; perspective has no single inverse basis.
    if (m[3] != 0 || m[7] != 0 || m[15] != 1) return null;
    final determinant = m[0] * m[5] - m[4] * m[1];
    if (determinant.abs() < 1e-9) return null;
    // Inverse of the 2D affine part: layer point -> shape-local point.
    final a = m[5] / determinant;
    final b = -m[4] / determinant;
    final c = -m[1] / determinant;
    final d = m[0] / determinant;
    final tx = -(a * m[12] + b * m[13]);
    final ty = -(c * m[12] + d * m[13]);
    final (type, radius) = switch (shape) {
      LiquidOval() => (0.0, 0.0),
      LiquidRoundedRectangle(:final borderRadius) => (1.0, borderRadius),
      LiquidRoundedSuperellipse(:final borderRadius) => (2.0, borderRadius),
    };
    return data..addAll([
      a, b, c, d, //
      tx - size.width / 2, ty - size.height / 2,
      size.width / 2, size.height / 2, //
      radius, type, math.sqrt((a * d - b * c).abs()), 0,
      if (shape is LiquidRoundedSuperellipse)
        ...roundedSuperellipseParameters(size, radius)
      else
        ...List<double>.filled(12, 0),
    ]);
  }

  /// Maps the edge pass's fragment coordinates (physical pixels of the
  /// enclosing render pass) to this layer's logical coordinates: a 2x2 basis,
  /// an offset, then the layer-space length of one physical pixel. `null`
  /// when the mapping is not invertible.
  List<double>? _edgeMapping() {
    final passToLayer = Matrix4.tryInvert(
      filterPassTransform(
        this,
        seeding: _compositionProbe.seeding,
        devicePixelRatio: devicePixelRatio,
        translation: _effectTranslation,
      ),
    );
    if (passToLayer == null) return null;
    final m = passToLayer.storage;
    final scale = 1 / devicePixelRatio;
    final basis = [m[0] * scale, m[4] * scale, m[1] * scale, m[5] * scale];
    final pixel = math.sqrt((basis[0] * basis[3] - basis[1] * basis[2]).abs());
    return [...basis, m[12], m[13], pixel];
  }

  /// The filter that restores the unfiltered backdrop outside the shapes'
  /// analytic coverage, or `null` when the backdrop is clipped to the shapes'
  /// path instead (Skia, whose clips are anti-aliased, or shapes the pass
  /// cannot express).
  ImageFilter? _backdropEdgeFilter() {
    final shader = _backdropEdgeShader;
    final shapes = _edgeShapes;
    if (shader == null || shapes == null || shapes.isEmpty) return null;
    if (_underOpacity()) return null;
    final mapping = _edgeMapping();
    if (mapping == null) return null;
    if (_edgeFilter != null && listEquals(_edgeFilterMapping, mapping)) {
      return _edgeFilter;
    }
    final pixel = mapping[6];
    shader.setFloatUniforms(initialIndex: 2, (value) {
      value
        ..setFloats(mapping.sublist(0, 6))
        ..setFloat(shapes.length / _edgeFloatsPerShape);
      for (var i = 0; i < shapes.length; i += _edgeFloatsPerShape) {
        value
          ..setFloats(shapes.sublist(i, i + 10))
          ..setFloat(shapes[i + 10] * pixel)
          ..setFloat(0)
          ..setFloats(shapes.sublist(i + 12, i + _edgeFloatsPerShape));
      }
    });
    _edgeFilterMapping = mapping;
    return _edgeFilter = ImageFilter.shader(shader);
  }

  /// Whether an opacity widget sits above this layer. The edge pass shares a
  /// keyed backdrop snapshot, and keyed backdrops inside an opacity pass
  /// escape its fade; a fade can start without repainting this subtree, so
  /// any opacity ancestor keeps the unkeyed path clip.
  bool _underOpacity() {
    for (var node = parent; node != null; node = node.parent) {
      if (node is RenderOpacity ||
          node is RenderAnimatedOpacity ||
          node is RenderSliverOpacity ||
          node is RenderSliverAnimatedOpacity) {
        return true;
      }
    }
    return false;
  }

  /// Keeps the edge pass aligned when retained motion moves this layer
  /// without a repaint.
  void _syncBackdropEdge() {
    final layer = _edgeLayer.layer;
    if (layer == null) return;
    final filter = _backdropEdgeFilter();
    if (filter == null) {
      _repaintAfterCompositing();
      return;
    }
    if (!identical(layer.filter, filter)) layer.filter = filter;
  }

  ImageFilter _buildBackdropFilter() {
    return fakeGlassBackdropFilter(
      settings,
      defaultAppearance,
      shortSide: _shortSide,
    )!;
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
        final shapeToLayer = shape.shapeToGeometry == null
            ? geometryToLayer
            : geometryToLayer.multiplied(shape.shapeToGeometry!);
        for (final shadow in shape.shadows) {
          final extent = math
              .max(
                shadow.spreadRadius +
                    glassShadowBlurSupport(
                      shadow.blurRadius *
                          shape.appearance.visibility.clamp(0.0, 1.0),
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

  double get _surfaceOutset => fakeGlassSurfaceOutset(settings);

  @override
  Rect? get effectBounds {
    final gathered = gatherGlassGeometryBounds(link, this);
    if (gathered == null) return null;
    final (bounds, shapes) = gathered;
    // One extra logical pixel covers the kernel's rounding at any DPR.
    final blur = _hasBlur ? settings.effectiveFrost * 3 + 1 : 0.0;
    return expandForGlassShadows(
      bounds.inflate(_surfaceOutset + blur),
      shapes,
      settings,
    );
  }

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
        final visibility = shape.appearance.visibility.clamp(0.0, 1.0);
        for (final shadow in shape.shadows) {
          _drawShape(
            canvas,
            shape.shape,
            rect.shift(shadow.offset).inflate(shadow.spreadRadius),
            shadow
                .copyWith(
                  color: shadow.color.withValues(
                    alpha: shadow.color.a * visibility,
                  ),
                  blurRadius: shadow.blurRadius * visibility,
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

  void _releaseGlassLayers() {
    _backdropLayer.layer = null;
    _clipLayer.layer = null;
    _edgeClipLayer.layer = null;
    _edgeLayer.layer = null;
    _edgeFilter = null;
    for (final layers in _fadingShapeLayers.values) {
      layers.dispose();
    }
    _fadingShapeLayers.clear();
  }

  void _releaseLayers() {
    _releaseGlassLayers();
    _effectLayer.layer = null;
  }

  @override
  void dispose() {
    _compositionProbe.dispose();
    _ancestorClips.dispose();
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
