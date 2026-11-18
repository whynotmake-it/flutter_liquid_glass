part of 'menu_anchor.dart';

/// The touches of a region over a menu's source or its layer, handed to
/// the menu in global coordinates at their stamps, with what the menu made
/// of them ([heard]) as the events the host plays haptics for.
///
/// It hears a touch at contact and claims it [claimAfter] later, when a
/// hold opens the menu under the finger, or at once without one: a scroll
/// view around the source takes a finger that moves before then and never
/// one that may choose from the menu. With [takes] it accepts a touch only
/// while that holds.
final class _MenuInput extends Interaction {
  _MenuInput({
    required this.down,
    this.move,
    this.up,
    this.cancel,
    this.heard,
    this.claimAfter,
    this.contends = false,
    this.takes,
  });

  final bool Function(int pointer, double t, Offset global) down;
  final void Function(int pointer, double t, Offset global)? move;
  final void Function(int pointer, double t, Offset global)? up;
  final void Function(int pointer, double t)? cancel;
  final List<InteractionEvent> Function()? heard;
  final double? claimAfter;
  final bool contends;
  final bool Function()? takes;

  int? _pointer;
  double? _claimAt;

  @override
  bool get contendsWithControls => contends;

  @override
  bool accepts(PointerDownInput down) =>
      super.accepts(down) && (takes?.call() ?? true);

  @override
  double? get nextDue => _claimAt;

  @override
  InteractionUpdate advance(double time) {
    final due = _claimAt;
    if (due == null || time < due) return InteractionUpdate.none;
    _claimAt = null;
    return const InteractionUpdate(claims: true);
  }

  @override
  InteractionUpdate handle(InteractionInput input) {
    var claims = false;
    switch (input) {
      case PointerDownInput() when _pointer == null && accepts(input):
        if (!down(input.pointer, input.time, input.globalPosition)) {
          return InteractionUpdate.none;
        }
        _pointer = input.pointer;
        final after = claimAfter;
        if (after == null) {
          claims = true;
        } else {
          _claimAt = input.time + after;
        }
      case PointerMoveInput() when input.pointer == _pointer:
        move?.call(input.pointer, input.time, input.globalPosition);
      case PointerUpInput() when input.pointer == _pointer:
        _pointer = null;
        _claimAt = null;
        up?.call(input.pointer, input.time, input.globalPosition);
      case PointerCancelInput() when input.pointer == _pointer:
        _pointer = null;
        _claimAt = null;
        cancel?.call(input.pointer, input.time);
      default:
    }
    final events = heard?.call() ?? const <InteractionEvent>[];
    if (!claims && events.isEmpty) return InteractionUpdate.none;
    return InteractionUpdate(claims: claims, events: events);
  }
}

/// Escape on an open submenu card sends it back; on the root list it
/// dismisses the menu through the presentation, as an app's remapping of
/// `DismissIntent` does.
class _MenuEscape extends Action<DismissIntent> {
  _MenuEscape(this.layer);

  final _MenuLayerState layer;

  @override
  bool isEnabled(DismissIntent intent) => layer.mounted;

  @override
  Object? invoke(DismissIntent intent) {
    if (layer.current && layer.built.top > 0) {
      layer._keys.back(keys: true);
      return null;
    }
    return Actions.maybeInvoke(layer.context, intent);
  }
}

/// A row's own input: Space, Enter and the accessibility tap choose it,
/// and the mouse resting on it moves the focus there. Touches stay with
/// the menu's region, whose motion follows the finger across the rows.
final class _RowInput extends Interaction {
  _RowInput({required this.onActivate, required this.onEnter});

  final VoidCallback onActivate;
  final VoidCallback onEnter;

  @override
  bool get activates => true;

  @override
  bool accepts(PointerDownInput down) => false;

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case ActivateInput():
        onActivate();
      case PointerHoverInput(inside: true):
        onEnter();
      default:
    }
    return InteractionUpdate.none;
  }
}

/// The mouse moving over the open menu, in the layer's coordinates.
final class _HoverInput extends Interaction {
  _HoverInput({required this.onHover});

  final ValueChanged<Offset> onHover;

  @override
  bool accepts(PointerDownInput down) => false;

  @override
  InteractionUpdate handle(InteractionInput input) {
    if (input case PointerHoverInput(inside: true, :final position)) {
      onHover(position);
    }
    return InteractionUpdate.none;
  }
}

/// Every touch on a region, heard outside the gesture arena however it
/// decides (a `Listener`'s view), handed on in global coordinates at its
/// stamps, with what the menu made of it ([heard]) as the events the
/// region plays haptics for.
final class _ObservedTouch extends Interaction {
  _ObservedTouch({
    required this.down,
    required this.move,
    required this.up,
    required this.cancel,
    required this.heard,
  }) : super(role: InteractionRole.observer);

  final void Function(int pointer, double t, Offset global) down;
  final void Function(int pointer, double t, Offset global) move;
  final void Function(int pointer, double t, Offset global) up;
  final void Function(int pointer, double t) cancel;
  final List<InteractionEvent> Function() heard;

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput():
        down(input.pointer, input.time, input.globalPosition);
      case PointerMoveInput():
        move(input.pointer, input.time, input.globalPosition);
      case PointerUpInput():
        up(input.pointer, input.time, input.globalPosition);
      case PointerCancelInput():
        cancel(input.pointer, input.time);
      default:
        return InteractionUpdate.none;
    }
    final events = heard();
    return events.isEmpty
        ? InteractionUpdate.none
        : InteractionUpdate(events: events);
  }
}
