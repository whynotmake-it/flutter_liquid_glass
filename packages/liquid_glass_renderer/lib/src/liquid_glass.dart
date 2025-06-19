// ignore_for_file: avoid_setters_without_getters

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_layer.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_settings.dart';
import 'package:liquid_glass_renderer/src/liquid_shape.dart';
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
  /// Creates a new [LiquidGlass] on its own layer with the given [child],
  /// [shape], and [settings].
  ///
  /// This shape will not blend together with other shapes, so
  /// [LiquidGlassSettings.blend] will be ignored.
  const LiquidGlass({
    required this.child,
    required this.shape,
    this.glassContainsChild = true,
    this.clipBehavior = Clip.hardEdge,
    super.key,
    LiquidGlassSettings settings = const LiquidGlassSettings(),
  }) : _settings = settings;

  /// Creates a new [LiquidGlass] on a shared layer with the given [child] and
  /// [shape].
  ///
  /// This widget will assume that it is a child of a [LiquidGlassLayer], from
  /// where it will take the [LiquidGlassSettings].
  /// It will also blend together with other shapes in that layer.
  const LiquidGlass.inLayer({
    required this.child,
    required this.shape,
    super.key,
    this.glassContainsChild = true,
    this.clipBehavior = Clip.hardEdge,
  }) : _settings = null;

  /// The child of this widget.
  ///
  /// You can choose whether this should be rendered "inside" of the glass, or
  /// on top using [glassContainsChild].
  final Widget child;

  /// The shape of this glass.
  ///
  /// This is the shape of the glass that will be rendered.
  final LiquidShape shape;

  /// Whether this glass should be rendered "inside" of the glass, or on top.
  ///
  /// If it is rendered inside, the color tint
  /// of the glass will affect the child, and it will also be refracted.
  final bool glassContainsChild;

  /// The clip behavior of this glass.
  ///
  /// Defaults to [Clip.none], so [child] will not be clipped.
  final Clip clipBehavior;

  final LiquidGlassSettings? _settings;

  @override
  Widget build(BuildContext context) {
    switch (_settings) {
      case null:
        return _RawLiquidGlass(
          shape: shape,
          glassContainsChild: glassContainsChild,
          child: ClipPath(
            clipper: ShapeBorderClipper(shape: shape),
            clipBehavior: clipBehavior,
            child: child,
          ),
        );
      case final settings:
        return LiquidGlassLayer(
          settings: settings,
          child: _RawLiquidGlass(
            shape: shape,
            glassContainsChild: glassContainsChild,
            child: ClipPath(
              clipper: ShapeBorderClipper(shape: shape),
              clipBehavior: clipBehavior,
              child: child,
            ),
          ),
        );
    }
  }
}

class _RawLiquidGlass extends SingleChildRenderObjectWidget {
  const _RawLiquidGlass({
    required super.child,
    required this.shape,
    required this.glassContainsChild,
  });

  final LiquidShape shape;

  final bool glassContainsChild;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderLiquidGlass(
      shape: shape,
      glassContainsChild: glassContainsChild,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLiquidGlass renderObject,
  ) {
    renderObject
      ..shape = shape
      ..glassContainsChild = glassContainsChild;
  }
}

@internal
class RenderLiquidGlass extends RenderProxyBox {
  RenderLiquidGlass({
    required LiquidShape shape,
    required bool glassContainsChild,
  })  : _shape = shape,
        _glassContainsChild = glassContainsChild;

  late LiquidShape _shape;
  LiquidShape get shape => _shape;
  set shape(LiquidShape value) {
    if (_shape == value) return;
    _shape = value;
    markNeedsPaint();
    _notifyLayerIfNeeded();
  }

  bool _glassContainsChild = true;
  bool get glassContainsChild => _glassContainsChild;
  set glassContainsChild(bool value) {
    if (_glassContainsChild == value) return;
    _glassContainsChild = value;
    markNeedsPaint();
    _notifyLayerIfNeeded();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    // Register with parent layer after attaching
    _registerWithParentLayer();
  }

  @override
  void detach() {
    _unregisterFromParentLayer();
    super.detach();
  }

  void _registerWithParentLayer() {
    // Walk up the render tree to find the nearest RenderLiquidGlassLayer
    var ancestor = parent;
    while (ancestor != null) {
      if (ancestor is RenderLiquidGlassLayer) {
        ancestor.registerShape(this);
        break;
      }
      ancestor = ancestor.parent;
    }
  }

  void _unregisterFromParentLayer() {
    final layer = RenderLiquidGlassLayer.layerRegistry[this];
    layer?.unregisterShape(this);
  }

  void _notifyLayerIfNeeded() {
    final layer = RenderLiquidGlassLayer.layerRegistry[this];
    layer?.markNeedsPaint();
  }

  @override
  void performLayout() {
    super.performLayout();
    // Notify parent layer when our layout changes
    _notifyLayerIfNeeded();
  }

  @override
  void paint(PaintingContext context, Offset offset) {}

  void paintFromLayer(PaintingContext context, Offset offset) {
    super.paint(context, offset);
  }

  void paintBlur(PaintingContext context, Offset offset, double blur) {
    if (blur <= 0) return;

    context.pushClipPath(
      true,
      offset,
      offset & size,
      ShapeBorderClipper(shape: shape).getClip(size),
      (context, offset) {
        context.pushLayer(
          BackdropFilterLayer(
            filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          ),
          (context, offset) {},
          offset,
        );
      },
    );
  }

  @override
  void markNeedsPaint() {
    super.markNeedsPaint();
    // Also notify the parent layer
    _notifyLayerIfNeeded();
  }
}
