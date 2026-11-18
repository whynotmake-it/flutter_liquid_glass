import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_appearance.dart';
import 'package:liquid_glass_renderer/src/rendering/appearance.dart';
import 'package:liquid_glass_renderer/src/rendering/geometry_render_link.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_blend_group.dart';
import 'package:liquid_glass_renderer/src/rendering/live_paint_size.dart';
import 'package:liquid_glass_renderer/src/widgets/glass_host.dart';
import 'package:liquid_glass_renderer/src/widgets/glass_pixel_ratio.dart';
import 'package:liquid_glass_renderer/src/widgets/liquid_glass_blend_group.dart';
import 'package:liquid_glass_renderer/src/widgets/liquid_glass_layer.dart';
import 'package:liquid_glass_renderer/src/widgets/liquid_glass_render_scope.dart';
import 'package:liquid_glass_renderer/src/widgets/liquid_glass_visibility.dart';
import 'package:liquid_glass_renderer/src/widgets/optimized_clip.dart';

/// A liquid glass shape.
///
/// It draws where the tree puts it:
///
///  * on the nearest [LiquidGlassLayer] above it, which there must be, beside
///    the layer's other shapes, sharing the layer's settings and its read of
///    the backdrop;
///  * in the nearest [LiquidGlassBlendGroup], when one lies between it and
///    that layer: it blends with the group's other shapes;
///  * inside the [child] of another [LiquidGlass], on a layer of its own with
///    the settings of the layer around it, so glass on glass never draws into
///    the same sample.
///
/// A shape that needs settings of its own goes in a [LiquidGlassLayer] of
/// its own.
///
/// ## Transforms
///
/// The glass follows the shape's layout position and transforms applied by
/// widgets like [Transform] or [RotatedBox]. Transforms applied only to the
/// paint canvas, for example by a [Flow] delegate or a
/// `PaintingContext.pushTransform` call that does not push a composited
/// layer, are invisible to the glass: the [child] will transform but the
/// glass stays behind. In those cases, apply the transform with a widget
/// like [Transform] instead.
class LiquidGlass extends StatefulWidget {
  /// Creates a glass [shape] behind [child].
  const LiquidGlass({
    required this.child,
    required LiquidShape this.shape,
    this.clipBehavior = Clip.hardEdge,
    this.shadows = const [],
    this.appearance,
    super.key,
  }) : frame = null;

  /// Creates a shape whose geometry, material and shadows follow [frame].
  ///
  /// Every notification of [frame] writes the new frame straight into the
  /// shape's render objects, on real and fake glass alike; the widget
  /// rebuilds only when the kind of shape changes. The frame's rect and
  /// scale never rebuild or lay out anything.
  ///
  /// The child is laid out in the widget's box and drawn centered on the
  /// frame's rect, so content stays in the middle of glass that grows or
  /// shrinks.
  ///
  /// Hit testing follows the box the widget was laid out in, not the rect
  /// the frame draws it at, as UIKit hit-tests a view's model rather than
  /// its presentation.
  const LiquidGlass.live({
    required ValueListenable<LiquidGlassShapeFrame> this.frame,
    required this.child,
    this.clipBehavior = Clip.hardEdge,
    super.key,
  }) : shape = null,
       shadows = const [],
       appearance = null;

  /// The child of this widget.
  ///
  /// Painted above the glass effect and clipped by [clipBehavior].
  final Widget child;

  /// {@template liquid_glass_renderer.LiquidGlass.shape}
  /// The shape of this glass.
  /// {@endtemplate}
  ///
  /// Null for a live shape ([LiquidGlass.live]), which takes it from its
  /// [frame].
  final LiquidShape? shape;

  /// The source of a live shape's frames, or null for a fixed shape.
  final ValueListenable<LiquidGlassShapeFrame>? frame;

