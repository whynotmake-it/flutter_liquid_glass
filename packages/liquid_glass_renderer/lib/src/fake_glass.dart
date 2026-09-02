// ignore_for_file: require_trailing_commas

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/glass_shadow.dart';
import 'package:liquid_glass_renderer/src/internal/fake_glass_color.dart';
import 'package:liquid_glass_renderer/src/internal/multi_shader_builder.dart';
import 'package:liquid_glass_renderer/src/internal/optimized_clip.dart';
import 'package:liquid_glass_renderer/src/internal/paint_fake_glass_surface.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_render_scope.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';
import 'package:meta/meta.dart';

/// A lower-cost approximation of [LiquidGlass] without refraction geometry.
///
/// Tint and saturation use one native affine color filter on Impeller and
/// Skia. Each shape renders tint, contour, bevel, and highlight with one
/// lightweight analytic-SDF fragment draw on both backends. Fake shapes inside
/// a [LiquidGlassBlendGroup] remain visually independent; this fallback does
/// not compute smooth-union geometry.
class FakeGlass extends StatelessWidget {
  /// Creates a new [FakeGlass] widget with the given [child], [shape], and
  /// [settings].
  const FakeGlass({
    required this.shape,
    required this.child,
    LiquidGlassSettings this.settings = const LiquidGlassSettings(),
    this.appearance,
    this.shadows = const [],
    this.backdropKey,
    this.useBackdropGroup = false,
    this.backdropHandledByLayer = false,
    super.key,
  }) : inheritVisibility = true;

  /// Creates a new [FakeGlass] widget that takes settings from the nearest
  /// ancestor [LiquidGlassLayer].
  const FakeGlass.inLayer({
    required this.shape,
    required this.child,
    this.appearance,
    this.shadows = const [],
    this.backdropHandledByLayer = false,
    super.key,
  }) : settings = null,
       backdropKey = null,
       useBackdropGroup = false,
       inheritVisibility = true;

  /// Creates an in-layer fallback whose appearance is already resolved.
  @internal
  const FakeGlass.inLayerResolved({
    required this.shape,
    required this.child,
    required this.appearance,
    this.shadows = const [],
    this.backdropHandledByLayer = false,
    super.key,
  }) : settings = null,
       backdropKey = null,
       useBackdropGroup = false,
       inheritVisibility = false;

  static final List<String> _surfaceShaderAssets = [
    ShaderKeys.fakeGlassSurface,
  ];

  /// {@macro liquid_glass_renderer.LiquidGlass.shape}
  final LiquidShape shape;

  /// The settings for the glass effect.
  ///
  /// This path approximates lighting and blur without refraction.
  /// [LiquidGlassSettings.edgeRefraction] and
  /// [LiquidGlassSettings.chromaticAberration] therefore have no effect.
  /// Refraction-only material controls ([LiquidGlassSettings.refractionSpread],
  /// [LiquidGlassSettings.backdropScale],
  /// and [LiquidGlassAppearance.vibrancy]) are likewise ignored. When tint or
  /// saturation already requires a native color filter, transmission gamma is
  /// approximated in that same filter at no additional pass cost. Thickness
  /// only controls the width of the approximate inner light bleed.
  final LiquidGlassSettings? settings;

  /// Color and materialization controls for this shape.
  ///
  /// [FakeGlass.inLayer] inherits the containing layer's default appearance.
  final LiquidGlassAppearance? appearance;

  /// The list of shadows to paint around the glass shape.
  ///
  /// Only outer-equivalent shadows are supported; [BoxShadow.blurStyle] is
  /// ignored. When any shadow has a non-zero [BoxShadow.offset], the glass
  /// shape is cut out of the composed shadow stack so the shadow does not
  /// bleed through the translucent glass body.
  final List<BoxShadow> shadows;

  /// An explicit key used to share backdrop capture work with other effects.
  final BackdropKey? backdropKey;

  /// Whether to use the nearest ancestor [BackdropGroup].
  ///
  /// [backdropKey] takes precedence. This is ignored by [FakeGlass.inLayer],
  /// which inherits the containing [LiquidGlassLayer]'s backdrop policy.
  final bool useBackdropGroup;

  /// Whether an ancestor layer already paints the shared backdrop effect.
  @internal
  final bool backdropHandledByLayer;

  /// Whether to apply the nearest [LiquidGlassVisibility] multiplier.
  @internal
  final bool inheritVisibility;

