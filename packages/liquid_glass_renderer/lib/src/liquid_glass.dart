// ignore_for_file: avoid_setters_without_getters

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/glass_shadow.dart';
import 'package:liquid_glass_renderer/src/internal/optimized_clip.dart';
import 'package:liquid_glass_renderer/src/internal/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_blend_group.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_render_scope.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';
import 'package:meta/meta.dart';

/// A liquid glass shape.
///
/// To render liquid glass, you probably want to wrap this in a
/// [LiquidGlassLayer], where the glass effect will be rendered.
///
/// This can either create a single shape, or be blended together with other
/// shapes in a parent [LiquidGlassBlendGroup] by using the
/// [LiquidGlass.grouped] constructor.
///
/// If you only need a single shape with its own settings, you can also use the
/// [LiquidGlass.withOwnLayer] constructor, which will create its own
/// [LiquidGlassLayer] internally.
/// Use that for glass that sits on other glass and needs an independent
/// backdrop sample or different settings. The regular constructor also creates
/// an independent sample when nested inside another glass shape, inheriting
/// the containing layer's settings. Siblings still share their parent sample.
///
/// If you don't know whether a [LiquidGlassLayer] ancestor exists, use the
/// [LiquidGlass.auto] constructor. It will render on a parent layer if one is
/// found, or create its own layer otherwise. Place a [LiquidGlassLayer] around
/// chrome (tab bars, toolbars) so sibling `auto` widgets share that sample.
///
/// See the [LiquidGlassLayer] documentation for more information.
class LiquidGlass extends StatelessWidget {
  /// Creates a new [LiquidGlass] with the given [child] and [shape].
  ///
  /// This will expect a parent [LiquidGlassLayer] to be present in the widget
  /// tree, where the liquid glass effect will be rendered.
  const LiquidGlass({
    required this.child,
    required this.shape,
    this.clipBehavior = Clip.hardEdge,
    this.shadows = const [],
    this.appearance,
    super.key,
  }) : grouped = false,
       blendGroupLink = null,
       ownLayerConfig = null,
       _auto = false;

  /// Creates a new [LiquidGlass] that automatically renders on a parent
  /// [LiquidGlassLayer] if one exists, or creates its own layer if not.
  ///
  /// This is useful when you don't know whether a [LiquidGlassLayer] ancestor
  /// is present. If one is found in the widget tree, the glass will render on
  /// that layer. Otherwise, it will create its own layer with the given
  /// [settings] (or default settings if not provided).
  ///
  /// Note that creating many individual layers can be expensive, so prefer
  /// placing a [LiquidGlassLayer] ancestor in the tree when possible. Sibling
  /// [LiquidGlass.auto] widgets under that ancestor share one backdrop sample
  /// and do not blend unless they are also inside a [LiquidGlassBlendGroup].
  /// If another [LiquidGlass] appears before that layer, this creates a new
  /// layer instead so nested glass never renders into the same sample.
  const LiquidGlass.auto({
    required this.child,
    required this.shape,
    LiquidGlassSettings settings = const LiquidGlassSettings(),
    bool fake = false,
    bool useBackdropGroup = false,
    BackdropKey? backdropKey,
    super.key,
    this.clipBehavior = Clip.hardEdge,
    this.shadows = const [],
    this.appearance,
  }) : grouped = true,
       blendGroupLink = null,
       ownLayerConfig = (
         settings: settings,
         fake: fake,
         useBackdropGroup: useBackdropGroup,
         backdropKey: backdropKey,
       ),
       _auto = true;

  /// Creates a new [LiquidGlass] that is part of a [LiquidGlassBlendGroup].
  ///
  /// This will expect a parent [LiquidGlassBlendGroup] to be present in the
  /// widget tree, as well as a parent [LiquidGlassLayer] above that, where the
  /// result will be rendered.
  const LiquidGlass.grouped({
    required this.child,
    required this.shape,
    super.key,
    this.clipBehavior = Clip.hardEdge,
    this.blendGroupLink,
    this.shadows = const [],
    this.appearance,
  }) : ownLayerConfig = null,
       grouped = true,
       _auto = false;

