part of 'tab_bar.dart';

enum _SearchSlot { bar, circle, field, close }

/// Builds a tab bar's selector under [collapse]; [hosted] when it hosts an
/// accessory or a search.
typedef _BarBuilder = Widget Function(
  GlassSelectorCollapse collapse, {
  required bool hosted,
});

/// A tab bar and its search tab, laid out over the screen's bottom.
class _SearchTabBar extends StatefulWidget {
  const _SearchTabBar({required this.controller, required this.bar});

  final GlassSearchController controller;
  final _BarBuilder bar;

  @override
  State<_SearchTabBar> createState() => _SearchTabBarState();
}

/// The collapse a search tab bar gives its bar: the bar turns into the tab
/// circle while searching, and a tap on the circle closes the search.
final class _SearchCollapse implements GlassSelectorCollapse {
  _SearchCollapse(this.motion, this.morph, this.onClose);

  final SearchTabMotion motion;
  final VoidCallback onClose;

  @override
  final MotionSelection<double> morph;

  @override
  MotionSelection<double>? get press => null;

  /// Whether the bar runs right to left.
  bool rtl = false;

  @override
  Rect circleIn(Size size) => _circleIn(size, rtl: rtl);

  @override
  bool get takesFinger => motion.isOpen;

  @override
  void pressDown(double t, double x) {}

  @override
  bool pressMove(double t, double x) => false;

  @override
  void pressUp(double t) {
    if (motion.tabTakesTaps) onClose();
  }

  @override
  void pressCancel(double t) {}

  @override
  void activate() => onClose();
}

class _SearchTabBarState extends State<_SearchTabBar> with SearchLaw {
  late final _motion = SearchTabMotion(open: widget.controller.isOpen);
  late final _activated = _motion.select((m) => m.activated);
  final _focus = FocusNode(debugLabel: 'GlassTabBar search');
  late final _q = _motion.select((m) => m.morph);
  late final _p = _motion.select((m) => m.focus.progress);
  late final _tabFade = _motion.select(
    (m) => (1 - m.focus.progress).clamp(0.0, 1.0),
  );
  late final _placeholder = _motion.select(
    (m) => ((m.morph - 0.4) / 0.6).clamp(0.0, 1.0),
  );
  late final _closeScale = _motion.select(
    (m) => SearchMotion.appearScaleFor(m.focus.progress),
  );
  late final _resting = _motion.select((m) => m.resting);
  late final _settled = _motion.select((m) => m.settled);
  late final _travelling = _motion.select((m) => !m.settled);
  late final _closeShown = _motion.select((m) => m.closeShown);
  late final _returned = _motion.select((m) => m.focus.progress == 0);
  late final _collapse = _SearchCollapse(_motion, _q, () {
    widget.controller.closeView();
  });

  double get _now => _motion.clock.now;

  @override
  bool get blurEnds => true;