  /// The child widget that will be displayed inside the glass.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final settings = this.settings ?? LiquidGlassSettings.of(context);
    final renderScope = this.settings == null
        ? LiquidGlassRenderScope.of(context)
        : null;
    final baseAppearance =
        this.appearance ??
        renderScope?.defaultAppearance ??
        const LiquidGlassAppearance();
    final appearance = inheritVisibility
        ? baseAppearance.copyWith(
            visibility:
                baseAppearance.visibility * LiquidGlassVisibility.of(context),
          )
        : baseAppearance;

    final backdropKey = this.settings == null
        ? LiquidGlassRenderScope.of(context).backdropKey
        : this.backdropKey ??
              (useBackdropGroup
                  ? BackdropGroup.of(context)?.backdropKey
                  : null);
    final glow = _maybeFade(
      appearance.visibility,
      GlassGlowLayer(child: child),
    );
    final paintsOwnSurface =
        !(renderScope?.consolidatesFakeSurface ?? false) ||
        !backdropHandledByLayer;
    final allowsSurfaceOutset =
        (renderScope?.consolidatesFakeSurface ?? false) &&
        !backdropHandledByLayer;
    RawFakeGlass buildRawFake(ui.FragmentShader? surfaceShader) => RawFakeGlass(
      shape: shape,
      settings: settings,
      appearance: appearance,
      backdropKey: backdropKey,
      backdropHandledByLayer: backdropHandledByLayer,
      surfaceShader: surfaceShader,
      paintSurface: paintsOwnSurface,
      allowSurfaceOutset: allowsSurfaceOutset,
      child: glow,
    );
    final fake = paintsOwnSurface
        ? MultiShaderBuilder(
            (_, shaders, _) => buildRawFake(shaders.single),
            assetKeys: _surfaceShaderAssets,
            child: buildRawFake(null),
          )
        : buildRawFake(null);
    final clipped = OptimizedClip(
      shape: shape,
      outset: allowsSurfaceOutset ? fakeGlassSurfaceOutset(settings) : 0,
      child: fake,
    );
    if (shadows.isEmpty) return clipped;
    return GlassShadow(
      shape: shape,
      shadows: shadows,
      settings: settings,
      appearanceVisibility: appearance.visibility,
      child: clipped,
    );
  }

  static Widget _maybeFade(double visibility, Widget child) {
    final opacity = visibility.clamp(0.0, 1.0);
    if (opacity >= 1) return child;
    return Opacity(opacity: opacity, child: child);
  }
}

@internal
class RawFakeGlass extends SingleChildRenderObjectWidget {
  const RawFakeGlass({
    required this.shape,
    required super.child,
    this.backdropKey,
    this.backdropHandledByLayer = false,
    this.surfaceShader,
    this.paintSurface = true,
    this.allowSurfaceOutset = false,
    this.settings = const LiquidGlassSettings(),
    this.appearance = const LiquidGlassAppearance(),
    super.key,
  });

  final LiquidShape shape;

  final LiquidGlassSettings settings;

  final LiquidGlassAppearance appearance;

  final BackdropKey? backdropKey;

  final bool backdropHandledByLayer;

  final ui.FragmentShader? surfaceShader;

  final bool paintSurface;

  final bool allowSurfaceOutset;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderFakeGlass(
      shape: shape,
      settings: settings,
      appearance: appearance,
      backdropKey: backdropKey,
      backdropHandledByLayer: backdropHandledByLayer,
      surfaceShader: surfaceShader,
      paintSurface: paintSurface,
      allowSurfaceOutset: allowSurfaceOutset,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    if (renderObject is RenderFakeGlass) {
      renderObject
        ..shape = shape
        ..settings = settings
        ..appearance = appearance
        ..backdropKey = backdropKey
        ..backdropHandledByLayer = backdropHandledByLayer
        ..surfaceShader = surfaceShader
        ..paintSurface = paintSurface
        ..allowSurfaceOutset = allowSurfaceOutset;
    }
  }
}

@visibleForTesting
@internal
class RenderFakeGlass extends RenderProxyBox {
  RenderFakeGlass({
    required this._shape,
    required this._settings,
    required this._appearance,
    required this._backdropKey,
    required this._backdropHandledByLayer,
    required this._surfaceShader,
    required bool paintSurface,
    required this._allowSurfaceOutset,
  }) : _shouldPaintSurface = paintSurface;

  bool _shouldPaintSurface;
  bool get paintSurface => _shouldPaintSurface;
  set paintSurface(bool value) {
    if (_shouldPaintSurface == value) return;
    _shouldPaintSurface = value;
    markNeedsPaint();
  }

