import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

/// The soft drop shadow iOS gives floating glass.
const glassShadows = [
  BoxShadow(color: Color(0x1F000000), blurRadius: 24, offset: Offset(0, 8)),
];

/// A glass shape that can be dragged around the stage.
///
/// Must be a direct child of a [Stack]. [offset] is measured from [center],
/// so the shape keeps its place relative to the middle of the stage when the
/// window resizes. Dragging rebuilds only this shape's [Positioned].
class DraggableGlass extends StatefulWidget {
  const DraggableGlass({
    required this.center,
    required this.offset,
    required this.size,
    required this.shape,
    this.grouped = false,
    this.appearance,
    this.child = const SizedBox.shrink(),
    super.key,
  });

  final Offset center;
  final Offset offset;
  final Size size;
  final LiquidShape shape;

  /// Whether the shape blends with its siblings in a [LiquidGlassBlendGroup].
  final bool grouped;

  final LiquidGlassAppearance? appearance;
  final Widget child;

  @override
  State<DraggableGlass> createState() => _DraggableGlassState();
}

class _DraggableGlassState extends State<DraggableGlass> {
  late final _offset = ValueNotifier(widget.offset);

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  void _drag(DragUpdateDetails details) {
    final limit = widget.center - widget.size.center(Offset.zero);
    final next = _offset.value + details.delta;
    _offset.value = Offset(
      next.dx.clamp(-limit.dx, limit.dx),
      next.dy.clamp(-limit.dy, limit.dy),
    );
  }

  @override
  Widget build(BuildContext context) {
    final glass = widget.grouped
        ? LiquidGlass.grouped(
            shape: widget.shape,
            appearance: widget.appearance,
            shadows: glassShadows,
            child: Center(child: widget.child),
          )
        : LiquidGlass(
            shape: widget.shape,
            appearance: widget.appearance,
            shadows: glassShadows,
            child: Center(child: widget.child),
          );
    return ValueListenableBuilder(
      valueListenable: _offset,
      builder: (context, offset, child) {
        final topLeft =
            widget.center + offset - widget.size.center(Offset.zero);
        return Positioned(
          left: topLeft.dx,
          top: topLeft.dy,
          width: widget.size.width,
          height: widget.size.height,
          child: child!,
        );
      },
      child: GestureDetector(
        onPanUpdate: _drag,
        child: LiquidStretch(child: glass),
      ),
    );
  }
}