  @override
  ValueListenable<bool> get returned => _returned;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _activated.addListener(_activate);
  }

  @override
  void didUpdateWidget(_SearchTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _changed();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _activated.removeListener(_activate);
    _focus.dispose();
    super.dispose();
  }

  void _activate() {
    if (mounted && _motion.activated && !_focus.hasFocus) {
      _focus.requestFocus();
    }
  }

  void _changed() {
    final open = widget.controller.isOpen;
    if (open == _motion.isOpen) return;
    setState(() => _motion.turn(_now, open: open));
    if (!open) {
      _focus.unfocus();
      // The query clears after the frame that closed the search, as the
      // field turns back.
      _motion.afterFrame(_now, () {
        if (mounted && !_motion.isOpen) widget.controller.clear();
      });
    }
  }

  @override
  void begin(double t, {required double keyboard}) {
    _motion.focused(t, keyboard: keyboard);
  }

  @override
  void end(double t) {
    _motion.unfocused(t);
  }

  @override
  void keyboardRose(double t) => _motion.keyboardRose(t);

  @override
  Widget build(BuildContext context) {
    final rtl = context.isRightToLeft;
    _collapse.rtl = rtl;
    final glyph = GlassDynamicColor.resolve(
      GlassTheme.labelColorOf(context),
      context,
    );
    final open = _motion.isOpen;
    return MotionScope(
      motion: _motion,
      child: SearchHost(
        law: this,
        field: GlassSearchField(
          controller: widget.controller,
          focusNode: _focus,
        ),
        builder: (context, parts) => CustomMultiChildLayout(
          delegate: _SearchTabLayout(
            q: _q,
            p: _p,
            settled: _settled,
            keyboard: parts.keyboard,
            rtl: rtl,
          ),
          children: [
            LayoutId(
              id: _SearchSlot.bar,
              child: MotionTransition(
                opacity: _tabFade,
                child: widget.bar(_collapse, hosted: true),
              ),
            ),
            LayoutId(
              id: _SearchSlot.circle,
              child: MotionVisibility(
                visible: _travelling,
                child: MotionVisibility(
                  visible: _resting,
                  maintainPaint: true,
                  maintainSemantics: true,
                  child: ExcludeFocus(
                    excluding: open,
                    child: _SearchCircle(
                      q: _q,
                      placeholder: _placeholder,
                      glyph: glyph,
                      rtl: rtl,
                      onTap: widget.controller.openView,
                    ),
                  ),
                ),
              ),
            ),
            if (open)
              LayoutId(
                id: _SearchSlot.field,
                child: MotionVisibility(
                  visible: _settled,
                  maintainSemantics: true,
                  child: parts.field,
                ),
              ),
            if (open)
              LayoutId(
                id: _SearchSlot.close,
                child: MotionVisibility(
                  visible: _closeShown,
                  child: MotionTransition(
                    opacity: _p,
                    scale: _closeScale,
                    child: parts.close,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Places a search tab bar's parts from the morph [q], the focus [p] and
/// the keyboard, laid out again on every change of any without a rebuild.
class _SearchTabLayout extends MultiChildLayoutDelegate {
  _SearchTabLayout({
    required this.q,
    required this.p,
    required this.settled,
    required this.keyboard,
    required this.rtl,
  }) : super(relayout: Listenable.merge([q, p, settled, keyboard]));

  final ValueListenable<double> q;
  final ValueListenable<double> p;
  final ValueListenable<bool> settled;
  final ValueListenable<double> keyboard;
  final bool rtl;

  @override
  void performLayout(Size size) {
    final room =
        size.width -
        2 * TabBarLayout.screenInset -
        SearchTabGeometry.circleSize -
        SearchBarGeometry.gap;
    final bar = layoutChild(
      _SearchSlot.bar,
      BoxConstraints.loose(Size(math.max(0, room), size.height)),
    );
    final g = searchTabLayout(
      size: size,
      barWidth: bar.width,
      keyboard: keyboard.value,
      rtl: rtl,
    );
    positionChild(_SearchSlot.bar, g.bar.topLeft);
    void place(_SearchSlot slot, Rect rect) {
      if (!hasChild(slot)) return;
      final box = Rect.fromLTWH(
        rect.left,
        rect.top,
        math.max(0, rect.width),
        math.max(0, rect.height),
      );
      layoutChild(slot, BoxConstraints.tight(box.size));
      positionChild(slot, box.topLeft);
    }

    final focus = p.value;
    place(_SearchSlot.circle, Rect.lerp(g.search, g.field, q.value)!);
    place(
      _SearchSlot.field,
      settled.value ? lerpRect(g.field, g.focusedField, focus) : g.field,
    );
    final closeFrom = Rect.fromLTWH(
      rtl ? g.field.left : g.field.right - RawGlassSearchField.height,
      g.field.top,
      RawGlassSearchField.height,
      RawGlassSearchField.height,
    );
    place(_SearchSlot.close, Rect.lerp(closeFrom, g.close, focus)!);
  }

  @override
  bool shouldRelayout(_SearchTabLayout oldDelegate) =>
      rtl != oldDelegate.rtl ||
      !identical(q, oldDelegate.q) ||
      !identical(p, oldDelegate.p) ||
      !identical(settled, oldDelegate.settled) ||
      !identical(keyboard, oldDelegate.keyboard);
}