  /// The clip behavior of this glass.
  ///
  /// Defaults to [Clip.hardEdge], so [child] is clipped to the glass shape.
  final Clip clipBehavior;

  /// The list of shadows to paint.
  ///
  /// A containing [LiquidGlassLayer] composes shadows from its real shapes
  /// together and cuts every glass silhouette out of the combined stack; a
  /// shape alone on its layer casts them as
  /// [LiquidGlassSilhouette.paintShadows] does.
  ///
  /// Empty for a live shape, which takes them from its [frame].
  final List<LiquidGlassShadow> shadows;

  /// Color and materialization override for this shape.
  ///
  /// Omit this to inherit the containing layer's default appearance. Null
  /// for a live shape, which takes it from its [frame].
  final LiquidGlassAppearance? appearance;

  @override
  State<LiquidGlass> createState() => _LiquidGlassState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty('shape', shape, defaultValue: null))
      ..add(DiagnosticsProperty('frame', frame, defaultValue: null))
      ..add(
        EnumProperty('clipBehavior', clipBehavior, defaultValue: Clip.hardEdge),
      )
      ..add(IterableProperty('shadows', shadows, ifEmpty: null))
      ..add(DiagnosticsProperty('appearance', appearance, defaultValue: null));
  }
}

class _LiquidGlassState extends State<LiquidGlass> {
  /// Keeps [LiquidGlass.child] mounted when the shape turns live or fixed,
  /// or moves onto or off a layer of its own.
  final _childKey = GlobalKey(debugLabel: 'LiquidGlass.child');

  // The render objects a live frame is written into, and what the tree was
  // built with: a frame that keeps the structure goes straight to them.
  final _rawKey = GlobalKey(debugLabel: 'LiquidGlass.raw');
  final _fadeKey = GlobalKey(debugLabel: 'LiquidGlass.fade');
  LiquidGlassShapeFrame? _built;
  LiquidGlassShapeFrame? _last;
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

  void _onFrame() {
    final frame = widget.frame!.value;
    final last = _last;
    _last = frame;
    // The rect and scale reach the render objects that listen to the frame.
    if (last != null &&
        frame.shape == last.shape &&
        frame.appearance == last.appearance &&
        listEquals(frame.shadows, last.shadows)) {
      return;
    }
    final built = _built;
    if (built == null || frame.shape.runtimeType != built.shape.runtimeType) {
      setState(() {});
      return;
    }
    final appearance = _visibleAppearance(frame.appearance);
    if (_rawKey.currentContext?.findRenderObject()
        case final RenderLiquidGlass raw) {
      raw
        ..shape = frame.shape
        ..layerShadows = frame.shadows
        ..appearance = frame.appearance;
    }
    if (_fadeKey.currentContext?.findRenderObject()
        case final RenderOpacity fade) {
      fade.opacity = drawnVisibility(appearance.visibility);
    }
  }

  LiquidShape get _shape => widget.frame?.value.shape ?? widget.shape!;

  List<LiquidGlassShadow> get _shadows =>
      widget.frame?.value.shadows ?? widget.shadows;

  LiquidGlassAppearance? get _appearance => switch (widget.frame) {
    final frame? => frame.value.appearance,
    null => widget.appearance,
  };

  Widget get _keyedChild {
    final child = KeyedSubtree(
      key: _childKey,
      child: GlassHost.body(child: widget.child),
    );
    return switch (widget.frame) {
      final frame? => _CenteredOnRect(live: frame, child: child),
      null => child,
    };
  }

  @override
  Widget build(BuildContext context) {
    _built = _last = widget.frame?.value;
    final glass = _buildShape(context);
    final frame = widget.frame;
    return frame == null ? glass : _LiveGlassFrame(frame: frame, child: glass);
  }

  Widget _buildShape(BuildContext context) {
    final host = GlassHost.of(context);
    return host != null && host.inBody
        ? nestedGlassLayer(context, _buildGlass)
        : _buildGlass(context);
  }

