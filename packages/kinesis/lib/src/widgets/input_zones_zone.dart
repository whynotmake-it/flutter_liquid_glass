part of 'input_zones.dart';

/// Tab order of the zones: every target in the order of the zones, or,
/// for a host of one stop, the entry alone besides the focused node.
class _ZonesTraversal<T extends Object> extends OrderedTraversalPolicy {
  _ZonesTraversal(this.host);

  final _InputZonesState<T> host;

  @override
  Iterable<FocusNode> sortDescendants(
    Iterable<FocusNode> descendants,
    FocusNode currentNode,
  ) {
    final sorted = super.sortDescendants(descendants, currentNode);
    if (host.widget.stops == InputZoneStops.each) return sorted;
    final zones = {for (final zone in host._zones.values) zone.node};
    final entry = host._entry();
    return [
      for (final node in sorted)
        if (!zones.contains(node) || node == entry || node == currentNode) node,
    ];
  }
}

class _ZoneKey<T extends Object> extends ValueKey<T> {
  const _ZoneKey(super.value);
}

class _Zone<T extends Object> extends StatefulWidget {
  const _Zone({
    required this.host,
    required this.zone,
    required this.order,
    super.key,
  });

  final _InputZonesState<T> host;
  final InputZone<T> zone;
  final int order;

  @override
  State<_Zone<T>> createState() => _ZoneState<T>();
}

/// One zone's session, focus node, hit target and semantics anchor.
///
/// The zone keeps none of its states. They live in the host's
/// [InputZonesController], by zone id, and the zone is their only writer.
/// A zone that leaves clears its states only while its host still holds the
/// controller, so a newer host's zone of the same id keeps them.
class _ZoneState<T extends Object> extends State<_Zone<T>> {
  late final _ZoneTarget<T> target = _ZoneTarget<T>(this);
  final FocusNode node = FocusNode();
  _RenderZoneAnchor<T>? _anchor;
  Offset _origin = Offset.zero;
  Size _size = Size.zero;

  // While the zone writes what its widget says, in a build: the
  // controller's listeners hear nothing then.
  bool _quiet = false;

  // Whether the zone was present when the frames last changed.
  bool _described = false;

  InputZone<T> get zone => widget.zone;

  T get id => zone.id;

  _InputZonesState<T> get host => widget.host;

  InputZonesController<T> get _controller => host.controller;

  InputZoneFrame? get frame => host._frameOf(id);

  /// Whether the zone is there for input and accessibility now.
  bool get present => frame?.live ?? false;

  /// Whether the zone takes input now.
  bool get takesInput => zone.enabled && present;

  void _rangeChanged() => _anchor?.markNeedsSemanticsUpdate();

  MouseCursor get cursor => resolveCursor(
    zone.mouseCursor,
    clickable: target.acts,
    states: _controller._statesOf(id),
  );

  @override
  void initState() {
    super.initState();
    node.debugLabel = 'InputZone $id';
    host._zones[id] = this;
    _publishQuietly();
    _syncNode();
    zone.adjustRange?.addListener(_rangeChanged);
  }

  @override
  void didUpdateWidget(_Zone<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.zone;
    target.interactions = zone.interactions;
    if (old.enabled != zone.enabled) {
      zone.enabled ? target.enable() : target.disable();
    }
    if (old.adjustRange != zone.adjustRange) {
      old.adjustRange?.removeListener(_rangeChanged);
      zone.adjustRange?.addListener(_rangeChanged);
    }
    _publishQuietly();
    _syncNode();
    _anchor?.markNeedsSemanticsUpdate();
  }

  @override
  void dispose() {
    zone.adjustRange?.removeListener(_rangeChanged);
    target.dispose();
    if (identical(host._zones[id], this)) host._zones.remove(id);
    // A host that leaves after a newer one took its controller leaves the
    // states and the focus to the newer host's zones of the same ids.
    if (identical(_controller._host, host)) {
      _controller._forget(id);
      if (target.hasFocus) _controller._focus(id, focused: false);
    }
    node.dispose();
    super.dispose();
  }

  void _publishQuietly() {
    _quiet = true;
    _publish();
    _quiet = false;
  }

  // Whether the zone may take focus, as of the last time its frame could
  // be read: the semantics are described inside a layout, where it cannot.
  bool _focusable = false;

  void _syncNode() {
    _focusable = zone.focusable && takesInput;
    node.canRequestFocus = _focusable;
    node.skipTraversal = !target.acts;
  }

