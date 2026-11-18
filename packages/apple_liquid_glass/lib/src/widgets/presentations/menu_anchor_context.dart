part of 'menu_anchor.dart';

/// Shows a menu beside a lifted preview of [child] when it is held, as an
/// iOS 27 context menu does.
///
/// UIKit: `UIContextMenuInteraction`. SwiftUI: `contextMenu`. Flutter:
/// `CupertinoContextMenu`.
///
/// A finger resting on [child] grows it by UIKit's measured law (nothing for
/// 0.184 s, then 32 points a second to 8 points, then 20 a second to 15 points
/// along its longest side); a finger that moves drops it back, and so does one
/// that lifts before 0.42 s. Held for 0.78 s, the page dims (20 percent light,
/// 48 percent dark), the preview lifts to 1.15 times its size (26 points at
/// most), fitted into the safe area, and the menu grows out of a blob at its
/// center beside it, on one spring of response 0.284 s (iPhone 16 Pro, iOS 27).
/// The finger then slides onto a row and chooses it on release; let go on the
/// preview, it leaves the menu open. A tap outside, Escape and Back close it.
/// [previewBuilder] draws the open preview in place of a copy of [child],
/// fading in as it lifts.
class GlassContextMenu extends StatefulWidget {
  /// Creates a context menu of [menuChildren] for [child].
  const GlassContextMenu({
    required this.menuChildren,
    required this.child,
    this.previewBuilder,
    this.controller,
    this.enabled = true,
    this.semanticLabel,
    this.order = GlassMenuOrder.automatic,
    this.style,
    super.key,
  });

  /// The menu's entries.
  final List<GlassMenuEntry> menuChildren;

  /// What is held.
  final Widget child;

  /// Builds the preview shown while the menu is open, or null for a copy
  /// of [child].
  final WidgetBuilder? previewBuilder;

  /// Opens and closes the menu from code.
  final GlassMenuController? controller;

  /// Whether a hold opens the menu.
  final bool enabled;

  /// What accessibility reads for the menu.
  final String? semanticLabel;

  /// How the rows order in a menu that opens upward.
  final GlassMenuOrder order;

  /// The look of the menu's rows, over the theme's.
  final GlassMenuStyle? style;

  /// The scale of UIKit's open preview over a preview of natural [size]:
  /// 1.15 while that adds at most 26 points along its longest side, those
  /// points beyond (iPhone 16 Pro, iOS 27).
  @internal
  static double previewScale(Size size) {
    final longest = size.longestSide;
    if (longest <= 0) return 1;
    return 1 + math.min(0.15 * longest, 26) / longest;
  }

  @override
  State<GlassContextMenu> createState() => _ContextMenuState();
}

class _ContextMenuState extends _MenuHost<GlassContextMenu> {
  late final _hold = ContextHold(
    onCommit: () => MotionHaptic.heavyImpact.play(context),
    onOpen: _openUnder,
  );
  late final _growth = _hold.select((hold) => hold.growth);

  // The hold hears the touch outside the gesture arena: a child that claims
  // its touch at once, a glass button, would win it, and Flutter's arena
  // never hands a won touch on, where UIKit cancels the button's.
  late final _hear = _ObservedTouch(
    down: _down,
    move: _move,
    up: _up,
    cancel: _cancel,
    heard: _takeHeard,
  );

  // Only claims the touch when the menu opens, so a surrounding scroll view
  // does not take the finger sliding into the rows.
  late final _claim = _MenuInput(
    claimAfter: ContextHold.openAfter,
    down: (pointer, t, global) => _enabled && !(_motion?.isPresented ?? false),
  );
  // One Tab stop, where the keyboard's context menu key lands.
  final _claimFocus = FocusNode(debugLabel: 'GlassContextMenu');

  // What the region reports of the keyboard focus and the mouse, which the
  // ring and the hover response around the anchor follow.
  final _states = WidgetStatesController();

