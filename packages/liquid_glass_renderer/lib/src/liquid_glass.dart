// ignore_for_file: avoid_setters_without_getters

import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/optimized_clip.dart';
import 'package:liquid_glass_renderer/src/internal/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_blend_group.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_render_scope.dart';
import 'package:liquid_glass_renderer/src/precache.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';

/// One frame of a live [LiquidGlass]: its geometry, material and shadows.
@immutable
class LiquidGlassShapeFrame {
  /// Describes one frame of a shape.
  const LiquidGlassShapeFrame({
    required this.shape,
    this.appearance,
    this.shadows = const [],
  });

  /// See [LiquidGlass.shape].
  final LiquidShape shape;

  /// See [LiquidGlass.appearance].
  final LiquidGlassAppearance? appearance;

  /// See [LiquidGlass.shadows].
  final List<BoxShadow> shadows;
}

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
///
/// ## Transforms
///
/// The glass follows the shape's layout position and transforms applied by
/// widgets like [Transform] or [RotatedBox]. Transforms applied only to the
/// paint canvas — e.g. by a [Flow] delegate or a
/// `PaintingContext.pushTransform` call that does not push a composited
/// layer — are invisible to the glass: the [child] will transform but the
/// glass stays behind. In those cases, apply the transform with a widget
/// like [Transform] instead.
class LiquidGlass extends StatefulWidget {
  /// Creates a new [LiquidGlass] with the given [child] and [shape].
  ///
  /// This will expect a parent [LiquidGlassLayer] to be present in the widget
  /// tree, where the liquid glass effect will be rendered.
  const LiquidGlass({
    required this.child,
    required LiquidShape this._shape,
    this.clipBehavior = Clip.hardEdge,
    this._shadows = const [],
    this._appearance,
    super.key,
  }) : _grouped = false,
       _ownLayerConfig = null,
       _auto = false,
       frame = null;

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
    required LiquidShape this._shape,
    LiquidGlassSettings settings = const LiquidGlassSettings(),
    bool fake = false,
    bool useBackdropGroup = false,
    BackdropKey? backdropKey,
    super.key,
    this.clipBehavior = Clip.hardEdge,
    this._shadows = const [],
    this._appearance,
  }) : _grouped = true,
       _ownLayerConfig = (
         settings: settings,
         fake: fake,
         useBackdropGroup: useBackdropGroup,
         backdropKey: backdropKey,
       ),
       _auto = true,
       frame = null;

  /// Creates a new [LiquidGlass] that is part of a [LiquidGlassBlendGroup].
  ///
  /// This will expect a parent [LiquidGlassBlendGroup] to be present in the
  /// widget tree, as well as a parent [LiquidGlassLayer] above that, where the
  /// result will be rendered.
  const LiquidGlass.grouped({
    required this.child,
    required LiquidShape this._shape,
    super.key,
    this.clipBehavior = Clip.hardEdge,
    this._shadows = const [],
    this._appearance,
  }) : _ownLayerConfig = null,
       _grouped = true,
       _auto = false,
       frame = null;

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
    required LiquidShape this._shape,
    LiquidGlassSettings settings = const LiquidGlassSettings(),
    bool fake = false,
    bool useBackdropGroup = false,
    BackdropKey? backdropKey,
    super.key,
    this.clipBehavior = Clip.hardEdge,
    this._shadows = const [],
    this._appearance,
  }) : _ownLayerConfig = (
         settings: settings,
         fake: fake,
         useBackdropGroup: useBackdropGroup,
         backdropKey: backdropKey,
       ),
       _grouped = false,
       _auto = false,
       frame = null;

  /// Creates a shape whose geometry, material and shadows follow [frame].
  ///
  /// Every notification of [frame] writes the new frame straight into the
  /// shape's render objects; the widget rebuilds only when the kind of shape
  /// changes, its shadows appear or vanish, or the layer draws fake glass.
  /// With `grouped` true, the shape joins the nearest
  /// [LiquidGlassBlendGroup].
  const LiquidGlass.live({
    required ValueListenable<LiquidGlassShapeFrame> this.frame,
    required this.child,
    this.clipBehavior = Clip.hardEdge,
    this._grouped = false,
    super.key,
  }) : _shape = null,
       _shadows = const [],
       _appearance = null,
       _ownLayerConfig = null,
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
  LiquidShape get shape => frame?.value.shape ?? _shape!;
  final LiquidShape? _shape;

  /// The source of a live shape's frames, or null for a fixed shape.
  final ValueListenable<LiquidGlassShapeFrame>? frame;

  /// The clip behavior of this glass.
  ///
  /// Defaults to [Clip.hardEdge], so [child] is clipped to the glass shape.
  final Clip clipBehavior;

  /// Whether this glass joins the nearest [LiquidGlassBlendGroup].
  final bool _grouped;

  /// The settings for this glass if it is supposed to create its own layer.
  final _OwnLayerConfig? _ownLayerConfig;

  /// The list of shadows to paint.
  ///
  /// A containing [LiquidGlassLayer] composes shadows from its real shapes
  /// together and cuts every glass silhouette out of the combined stack.
  /// [BoxShadow.blurStyle] is ignored. A singleton standalone shape with only
  /// zero-offset, nonnegative-spread shadows keeps the native outer-blur
  /// behavior.
  List<BoxShadow> get shadows => frame?.value.shadows ?? _shadows;
  final List<BoxShadow> _shadows;

  /// Color and materialization override for this shape.
  ///
  /// Omit this to inherit the containing layer's default appearance.
  LiquidGlassAppearance? get appearance =>
      frame?.value.appearance ?? _appearance;
  final LiquidGlassAppearance? _appearance;

  /// Whether this glass should automatically detect a parent layer.
  final bool _auto;

  /// Loads and compiles every shader the renderer can use on this platform.
  ///
  /// Shaders otherwise load on first use, so the first glass on screen paints
  /// its fallback for a frame or two: fake glass without its surface shader,
  /// real glass as fake glass. Glass layers mounted after the returned future
  /// completes render real glass from their first frame.
  ///
  /// This can be awaited before `runApp`, including on Android: loading GPU
  /// resources does not depend on rendering a frame. Acquiring the engine's
  /// GPU context may add startup time; drawing can still incur first-use work.
  ///
  /// Failures are reported through [FlutterError] and never thrown; glass
  /// layers fall back the same way they would without precaching.
  static Future<void> precache() => precacheLiquidGlass();

  @override
  State<LiquidGlass> createState() => _LiquidGlassState();
}

