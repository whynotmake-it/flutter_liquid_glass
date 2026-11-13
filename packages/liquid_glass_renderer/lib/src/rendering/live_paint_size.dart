import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/painting.dart';

/// A glass render object that paints at the size of a live shape frame's
/// rect, which the frame changes without a layout.
mixin LivePaintSize on RenderBox {
  ValueListenable<LiquidGlassShapeFrame>? _live;
  Size? _liveSize;

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

  void _onLive() {
    final next = _live?.value.rect?.size;
    if (next == _liveSize) return;
    _liveSize = next;
    livePaintSizeChanged();
  }

  /// Called when [paintSize] changes without a layout.
  @protected
  void livePaintSizeChanged() => markNeedsPaint();

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