  // A mouse opens the menu at the press of its secondary button, as a
  // context menu does on iPadOS and macOS.
  late final _secondary = SecondaryClickInteraction(
    onClick: (t, position) => _openFromCode(),
  );

  @override
  void dispose() {
    _claimFocus.dispose();
    _states.dispose();
    super.dispose();
  }

  int? _held;
  Offset _from = Offset.zero;
  Offset _finger = Offset.zero;
  Rect _heldRect = Rect.zero;
  Rect _previewRect = Rect.zero;

  // Where the preview grows out of and lands: the held view as the hold
  // grew it while the menu opens, at its natural size once it closes, as
  // the hidden view is by then.
  Rect _home = Rect.zero;

  @override
  List<GlassMenuEntry> get _entries => widget.menuChildren;

  @override
  GlassMenuOrder get _order => widget.order;

  @override
  GlassMenuController? get _controller => widget.controller;

  @override
  bool get _enabled => widget.enabled;

  @override
  String? get _semanticLabel => widget.semanticLabel;

  @override
  Widget? get _look => null;

  @override
  void didUpdateWidget(GlassContextMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updated(
      oldController: oldWidget.controller,
      wasEnabled: oldWidget.enabled,
    );
  }

  MenuAttachment _attach(Rect held, Size bounds, EdgeInsets padding) {
    final preferred = held.size * GlassContextMenu.previewScale(held.size);
    final fitted = MenuAttachment.fitPreview(
      preferred: preferred,
      bounds: bounds,
      padding: padding,
    );
    return MenuAttachment(
      held: held,
      preview: Rect.fromCenter(
        center: held.center,
        width: fitted.width,
        height: fitted.height,
      ),
    );
  }

  @override
  MenuMotion _createMotion(
    MenuSource source,
    Size bounds,
    EdgeInsets padding,
  ) {
    final attachment = _attach(source.shape, bounds, padding);
    final motion = MenuMotion.context(
      source: source,
      layout: _content.root,
      bounds: bounds,
      padding: padding,
      metrics: _content.metrics,
      attachment: attachment,
    );
    _placePreview(motion, source.shape);
    return motion;
  }

  @override
  void _relayout(
    MenuMotion motion,
    MenuSource source,
    Size bounds,
    EdgeInsets padding,
  ) {
    motion.relayout(
      source: source,
      bounds: bounds,
      padding: padding,
      metrics: _content.metrics,
      attachment: _attach(source.shape, bounds, padding),
    );
    _placePreview(motion, source.shape);
  }

  void _placePreview(MenuMotion motion, Rect held) {
    _heldRect = held;
    _home = held;
    _previewRect = motion.attachment!.preview.shift(motion.previewShift);
  }

  @override
  void _stepped() {
    super._stepped();
    if (_motion?.isClosing ?? false) _home = _heldRect;
  }

  void _openUnder(double t, double growth) {
    final pointer = _held;
    _held = null;
    if (pointer == null || !mounted || !_enabled || _isOpen) return;
    final motion = _prepare(at: t);
    final longest = _heldRect.size.longestSide;
    final grown = longest <= 0 ? 1.0 : 1 + growth / longest;
    _home = Rect.fromCenter(
      center: _heldRect.center,
      width: _heldRect.width * grown,
      height: _heldRect.height * grown,
    );
    _pointer = pointer;
    final local = _local(_finger);
    _command(
      (motion, t) => motion.holdOpen(t, local),
      at: math.max(t, motion.now),
    );
  }

  void _drop(double t) {
    _held = null;
    _hold.release(t);
  }

  void _down(int pointer, double t, Offset global) {
    if (!_enabled ||
        _held != null ||
        _pointer != null ||
        (_motion?.isPresented ?? false)) {
      return;
    }
    _held = pointer;
    _from = global;
    _finger = global;
    _hold.down(t);
  }

