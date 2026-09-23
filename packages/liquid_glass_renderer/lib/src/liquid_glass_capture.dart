// ignore_for_file: prefer_initializing_formals

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/src/internal/capture_pass.dart';

/// Captures the backdrop once for all the glass inside it.
///
/// Every `BackdropFilter`, and so every `LiquidGlassLayer`, has to read the
/// pixels behind it. On Impeller that copies the whole current render pass,
/// the entire screen at the top level, into a texture. Two glass layers that
/// must stay independent (an indicator that refracts its tab bar) therefore
/// pay two full-screen copies.
///
/// [LiquidGlassCapture] pays that copy once. It clips to the glass inside it
/// plus everything that glass paints or samples, and starts a render pass of
/// that size seeded with the backdrop. Glass layers inside then read back only
/// this small pass. The look is identical to glass without a capture.
///
/// Paint the content the glass should refract below the capture, not inside
/// it. Keep captures small: a capture the size of the screen saves nothing.
///
/// The capture sizes itself from the glass layers inside it (material, blur
/// reach, refraction reach, exterior shadows). Pass [bleed] to size it
/// yourself instead, for example when the child paints something outside its
/// own layout box.
///
/// See also the "Glass on glass" section of the package README.
class LiquidGlassCapture extends SingleChildRenderObjectWidget {
  /// Creates a capture around [child].
  const LiquidGlassCapture({required super.child, this.bleed, super.key});

  /// How far the capture extends past this widget's layout box.
  ///
  /// `null` (the default) computes it from the glass layers inside: the
  /// distance their blur, refraction and shadows reach past the layout box.
  /// A value replaces that computation entirely.
  final EdgeInsets? bleed;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderLiquidGlassCapture(
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        bleed: bleed,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLiquidGlassCapture renderObject,
  ) {
    renderObject
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context)
      ..bleed = bleed;
  }
}

/// Render object for [LiquidGlassCapture]. Glass layers below it map their
/// filter coordinates to this object's captured pass instead of the screen.
class RenderLiquidGlassCapture extends RenderProxyBox {
  /// Creates the capture render object.
  RenderLiquidGlassCapture({
    required double devicePixelRatio,
    EdgeInsets? bleed,
  }) : _devicePixelRatio = devicePixelRatio,
       _bleed = bleed;

  EdgeInsets? _bleed;

  /// See [LiquidGlassCapture.bleed].
  EdgeInsets? get bleed => _bleed;
  set bleed(EdgeInsets? value) {
    if (_bleed == value) return;
    _bleed = value;
    markNeedsPaint();
  }

  double _devicePixelRatio;

  /// Device pixels per logical pixel, used to snap the pass origin.
  double get devicePixelRatio => _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  /// The region this capture covered at its last paint, in local coordinates.
  /// Starts as the layout box before the first paint.
  Rect get captureRect => _pass.captureRect ?? (Offset.zero & size);

  /// Origin of the captured pass in local coordinates: the top-left of
  /// [captureRect], snapped down to a whole device pixel so it matches the
  /// origin Impeller derives from the rounded coverage.
  Offset get passOrigin => captureRect.topLeft;

  @override
  Rect get paintBounds => captureRect;

  /// The captured pass is what descendants paint into; reporting it here
  /// lets the glass layers' pass-origin prediction see it like any clip.
  @override
  Rect? describeApproximatePaintClip(RenderObject child) => captureRect;

  @override
  bool get alwaysNeedsCompositing => true;

  final _pass = CapturePass();

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    if (_pass.computeRegion(this, bleed: _bleed) == null) return;
    _pass.paint(
      context,
      offset,
      this,
      super.paint,
      enabled: true,
      bleed: _bleed,
    );
  }

  @override
  void dispose() {
    _pass.dispose();
    super.dispose();
  }

  /// Nearest enclosing capture of [node], if any.
  static RenderLiquidGlassCapture? enclosing(RenderObject node) {
    for (var n = node.parent; n != null; n = n.parent) {
      if (n is RenderLiquidGlassCapture) return n;
    }
    return null;
  }
}
