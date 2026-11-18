part of 'alert.dart';

class _AlertViewState extends State<_AlertView> {
  final _press = GlassPress();
  late final _lean = _press.select((p) => p.lean);
  late final _pressX = _press.select((p) => p.scaleX);
  late final _pressY = _press.select((p) => p.scaleY);
  // A scroll of the content takes the touch from the platter and from the
  // actions, which cancels the lift and the press.
  late final List<Interaction> _platter = [
    FollowInteraction(_press, role: InteractionRole.content),
  ];
  final _zones = InputZonesController<int>();
  final _scroll = ScrollController();
  // Bumped when the card's size settles, as the actions' frames read the
  // layout.
  final _layouts = ValueNotifier<int>(0);
  late final _frames = Listenable.merge([_scroll, _layouts]);
  final _card = GlobalKey(debugLabel: 'alert card');
  final _block = GlobalKey(debugLabel: 'alert actions');
  final List<List<Interaction>> _presses = [];
  final List<GlassHighlight> _highlights = [];
  late GlassHighlightLook _highlightLook;
  late final _opacity = widget.motion.select((m) => m.opacity);
  late final _scale = widget.motion.select((m) => m.scale);
  late final _leaving = widget.motion.select((m) => m.isLeaving);
  late final _frame = widget.motion.select(
    (m) => GlassFrame(shape: _platterShape, opacity: m.opacity),
  );
  static const _platterShape = LiquidRoundedSuperellipse(
    radius: _AlertLook.cornerRadius,
  );

  List<GlassAlertAction> _shown = const [];
  bool _row = false;
  bool _rtl = false;

  @override
  void initState() {
    super.initState();
    _leaving.addListener(_left);
  }

  @override
  void dispose() {
    _leaving.removeListener(_left);
    _zones.dispose();
    _scroll.dispose();
    _layouts.dispose();
    super.dispose();
  }

  // The presentation is inert from its leave on; a finger already down
  // stops lifting the platter.
  void _left() {
    if (_leaving.value && _press.isPressed) {
      _press.pointerCancel(widget.motion.clock.now);
    }
  }

  void _choose(GlassAlertAction action) {
    if (_leaving.value || !action.enabled) return;
    PresentationHandle.of(
      context,
    ).dismiss(DismissTrigger.programmatic, action);
  }

  List<Interaction> _pressOf(int index) {
    while (_presses.length <= index) {
      final i = _presses.length;
      _presses.add([
        PressInteraction(
          role: InteractionRole.content,
          onTap: (t) => _choose(_shown[i]),
        ),
      ]);
    }
    return _presses[index];
  }

  GlassHighlight _highlightOf(int index) {
    while (_highlights.length <= index) {
      _highlights.add(
        GlassHighlight(
          look: _highlightLook,
          states: _zones.states(_highlights.length),
        ),
      );
    }
    return _highlights[index];
  }

  // Where action [index] lies in the card: its slot in the block of
  // buttons, carried by the layout and the scroll to the card's box, and
  // cut to what the card shows.
  InputZoneFrame? _frameOf(int index) {
    final card = _card.currentContext?.findRenderObject();
    final block = _block.currentContext?.findRenderObject();
    if (card is! RenderBox ||
        block is! RenderBox ||
        !card.hasSize ||
        !block.hasSize ||
        !block.attached ||
        index >= _shown.length) {
      return null;
    }
    final slot = _slot(index, block.size.width);
    final rect = MatrixUtils.transformRect(block.getTransformTo(card), slot);
    return InputZoneFrame(
      rect.intersect(Offset.zero & card.size),
      radius: BorderRadius.circular(_AlertLook.buttonHeight / 2),
    );
  }

  Rect _slot(int index, double width) {
    const height = _AlertLook.buttonHeight;
    if (_row) {
      final each = (width - _AlertLook.buttonGap) / 2;
      final first = (index == 0) != _rtl;
      return Rect.fromLTWH(
        first ? 0 : each + _AlertLook.buttonGap,
        0,
        each,
        height,
      );
    }
    return Rect.fromLTWH(
      0,
      index * (height + _AlertLook.buttonGap),
      width,
      height,
    );
  }

