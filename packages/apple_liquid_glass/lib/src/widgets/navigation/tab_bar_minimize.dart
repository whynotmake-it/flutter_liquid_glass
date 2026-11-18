part of 'tab_bar.dart';

/// What a minimizing bar reads of its motion: the hint scale, the morph to
/// the circle, the accessory's two axes and whether the bar is minimized;
/// and the collapse it gives the bar below it.
final class _MinimizeFrames implements GlassSelectorCollapse {
  _MinimizeFrames(this.motion);

  final TabBarMinimizeMotion motion;
  late final hint = motion.select((m) => m.hint);
  @override
  late final morph = motion.select((m) => m.morph);
  @override
  late final press = motion.select((m) => m.press);
  late final accessoryX = motion.select((m) => m.accessoryX);
  late final accessoryY = motion.select((m) => m.accessoryY);
  late final minimized = motion.select((m) => m.minimized);

  /// Whether the group runs right to left, which puts the circle at its
  /// right.
  bool rtl = false;

  @override
  Rect circleIn(Size size) => _circleIn(size, rtl: rtl);

  @override
  bool get takesFinger => motion.minimized;

  @override
  void pressDown(double t, double x) => motion.pressDown(t, x);

  @override
  bool pressMove(double t, double x) => motion.pressMove(t, x);

  @override
  void pressUp(double t) => motion.pressUp(t);

  @override
  void pressCancel(double t) => motion.pressCancel(t);

  @override
  void activate() => motion.setMinimized(motion.clock.now, minimized: false);
}

/// The layout numbers of the minimized bar's circle and the bottom
/// accessory around it, read from UIKit's layout record on iOS 27.
abstract final class _Minimized {
  /// The space between the minimized bar and the expanded bar's edges,
  /// read from UIKit's layout record: the circle centered in the bar's
  /// height, so with the bar [TabBarLayout.screenInset] from the screen's
  /// side and bottom it sits 28 from both, as the measured search tab
  /// circle does.
  static const double collapsedInset =
      (TabBarLayout.height - TabBarMinimizeMotion.collapsedSize) / 2;

  /// The space between the expanded bar and the accessory above it: the
  /// accessory's bottom stands 8 above the bar's top (read from UIKit).
  static const double accessoryGap = 8;

  /// The space between the minimized circle and the inline accessory, and
  /// between the accessory and a minimized search circle (read from
  /// UIKit).
  static const double inlineGap = 14;

  /// The height of the bottom accessory, expanded and inline (read from
  /// UIKit; content may opt into 48 - 64 there, which this package does
  /// not offer).
  static const double accessoryHeight = 48;
}

Rect _circleIn(Size size, {required bool rtl}) {
  const inset = _Minimized.collapsedInset;
  const diameter = TabBarMinimizeMotion.collapsedSize;
  return Rect.fromLTWH(
    rtl ? size.width - inset - diameter : inset,
    size.height - inset - diameter,
    diameter,
    diameter,
  );
}

/// A tab bar that minimizes into a circle as the followed content scrolls.
class _MinimizingBar extends StatefulWidget {
  const _MinimizingBar({
    required this.behavior,
    required this.accessory,
    required this.look,
    required this.bar,
  });

  final GlassTabBarMinimizeBehavior behavior;
  final Widget? accessory;
  final GlassTabBarStyle look;
  final _BarBuilder bar;

  @override
  State<_MinimizingBar> createState() => _MinimizingBarState();
}

class _MinimizingBarState extends State<_MinimizingBar> {
  late final _MinimizeFrames _body = _MinimizeFrames(
    TabBarMinimizeMotion(behavior: widget.behavior),
  );

  double get _now => _body.motion.clock.now;
  ValueNotifier<MotionScroll?>? _active;
  MotionScroll? _scroll;
  MotionSelection<Object?>? _scrolling;
  MotionScrollPhase _phase = MotionScrollPhase.idle;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = GlassChrome.maybeOf(context)?.active;
    if (identical(active, _active)) return;
    _active?.removeListener(_follow);
    _active = active;
    active?.addListener(_follow);
    _follow();
  }

  @override
  void didUpdateWidget(_MinimizingBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.behavior != widget.behavior) {
      _body.motion.setBehavior(_now, widget.behavior);
    }
  }

  @override
  void dispose() {
    _active?.removeListener(_follow);
    _scrolling?.removeRenderListener(_scrolled);
    super.dispose();
  }

  void _follow() {
    final next = _active?.value;
    if (identical(next, _scroll)) return;
    _scrolling?.removeRenderListener(_scrolled);
    _scroll = next;
    _phase = MotionScrollPhase.idle;
    final scrolling = _scrolling = next?.select((s) => (s.phase, s.metrics));
    scrolling?.addRenderListener(_scrolled);
  }

  void _scrolled() {
    final scroll = _scroll;
    final metrics = scroll?.metrics;
    if (scroll == null || metrics == null || !metrics.hasContentDimensions) {
      return;
    }
    final away = _body.motion.scrollAway;
    final phase = scroll.phase;
    final previous = _phase;
    _phase = phase;
    final offset = metrics.pixels;
    final min = metrics.minScrollExtent;
    final max = metrics.maxScrollExtent;
    if (!_body.motion.behavior.minimizes) {
      away.last = offset;
      return;
    }
    _body.motion.advance(_now);
    final user =
        previous == MotionScrollPhase.dragging ||
        previous == MotionScrollPhase.decelerating;
    if (phase == MotionScrollPhase.dragging &&
        previous != MotionScrollPhase.dragging) {
      away.beginDrag();
    }
    // A drag that began and went into its glide within one frame is heard
    // only as its glide.
    if (phase == MotionScrollPhase.decelerating && !user) {
      away.beginDrag();
      away.endDrag(decelerates: true);
    }
    if (previous == MotionScrollPhase.dragging &&
        phase != MotionScrollPhase.dragging) {
      away.endDrag(decelerates: phase == MotionScrollPhase.decelerating);
    }
    switch (phase) {
      case MotionScrollPhase.dragging || MotionScrollPhase.decelerating:
        away.scroll(
          offset,
          min: min,
          max: max,
          tracking: phase == MotionScrollPhase.dragging,
        );
      case MotionScrollPhase.programmatic || MotionScrollPhase.idle:
        away.last = offset;
        if (previous == MotionScrollPhase.decelerating) {
          away.endDeceleration();
        }
        if (_body.motion.minimized && offset <= min + 0.5) {
          away.scrollToTop();
        }
    }
  }

  @override
  Widget build(BuildContext context) => MotionScope(
    motion: _body.motion,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        _body.motion.extent = width;
        final accessory = widget.accessory;
        final rtl = context.isRightToLeft;
        _body.rtl = rtl;
        final bar = SizedBox(
          width: width,
          height: GlassTabBar.height,
          child: MotionTransition(
            scale: _body.hint,
            child: widget.bar(_body, hosted: accessory != null),
          ),
        );
        if (accessory == null) return bar;
        return SizedBox(
          width: width,
          height: GlassTabBar.groupHeight(accessory: true),
          child: Stack(
            children: [
              Positioned.fill(
                child: _Accessory(
                  body: _body,
                  width: width,
                  rtl: rtl,
                  look: widget.look,
                  child: accessory,
                ),
              ),
              Positioned(left: 0, right: 0, bottom: 0, child: bar),
            ],
          ),
        );
      },
    ),
  );
}
