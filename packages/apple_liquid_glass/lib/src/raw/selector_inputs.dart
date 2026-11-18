part of 'selector.dart';

/// An item's look for its own states and those its zone has.
class _ItemStates extends StatefulWidget {
  const _ItemStates({
    required this.zones,
    required this.id,
    required this.own,
    required this.builder,
  });

  final InputZonesController<Object> zones;
  final Object id;
  final Set<WidgetState> own;
  final Widget Function(BuildContext context, Set<WidgetState> states) builder;

  @override
  State<_ItemStates> createState() => _ItemStatesState();
}

class _ItemStatesState extends State<_ItemStates> {
  late ValueListenable<Set<WidgetState>> _states = widget.zones.states(
    widget.id,
  );
  late Set<WidgetState> _zone = _read();

  Set<WidgetState> _read() => {
    for (final state in _states.value)
      if (state != WidgetState.disabled) state,
  };

  @override
  void initState() {
    super.initState();
    _states.addListener(_changed);
  }

  @override
  void didUpdateWidget(_ItemStates oldWidget) {
    super.didUpdateWidget(oldWidget);
    final states = widget.zones.states(widget.id);
    if (states != _states) {
      _states.removeListener(_changed);
      _states = states..addListener(_changed);
    }
    _zone = _read();
  }

  @override
  void dispose() {
    _states.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final next = _read();
    if (!setEquals(next, _zone)) setState(() => _zone = next);
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, {...widget.own, ..._zone});
}

/// An item's press: it holds no touch, so the selector's lens drag takes a
/// finger that moves, and a key or a screen reader activates the item.
final class _ItemPress extends PressInteraction {
  _ItemPress(this.onActivate) : super(role: InteractionRole.content);

  final VoidCallback onActivate;

  @override
  InteractionUpdate handle(InteractionInput input) {
    if (input is ActivateInput) onActivate();
    return super.handle(input);
  }
}

/// A selector's touch: the lens follows it from its first event, and it
/// takes the touch from the items once it moves, which holds it against a
/// scroll.
final class _SelectorInput extends Interaction {
  _SelectorInput(this._owner) : super(role: InteractionRole.control);

  final _RawGlassSelectorState _owner;
  int? _pointer;
  bool _claimed = false;

  bool get active => _pointer != null;

  @override
  bool get pressed => _pointer != null;

  @override
  bool get dragged => _pointer != null && _owner._motion.isDragging;

  @override
  InteractionUpdate handle(InteractionInput input) {
    final update = _handle(input);
    _owner._restateParts();
    return update;
  }

  InteractionUpdate _handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput() when _pointer == null && accepts(input):
        _pointer = input.pointer;
        _claimed = false;
        _owner._down(input);
      case PointerMoveInput() when input.pointer == _pointer:
        _owner._move(input);
        if (!_claimed) {
          _claimed = true;
          return const InteractionUpdate(claims: true);
        }
      case PointerUpInput() when input.pointer == _pointer:
        _pointer = null;
        _owner._up(input);
        return const InteractionUpdate(recognizes: true);
      case PointerCancelInput() when input.pointer == _pointer:
        _pointer = null;
        _owner._cancel(input.time);
        return const InteractionUpdate(fails: true);
      default:
    }
    return InteractionUpdate.none;
  }
}
