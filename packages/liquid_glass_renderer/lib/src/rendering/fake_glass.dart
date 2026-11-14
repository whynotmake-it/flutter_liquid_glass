import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/rendering/backdrop_filter_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/drawn_values.dart';
import 'package:liquid_glass_renderer/src/rendering/fake_glass_color.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_blur.dart';
import 'package:liquid_glass_renderer/src/rendering/live_paint_size.dart';
import 'package:liquid_glass_renderer/src/rendering/paint_fake_glass_surface.dart';

/// Who reads the backdrop and paints the surface of a fake glass shape.
enum FakeGlassRole {
  /// The consolidated fake layer reads the backdrop and paints the surface.
  layerPaints,

  /// The glass reads its backdrop and paints its surface inside a fake
  /// layer, unclipped where the surface reaches past the shape.
  inFakeLayer,

  /// The glass reads its backdrop clipped to the shape and draws its
  /// exterior border as a separate ring.
  standalone,
}

/// Draws one fake glass shape: its backdrop blurred and color filtered and its
/// surface drawn analytically, or only its surface where a fake layer reads the
/// backdrop for it.
class RenderFakeGlass extends RenderProxyBox
    with LivePaintSize, LiquidGlassBackdropFilterHost {
  /// Creates the render object of one fake glass shape.
  RenderFakeGlass({
    required this._devicePixelRatio,
    required this._shape,
    required this._settings,
    required this._appearance,
    required this._role,
    required this._surfaceShader,
  });

  FakeGlassRole _role;

  /// Who reads the backdrop and paints the surface.
  FakeGlassRole get role => _role;
  set role(FakeGlassRole value) {
    if (_role == value) return;
    _role = value;
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  bool get _handledByLayer => _role == FakeGlassRole.layerPaints;

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

  /// The settings it draws with.
  LiquidGlassSettings get settings => _settings;
  set settings(LiquidGlassSettings value) {
    if (_settings == value) return;
    _settings = value;
    markNeedsPaint();
  }

  LiquidGlassAppearance _appearance;

  /// The appearance it draws with.
  LiquidGlassAppearance get appearance => _appearance;
  set appearance(LiquidGlassAppearance value) {
    if (_appearance == value) return;
    _appearance = value;
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  // The appearance as glass of the size it paints at wears it.
  LiquidGlassAppearance get _worn => appearance.at(paintSize);

  bool get _hasBlur =>
      settings.effectiveFrost != 0 && appearance.visibility > 0;

  bool get _hasColorTransfer =>
      appearance.visibility > 0 &&
      (appearance.colorModel.saturation != 1 ||
          appearance.colorModel.transmissionGamma != 1 ||
          appearance.colorModel.parameters != null);

  bool get _hasBackdropEffect => _hasBlur || _hasColorTransfer;

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

  /// How many times it painted, in debug builds.
  @visibleForTesting
  int debugPaintCount = 0;

  @override
  bool get alwaysNeedsCompositing => _hasBackdropEffect && !_handledByLayer;

  @override
  LiquidGlassBackdropFilterLayer? get layer =>
      super.layer as LiquidGlassBackdropFilterLayer?;

  /// The backdrop filter layer it reads its backdrop with, if any.
  @visibleForTesting
  LiquidGlassBackdropFilterLayer? get debugBackdropFilterLayer => layer;

  @override
  Layer? get composedLayer => layer;

  @override
  void paint(PaintingContext context, Offset offset) {
    assert(() {
      debugPaintCount++;
      return true;
    }(), 'Track fake surface paints in debug builds.');
    if (_surfaceShader case final shader?) _surfaceShaders.begin(shader);
    if (!_hasBackdropEffect || _handledByLayer) {
      // The consolidated layer reads the backdrop for this glass, or there is
      // nothing to read: no backdrop layer.
      this.layer = null;
      _paintRecordedSurface(context.canvas, offset);
      if (_paintsBorderRing) {
        _paintBorderRing(context.canvas, offset);
        final localBounds = Offset.zero & paintSize;
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

    final parts = fakeGlassBackdropFilterParts(
      settings,
      _worn,
      deviceScale: devicePixelRatio,
      shapeShortSide: paintSize.shortestSide,
    )!;
    final clip = offset & paintSize;
    final reach = glassBlurReach(parts.sigma);
    final layer = this.layer ??= LiquidGlassBackdropFilterLayer(
      filter: parts.full,
      clip: clip,
      reach: reach,
      devicePixelRatio: devicePixelRatio,
      blendMode: BlendMode.srcATop,
    );
    if (parts.frost case final frost?) {
      layer.frost = frost;
    } else {
      layer.filter = parts.full;
    }
    layer
      ..clip = clip
      ..reach = reach
      ..devicePixelRatio = devicePixelRatio;

    if (_role == FakeGlassRole.inFakeLayer) {
      final localBounds = Offset.zero & paintSize;
      final clipPath = shape.getOuterPath(localBounds);
      context.pushClipPath(
        true,
        offset,
        localBounds,
        clipPath,
        (context, offset) {
          if (!ui.ImageFilter.isShaderFilterSupported) {
            context.setWillChangeHint();
          }
          context.pushLayer(layer, (_, _) {}, offset);
        },
      );
      _paintRecordedSurface(context.canvas, offset);
      context.pushClipPath(
        true,
        offset,
        localBounds,
        clipPath,
        (context, offset) => super.paint(context, offset),
      );
      return;
    }

    void paintBackdropLayer(PaintingContext context, Offset offset) {
      context.pushLayer(layer, (context, offset) {
        // Skia would raster-cache the layer and keep a stale backdrop.
        if (!ui.ImageFilter.isShaderFilterSupported) {
          context.setWillChangeHint();
        }
        _paintRecordedSurface(context.canvas, offset);
        super.paint(context, offset);
      }, offset);
    }

    if (_paintsBorderRing) {
      final localBounds = Offset.zero & paintSize;
      context.pushClipPath(
        true,
        offset,
        localBounds,
        shape.getOuterPath(localBounds),
        paintBackdropLayer,
      );
      _paintBorderRing(context.canvas, offset);
      return;
    }
    paintBackdropLayer(context, offset);
  }

  @override
  void dispose() {
    _surfaceShaders.dispose();
    super.dispose();
  }

  bool get _paintsBorderRing =>
      _role == FakeGlassRole.standalone &&
      _surfaceShader != null &&
      settings.contourWidth > 0;

  /// Draws the analytic surface only outside the silhouette, where the
  /// exterior border lives, without widening the backdrop clip.
  void _paintBorderRing(Canvas canvas, Offset offset) {
    final localBounds = Offset.zero & paintSize;
    final ring = Path.from(shape.getOuterPath(localBounds))
      ..addRect(localBounds.inflate(fakeGlassSurfaceOutset(settings)))
      ..fillType = PathFillType.evenOdd;
    canvas
      ..save()
      ..translate(offset.dx, offset.dy)
      ..clipPath(ring);
    paintFakeGlassSurface(
      canvas,
      shader: _surfaceShaders.next(),
      size: paintSize,
      shape: shape,
      settings: settings,
      appearance: _worn,
      devicePixelRatio: devicePixelRatio,
      exteriorOnly: true,
    );
    canvas.restore();
  }

  void _paintRecordedSurface(Canvas canvas, Offset offset) {
    if (_handledByLayer) return;
    if (_surfaceShader != null) {
      _paintShaderSurface(canvas, offset);
      return;
    }
    final visibility = appearance.visibility.clamp(0.0, 1.0);
    final surfaceTint = appearance.colorModel.approximateSurfaceTint(
      appearance.tint,
    );
    final tint = surfaceTint.withValues(
      alpha: surfaceTint.a * visibility,
    );
    if (tint.a == 0) return;
    canvas
      ..save()
      ..translate(offset.dx, offset.dy)
      ..clipPath(shape.getOuterPath(Offset.zero & paintSize))
      ..drawPaint(Paint()..color = tint)
      ..restore();
  }

  void _paintShaderSurface(Canvas canvas, Offset offset) {
    canvas
      ..save()
      ..translate(offset.dx, offset.dy);
    if (_role != FakeGlassRole.inFakeLayer) {
      canvas.clipPath(shape.getOuterPath(Offset.zero & paintSize));
    }
    paintFakeGlassSurfaceWithHighlight(
      canvas,
      shaders: _surfaceShaders,
      size: paintSize,
      shape: shape,
      settings: settings,
      appearance: _worn,
      devicePixelRatio: devicePixelRatio,
    );
    canvas.restore();
  }
}