  bool _allowSurfaceOutset;
  bool get allowSurfaceOutset => _allowSurfaceOutset;
  set allowSurfaceOutset(bool value) {
    if (_allowSurfaceOutset == value) return;
    _allowSurfaceOutset = value;
    markNeedsPaint();
  }

  LiquidShape _shape;
  LiquidShape get shape => _shape;
  set shape(LiquidShape value) {
    if (_shape == value) return;
    _shape = value;
    markNeedsPaint();
  }

  LiquidGlassSettings _settings;
  LiquidGlassSettings get settings => _settings;
  set settings(LiquidGlassSettings value) {
    if (_settings == value) return;
    _settings = value;
    markNeedsPaint();
  }

  LiquidGlassAppearance _appearance;
  LiquidGlassAppearance get appearance => _appearance;
  set appearance(LiquidGlassAppearance value) {
    if (_appearance == value) return;
    _appearance = value;
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

  bool get _hasBlur =>
      settings.effectiveFrost != 0 && appearance.visibility > 0;

  bool get _hasColorTransfer =>
      appearance.visibility > 0 &&
      (appearance.saturation != 1 || appearance.transmissionGamma != 1);

  bool get _hasBackdropEffect => _hasBlur || _hasColorTransfer;

  bool _backdropHandledByLayer;
  bool get backdropHandledByLayer => _backdropHandledByLayer;
  set backdropHandledByLayer(bool value) {
    if (_backdropHandledByLayer == value) return;
    _backdropHandledByLayer = value;
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  ui.FragmentShader? _surfaceShader;
  ui.FragmentShader? get surfaceShader => _surfaceShader;
  set surfaceShader(ui.FragmentShader? value) {
    if (identical(_surfaceShader, value)) return;
    _surfaceShader = value;
    markNeedsPaint();
  }

  @visibleForTesting
  int debugPaintCount = 0;

  @override
  bool get alwaysNeedsCompositing =>
      _hasBackdropEffect && !backdropHandledByLayer;

  @override
  BackdropFilterLayer? get layer => super.layer as BackdropFilterLayer?;

  @visibleForTesting
  BackdropFilterLayer? get debugBackdropFilterLayer => layer;

  @override
  void paint(PaintingContext context, Offset offset) {
    assert(() {
      debugPaintCount++;
      return true;
    }(), 'Track fake surface paints in debug builds.');
    if (!_hasBackdropEffect || backdropHandledByLayer) {
      // No blur or saturation change — skip the BackdropFilterLayer entirely
      // and just paint the specular highlights and child directly.
      this.layer = null;
      _paintRecordedSurface(context.canvas, offset);
      super.paint(context, offset);
      return;
    }

    final backdropFilter = fakeGlassBackdropFilter(settings, appearance)!;

    final layer = (this.layer ??= BackdropFilterLayer())
      ..filter = backdropFilter
      ..blendMode = BlendMode.srcATop
      ..backdropKey = backdropKey;

    if (allowSurfaceOutset) {
      final localBounds = Offset.zero & size;
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

    context.pushLayer(layer, (context, offset) {
      // If we are on Skia, we need to avoid the raster cache.
      if (!ui.ImageFilter.isShaderFilterSupported) {
        context.setWillChangeHint();
      }

      _paintInnerContent(context, offset);
    }, offset);
  }

  /// Paints content inside the single composed backdrop-filter pass.
  void _paintInnerContent(PaintingContext context, Offset offset) {
    _paintRecordedSurface(context.canvas, offset);
    super.paint(context, offset);
  }

  void _paintRecordedSurface(Canvas canvas, Offset offset) {
    if (!paintSurface) return;
    if (_surfaceShader case final shader?) {
      _paintShaderSurface(canvas, offset, shader);
      return;
    }
    final visibility = appearance.visibility;
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
      ..clipPath(shape.getOuterPath(Offset.zero & size))
      ..drawPaint(Paint()..color = tint)
      ..restore();
  }

  void _paintShaderSurface(
    Canvas canvas,
    Offset offset,
    ui.FragmentShader shader,
  ) {
    canvas
      ..save()
      ..translate(offset.dx, offset.dy);
    if (!allowSurfaceOutset) {
      canvas.clipPath(shape.getOuterPath(Offset.zero & size));
    }
    paintFakeGlassSurface(
      canvas,
      shader: shader,
      size: size,
      shape: shape,
      settings: settings,
      appearance: appearance,
    );
    canvas.restore();
  }
}