  void _publish() {
    final before = target.hovering ? cursor : null;
    _controller._publish(
      id,
      shownStates(
        said: zone.states,
        enabled: zone.enabled,
        live: target.live,
        navigation: host._navigation,
      ),
      notify: !_quiet,
    );
    if (target.hovering && cursor != before) {
      WidgetsBinding.instance.ensureVisualUpdate();
    }
  }

  void _focusChanged(bool focused) {
    target.hasFocus = focused;
    _controller._focus(id, focused: focused);
    if (focused) host._lastFocused = id;
    _anchor?.markNeedsSemanticsUpdate();
  }

  /// [input], given in the host's coordinates, in the zone's: its rect's
  /// top left is the origin, read at this input.
  InteractionInput _local(InteractionInput input) {
    if (frame case final frame?) {
      _origin = frame.rect.topLeft;
      _size = frame.rect.size;
    }
    final origin = _origin;
    return switch (input) {
      PointerDownInput() => input.copyWith(
        position: input.position - origin,
        regionSize: _size,
        reach: zone.reach,
      ),
      PointerMoveInput() => input.copyWith(
        position: input.position - origin,
        regionBox: _shiftedWithHost(input.regionBox),
      ),
      PointerUpInput() => input.copyWith(
        position: input.position - origin,
        regionBox: _shiftedWithHost(input.regionBox),
      ),
      PointerHoverInput() => PointerHoverInput(
        time: input.time,
        position: input.position - origin,
        inside: input.inside,
      ),
      PointerScrollInput() => PointerScrollInput(
        time: input.time,
        position: input.position - origin,
        scrollDelta: input.scrollDelta,
        kind: input.kind,
      ),
      ContextMenuInput() => ContextMenuInput(
        time: input.time,
        position: input.position - origin,
        source: input.source,
      ),
      PointerCancelInput() ||
      PointerAcceptedInput() ||
      ActivateInput() ||
      AdjustInput() => input,
    };
  }

  Rect _shiftedWithHost(Rect hostBox) => hostBox.topLeft & _size;

  /// The zone's hit rectangle now, in the host's coordinates.
  Rect get bounds {
    final frame = this.frame;
    if (frame == null) return Rect.zero;
    return zone.reach.takes(frame.rect);
  }

  static const Map<ShortcutActivator, Intent> _moves = {
    SingleActivator(LogicalKeyboardKey.arrowLeft): DirectionalFocusIntent(
      TraversalDirection.left,
    ),
    SingleActivator(LogicalKeyboardKey.arrowRight): DirectionalFocusIntent(
      TraversalDirection.right,
    ),
    SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(
      TraversalDirection.up,
    ),
    SingleActivator(LogicalKeyboardKey.arrowDown): DirectionalFocusIntent(
      TraversalDirection.down,
    ),
    SingleActivator(LogicalKeyboardKey.home): _ZoneEndIntent(last: false),
    SingleActivator(LogicalKeyboardKey.end): _ZoneEndIntent(last: true),
  };

  @override
  Widget build(BuildContext context) {
    if (!zone.focusable) return _ZoneAnchor<T>(state: this);
    final own = target.shortcuts(
      Directionality.maybeOf(context) ?? TextDirection.ltr,
    );
    return Actions(
      actions: target.actions,
      child: Shortcuts(
        includeSemantics: false,
        // The zone's own keys win over the arrows that move between zones.
        shortcuts: own.isEmpty ? _moves : {..._moves, ...own},
        child: FocusTraversalOrder(
          order: NumericFocusOrder(widget.order.toDouble()),
          child: Focus(
            focusNode: node,
            autofocus: zone.autofocus,
            includeSemantics: false,
            onFocusChange: _focusChanged,
            child: _ZoneAnchor<T>(state: this),
          ),
        ),
      ),
    );
  }
}

/// Moves focus to the first or the last zone: Home and End.
class _ZoneEndIntent extends Intent {
  const _ZoneEndIntent({required this.last});

  final bool last;
}

class _ZoneMove<T extends Object> extends Action<DirectionalFocusIntent> {
  _ZoneMove(this.zone);

  final _ZoneState<T> zone;

  @override
  Object? invoke(DirectionalFocusIntent intent) {
    zone.host._moveFocus(zone, intent.direction);
    return null;
  }
}

class _ZoneEnd<T extends Object> extends Action<_ZoneEndIntent> {
  _ZoneEnd(this.zone);

  final _ZoneState<T> zone;

  @override
  Object? invoke(_ZoneEndIntent intent) {
    zone.host._toEnd(zone, last: intent.last);
    return null;
  }
}
