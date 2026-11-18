import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/rendering/drawn_values.dart';

/// A glass render object that paints at the size of a live shape frame's
/// rect, and with its glow, which the frame changes without a layout.
mixin LivePaintSize on RenderBox {
  ValueListenable<LiquidGlassShapeFrame>? _live;
  Size? _liveSize;
  DrawnGlow? _glow;

  /// The live frame whose rect sets [paintSize], or null to paint at the
  /// layout size.
  ValueListenable<LiquidGlassShapeFrame>? get live => _live;
  set live(ValueListenable<LiquidGlassShapeFrame>? value) {
    if (identical(_live, value)) return;
    if (attached) _live?.removeListener(_onLive);
    _live = value;
    if (attached) _live?.addListener(_onLive);
    _onLive();
  }

  /// The size the glass paints at: the live frame's rect size, or the
  /// layout size without one.
  Size get paintSize => _liveSize ?? size;

  /// Where the live frame draws the body in this box.
  LiquidGlassBody get body =>
      _live?.value.bodyIn(size) ?? LiquidGlassBody(size);

  /// The live frame's glow where it draws, else null.
  DrawnGlow? get glow => _glow;

  void _onLive() {
    final frame = _live?.value;
    final glow = DrawnGlow.of(frame?.glow);
    if (glow != _glow) {
      _glow = glow;
      liveGlowChanged();
    }
    final next = frame?.rect?.size;
    if (next == _liveSize) return;
    _liveSize = next;
    livePaintSizeChanged();
  }

  /// Called when [paintSize] changes without a layout.
  @protected
  void livePaintSizeChanged() => markNeedsPaint();

  /// Called when [glow] changes.
  @protected
  void liveGlowChanged() {}

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _live?.addListener(_onLive);
    _onLive();
  }

  @override
  void detach() {
    _live?.removeListener(_onLive);
    super.detach();
  }
}
