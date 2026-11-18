part of 'menu_anchor.dart';

/// The open menu on the overlay: its glass, the source's look on it, its
/// rows and the submenu cards over them, each following the motion's
/// frames without a rebuild.
///
/// The targets of the top card are the zones of one host: one Tab stop,
/// whose arrows, Home and End move the focus among them, Space and Enter
/// choose, the arrow toward the trailing edge opens a submenu and the one
/// toward the leading edge or Escape goes back. The focused row is the
/// highlighted one; the mouse focuses the row it rests on. Touches stay
/// with the motion, which follows the finger over the whole menu.
class _MenuLayer extends StatefulWidget {
  const _MenuLayer({required this.host});

  final _MenuHost<StatefulWidget> host;

  @override
  State<_MenuLayer> createState() => _MenuLayerState();
}

class _MenuLayerState extends State<_MenuLayer> implements MenuLayerScope {
  late final _scroll = MenuLayerScroll(this);
  final _ids = MenuZoneIds();
  late final _highlight = MenuLayerHighlight(this, zones: _zones, ids: _ids);
  late final _keys = MenuLayerKeys(
    this,
    zones: _zones,
    ids: _ids,
    scroll: _scroll,
  );
  late final _hover = MenuLayerHover(this, keys: _keys);
  late final _cards = MenuLayerCards(
    this,
    scroll: _scroll,
    highlight: _highlight,
  );
  final _zones = InputZonesController<int>();
  final Map<int, List<Interaction>> _rowInputs = {};
  late MenuLayerStructure _built;

  _MenuHost<StatefulWidget> get _host => widget.host;

  @override
  late final MotionSelection<MenuMotion> frames = _host._steps!;

  late final _input = _MenuInput(
    down: _host._pointerDown,
    move: _host._pointerMove,
    up: _host._pointerUp,
    cancel: _host._pointerCancel,
    heard: _host._takeHeard,
  );

  late final _hoverInput = _HoverInput(onHover: _hovered);

  @override
  MenuMotion get motion => _host._motion!;

  @override
  MenuLayerStructure get built => _built;

  @override
  MenuContent get content => _host._content;

  @override
  void command(void Function(MenuMotion motion, double t) command) =>
      _host._command(command);

  @override
  void initState() {
    super.initState();
    frames.addListener(_tick);
    _zones.addListener(_keys.focusMoved);
    _built = _structure();
  }

  @override
  void dispose() {
    frames.removeListener(_tick);
    _zones.removeListener(_keys.focusMoved);
    _zones.dispose();
    _scroll.dispose();
    super.dispose();
  }

  MenuLayerStructure _structure() {
    final cards = motion.cards;
    final root = cards[0].layout;
    return MenuLayerStructure(
      layouts: [for (final card in cards) card.layout],
      hidden: [for (final card in cards.skip(1)) card.source, null],
      open: motion.isOpen,
      scrolls: root.height > motion.visibleRootHeight + 0.5,
      top: motion.topCard,
    );
  }

  void _tick() {
    final structure = _structure();
    if (structure == _built) return;
    if (structure.top != _built.top) {
      _keys.cardChanged(structure.top);
      _hover.cardChanged();
    }
    setState(() => _built = structure);
  }

  @override
  bool get current => motion.isOpen && motion.topCard == _built.top;

  void _menuFocused(bool focused) {
    if (focused) _keys.menuFocused();
  }

  void _hovered(Offset local) => _hover.hovered(
    _host._local(
      (context.findRenderObject()! as RenderBox).localToGlobal(local),
    ),
  );

  List<Interaction> _inputsOf(int id) => _rowInputs.putIfAbsent(
    id,
    () => [
      _RowInput(
        onActivate: () => _keys.choose(_ids.targetOf(id), pending: -1),
        onEnter: () => _hover.rowEntered(id),
      ),
    ],
  );