  static MotionHaptic? _feedback(int action, InteractionEvent event) =>
      switch (event) {
        ScrubChangeEvent(atDown: false) => MotionHaptic.selection,
        _ => null,
      };

  GlassAlertStyle _look = const GlassAlertStyle();
  late GlassTextScale _text;

  bool _fitsInRow(double width, BuildContext context) {
    final each =
        (width - 2 * _AlertLook.buttonInset - _AlertLook.buttonGap) / 2;
    final direction = Directionality.of(context);
    for (final action in widget.actions) {
      final label = action.child;
      if (label is! Text || label.data == null) return false;
      final measured = _text.measure(
        label.data!,
        _labelStyle(action, context),
        textDirection: direction,
        maxLines: 1,
      );
      if (measured.size.width + 2 * _AlertLook.buttonTextInset > each) {
        return false;
      }
    }
    return true;
  }

  TextStyle _labelStyle(GlassAlertAction action, BuildContext context) {
    final look = _look;
    final label = GlassTheme.labelColorOf(context);
    final color = !action.enabled
        ? GlassTheme.tertiaryLabelColorOf(context)
        : action.isDefaultAction
        ? look.defaultActionColor ?? const Color(0xFFFFFFFF)
        : action.isDestructive
        ? look.destructiveActionColor ?? GlassColors.systemRed
        : look.actionColor ?? label;
    return _text.resolve(
      TextStyle(
            fontSize: _AlertLook.textFontSize,
            height: _AlertLook.textHeight,
            fontWeight: action.isDefaultAction
                ? _AlertLook.preferredWeight
                : FontWeight.w500,
          )
          .merge(look.actionTextStyle)
          .copyWith(
            color: GlassDynamicColor.resolve(color, context),
          ),
    );
  }