  void _move(int pointer, double t, Offset global) {
    if (pointer == _held) {
      _finger = global;
      if (ContextHold.leaves(global - _from)) _drop(t);
      return;
    }
    _pointerMove(pointer, t, global);
  }

  void _up(int pointer, double t, Offset global) {
    if (pointer == _held) {
      _finger = global;
      if (_hold.isCommitted) {
        _openUnder(t, _hold.release(t));
        _pointerUp(pointer, t, global);
      } else {
        _drop(t);
      }
      return;
    }
    _pointerUp(pointer, t, global);
  }

  void _cancel(int pointer, double t) {
    if (pointer == _held) {
      _drop(t);
      return;
    }
    _pointerCancel(pointer, t);
  }

  Matrix4 _growthTransform() {
    final size = _heldRect.isEmpty
        ? (context.findRenderObject() as RenderBox?)?.size ?? Size.zero
        : _heldRect.size;
    final longest = size.longestSide;
    final s = longest <= 0 ? 1.0 : 1 + _hold.growth / longest;
    return Matrix4.diagonal3Values(s, s, 1);
  }

  Rect _previewNow() {
    final motion = _motion;
    if (motion == null) return _home;
    return Rect.lerp(_home, _previewRect, motion.progress) ?? _previewRect;
  }

  // The page dims to 20 percent black in light mode, 48 in dark
  // (context-menu.md).
  @override
  double Function(MenuMotion motion) _dim(BuildContext context) {
    final full = GlassTraits.of(context).brightness == Brightness.dark
        ? 0.48
        : 0.2;
    return (motion) => full * motion.dim;
  }

  @override
  List<Widget> _backdrop(_MenuLayerState layer) {
    final natural = _heldRect.size;
    final builder = widget.previewBuilder;
    final frames = layer.frames;
    Widget carried(Size size, Widget child) => menuDriven(frames, (_) {
      final rect = _previewNow();
      return menuPlacement(
        rect.topLeft & size,
        Transform(
          alignment: Alignment.topLeft,
          transform: Matrix4.diagonal3Values(
            size.width <= 0 ? 1 : rect.width / size.width,
            size.height <= 0 ? 1 : rect.height / size.height,
            1,
          ),
        ),
      );
    }, child: child);
    double shown() => ((_motion?.progress ?? 0) * 2).clamp(0.0, 1.0);
    // The preview is a picture of the anchor, which screen readers read
    // in its place.
    return [
      IgnorePointer(
        child: ExcludeSemantics(
          child: Stack(
            children: [
              carried(
                natural,
                builder == null
                    ? widget.child
                    : menuDriven(
                        frames,
                        (_) => Opacity(opacity: 1 - shown()),
                        child: widget.child,
                      ),
              ),
              if (builder != null)
                carried(
                  _previewRect.size,
                  menuDriven(
                    frames,
                    (_) => Opacity(opacity: shown()),
                    child: Builder(builder: builder),
                  ),
                ),
            ],
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    _style = MenuAppearance.of(context, widget.style);
    final enabled = widget.enabled;
    // The anchor is the region's one node, named by what it shows, with
    // the hold as its long press; the menu is read after it.
    return _host(
      InputRegion(
        interactions: [_hear, _claim, _secondary],
        feedback: _MenuHost._feedback,
        statesController: _states,
        mouseCursor: WidgetStateMouseCursor.adaptiveClickable,
        enabled: enabled,
        focusNode: _claimFocus,
        semantics: SemanticsProperties(
          onLongPress: enabled ? _openFromCode : null,
        ),
        child: MotionSourceBox(
          source: _source,
          child: menuDriven(
            _growth,
            (_) => Transform(
              alignment: Alignment.center,
              transform: _growthTransform(),
            ),
            child: GlassHighlightPaint.of(
              context,
              states: _states,
              shape: const LiquidRoundedRectangle(radius: 0),
              wash: true,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
