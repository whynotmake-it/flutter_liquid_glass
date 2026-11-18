part of 'tab_bar.dart';

class _AccessoryScope
    extends InheritedNotifier<ValueNotifier<GlassTabAccessoryPlacement>> {
  const _AccessoryScope({required super.notifier, required super.child});
}

/// Lays the accessory's content out in the rect of its placement, laid out
/// again when the placement changes, without a rebuild.
class _AccessoryLayout extends SingleChildLayoutDelegate {
  _AccessoryLayout({
    required this.placement,
    required this.inline,
    required this.expanded,
  }) : super(relayout: placement);

  final ValueListenable<GlassTabAccessoryPlacement> placement;
  final Rect inline;
  final Rect expanded;

  Rect get _rect =>
      placement.value == GlassTabAccessoryPlacement.inline ? inline : expanded;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.tight(_rect.size);

  @override
  Offset getPositionForChild(Size size, Size childSize) => _rect.topLeft;

  @override
  bool shouldRelayout(_AccessoryLayout oldDelegate) =>
      !identical(oldDelegate.placement, placement) ||
      oldDelegate.inline != inline ||
      oldDelegate.expanded != expanded;
}

/// The bottom accessory: its glass goes from above the bar to beside the
/// circle with the bar's glass, and its content stands in either place,
/// switching as the transition starts, clipped to the moving glass.
class _Accessory extends StatefulWidget {
  const _Accessory({
    required this.body,
    required this.width,
    required this.rtl,
    required this.look,
    required this.child,
  });

  final _MinimizeFrames body;
  final double width;
  final bool rtl;
  final GlassTabBarStyle look;
  final Widget child;

  @override
  State<_Accessory> createState() => _AccessoryState();
}

class _AccessoryState extends State<_Accessory> {
  late MotionSelection<GlassFrame> _frame = _frameNow();
  late MotionSelection<Offset> _carried = _carriedNow();
  final _placement = ValueNotifier(GlassTabAccessoryPlacement.expanded);

  @override
  void initState() {
    super.initState();
    widget.body.minimized.addListener(_placed);
    _placed();
  }

  @override
  void didUpdateWidget(_Accessory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.body, widget.body)) {
      oldWidget.body.minimized.removeListener(_placed);
      widget.body.minimized.addListener(_placed);
    }
    if (!identical(oldWidget.body, widget.body) ||
        oldWidget.width != widget.width ||
        oldWidget.rtl != widget.rtl) {
      _frame = _frameNow();
      _carried = _carriedNow();
    }
    _placed();
  }

  @override
  void dispose() {
    widget.body.minimized.removeListener(_placed);
    _placement.dispose();
    super.dispose();
  }

  Rect _mirror(Rect rect) => widget.rtl
      ? Rect.fromLTRB(
          widget.width - rect.right,
          rect.top,
          widget.width - rect.left,
          rect.bottom,
        )
      : rect;

  Rect get _expanded => Rect.fromLTWH(
    0,
    0,
    widget.width,
    _Minimized.accessoryHeight,
  );

  Rect get _inline {
    const inset = _Minimized.collapsedInset;
    const circleTop =
        _Minimized.accessoryGap + _Minimized.accessoryHeight + inset;
    const circleEnd = inset + TabBarMinimizeMotion.collapsedSize;
    return _mirror(
      Rect.fromLTRB(
        circleEnd + _Minimized.inlineGap,
        circleTop,
        widget.width - inset,
        circleTop + _Minimized.accessoryHeight,
      ),
    );
  }

  MotionSelection<GlassFrame> _frameNow() {
    final body = widget.body;
    final from = _expanded;
    final to = _inline;
    double lerp(double a, double b, double t) => a + (b - a) * t;
    return MotionSelection(() {
      final x = body.accessoryX.value;
      final y = body.accessoryY.value;
      return GlassFrame(
        rect: Rect.fromLTRB(
          lerp(from.left, to.left, x),
          lerp(from.top, to.top, y),
          lerp(from.right, to.right, x),
          lerp(from.bottom, to.bottom, y),
        ),
      );
    });
  }

  // The content stands laid out where it heads and travels there with the
  // glass's center.
  MotionSelection<Offset> _carriedNow() => MotionSelection(() {
    final end = widget.body.minimized.value ? _inline : _expanded;
    return _frame.value.rect!.center - end.center;
  });

  void _placed() {
    _placement.value = widget.body.minimized.value
        ? GlassTabAccessoryPlacement.inline
        : GlassTabAccessoryPlacement.expanded;
  }

  @override
  Widget build(BuildContext context) {
    final background = widget.look.backgroundColor?.resolve(const {});
    return Stack(
      children: [
        Positioned.fill(
          child: GlassSurface.live(
            role: GlassRole.bar,
            glass: Glass.regular(
              tint: background == null
                  ? null
                  : GlassDynamicColor.resolve(background, context),
            ),
            frame: _frame,
            child: const SizedBox.expand(),
          ),
        ),
        Positioned.fill(
          child: GlassClip.live(
            frame: _frame,
            child: CustomSingleChildLayout(
              delegate: _AccessoryLayout(
                placement: _placement,
                inline: _inline,
                expanded: _expanded,
              ),
              child: MotionTransition(
                offset: _carried,
                child: _AccessoryScope(
                  notifier: _placement,
                  child: Padding(
                    padding: _accessoryPadding,
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The space between the bottom accessory's glass and its content (top 8,
/// leading 16, bottom 8, trailing 16; read from UIKit).
const _accessoryPadding = EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8);
