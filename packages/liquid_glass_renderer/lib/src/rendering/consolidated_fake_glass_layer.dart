import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/glass_shadow.dart';
import 'package:liquid_glass_renderer/src/internal/fake_glass_color.dart';
import 'package:liquid_glass_renderer/src/internal/glass_composition_probe.dart';
import 'package:liquid_glass_renderer/src/internal/paint_fake_glass_surface.dart';
import 'package:liquid_glass_renderer/src/internal/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/internal/retained_glass_clip.dart';
import 'package:liquid_glass_renderer/src/internal/retained_glass_opacity_probe.dart';
import 'package:liquid_glass_renderer/src/internal/snap_rect_to_pixels.dart';
import 'package:liquid_glass_renderer/src/internal/transform_tracking_repaint_boundary_mixin.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';
import 'package:meta/meta.dart';

part 'independent_fake_glass_opacity.dart';

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
      ..link = link
      ..settings = settings
      ..defaultAppearance = defaultAppearance
      ..backdropKey = backdropKey
      ..surfaceShader = surfaceShader;
  }
}

@visibleForTesting
@internal
class RenderConsolidatedFakeGlassLayer extends RenderProxyBox
    with TransformTrackingRenderObjectMixin
    implements LiquidGlassLayerRenderObject {
  RenderConsolidatedFakeGlassLayer({
    required this._link,
    required this._settings,
    required this._defaultAppearance,
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

  final _backdropLayer = LayerHandle<BackdropFilterLayer>();
  final _clipLayer = LayerHandle<ClipPathLayer>();
  final _effectLayer = LayerHandle<OffsetLayer>();
  final _ancestorClips = RetainedGlassClip();
  final _independentOpacity = LayerHandle<_IndependentFakeOpacityLayer>();
  ImageFilter? _cachedFilter;
  Path? _cachedClipPath;
  Rect? _cachedClipBounds;
  final List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)>
  _cachedClipInputs = [];
  Rect _paintBounds = Rect.zero;
  bool _repaintAfterCompositingScheduled = false;
  Offset _effectTranslation = Offset.zero;

  @visibleForTesting
  int debugPaintCount = 0;

  @visibleForTesting
  int get debugIndependentPassRecordCount =>
      _independentOpacity.layer?.debugRecordedPassCount ?? 0;

  @visibleForTesting
  int get debugIndependentPassCount =>
      _independentOpacity.layer?._passes.length ?? 0;

  @visibleForTesting
  Offset get debugCompositorTranslation => _effectTranslation;

  bool get _hasBlur => settings.effectiveFrost > 0;
  bool get _hasColorTransfer =>
      defaultAppearance.saturation != 1 ||
      defaultAppearance.transmissionGamma != 1;
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
  final _compositionProbe = GlassCompositionProbe();

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
      _independentOpacity.layer?.sync(translation);
      return;
    }
    _independentOpacity.layer?.sync(_effectTranslation);
    if (!motion.needsRepaint || _repaintAfterCompositingScheduled) return;
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
    for (final geometryRenderObject in link.shapes) {
      final transformPoll = geometryRenderObject.pollRelativeTransforms(this);
      final geometry = geometryRenderObject.maybeRebuildGeometry();
      final transform = transformPoll.transform;
      if (geometry == null || transform == null) continue;
      geometries.add((geometryRenderObject, geometry, transform));
    }

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
      final rebuiltPath = Path();
      for (final (_, geometry, transform) in geometries) {
        for (final shape in geometry.shapes) {
          if (shape.appearance.visibility <= 0) continue;
          final shapeToLayer = shape.shapeToGeometry == null
              ? transform
              : transform.multiplied(shape.shapeToGeometry!);
          final shapeBounds = Offset.zero & shape.renderObject.size;
          final transformedBounds = MatrixUtils.transformRect(
            shapeToLayer,
            shapeBounds,
          );
          rebuiltBounds =
              rebuiltBounds?.expandToInclude(transformedBounds) ??
              transformedBounds;
          rebuiltPath.addPath(
            shape.shape.getOuterPath(shapeBounds),
            Offset.zero,
            matrix4: shapeToLayer.storage,
          );
        }
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
    final bounds = _cachedClipBounds;
    if (bounds == null) {
      debugClipBounds = null;
      _paintBounds = super.paintBounds;
      _releaseLayers();
      paintTrackedChild(context, offset);
      return;
    }
    final clipPath = _cachedClipPath!;
    const nestBackdropContents = bool.fromEnvironment('NEST_GLASS_CONTENTS');

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
            final filter = _cachedFilter ??= _buildBackdropFilter();
            final backdropLayer =
                (_backdropLayer.layer ??= BackdropFilterLayer())
                  ..filter = filter
                  ..blendMode = BlendMode.srcOver
                  ..backdropKey = backdropKey;
            _clipLayer.layer = effectContext.pushClipPath(
              true,
              effectOffset,
              bounds,
              clipPath,
              (clipContext, clipOffset) {
                if (nestBackdropContents) {
                  clipContext.pushLayer(backdropLayer, (context, offset) {
                    _paintSurfaces(context.canvas, offset, geometries);
                    paintTrackedChild(context, offset);
                  }, clipOffset);
                  return;
                }
                clipContext.pushLayer(backdropLayer, (_, _) {}, clipOffset);
              },
              oldLayer: _clipLayer.layer,
            );
          } else {
            _releaseGlassLayers();
          }

          assert(() {
            _debugLastPaintStages.add(_FakeGlassPaintStage.surfaces);
            return true;
          }(), 'Record layer-owned surface composition order.');
          if (!nestBackdropContents || !_hasBackdropEffect) {
            _paintSurfaces(effectContext.canvas, effectOffset, geometries);
          }
        },
        offset,
      );
    }

    // Foreground remains in its existing render ancestry.
    if (const bool.fromEnvironment(
          'INDEPENDENT_GLASS_OPACITY',
          defaultValue: true,
        ) &&
        !nestBackdropContents) {
      final selector =
          (_independentOpacity.layer ??= _IndependentFakeOpacityLayer())
            ..prepare(this, geometries, offset);
      context.pushLayer(selector, (context, offset) {
        // The common-opacity replay in _ancestorClips belongs ONLY to the
        // original branch. Subset branches replace it, not sit inside it.
        context.pushLayer(selector.original, paintOriginalEffect, offset);
      }, offset);
    } else {
      _independentOpacity.layer = null;
      paintOriginalEffect(context, offset);
    }
    assert(() {
      _debugLastPaintStages.add(_FakeGlassPaintStage.contents);
      return true;
    }(), 'Record normal subtree composition order.');
    if (!nestBackdropContents || !_hasBackdropEffect) {
      paintTrackedChild(context, offset);
    }
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

  ({bool needsRepaint, Offset? translation}) _pollCompositorTranslation() {
    final current = link.shapes;
    if (current.isEmpty && _cachedClipInputs.isEmpty) {
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
    _cachedClipInputs.clear();
  }

  ImageFilter _buildBackdropFilter() {
    return fakeGlassBackdropFilter(settings, defaultAppearance)!;
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
                      shadow.blurRadius *
                          shape.appearance.visibility.clamp(0.0, 1.0) *
                          scale.blur,
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
        final visibility = shape.appearance.visibility.clamp(0.0, 1.0);
        for (final shadow in shape.shadows) {
          _drawShape(
            canvas,
            shape.shape,
            rect.shift(shadow.offset).inflate(shadow.spreadRadius),
            shadow
                .copyWith(
                  color: shadow.color.withValues(
                    alpha: shadow.color.a * visibility * scale.energy,
                  ),
                  blurRadius: shadow.blurRadius * visibility * scale.blur,
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
  }

  void _releaseLayers() {
    _independentOpacity.layer = null;
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
