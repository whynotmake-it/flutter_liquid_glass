// ignore_for_file: avoid_setters_without_getters

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/links.dart';
import 'package:liquid_glass_renderer/src/internal/transform_tracking_repaint_boundary_mixin.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_blend_group.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_scope.dart';
import 'package:meta/meta.dart';

/// A liquid glass shape.
///
/// This can either be used on its own, or be part of a shared
/// [LiquidGlassLayer], where all shapes will blend together.
///
/// The simplest use of this widget is to create a [LiquidGlass] on its own
/// layer:
///
/// ```dart
/// Widget build(BuildContext context) {
///   return LiquidGlass(
///     shape: LiquidGlassSquircle(
///       borderRadius: Radius.circular(10),
///     ),
///     child: FlutterLogo(),
///   );
/// }
/// ```
///
/// If you want multiple shapes to blend together, you need to construct your
/// own [LiquidGlassLayer], and place this widget inside of there using the
/// [LiquidGlass.inLayer] constructor.
///
/// See the [LiquidGlassLayer] documentation for more information.
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    required this.child,
    required this.shape,
    this.glassContainsChild = false,
    this.clipBehavior = Clip.hardEdge,
    super.key,
  }) : blendGroupLink = null;

  const LiquidGlass.blended({
    required this.child,
    required this.shape,
    super.key,
    this.glassContainsChild = false,
    this.clipBehavior = Clip.hardEdge,
    this.blendGroupLink,
  });

  /// The child of this widget.
  ///
  /// You can choose whether this should be rendered "inside" of the glass, or
  /// on top using [glassContainsChild].
  final Widget child;

  /// {@template liquid_glass_renderer.LiquidGlass.shape}
  /// The shape of this glass.
  ///
  /// This is the shape of the glass that will be rendered.
  /// {@endtemplate}
  final LiquidShape shape;

  /// Whether this glass should be rendered "inside" of the glass, or on top.
  ///
  /// If it is rendered inside, the color tint
  /// of the glass will affect the child, and it will also be refracted.
  ///
  /// Defaults to `false`.
  final bool glassContainsChild;

  /// The clip behavior of this glass.
  ///
  /// Defaults to [Clip.none], so [child] will not be clipped.
  final Clip clipBehavior;

  /// The link to this glass's blend group if it is part of one.
  final BlendGroupLink? blendGroupLink;

  @override
  Widget build(BuildContext context) {
    final fake = LiquidGlassScope.of(context).useFake;

    if (fake) {
      return FakeGlass.inLayer(
        shape: shape,
        child: child,
      );
    }

    // if (blendGroupLink == null) {
    //   return LiquidGlassBlendGroup(
    //     child: Builder(
    //       builder: (context) => _RawLiquidGlass(
    //         blendGroupLink: LiquidGlassBlendGroup.maybeOf(context),
    //         shape: shape,
    //         glassContainsChild: glassContainsChild,
    //         child: ClipPath(
    //           clipper: ShapeBorderClipper(shape: shape),
    //           clipBehavior: clipBehavior,
    //           child: Opacity(
    //             opacity: LiquidGlassSettings.of(context).visibility.clamp(0, 1),
    //             child: GlassGlowLayer(
    //               child: child,
    //             ),
    //           ),
    //         ),
    //       ),
    //     ),
    //   );
    // }

    return _RawLiquidGlass(
      blendGroupLink: LiquidGlassBlendGroup.maybeOf(context),
      shape: shape,
      glassContainsChild: glassContainsChild,
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        clipBehavior: clipBehavior,
        child: Opacity(
          opacity: LiquidGlassSettings.of(context).visibility.clamp(0, 1),
          child: GlassGlowLayer(
            child: child,
          ),
        ),
      ),
    );
  }
}

class _RawLiquidGlass extends SingleChildRenderObjectWidget {
  const _RawLiquidGlass({
    required super.child,
    required this.shape,
    required this.glassContainsChild,
    required this.blendGroupLink,
  });

  final LiquidShape shape;

  final bool glassContainsChild;

  final BlendGroupLink? blendGroupLink;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderLiquidGlass(
      shape: shape,
      glassContainsChild: glassContainsChild,
      blendGroupLink: blendGroupLink,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLiquidGlass renderObject,
  ) {
    renderObject
      ..shape = shape
      ..glassContainsChild = glassContainsChild
      ..blendGroupLink = blendGroupLink;
  }
}

@internal
class RenderLiquidGlass extends RenderProxyBox
    with TransformTrackingRenderObjectMixin {
  RenderLiquidGlass({
    required LiquidShape shape,
    required bool glassContainsChild,
    required BlendGroupLink? blendGroupLink,
  })  : _shape = shape,
        _glassContainsChild = glassContainsChild,
        _blendGroupLink = blendGroupLink;

  late LiquidShape _shape;
  LiquidShape get shape => _shape;
  set shape(LiquidShape value) {
    if (_shape == value) return;
    _shape = value;
    markNeedsPaint();
    _updateBlendGroupLink();
  }

  bool _glassContainsChild = true;
  bool get glassContainsChild => _glassContainsChild;
  set glassContainsChild(bool value) {
    if (_glassContainsChild == value) return;
    _glassContainsChild = value;
    _updateBlendGroupLink();
  }

  BlendGroupLink? _blendGroupLink;
  set blendGroupLink(BlendGroupLink? value) {
    if (_blendGroupLink == value) return;
    _unregisterFromParentLayer();
    _blendGroupLink = value;
    _registerWithLink();
  }

  final transformLayerHandle = LayerHandle<TransformLayer>();

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _registerWithLink();
  }

  @override
  void detach() {
    _unregisterFromParentLayer();
    transformLayerHandle.layer = null;
    super.detach();
  }

  void _registerWithLink() {
    if (_blendGroupLink != null) {
      _blendGroupLink!.registerShape(
        this,
        _shape,
        _glassContainsChild,
      );
    }
  }

  void _unregisterFromParentLayer() {
    _blendGroupLink?.unregisterShape(this);
  }

  void _updateBlendGroupLink() {
    _blendGroupLink?.updateShape(
      this,
      _shape,
      _glassContainsChild,
    );
  }

  late Path _lastPath;

  @override
  void performLayout() {
    super.performLayout();
    // Notify parent layer when our layout changes
    _lastPath = shape.getOuterPath(Offset.zero & size);
    _blendGroupLink?.notifyShapeLayoutChanged(this);
  }

  @override
  void onTransformChanged() {
    _blendGroupLink?.notifyShapeLayoutChanged(this);
  }

  @override
  // ignore: must_call_super
  void paint(PaintingContext context, Offset offset) {
    setUpLayer(offset);
  }

  void paintFromLayer(
    PaintingContext context,
    Matrix4 transform,
    Offset offset,
  ) {
    if (attached) {
      transformLayerHandle.layer = context.pushTransform(
        needsCompositing,
        offset,
        transform,
        super.paint,
        oldLayer: transformLayerHandle.layer,
      );
    }
  }

  Path getPath() {
    return _lastPath;
  }
}