  /// Creates a new [LiquidGlass] that creates its own [LiquidGlassLayer].
  ///
  /// While this might seem convenient, creating many individual layers can be
  /// expensive.
  ///
  /// You should prefer rendering multiple [LiquidGlass] shapes that share the
  /// same settings inside a single [LiquidGlassLayer] for better performance.
  /// This constructor is the right choice when the glass sits on other glass
  /// or needs its own [LiquidGlassSettings].
  const LiquidGlass.withOwnLayer({
    required this.child,
    required this.shape,
    LiquidGlassSettings settings = const LiquidGlassSettings(),
    bool fake = false,
    bool useBackdropGroup = false,
    BackdropKey? backdropKey,
    super.key,
    this.clipBehavior = Clip.hardEdge,
    this.blendGroupLink,
    this.shadows = const [],
    this.appearance,
  }) : ownLayerConfig = (
         settings: settings,
         fake: fake,
         useBackdropGroup: useBackdropGroup,
         backdropKey: backdropKey,
       ),
       grouped = false,
       _auto = false;

  /// The child of this widget.
  ///
  /// Painted above the glass effect and clipped by [clipBehavior].
  final Widget child;

  /// {@template liquid_glass_renderer.LiquidGlass.shape}
  /// The shape of this glass.
  ///
  /// This is the shape of the glass that will be rendered.
  /// {@endtemplate}
  final LiquidShape shape;

  /// The clip behavior of this glass.
  ///
  /// Defaults to [Clip.hardEdge], so [child] is clipped to the glass shape.
  final Clip clipBehavior;

  /// Whether this glass is part of a blend group.
  final bool grouped;

  /// The link to this glass's blend group if it is part of one.
  final GlassGroupLink? blendGroupLink;

  /// The settings for this glass if it is supposed to create its own layer.
  final ({
    LiquidGlassSettings settings,
    bool fake,
    bool useBackdropGroup,
    BackdropKey? backdropKey,
  })?
  ownLayerConfig;

  /// The list of shadows to paint.
  ///
  /// Only outer-equivalent shadows are supported; [BoxShadow.blurStyle] is
  /// ignored. When any shadow has a non-zero [BoxShadow.offset], the glass
  /// shape is cut out of the composed shadow stack so the shadow does not
  /// bleed through the translucent glass body.
  final List<BoxShadow> shadows;

  /// Color and materialization override for this shape.
  ///
  /// Omit this to inherit the containing layer's default appearance.
  final LiquidGlassAppearance? appearance;

  /// Whether this glass should automatically detect a parent layer.
  final bool _auto;

  @override
  Widget build(BuildContext context) {
    // Join an existing sample whenever one is already in the tree. Creating a
    // layer is the fallback, not the default for a row of siblings. A glass
    // ancestor blocks reuse of the layer above it because nested shapes cannot
    // render correctly into the same sample.
    if (_auto &&
        _nearestLiquidGlassBoundary(context) ==
            _LiquidGlassAncestorBoundary.layer) {
      return _buildGlass(context);
    }

    if (ownLayerConfig case final config?) {
      return LiquidGlassLayer(
        settings: config.settings,
        defaultAppearance: appearance,
        fake: config.fake,
        useBackdropGroup: config.useBackdropGroup,
        backdropKey: config.backdropKey,
        child: Builder(builder: _buildGlass),
      );
    }

    if (!grouped &&
        _nearestLiquidGlassBoundary(context) ==
            _LiquidGlassAncestorBoundary.glass) {
      final scope = LiquidGlassRenderScope.of(context);
      // Nested materials need separate backdrop passes. Combining their SDFs
      // makes the inner shape disappear into the outer shape's interior. Keep
      // this pass in the child's real paint ancestry so it inherits the outer
      // shape's clipping and moves with it. Never reuse the outer backdrop key:
      // these materials overlap and the inner must sample the painted outer.
      return LiquidGlassLayer(
        settings: scope.settings,
        defaultAppearance: scope.defaultAppearance,
        fake: scope.useFake || scope.consolidatesFakeBackdrop,
        child: Builder(builder: _buildGlass),
      );
    }

    return _buildGlass(context);
  }

  _LiquidGlassAncestorBoundary _nearestLiquidGlassBoundary(
    BuildContext context,
  ) {
    var result = _LiquidGlassAncestorBoundary.none;
    context.visitAncestorElements((element) {
      result = switch (element.widget) {
        LiquidGlass() => _LiquidGlassAncestorBoundary.glass,
        LiquidGlassLayer() => _LiquidGlassAncestorBoundary.layer,
        _ => _LiquidGlassAncestorBoundary.none,
      };
      return result == _LiquidGlassAncestorBoundary.none;
    });
    return result;
  }