class _LiquidGlassState extends State<LiquidGlass> {
  /// Keeps [LiquidGlass.child] mounted when the layer switches this shape
  /// between its fake and real subtrees.
  final _childKey = GlobalKey(debugLabel: 'LiquidGlass.child');

  // The render objects a live frame is written into, and what the tree was
  // built with: a frame that keeps the structure goes straight to them.
  final _rawKey = GlobalKey(debugLabel: 'LiquidGlass.raw');
  final _fadeKey = GlobalKey(debugLabel: 'LiquidGlass.fade');
  final _clipKey = GlobalKey(debugLabel: 'LiquidGlass.clip');
  LiquidGlassShapeFrame? _built;
  bool _writable = false;
  late LiquidGlassAppearance _defaultAppearance;
  double _visibility = 1;

  @override
  void initState() {
    super.initState();
    widget.frame?.addListener(_onFrame);
  }

  @override
  void didUpdateWidget(covariant LiquidGlass oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.frame, widget.frame)) {
      oldWidget.frame?.removeListener(_onFrame);
      widget.frame?.addListener(_onFrame);
    }
  }

  @override
  void dispose() {
    widget.frame?.removeListener(_onFrame);
    super.dispose();
  }

  /// Writes [shape]'s corners into the child's clip, or returns false when
  /// the clip cannot follow it without a rebuild.
  bool _clipFollows(LiquidShape shape) {
    if (widget.clipBehavior == Clip.none) return true;
    final clip = _clipKey.currentContext?.findRenderObject();
    switch ((shape, clip)) {
      case (
        LiquidRoundedSuperellipse(:final radii),
        final RenderClipRSuperellipse clip,
      ):
        clip.borderRadius = radii;
        return true;
      case (
        LiquidRoundedRectangle(:final borderRadius),
        final RenderClipRRect clip,
      ):
        clip.borderRadius = BorderRadius.circular(borderRadius);
        return true;
      case (LiquidOval(), RenderClipOval()):
        return true;
      default:
        return false;
    }
  }

  void _onFrame() {
    final frame = widget.frame!.value;
    final built = _built;
    final raw = _rawKey.currentContext?.findRenderObject();
    if (!_writable ||
        built == null ||
        raw is! RenderLiquidGlass ||
        frame.shape.runtimeType != built.shape.runtimeType ||
        frame.shadows.isEmpty != built.shadows.isEmpty ||
        !_clipFollows(frame.shape)) {
      setState(() {});
      return;
    }
    final appearance = _visibleAppearance(frame.appearance);
    raw
      ..shape = frame.shape
      ..layerShadows = frame.shadows
      ..appearance = appearance;
    final fade = _fadeKey.currentContext?.findRenderObject();
    if (fade is RenderOpacity) {
      fade.opacity = appearance.visibility.clamp(0.0, 1.0);
    }
  }

  Widget get _keyedChild => KeyedSubtree(key: _childKey, child: widget.child);

  @override
  Widget build(BuildContext context) {
    _built = widget.frame?.value;
    _writable = false;
    // Join an existing sample whenever one is already in the tree. Creating a
    // layer is the fallback, not the default for a row of siblings. A glass
    // ancestor blocks reuse of the layer above it because nested shapes cannot
    // render correctly into the same sample.
    if (widget._auto &&
        _nearestLiquidGlassBoundary(context) ==
            _LiquidGlassAncestorBoundary.layer) {
      return _buildGlass(context);
    }

    if (widget._ownLayerConfig case final config?) {
      return LiquidGlassLayer(
        settings: config.settings,
        defaultAppearance: widget.appearance,
        fake: config.fake,
        useBackdropGroup: config.useBackdropGroup,
        backdropKey: config.backdropKey,
        child: Builder(builder: _buildGlass),
      );
    }

    if (!widget._grouped &&
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

  /// [own] or the layer's default appearance, faded by the visibility
  /// around the shape.
  LiquidGlassAppearance _visibleAppearance(LiquidGlassAppearance? own) {
    final base = own ?? _defaultAppearance;
    return base.copyWith(visibility: base.visibility * _visibility);
  }

  /// Renders this shape on the nearest [LiquidGlassLayer].
  ///
  /// Grouped constructors join a [LiquidGlassBlendGroup] when one exists.
  /// Otherwise the shape registers directly on the layer so siblings share
  /// one backdrop sample without a dummy blend group.
  Widget _buildGlass(BuildContext context) {
    final scopeSettings = LiquidGlassRenderScope.of(context);
    _defaultAppearance = scopeSettings.defaultAppearance;
    _visibility = LiquidGlassVisibility.of(context);
    final appearance = _visibleAppearance(widget.appearance);
    if (scopeSettings.useFake) {
      return FakeGlass.inLayerResolved(
        shape: widget.shape,
        appearance: appearance,
        shadows: widget.shadows,
        child: _keyedChild,
      );
    }

    final groupLink = widget._grouped
        ? LiquidGlassBlendGroup.maybeOf(context)
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
        shape: widget.shape,
        appearance: appearance,
        shadows: widget.shadows,
        child: _keyedChild,
      );
    }

    final renderLink = blendGroupLink == null
        ? InheritedGeometryRenderLink.of(context)
        : null;

    _writable = !scope.consolidatesFakeBackdrop;
    final registeredChild = scope.consolidatesFakeBackdrop
        ? FakeGlass.inLayerResolved(
            shape: widget.shape,
            appearance: appearance,
            backdropHandledByLayer: true,
            child: _keyedChild,
          )
        : OptimizedClip(
            shape: widget.shape,
            clipBehavior: widget.clipBehavior,
            clipKey: _clipKey,
            child: _fadeChildren(
              appearance.visibility,
              GlassGlowLayer(
                child: _keyedChild,
              ),
              key: _fadeKey,
            ),
          );
    return _RawLiquidGlass(
      key: _rawKey,
      blendGroupLink: blendGroupLink,
      renderLink: renderLink,
      settings: settings,
      appearance: appearance,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      shape: widget.shape,
      layerShadows: widget.shadows,
      child: registeredChild,
    );
  }

  static Widget _fadeChildren(double visibility, Widget child, {Key? key}) {
    return Opacity(
      key: key,
      opacity: visibility.clamp(0.0, 1.0),
      child: child,
    );
  }
}

enum _LiquidGlassAncestorBoundary { none, glass, layer }

typedef _OwnLayerConfig = ({
  LiquidGlassSettings settings,
  bool fake,
  bool useBackdropGroup,
  BackdropKey? backdropKey,
});

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
    super.key,
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
    markGeometryNeedsUpdate();
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

  @override
  void performLayout() {
    super.performLayout();
    if (_blendGroupLink != null) {
      _blendGroupLink!.notifyShapeLayoutChanged(this);
    } else {
      // A child opacity layer can trigger layout without changing our size.
      // gatherShapeData compares the shape bounds before reusing the matte.
      markGeometryNeedsUpdate();
    }
  }

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
