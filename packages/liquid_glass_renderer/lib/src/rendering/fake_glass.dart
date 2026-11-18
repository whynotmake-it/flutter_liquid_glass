import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/rendering/appearance.dart';
import 'package:liquid_glass_renderer/src/rendering/backdrop_filter_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/fake_glass_color.dart';
import 'package:liquid_glass_renderer/src/rendering/full_glass.dart';
import 'package:liquid_glass_renderer/src/rendering/paint_fake_glass_surface.dart';

/// Draws one fake glass shape that stands alone: its backdrop blurred and
/// color filtered inside the shape, its surface drawn analytically and its
/// contour as a ring outside the shape.
class RenderFakeGlass extends RenderProxyBox
    with LiquidGlassBackdropFilterHost {
  /// Creates the render object of one fake glass shape.
  RenderFakeGlass({
    required this._devicePixelRatio,
    required this._shape,
    required this._settings,
    required this._shownAppearance,
    required this._surfaceShader,
  });

  double _devicePixelRatio;

  /// The device pixels per logical pixel it draws at.
  double get devicePixelRatio => _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  LiquidShape _shape;

  /// The shape of the glass.
  LiquidShape get shape => _shape;
  set shape(LiquidShape value) {
    if (_shape == value) return;
    _shape = value;
    markNeedsPaint();
  }

  LiquidGlassSettings _settings;
  late FakeGlassLook _look = FakeGlassLook.of(_settings);

  /// The settings it draws with.
  LiquidGlassSettings get settings => _settings;
  set settings(LiquidGlassSettings value) {
    if (_settings == value) return;
    _settings = value;
    final look = FakeGlassLook.of(value);
    if (look == _look) return;
    _look = look;
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  LiquidGlassAppearance _shownAppearance;

  /// The appearance it draws with ([shownAppearance]): its own or its
  /// layer's, faded.
  LiquidGlassAppearance get shownAppearance => _shownAppearance;
  set shownAppearance(LiquidGlassAppearance value) {
    if (_shownAppearance == value) return;
    _shownAppearance = value;
    _wornAppearance = null;
    _wornByNone = null;
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  // The appearance as glass of the size it paints at wears it.
  WornAppearance get _worn {
    if (_wornAppearance case final worn? when size == _wornAt) return worn;
    _wornAt = size;
    return _wornAppearance = shownAppearance.wear(size);
  }

  WornAppearance? _wornAppearance;
  Size? _wornAt;
  WornAppearance? _wornByNone;

  ui.FragmentShader? _surfaceShader;

  /// The surface shader, or null before it has loaded; without it the surface
  /// is a plain tint.
  ui.FragmentShader? get surfaceShader => _surfaceShader;
  set surfaceShader(ui.FragmentShader? value) {
    if (identical(_surfaceShader, value)) return;
    _surfaceShader = value;
    markNeedsPaint();
  }

  final _surfaceShaders = FakeGlassSurfaceShaders();

  @override
  bool get alwaysNeedsCompositing => fakeGlassReadsBackdrop(
    _look,
    _wornByNone ??= shownAppearance.wornByNone,
  );

  @override
  LiquidGlassBackdropFilterLayer? get layer =>
      super.layer as LiquidGlassBackdropFilterLayer?;

  @override
  LiquidGlassBackdropFilterLayer? get backdropFilterLayer => layer;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_surfaceShader case final shader?) _surfaceShaders.begin(shader);
    final parts = fakeGlassBackdropFilterParts(
      _look,
      _worn,
      devicePixelRatio: devicePixelRatio,
      shapeShortSide: size.shortestSide,
    );
    if (parts == null) {
      this.layer = null;
      _paintRecordedSurface(context.canvas, offset);
      if (_paintsContourRing) {
        _paintContourRing(context.canvas, offset);
        final localBounds = Offset.zero & size;
        context.pushClipPath(
          needsCompositing,
          offset,
          localBounds,
          shape.getOuterPath(localBounds),
          (context, offset) => super.paint(context, offset),
        );
        return;
      }
      super.paint(context, offset);
      return;
    }

    final clip = offset & size;
    final filter = parts.frost ?? LiquidGlassBackdropFilter.image(parts.full);
    final layer =
        (this.layer ??= LiquidGlassBackdropFilterLayer(
            filter: filter,
            clip: clip,
            blendMode: BlendMode.srcATop,
          ))
          ..filter = filter
          ..clip = clip;

    void paintBackdropLayer(PaintingContext context, Offset offset) {
      context.pushLayer(layer, (context, offset) {
        // Skia would raster-cache the layer and keep a stale backdrop.
        if (!FullGlass.shaderFilters) {
          context.setWillChangeHint();
        }
        _paintRecordedSurface(context.canvas, offset);
        super.paint(context, offset);
      }, offset);
    }

    if (_paintsContourRing) {
      final localBounds = Offset.zero & size;
      context.pushClipPath(
        true,
        offset,
        localBounds,
        shape.getOuterPath(localBounds),
        paintBackdropLayer,
      );
      _paintContourRing(context.canvas, offset);
      return;
    }
    paintBackdropLayer(context, offset);
  }

  @override
  void dispose() {
    _surfaceShaders.dispose();
    super.dispose();
  }

  bool get _paintsContourRing =>
      _surfaceShader != null && _look.contourWidth > 0;

  void _paintContourRing(Canvas canvas, Offset offset) {
    canvas
      ..save()
      ..translate(offset.dx, offset.dy);
    paintFakeGlassContourRing(
      canvas,
      shader: _surfaceShaders.next(),
      size: size,
      shape: shape,
      look: _look,
      appearance: _worn,
      devicePixelRatio: devicePixelRatio,
    );
    canvas.restore();
  }

  void _paintRecordedSurface(Canvas canvas, Offset offset) {
    if (_surfaceShader != null) {
      _paintShaderSurface(canvas, offset);
      return;
    }
    final tint = fakeGlassSurfaceTint(_worn);
    if (tint.a == 0) return;
    canvas
      ..save()
      ..translate(offset.dx, offset.dy)
      ..clipPath(shape.getOuterPath(Offset.zero & size))
      ..drawPaint(Paint()..color = tint)
      ..restore();
  }

  void _paintShaderSurface(Canvas canvas, Offset offset) {
    canvas
      ..save()
      ..translate(offset.dx, offset.dy)
      ..clipPath(shape.getOuterPath(Offset.zero & size));
    paintFakeGlassSurfaceWithGlint(
      canvas,
      shaders: _surfaceShaders,
      size: size,
      shape: shape,
      look: _look,
      appearance: _worn,
      devicePixelRatio: devicePixelRatio,
    );
    canvas.restore();
  }
}