  /// Renders this shape on the nearest [LiquidGlassLayer].
  ///
  /// Grouped constructors join a [LiquidGlassBlendGroup] when one exists.
  /// Otherwise the shape registers directly on the layer so siblings share
  /// one backdrop sample without a dummy blend group.
  Widget _buildGlass(BuildContext context) {
    final scopeSettings = LiquidGlassRenderScope.of(context);
    final baseAppearance = this.appearance ?? scopeSettings.defaultAppearance;
    final appearance = baseAppearance.copyWith(
      visibility: baseAppearance.visibility * LiquidGlassVisibility.of(context),
    );
    if (scopeSettings.useFake) {
      return FakeGlass.inLayerResolved(
        shape: shape,
        appearance: appearance,
        shadows: shadows,
        child: child,
      );
    }

    final groupLink = grouped
        ? blendGroupLink ?? LiquidGlassBlendGroup.maybeOf(context)
        : null;
    return _buildContent(context, groupLink, appearance);
  }

  Widget _buildContent(
    BuildContext context,
    GlassGroupLink? blendGroupLink,
    LiquidGlassAppearance appearance,
  ) {
    final scope = LiquidGlassRenderScope.of(context);
    final settings = scope.settings;

    if (scope.useFake ||
        (!ImageFilter.isShaderFilterSupported &&
            !scope.consolidatesFakeBackdrop)) {
      return FakeGlass.inLayerResolved(
        shape: shape,
        appearance: appearance,
        shadows: shadows,
        child: child,
      );
    }

    final renderLink = blendGroupLink == null
        ? InheritedGeometryRenderLink.of(context)
        : null;

    // One consolidated BackdropFilter cannot represent different opacity for
    // overlapping clips. Keep the zero-cost shared path at stable visibility,
    // but let a transitioning shape composite its backdrop and surface in the
    // same order as the parent layer.
    if (scope.consolidatesFakeBackdrop &&
        appearance.visibility > 0 &&
        appearance.visibility < 1) {
      return FakeGlass.inLayerResolved(
        shape: shape,
        appearance: appearance,
        shadows: shadows,
        child: child,
      );
    }

    final registeredChild = scope.consolidatesFakeBackdrop
        ? FakeGlass.inLayerResolved(
            shape: shape,
            appearance: appearance,
            backdropHandledByLayer: true,
            child: child,
          )
        : OptimizedClip(
            shape: shape,
            clipBehavior: clipBehavior,
            child: _maybeFade(
              appearance.visibility,
              GlassGlowLayer(
                child: child,
              ),
            ),
          );
    final content = _RawLiquidGlass(
      blendGroupLink: blendGroupLink,
      renderLink: renderLink,
      settings: settings,
      appearance: appearance,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      shape: shape,
      layerShadows: scope.consolidatesFakeBackdrop || blendGroupLink != null
          ? shadows
          : const [],
      child: registeredChild,
    );
    if (shadows.isEmpty ||
        blendGroupLink != null ||
        scope.consolidatesFakeBackdrop) {
      return content;
    }
    return GlassShadow(
      settings: settings,
      appearanceVisibility: appearance.visibility,
      shape: shape,
      shadows: shadows,
      child: content,
    );
  }

  static Widget _maybeFade(double visibility, Widget child) {
    final opacity = visibility.clamp(0.0, 1.0);
    if (opacity >= 1) return child;
    return Opacity(opacity: opacity, child: child);
  }
}

enum _LiquidGlassAncestorBoundary { none, glass, layer }

class _RawLiquidGlass extends SingleChildRenderObjectWidget {
  const _RawLiquidGlass({
    required super.child,
    required this.shape,
    required this.layerShadows,
    required this.blendGroupLink,
    required this.renderLink,
    required this.settings,
    required this.appearance,
    required this.devicePixelRatio,
  });

  final LiquidShape shape;

  final List<BoxShadow> layerShadows;

  final GlassGroupLink? blendGroupLink;

  final GeometryRenderLink? renderLink;

  final LiquidGlassSettings settings;

  final LiquidGlassAppearance appearance;

