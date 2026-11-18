part of 'interaction.dart';

InteractionUpdate _then(InteractionUpdate a, InteractionUpdate b) {
  if (identical(b, InteractionUpdate.none)) return a;
  if (identical(a, InteractionUpdate.none)) return b;
  return InteractionUpdate(
    claims: a.claims || b.claims,
    recognizes: a.recognizes || b.recognizes,
    fails: a.fails || b.fails,
    events: [...a.events, ...b.events],
  );
}

double? _earliest(double? a, double? b) =>
    a == null ? b : (b == null ? a : math.min(a, b));

abstract final class _Pair extends Interaction {
  _Pair(this.a, this.b, {required super.role});

  final Interaction a;
  final Interaction b;

  @override
  bool get activates => a.activates || b.activates;

  @override
  bool get adjusts => a.adjusts || b.adjusts;

  @override
  bool get opensContextMenu => a.opensContextMenu || b.opensContextMenu;

  @override
  bool get contendsWithControls =>
      a.contendsWithControls || b.contendsWithControls;

  @override
  bool get takesWheel => a.takesWheel || b.takesWheel;

  @override
  bool get pressed => a.pressed || b.pressed;

  @override
  bool get dragged => a.dragged || b.dragged;

  @override
  void bindRegion(Offset Function(Offset local) toGlobal) {
    a.bindRegion(toGlobal);
    b.bindRegion(toGlobal);
  }

  @override
  bool get takesPointers => a.takesPointers || b.takesPointers;

  @override
  bool accepts(PointerDownInput down) => a.accepts(down) || b.accepts(down);
}

final class _Simultaneous extends _Pair {
  _Simultaneous(super.a, super.b) : super(role: _stronger(a.role, b.role));

  bool _aFailed = false;
  bool _bFailed = false;

  static InteractionRole _stronger(InteractionRole a, InteractionRole b) =>
      a == InteractionRole.observer && b == InteractionRole.observer
      ? InteractionRole.observer
      : a == InteractionRole.gesture || b == InteractionRole.gesture
      ? InteractionRole.gesture
      : a == InteractionRole.control || b == InteractionRole.control
      ? InteractionRole.control
      : InteractionRole.content;

  @override
  double get onset => math.min(a.onset, b.onset);

  InteractionUpdate _both(InteractionUpdate fromA, InteractionUpdate fromB) {
    _aFailed = _aFailed || fromA.fails;
    _bFailed = _bFailed || fromB.fails;
    return InteractionUpdate(
      claims: fromA.claims || fromB.claims,
      recognizes: fromA.recognizes || fromB.recognizes,
      fails: _aFailed && _bFailed,
      events: [...fromA.events, ...fromB.events],
    );
  }

  @override
  InteractionUpdate handle(InteractionInput input) {
    if (input is PointerDownInput) {
      _aFailed = false;
      _bFailed = false;
    }
    return _both(a.handle(input), b.handle(input));
  }

  @override
  double? get nextDue => _earliest(a.nextDue, b.nextDue);

  @override
  InteractionUpdate advance(double time) =>
      _both(a.advance(time), b.advance(time));
}

final class _Exclusive extends _Pair {
  _Exclusive(super.a, super.b) : super(role: a.role);

  final List<InteractionInput> _waiting = [];
  bool _recognized = false;
  bool _aFailed = false;

  @override
  double get onset => a.onset;

  bool get _decided => _recognized || _aFailed;

  InteractionUpdate _fromA(InteractionUpdate update) {
    if (update.recognizes) {
      _recognized = true;
      _waiting.clear();
      return update;
    }
    if (!update.fails) return update;
    _aFailed = true;
    var replayed = InteractionUpdate(claims: update.claims);
    for (final input in _waiting) {
      replayed = _then(replayed, b.handle(input));
    }
    _waiting.clear();
    return replayed;
  }

  @override
  InteractionUpdate handle(InteractionInput input) {
    if (input is PointerDownInput && _decided) {
      _recognized = false;
      _aFailed = false;
      _waiting.clear();
    }
    if (_aFailed) return b.handle(input);
    if (!_recognized &&
        (input is PointerDownInput ||
            input is PointerMoveInput ||
            input is PointerUpInput ||
            input is PointerCancelInput ||
            input is PointerAcceptedInput)) {
      _waiting.add(input);
    }
    return _fromA(a.handle(input));
  }

  @override
  double? get nextDue => _aFailed ? b.nextDue : a.nextDue;

  @override
  InteractionUpdate advance(double time) {
    if (_aFailed) return b.advance(time);
    final update = _fromA(a.advance(time));
    if (!_aFailed) return update;
    return _then(update, b.advance(time));
  }
}

final class _Sequenced extends Interaction {
  _Sequenced(this.a, this.b) : super(role: a.role);

  final Interaction a;
  final Interaction b;
  PointerDownInput? _down;
  Offset _latest = Offset.zero;
  Offset _latestGlobal = Offset.zero;
  bool _handedOn = false;

  @override
  double get onset => a.onset;

  @override
  bool get activates => a.activates;

  @override
  bool get adjusts => a.adjusts;

  @override
  bool get opensContextMenu => a.opensContextMenu;

  @override
  bool get contendsWithControls =>
      a.contendsWithControls || b.contendsWithControls;

  @override
  bool get takesWheel => a.takesWheel;

  @override
  bool get takesPointers => a.takesPointers;

  @override
  bool get pressed => a.pressed || b.pressed;

  @override
  bool get dragged => a.dragged || b.dragged;

  @override
  void bindRegion(Offset Function(Offset local) toGlobal) {
    a.bindRegion(toGlobal);
    b.bindRegion(toGlobal);
  }

  @override
  bool accepts(PointerDownInput down) => a.accepts(down);

  InteractionUpdate _fromA(InteractionUpdate update, double time) {
    final down = _down;
    if (!update.recognizes || _handedOn || down == null) return update;
    _handedOn = true;
    return _then(
      update,
      b.handle(
        down.copyWith(
          time: time,
          position: _latest,
          globalPosition: _latestGlobal,
        ),
      ),
    );
  }

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput():
        _down = input;
        _latest = input.position;
        _latestGlobal = input.globalPosition;
        _handedOn = false;
        return _fromA(a.handle(input), input.time);
      case PointerMoveInput(:final position, :final globalPosition) ||
          PointerUpInput(:final position, :final globalPosition):
        _latest = position;
        _latestGlobal = globalPosition;
      case PointerAcceptedInput() ||
          PointerCancelInput() ||
          PointerHoverInput() ||
          PointerScrollInput() ||
          ActivateInput() ||
          AdjustInput() ||
          ContextMenuInput():
    }
    final fromA = _fromA(a.handle(input), input.time);
    if (!_handedOn ||
        input is PointerHoverInput ||
        input is PointerScrollInput ||
        input is ActivateInput ||
        input is AdjustInput ||
        input is ContextMenuInput) {
      return fromA;
    }
    final handed = _then(fromA, b.handle(input));
    if (input is PointerUpInput || input is PointerCancelInput) {
      _down = null;
      _handedOn = false;
    }
    return handed;
  }

  @override
  double? get nextDue =>
      _handedOn ? _earliest(a.nextDue, b.nextDue) : a.nextDue;

  @override
  InteractionUpdate advance(double time) {
    final due = a.nextDue;
    final fromA = due != null && due <= time
        ? _fromA(a.advance(time), due)
        : InteractionUpdate.none;
    if (!_handedOn) return fromA;
    final dueB = b.nextDue;
    if (dueB == null || dueB > time) return fromA;
    return _then(fromA, b.advance(time));
  }
}
