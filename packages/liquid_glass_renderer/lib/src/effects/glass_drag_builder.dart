import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// {@template gesture_mode}
/// Which gesture mechanism drives the effect. [GestureMode.listener] reacts
/// to raw pointer events, even when a descendant handles the gesture.
/// [GestureMode.gestureDetector] joins the gesture arena and starts the
/// effect only once its pan wins, so a descendant that claims the gesture (a
/// button) suppresses it.
/// {@endtemplate}
enum GestureMode {
  /// Reacts to raw pointer events, including those a descendant handles.
  listener,

  /// Joins the gesture arena; a descendant that claims the gesture
  /// suppresses the effect.
  gestureDetector,
}

@internal
class GlassDragBuilder extends StatefulWidget {
  const GlassDragBuilder({
    required this.builder,
    this.behavior = HitTestBehavior.opaque,
    this.gestureMode = GestureMode.listener,
    this.child,
    super.key,
  });

  final HitTestBehavior behavior;
  final GestureMode gestureMode;

  final ValueWidgetBuilder<Offset?> builder;

  final Widget? child;

  @override
  State<GlassDragBuilder> createState() => _GlassDragBuilderState();
}

class _GlassDragBuilderState extends State<GlassDragBuilder> {
  Offset? _offset;

  void _set(Offset? offset) {
    if (!mounted) return;
    setState(() => _offset = offset);
  }

  void _begin() => _set(Offset.zero);

  void _move(Offset delta) => _set((_offset ?? Offset.zero) + delta);

  void _end() => _set(null);

  @override
  Widget build(BuildContext context) {
    final child = widget.builder(context, _offset, widget.child);
    return switch (widget.gestureMode) {
      GestureMode.listener => Listener(
        behavior: widget.behavior,
        onPointerDown: (_) => _begin(),
        onPointerMove: (event) => _move(event.delta),
        onPointerUp: (_) => _end(),
        onPointerCancel: (_) => _end(),
        child: child,
      ),
      GestureMode.gestureDetector => GestureDetector(
        behavior: widget.behavior,
        onPanStart: (_) => _begin(),
        onPanUpdate: (details) => _move(details.delta),
        onPanEnd: (_) => _end(),
        onPanCancel: _end,
        child: child,
      ),
    };
  }
}