  final double devicePixelRatio;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderLiquidGlass(
      shape: shape,
      layerShadows: layerShadows,
      blendGroupLink: blendGroupLink,
      renderLink: renderLink,
      settings: settings,
      appearance: appearance,
      devicePixelRatio: devicePixelRatio,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLiquidGlass renderObject,
  ) {
    renderObject
      ..shape = shape
      ..layerShadows = layerShadows
      ..settings = settings
      ..appearance = appearance
      ..devicePixelRatio = devicePixelRatio
      ..bindLinks(
        blendGroupLink: blendGroupLink,
        renderLink: renderLink,
      );
  }
}

@internal
class RenderLiquidGlass extends RenderLiquidGlassGeometry
    with LiquidGlassShapeRenderObject {
  RenderLiquidGlass({
    required this._shape,
    required this._layerShadows,
    required super.settings,
    required this._appearance,
    required super.devicePixelRatio,
    this._blendGroupLink,
    super.renderLink,
  });

  LiquidGlassAppearance _appearance;
  @override
  LiquidGlassAppearance get appearance => _appearance;
  set appearance(LiquidGlassAppearance value) {
    if (_appearance == value) return;
    _appearance = value;
    // Refresh material metadata without invalidating an unchanged shape. The
    // owning layer decides whether its material texture also needs updating.
    markGeometryNeedsUpdate();
    _blendGroupLink?.notifyShapeLayoutChanged(this);
    markNeedsPaint();
  }

  LiquidShape _shape;

  LiquidShape get shape => _shape;
  set shape(LiquidShape value) {
    if (_shape == value) return;
    _shape = value;
    markNeedsPaint();
    _onShapeConfigurationChanged();
  }

  List<BoxShadow> _layerShadows;
  @override
  List<BoxShadow> get layerShadows => _layerShadows;
  set layerShadows(List<BoxShadow> value) {
    if (_layerShadows == value) return;
    _layerShadows = value;
    _blendGroupLink?.notifyShapeLayoutChanged(this);
    markNeedsPaint();
  }

  GlassGroupLink? _blendGroupLink;

  /// Registers this shape with either a blend group or the parent layer.
  ///
  /// A shape is never in both: grouped glass is packed by the blend group,
  /// standalone glass is its own geometry node on the layer.
  void bindLinks({
    GlassGroupLink? blendGroupLink,
    GeometryRenderLink? renderLink,
  }) {
    if (blendGroupLink != null) {
      this.renderLink = null;
      _setBlendGroupLink(blendGroupLink);
    } else {
      _setBlendGroupLink(null);
      this.renderLink = renderLink;
    }
  }

  void _setBlendGroupLink(GlassGroupLink? value) {
    if (_blendGroupLink == value) return;
    _unregisterFromBlendGroup();
    _blendGroupLink = value;
    _registerWithBlendGroup();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _registerWithBlendGroup();
  }

  @override
  void detach() {
    _unregisterFromBlendGroup();
    super.detach();
  }

  void _registerWithBlendGroup() {
    _blendGroupLink?.registerShape(
      this,
      _shape,
    );
  }

  void _unregisterFromBlendGroup() {
    _blendGroupLink?.unregisterShape(this);
  }

  void _onShapeConfigurationChanged() {
    if (_blendGroupLink != null) {
      _blendGroupLink!.updateShape(
        this,
        _shape,
      );
    } else {
      markGeometryNeedsUpdate(force: true);
    }
  }

  late Path _lastPath;

  @override
  void performLayout() {
    super.performLayout();
    _lastPath = shape.getOuterPath(Offset.zero & size);
    if (_blendGroupLink != null) {
      _blendGroupLink!.notifyShapeLayoutChanged(this);
    } else {
      // A child opacity layer can trigger layout without changing our size.
      // gatherShapeData compares the shape bounds before reusing the matte.
      markGeometryNeedsUpdate();
    }
  }

  @override
  Path shapePath() => _lastPath;

  @override
  double get geometryBlend => 0;

  @override
  (Rect, List<ShapeGeometry>, bool) gatherShapeData() {
    if (!hasSize) {
      return (Rect.zero, const [], false);
    }

    final shapeData = ShapeGeometry(
      renderObject: this,
      shape: shape,
      appearance: appearance,
      shapeBounds: Offset.zero & size,
      shadows: layerShadows,
    );
    final cached = geometry?.shapes ?? const <ShapeGeometry>[];
    final changed =
        cached.length != 1 ||
        cached.first.shapeBounds != shapeData.shapeBounds ||
        cached.first.shape != shapeData.shape;

    return (shapeData.shapeBounds, [shapeData], changed);
  }
}