  MotionDriven _driven(
    SingleChildRenderObjectWidget Function(MenuMotion motion) template, {
    Widget? child,
    Key? key,
  }) => menuDriven(frames, template, child: child, key: key);

  // A blur too small to see costs a layer and shows nothing.
  static double _visible(double sigma) => sigma > 0.01 ? sigma : 0;

  late final _contentBlur = MotionSelection<double>(() {
    final motion = frames.value;
    return _visible(motion.contentBlur / motion.contentScale);
  });

  late final _lookBlur = MotionSelection<double>(
    () => _visible(frames.value.buttonLookBlur),
  );

  Matrix4 _contentTransform() {
    final scale = motion.contentScale;
    final stretch = motion.contentStretch;
    return Matrix4.diagonal3Values(scale * stretch.dx, scale * stretch.dy, 1);
  }

  Matrix4 _lookTransform() {
    final blob = motion.buttonBlob;
    return Matrix4.diagonal3Values(
      blob.scale * motion.buttonLookStretch,
      blob.scale,
      1,
    );
  }

  @override
  Widget build(BuildContext context) {
    final structure = _built;
    final style = _host._style;
    final layouts = structure.layouts;
    final top = layouts.length - 1;
    final under = top == 0 ? layouts.length : top;
    final content = Stack(
      clipBehavior: Clip.none,
      children: [
        // A fade in a chain drops what it hides from screen readers, as
        // a transition's would not.
        _driven(
          (motion) => Opacity(
            opacity: motion.cardGlassTransferred
                ? 0
                : motion.contentOpacity.clamp(0.0, 1.0),
          ),
          child: MotionTransition(
            blur: _contentBlur,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var i = 0; i < under; i++)
                  _cards.card(i, layouts[i], style),
              ],
            ),
          ),
        ),
        if (top > 0) _cards.card(top, layouts[top], style),
      ],
    );
    final layer = InputZones<int>(
      zones: structure.open
          ? _keys.zonesOf(layouts[structure.top], _inputsOf)
          : const [],
      frameOf: _keys.frameOf,
      frames: frames,
      controller: _zones,
      axis: null,
      stops: InputZoneStops.one,
      onEdge: _keys.edge,
      excludeChildSemantics: false,
      interactions: [_input, _hoverInput],
      hostFeedback: _MenuHost._feedback,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ..._host._backdrop(this),
          IgnorePointer(
            child: MenuLiveGlass(
              live: frames,
              frameOf: () => menuFrame(
                motion,
                sourceTint: _host._sourceTint,
                opacity: motion.glassOpacity,
              ),
            ),
          ),
          if (motion.drawsSource)
            IgnorePointer(
              child: _driven(
                (motion) => menuPlacement(
                  motion.buttonBlob.localRect,
                  Transform(
                    alignment: Alignment.center,
                    transform: _lookTransform(),
                    child: Opacity(
                      opacity: motion.buttonLookOpacity.clamp(0.0, 1.0),
                    ),
                  ),
                ),
                // A picture of the source, which screen readers read in its
                // place.
                child: ExcludeSemantics(
                  child: MotionTransition(
                    blur: _lookBlur,
                    child: Center(child: _host._look),
                  ),
                ),
              ),
            ),
          _driven(
            (motion) => ClipRRect(
              clipper: MenuClip(
                motion.cards.length < 2
                    ? motion.menuBlob.rrect
                    : RRect.fromRectAndRadius(Rect.largest, Radius.zero),
              ),
              child: menuPlacement(
                motion.contentRect.topLeft & motion.menuRect.size,
                Transform(
                  alignment: Alignment.topLeft,
                  transform: _contentTransform(),
                ),
              ),
            ),
            child: IgnorePointer(ignoring: !structure.open, child: content),
          ),
        ],
      ),
    );
    return Actions(
      actions: {DismissIntent: _MenuEscape(this)},
      child: Focus(
        focusNode: _host._menuFocus,
        includeSemantics: false,
        onFocusChange: _menuFocused,
        child: layer,
      ),
    );
  }
}
