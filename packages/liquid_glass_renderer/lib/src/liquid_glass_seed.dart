// ignore_for_file: prefer_initializing_formals

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// EXPERIMENTAL. Bounds the render passes of the glass inside it.
///
/// Impeller executes every `BackdropFilter` by ending the current render pass,
/// making its texture readable, and starting a new pass — a "flip" whose cost
/// is proportional to the *pass* size, not to the filter. At the root that is
/// the whole screen (~115 mW GPU per independent filter on a Pixel 10), and a
/// shader filter's intermediate is anchored at the pass origin as well.
///
/// [LiquidGlassSeed] paints a pixel-snapped clip plus a passthrough
/// `BackdropFilter`, which creates one screen-sized flip and a subpass the
/// size of this widget seeded with the backdrop. Glass layers inside it then
/// flip only that subpass, and a glass layer that must refract *another* glass
/// layer (a tab indicator over its bar) can keep its own capture cheaply.
///
/// Size it to the glass plus the blur reach (≈3 σ), the maximum refraction
/// displacement and any exterior shadow. Content the glass should refract must
/// be painted *below* the seed, not inside it.
class LiquidGlassSeed extends SingleChildRenderObjectWidget {
  /// Creates a seed around [child]; see [reach] for sizing.
  const LiquidGlassSeed({
    required super.child,
    this.reach = EdgeInsets.zero,
    super.key,
  });

  /// How far the seeded region extends beyond this widget's layout box, so a
  /// glass bar keeps its layout while its blur halo, refraction and exterior
  /// shadow still fall inside the seed (≈ 3 σ + max displacement + shadow).
  final EdgeInsets reach;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderLiquidGlassSeed(
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        reach: reach,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLiquidGlassSeed renderObject,
  ) {
    renderObject
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context)
      ..reach = reach;
  }
}

/// Render object for [LiquidGlassSeed]; glass layers below it map their filter
/// coordinates relative to this object instead of the root.
class RenderLiquidGlassSeed extends RenderProxyBox {
  /// Creates the seed render object.
  RenderLiquidGlassSeed({
    required double devicePixelRatio,
    EdgeInsets reach = EdgeInsets.zero,
  }) : _devicePixelRatio = devicePixelRatio,
       _reach = reach;

  EdgeInsets _reach;

  /// See [LiquidGlassSeed.reach].
  EdgeInsets get reach => _reach;
  set reach(EdgeInsets value) {
    if (_reach == value) return;
    _reach = value;
    markNeedsPaint();
  }

  @override
  Rect get paintBounds => _reach.inflateRect(Offset.zero & size);

  @override
  Rect? describeApproximatePaintClip(RenderObject child) => null;

  static const _identity = ColorFilter.matrix(<double>[
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  double _devicePixelRatio;

  /// Device pixels per logical pixel, used to snap the subpass origin.
  double get devicePixelRatio => _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  final _clipHandle = LayerHandle<ClipRectLayer>();
  final _seedHandle = LayerHandle<BackdropFilterLayer>();

  /// Origin of the seeded subpass in this object's local coordinates: the
  /// reach-inflated clip's top-left, snapped down to a whole device pixel so
  /// the subpass origin Impeller derives from the rounded coverage is
  /// integral and filter coordinates stay exact.
  Offset get subpassOrigin => _subpassOrigin;
  Offset _subpassOrigin = Offset.zero;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    final dpr = devicePixelRatio;
    final toGlobal = getTransformTo(null);
    var region = MatrixUtils.transformRect(
      toGlobal,
      _reach.inflateRect(Offset.zero & size),
    );
    // Impeller's subpass covers the clip intersected with the enclosing pass
    // (the screen at the root); keep the region inside it so the origin we
    // hand to the glass shaders is the origin the subpass actually gets.
    final view = _enclosingView();
    if (view != null) {
      region = region.intersect(Offset.zero & view.size);
      if (region.isEmpty) return;
    }
    // Snap the global origin down and the far edge up to device pixels so the
    // subpass origin Impeller derives from the rounded coverage matches ours.
    final snapped = Rect.fromLTRB(
      (region.left * dpr).floorToDouble() / dpr,
      (region.top * dpr).floorToDouble() / dpr,
      (region.right * dpr).ceilToDouble() / dpr,
      (region.bottom * dpr).ceilToDouble() / dpr,
    );
    final toLocal = Matrix4.inverted(toGlobal);
    final clip = MatrixUtils.transformRect(toLocal, snapped);
    _subpassOrigin = clip.topLeft;
    _clipHandle.layer = context.pushClipRect(
      true,
      offset,
      clip,
      (context, offset) {
        final seed = _seedHandle.layer ??= BackdropFilterLayer()
          ..filter = _identity
          ..blendMode = ui.BlendMode.srcOver;
        context.pushLayer(seed, super.paint, offset);
      },
      oldLayer: _clipHandle.layer,
    );
  }

  @override
  void dispose() {
    _clipHandle.layer = null;
    _seedHandle.layer = null;
    super.dispose();
  }

  RenderView? _enclosingView() {
    for (RenderObject? n = this; n != null; n = n.parent) {
      if (n is RenderView) return n;
    }
    return null;
  }

  /// Nearest enclosing seed of [node], if any.
  static RenderLiquidGlassSeed? enclosing(RenderObject node) {
    for (var n = node.parent; n != null; n = n.parent) {
      if (n is RenderLiquidGlassSeed) return n;
    }
    return null;
  }
}