  Color _fillOf(GlassAlertAction action, BuildContext context) =>
      GlassDynamicColor.resolve(
        action.isDefaultAction && action.enabled
            ? _look.defaultActionFillColor ??
                  GlassTheme.primaryColorOf(context) ??
                  GlassColors.systemBlue
            : _look.actionFillColor ?? GlassColors.tertiarySystemFill,
        context,
      );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _derive();
  }

  @override
  void didUpdateWidget(_AlertView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _derive();
  }

  // Everything a handler or a slot reads is settled where its inputs
  // change, not in build: the look and direction from the context, the row
  // fit and the order from the actions.
  void _derive() {
    _look = (widget.style ?? const GlassAlertStyle()).merge(
      GlassAlertStyle.maybeOf(context),
    );
    _rtl = Directionality.of(context) == TextDirection.rtl;
    _text = GlassTextScale.of(context, max: _AlertLook.maxTextScale);
    _row =
        !widget.actionSheet &&
        widget.actions.length == 2 &&
        _fitsInRow(_cardWidth(context), context);
    _shown = _ordered(widget.actions, row: _row, popover: _inPopover);
  }

  bool get _inPopover => widget.anchorRect != null;

  double _cardWidth(BuildContext context) => math.min(
    _inPopover ? _AlertLook.popoverWidth : AlertMotion.width,
    MediaQuery.sizeOf(context).width - 2 * _AlertLook.screenMargin,
  );

  @override
  Widget build(BuildContext context) {
    final width = _cardWidth(context);
    _highlightLook = GlassHighlightLook.of(context);
    for (final highlight in _highlights) {
      highlight.look = _highlightLook;
    }
    return MotionScope(
      motion: _press,
      child: _place(_buildCard(width, context), context),
    );
  }

  Widget _place(Widget card, BuildContext context) {
    final popover = widget.anchorRect;
    if (popover != null) {
      final media = MediaQuery.of(context);
      return PopoverLayout(
        source: popover,
        scale: _scale,
        opacity: _opacity,
        maxWidth: _AlertLook.popoverWidth,
        padding: media.paddingAboveKeyboard,
        direction: Directionality.of(context),
        card: card,
      );
    }
    final safe = MediaQuery.paddingOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        safe.left,
        safe.top,
        safe.right,
        math.max(safe.bottom, keyboard),
      ),
      child: Center(
        child: MotionTransition(
          scale: _scale,
          child: MotionTransition(
            offset: _lean,
            scaleX: _pressX,
            scaleY: _pressY,
            child: card,
          ),
        ),
      ),
    );
  }

  Widget _buildCard(double width, BuildContext context) {
    final label = GlassTheme.labelColorOf(context);
    final title = widget.title;
    final message = widget.message;
    final both = title != null && message != null;
    final header = <Widget>[
      if (title != null)
        DefaultTextStyle(
          style: _text.resolve(
            TextStyle(
              fontSize: _AlertLook.textFontSize,
              height: _AlertLook.textHeight,
              fontWeight: both
                  ? FontWeight.w600
                  : _AlertLook.singleHeaderWeight,
              color: label,
            ).merge(_look.titleTextStyle).resolvedColor(context),
          ),
          child: title,
        ),
      if (both) const SizedBox(height: _AlertLook.titleGap),
      if (message != null)
        DefaultTextStyle(
          style: _text.resolve(
            (both
                    ? const TextStyle(
                        fontSize: 15,
                        height: _AlertLook.messageHeight,
                        color: _messageColor,
                      )
                    : TextStyle(
                        fontSize: _AlertLook.textFontSize,
                        height: _AlertLook.textHeight,
                        color: label,
                      ))
                .merge(_look.messageTextStyle)
                .resolvedColor(context),
          ),
          child: message,
        ),
    ];
    final buttons = [
      for (final (i, action) in _shown.indexed)
        _AlertButton(
          action: action,
          states: _zones.states(i),
          highlight: _highlightOf(i),
          label: _labelStyle(action, context),
          fill: _fillOf(action, context),
        ),
    ];
    final block = _row
        ? Row(
            key: _block,
            children: [
              Expanded(child: buttons[0]),
              const SizedBox(width: _AlertLook.buttonGap),
              Expanded(child: buttons[1]),
            ],
          )
        : Column(
            key: _block,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < buttons.length; i++) ...[
                if (i > 0) const SizedBox(height: _AlertLook.buttonGap),
                buttons[i],
              ],
            ],
          );
    final content = Padding(
      padding: EdgeInsets.only(
        top: header.isNotEmpty ? _AlertLook.headerTop : 0,
        bottom: _AlertLook.buttonInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(
                left: _AlertLook.textInset,
                right: _AlertLook.textInset,
                bottom: both
                    ? _AlertLook.headerBottom
                    : _AlertLook.singleHeaderBottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: header,
              ),
            ),
          if (buttons.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(
                top: _AlertLook.buttonInset,
                left: _AlertLook.buttonInset,
                right: _AlertLook.buttonInset,
              ),
              child: block,
            ),
        ],
      ),
    );
    return _text.apply(
      InputZones<int>(
        zones: [
          for (final (i, action) in _shown.indexed)
            InputZone<int>(
              id: i,
              interactions: _pressOf(i),
              enabled: action.enabled,
              reach: glassTargetReach,
              autofocus: action.isDefaultAction && action.enabled,
              semantics: SemanticsProperties(
                label: glassLabelTextOf(action.child),
                button: true,
              ),
            ),
        ],
        frameOf: _frameOf,
        frames: _frames,
        controller: _zones,
        axis: _row ? Axis.horizontal : Axis.vertical,
        slides: true,
        feedback: _feedback,
        excludeChildSemantics: false,
        // The platter's lift sits below the zones: a region above them
        // would answer their Space and Enter.
        child: _inPopover
            ? _measured(width, content)
            : InputRegion(
                interactions: _platter,
                child: _measured(width, content),
              ),
      ),
    );
  }

  Widget _measured(double width, Widget content) => MotionMeasure(
    onSize: (t, size) => _layouts.value++,
    child: SizedBox(
      key: _card,
      width: width,
      child: Stack(
        children: [
          if (!_inPopover)
            Positioned.fill(
              child: GlassSurface.live(
                role: GlassRole.panel,
                frame: _frame,
                child: const SizedBox.expand(),
              ),
            ),
          MotionTransition(
            opacity: _opacity,
            child: ClipRSuperellipse(
              borderRadius: BorderRadius.circular(
                _inPopover ? popoverCornerRadius : _AlertLook.cornerRadius,
              ),
              child: ListView(
                controller: _scroll,
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                physics: const ClampingScrollPhysics(),
                children: [content],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
