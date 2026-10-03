import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

/// The soft drop shadow iOS gives floating glass.
const glassShadows = [
  BoxShadow(color: Color(0x1F000000), blurRadius: 24, offset: Offset(0, 8)),
];

/// Content of an interactive glass element, with the package's touch glow
/// following the pointer beneath it.
class GlowContent extends StatelessWidget {
  const GlowContent({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GlassGlowLayer(
      child: GlassGlow(glowColor: const Color(0x29FFFFFF), child: child),
    );
  }
}

/// Drags [child] from the first pointer contact, winning over the scrolling
/// backdrop beneath it, like Flutter's `Draggable`.
class ImmediateDrag extends StatelessWidget {
  const ImmediateDrag({required this.onUpdate, required this.child, super.key});

  final GestureDragUpdateCallback onUpdate;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        ImmediateMultiDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
              ImmediateMultiDragGestureRecognizer
            >(
              ImmediateMultiDragGestureRecognizer.new,
              (recognizer) => recognizer.onStart = (_) => _Drag(onUpdate),
            ),
      },
      child: child,
    );
  }
}

class _Drag extends Drag {
  _Drag(this._onUpdate);

  final GestureDragUpdateCallback _onUpdate;

  @override
  void update(DragUpdateDetails details) => _onUpdate(details);
}

/// A glass shape that can be dragged around the stage.
///
/// Must be a direct child of a [Stack]. The offset is measured from
/// [center], so the shape keeps its place relative to the middle of the
/// stage when the window resizes. Dragging rebuilds only this shape's
/// [Positioned].
class DraggableGlass extends StatefulWidget {
  const DraggableGlass({
    required this.center,
    required this.size,
    required this.shape,
    this.offset = Offset.zero,
    this.position,
    this.grouped = false,
    this.interactive = true,
    this.appearance,
    this.child = const SizedBox.shrink(),
    super.key,
  });

  final Offset center;

  /// The initial offset from [center] when [position] is not given.
  final Offset offset;

  /// Drives the offset from [center] when something else needs to follow the
  /// shape.
  final ValueNotifier<Offset>? position;

  final Size size;
  final LiquidShape shape;

  /// Whether the shape blends with its siblings in a [LiquidGlassBlendGroup].
  final bool grouped;

  /// Whether the shape stretches and glows under the pointer.
  final bool interactive;

  final LiquidGlassAppearance? appearance;
  final Widget child;

  @override
  State<DraggableGlass> createState() => _DraggableGlassState();
}

class _DraggableGlassState extends State<DraggableGlass> {
  ValueNotifier<Offset>? _ownPosition;

  ValueNotifier<Offset> get _position =>
      widget.position ?? (_ownPosition ??= ValueNotifier(widget.offset));

  @override
  void dispose() {
    _ownPosition?.dispose();
    super.dispose();
  }

  void _drag(DragUpdateDetails details) {
    final limit = widget.center - widget.size.center(Offset.zero);
    final next = _position.value + details.delta;
    _position.value = Offset(
      next.dx.clamp(-limit.dx, limit.dx),
      next.dy.clamp(-limit.dy, limit.dy),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = Center(child: widget.child);
    final child = widget.interactive ? GlowContent(child: content) : content;
    Widget glass = widget.grouped
        ? LiquidGlass.grouped(
            shape: widget.shape,
            appearance: widget.appearance,
            shadows: glassShadows,
            child: child,
          )
        : LiquidGlass(
            shape: widget.shape,
            appearance: widget.appearance,
            shadows: glassShadows,
            child: child,
          );
    if (widget.interactive) glass = LiquidStretch(child: glass);
    return ValueListenableBuilder(
      valueListenable: _position,
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
      child: ImmediateDrag(onUpdate: _drag, child: glass),
    );
  }
}