  LiquidGlassAppearance _visibleAppearance(LiquidGlassAppearance? own) =>
      shownAppearance(
        own,
        layerDefault: _defaultAppearance,
        visibility: _visibility,
      );

  Widget _buildGlass(BuildContext context) {
    _defaultAppearance = LiquidGlassRenderScope.defaultAppearanceOf(context);
    _visibility = LiquidGlassVisibility.of(context);
    final shape = _shape;
    final appearance = _visibleAppearance(_appearance);
    final host = GlassHost.of(context)!;
    final blendGroupLink = host.group;
    return _RawLiquidGlass(
      key: _rawKey,
      blendGroupLink: blendGroupLink,
      renderLink: blendGroupLink == null ? host.link : null,
      appearance: _appearance,
      visibility: _visibility,
      devicePixelRatio: glassDevicePixelRatioOf(context),
      shape: shape,
      layerShadows: _shadows,
      live: widget.frame,
      child: OptimizedClip(
        shape: shape,
        clipBehavior: widget.clipBehavior,
        live: widget.frame,
        child: Opacity(
          key: _fadeKey,
          opacity: drawnVisibility(appearance.visibility),
          child: _keyedChild,
        ),
      ),
    );
  }
}

class _RawLiquidGlass extends SingleChildRenderObjectWidget {
  const _RawLiquidGlass({
    required super.child,
    required this.shape,
    required this.layerShadows,
    required this.blendGroupLink,
    required this.renderLink,
    required this.appearance,
    required this.visibility,
    required this.devicePixelRatio,
    required this.live,
    super.key,
  });

  final LiquidShape shape;

  final ValueListenable<LiquidGlassShapeFrame>? live;

  final List<LiquidGlassShadow> layerShadows;

  final GlassGroupLink? blendGroupLink;

  final GeometryRenderLink? renderLink;

  final LiquidGlassAppearance? appearance;

  final double visibility;

  final double devicePixelRatio;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderLiquidGlass(
      shape: shape,
      layerShadows: layerShadows,
      blendGroupLink: blendGroupLink,
      renderLink: renderLink,
      appearance: appearance,
      visibility: visibility,
      devicePixelRatio: devicePixelRatio,
    )..live = live;
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLiquidGlass renderObject,
  ) {
    renderObject
      ..shape = shape
      ..layerShadows = layerShadows
      ..appearance = appearance
      ..visibility = visibility
      ..devicePixelRatio = devicePixelRatio
      ..live = live
      ..bindLinks(
        blendGroupLink: blendGroupLink,
        renderLink: renderLink,
      );
  }
}

class _LiveGlassFrame extends SingleChildRenderObjectWidget {
  const _LiveGlassFrame({required this.frame, required super.child});

  final ValueListenable<LiquidGlassShapeFrame> frame;

  @override
  RenderLiveGlassFrame createRenderObject(BuildContext context) =>
      RenderLiveGlassFrame(frame: frame);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLiveGlassFrame renderObject,
  ) {
    renderObject.frame = frame;
  }
}

class _CenteredOnRect extends SingleChildRenderObjectWidget {
  const _CenteredOnRect({required this.live, required super.child});

  final ValueListenable<LiquidGlassShapeFrame> live;

  @override
  _RenderCenteredOnRect createRenderObject(BuildContext context) =>
      _RenderCenteredOnRect()..live = live;

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCenteredOnRect renderObject,
  ) {
    renderObject.live = live;
  }
}

class _RenderCenteredOnRect extends RenderProxyBox with LivePaintSize {
  Offset get _shift => hasSize ? body.childOffset : Offset.zero;

  @override
  void paint(PaintingContext context, Offset offset) =>
      super.paint(context, offset + _shift);

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    super.applyPaintTransform(child, transform);
    final shift = _shift;
    transform.translateByDouble(shift.dx, shift.dy, 0, 1);
  }
}
