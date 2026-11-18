part of 'sheet.dart';

class _SheetView extends StatefulWidget {
  const _SheetView({required this.motion, required this.spec});

  final SheetMotion motion;
  final _SheetSpec spec;

  @override
  State<_SheetView> createState() => _SheetViewState();
}

class _SheetViewState extends State<_SheetView> implements GlassSheet {
  // Everything _publish reads, so a frame that moved the sheet publishes it
  // and one that did not costs nothing.
  late final MotionSelection<Object?> _frames = widget.motion.select((m) {
    final layout = m.lastLayout;
    if (layout == null) return null;
    return (
      m.height,
      m.visibleRect(layout.size.height),
      m.bottomRadius,
      m.fill,
      m.hasEvents,
    );
  });
  late final _SheetScrollController _scroll = _SheetScrollController(this);
  final _frame = ValueNotifier(
    _Frame(
      height: 0,
      transform: Matrix4.identity(),
      body: RSuperellipse.zero,
    ),
  );
  final _fill = ValueNotifier<double>(0);
  late final MotionSelection<bool> _glass = widget.motion.select(
    (m) => _fillOf(m) < 1,
  );
  late final MotionSelection<bool> _opaque = widget.motion.select(
    (m) => _fillOf(m) >= 1,
  );
  late final MotionSelection<bool> _fading = widget.motion.select((m) {
    final fill = _fillOf(m);
    return fill > 0 && fill < 1;
  });
  // The detent the sheet rests at or heads to, as an index of its detents.
  final _detent = ValueNotifier<int>(0);
  // The layout the law last took, which orders the detents the grabber
  // steps through.
  final _laidOut = ValueNotifier<SheetLayout?>(null);
  late final _range = _DetentRange(this);
  late final List<Interaction> _detentInput = [_DetentStep(_step)];
  // NEAR: over a control or a list that wants the touch too, the drag
  // starts past the gesture arena's 18 point slop, against 12 on the
  // device.
  late final _drag = DragInteraction(
    axis: Axis.vertical,
    slop: SheetMotion.dragSlop,
    contends: true,
    global: true,
    onStart: _dragStart,
    onUpdate: _dragUpdate,
    onEnd: (details) => _release(details.time, details.velocity.dy),
    onCancel: (t) => _motion?.dragCancel(_frameTime),
  );
  late final List<Interaction> _interactions = [_SheetTouch(this), _drag];
  EdgeInsets _padding = EdgeInsets.zero;
  double _keyboard = 0;
  double? _fitted;
  double _dragY = 0;
  // The stamp of the latest event of a touch on the sheet, which a drag
  // the content's scrollable hands on happens at.
  double _stamp = 0;
  int? _touch;
  bool _touchDragged = false;
  Offset _touchFrom = Offset.zero;

  _SheetSpec get _spec => widget.spec;

  SheetMotion? get _motion => widget.motion.isLaidOut ? widget.motion : null;

  static double _fillOf(SheetMotion motion) =>
      motion.isLaidOut ? motion.fill : 0;

  bool get _leaving => widget.motion.hasLeft;

  double get _now => widget.motion.clock.now;

  // The time a release or a cancel acts at: the frame's, not an earlier
  // stamp's.
  double get _frameTime => widget.motion.clock.frameTime;

  @override
  List<GlassSheetDetent> get detents => _spec.detents;

  @override
  GlassSheetDetent get detent => detents[_detent.value];

  @override
  void initState() {
    super.initState();
    _detent.value = math.max(
      0,
      detents.indexOf(_spec.initialDetent ?? detents[0]),
    );
    _frames.addListener(_stepped);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final padding = MediaQuery.paddingOf(context);
    _padding = EdgeInsets.only(top: padding.top, bottom: padding.bottom);
    _keyboard = MediaQuery.viewInsetsOf(context).bottom;
    widget.motion.displayRadius = MediaQuery.maybeDisplayCornerRadiiOf(
      context,
    )?.bottomLeft.x;
    _relayout(_now);
  }

  @override
  void didUpdateWidget(_SheetView oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(
      identical(oldWidget.motion, widget.motion),
      'a sheet keeps its law',
    );
    if (oldWidget.spec != widget.spec) _relayout(_now);
  }

  @override
  void dispose() {
    _frames.removeListener(_stepped);
    _laidOut.dispose();
    _scroll.dispose();
    _frame.dispose();
    _fill.dispose();
    _detent.dispose();
    super.dispose();
  }

  void _stepped() {
    _deliver();
    _publish();
  }

  @override
  void animateTo(GlassSheetDetent detent) {
    final i = detents.indexOf(detent);
    final motion = _motion;
    if (i < 0 || motion == null || _leaving) return;
    motion.animateTo(_now, motion.indexOfDetent(i));
    _deliver();
  }

  void _deliver() {
    final motion = _motion;
    if (motion == null) return;
    for (final event in motion.drainEvents()) {
      if (!mounted) return;
      switch (event) {
        case SheetDetentChanged(:final index, :final byUser):
          _detent.value = motion.detentAt(index);
          // UIKit reports a detent the user picks, not one set from code.
          if (byUser) _spec.onDetentChanged?.call(detent);
        case SheetDismissed() || SheetDismissRefused():
          if (!_leaving) {
            PresentationHandle.of(
              context,
            ).dismiss(DismissTrigger.interaction);
          }
      }
    }
  }

  bool get _dismissAllowed =>
      PresentationHandle.of(context).canDismiss(DismissTrigger.interaction);

  // The container's size reaches the law in the frame's resolve phase, so
  // the sheet's first frame draws it where it starts.
  void _sized(double t, Size size) {
    if (!mounted) return;
    _layout(t, size);
    _publish();
  }

  // Unlike the container's, the content's size moves the sheet a frame
  // later, as its spring publishes.
  void _fittedHeight(double t, Size size) {
    if (!mounted || _fitted == size.height) return;
    _fitted = size.height;
    _layout(t, widget.motion.lastLayout?.size);
  }

  void _relayout(double t) {
    if (_layout(t, widget.motion.lastLayout?.size)) _publish();
  }

  bool _layout(double t, Size? size) {
    if (size == null) return false;
    widget.motion.layout(
      t,
      SheetLayout(
        size: size,
        padding: _padding,
        keyboard: _keyboard,
        fittedHeight: _fitted,
        detents: detents,
        selected: detent,
        largestUndimmed: _spec.largestUndimmedDetent,
      ),
    );
    _laidOut.value = widget.motion.lastLayout;
    return true;
  }

  void _publish() {
    final motion = _motion;
    if (motion == null) return;
    final size = motion.lastLayout!.size;
    final h = motion.height;
    final drawn = motion.visibleRect(size.height);
    final k = size.width <= 0 ? 1.0 : drawn.width / size.width;
    final ky = motion.stretch != 1 && h > 0 ? drawn.height / h : k;
    final transform = Matrix4.translationValues(drawn.left, drawn.top, 0);
    transform.multiply(Matrix4.diagonal3Values(k, ky, 1));
    final bottom = Radius.circular(motion.bottomRadius);
    const top = Radius.circular(_SheetLook.topRadius);
    _frame.value = _Frame(
      height: h,
      transform: transform,
      body: RSuperellipse.fromLTRBAndCorners(
        0,
        0,
        size.width,
        h,
        topLeft: top,
        topRight: top,
        bottomLeft: bottom,
        bottomRight: bottom,
      ),
    );
    _fill.value = motion.fill;
  }

  void _down(PointerDownInput input) {
    _stamp = input.time;
    final motion = _motion;
    if (motion == null || _leaving || _touch != null) return;
    _touch = input.pointer;
    _touchDragged = false;
    _touchFrom = input.position;
    motion.press(_stamp);
  }

  void _move(PointerMoveInput input) => _stamp = input.time;

  void _up(int pointer, double t, {required bool lifted}) {
    _stamp = t;
    if (pointer != _touch) return;
    _touch = null;
    final motion = _motion;
    if (motion == null) return;
    if (!motion.isDragging) motion.unpress(_stamp);
    if (lifted &&
        !_touchDragged &&
        _touchFrom.dy < SheetMotion.grabberHitHeight) {
      motion.tapGrabber(_stamp);
    }
    _deliver();
  }

  void _dragStart(DragInteractionDetails details) {
    _touchDragged = true;
    final motion = _motion;
    if (motion == null || _leaving) return;
    motion.dismissible = _dismissAllowed;
    motion.dragStart(details.time, details.translation.dy);
  }

  void _dragUpdate(DragInteractionDetails details) {
    final motion = _motion;
    if (motion == null || !motion.isDragging) return;
    motion.dragUpdate(details.time, details.translation.dy);
  }

  void _release(double t, double velocity) {
    final motion = _motion;
    if (motion == null || !motion.isDragging) return;
    motion.dragEnd(math.max(t, _frameTime), velocity);
    _deliver();
  }

  void _scrollDragBy(double delta) {
    final motion = _motion;
    if (motion == null || _leaving) return;
    final t = math.max(_stamp, _frameTime);
    if (!motion.isDragging) {
      motion.dismissible = _dismissAllowed;
      _dragY = 0;
      motion.dragStart(t, 0);
    }
    _dragY += delta;
    motion.dragUpdate(t, _dragY);
  }

  bool get _canExpand {
    final motion = _motion;
    if (motion == null) return false;
    return motion.height < motion.heights.last - 0.5;
  }

  bool get _scrollDragging => _motion?.isDragging ?? false;

  // The content widget is reused while its inputs hold, so a rebuild of
  // the chrome (each keyboard-inset frame) leaves the app's builder alone.
  // A detent change hands the scope a new detent over the same content:
  // only what reads the sheet through GlassSheet.of rebuilds.
  Widget? _content;
  TextStyle? _style;

  Widget _contentFor(BuildContext context) {
    final text = TextStyle(
      fontSize: 17,
      color: GlassTheme.labelColorOf(context),
    ).merge(_spec.lookOf(context).textStyle);
    final style = GlassTextScale.of(context).resolve(
      text.copyWith(color: GlassDynamicColor.resolve(text.color!, context)),
    );
    var content = _content;
    if (content == null || style != _style) {
      _style = style;
      content = _content = DefaultTextStyle(
        style: style,
        child: detents.any((d) => d.isFitted)
            ? Align(
                alignment: Alignment.topLeft,
                child: MotionMeasure(
                  onSize: _fittedHeight,
                  child: Builder(builder: _spec.builder),
                ),
              )
            : Builder(builder: _spec.builder),
      );
    }
    return content;
  }

  // A step of the keyboard or a screen reader, along the detents by
  // height.
  void _step(double t, ValueCommand command) {
    final motion = _motion;
    if (motion == null || _leaving) return;
    final at = motion.indexOfDetent(_detent.value);
    final last = motion.heights.length - 1;
    final to = switch (command) {
      .increase || .increaseLarge => at + 1,
      .decrease || .decreaseLarge => at - 1,
      .toMinimum => 0,
      .toMaximum => last,
    }.clamp(0, last);
    if (to == at) return;
    motion.pick(t, to);
    _deliver();
  }

  String _detentName(GlassLocalizations strings, int index) {
    final detent = detents[index];
    if (detent.isLarge) return strings.sheetLargeDetentValue;
    if (detent == GlassSheetDetent.medium) {
      return strings.sheetMediumDetentValue;
    }
    final motion = widget.motion;
    return strings.sheetDetentValue(
      motion.indexOfDetent(index) + 1,
      motion.heights.length,
    );
  }

  // The scale of the sheet floating on a screen of this width: the target
  // keeps its 44 points on screen at the smallest scale the sheet rests at.
  double _floatingScale(BuildContext context) =>
      1 - 2 * SheetMotion.floatingInset / MediaQuery.sizeOf(context).width;

  // The band at the top where a tap cycles the detents, as a target the
  // keyboard and screen readers step the detents with: a box from the
  // sheet's top edge at least 44 points square on screen, so the target
  // stays inside the sheet's clip. No finger reaches it: a touch there is
  // the sheet's drag and tap, and reaches the content below.
  Widget _grabber(BuildContext context, Color color) {
    final handle = SizedBox.fromSize(size: _SheetLook.grabberSize);
    final top = _SheetLook.grabberOffset - _SheetLook.grabberSize.height / 2;
    final side = glassMinimumTargetExtent / _floatingScale(context);
    return Align(
      alignment: Alignment.topCenter,
      child: InputRegion(
        interactions: _detentInput,
        semantics: SemanticsProperties(
          label: GlassLocalizations.of(context).sheetGrabberLabel,
        ),
        adjustRange: _range,
        child: _DetentValue(
          state: this,
          child: SizedBox(
            width: math.max(_SheetLook.grabberSize.width, side),
            height: math.max(top + _SheetLook.grabberSize.height, side),
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.only(top: top),
                child: _spec.showDragHandle
                    ? DecoratedBox(
                        decoration: ShapeDecoration(
                          color: color,
                          shape: const StadiumBorder(),
                        ),
                        child: handle,
                      )
                    : handle,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final content = _contentFor(context);
    final look = _spec.lookOf(context);
    final docked = GlassDynamicColor.resolve(
      look.backgroundColor ?? _Colors.docked,
      context,
    );
    final grabber = GlassDynamicColor.resolve(
      look.dragHandleColor ?? _Colors.grabber,
      context,
    );
    final inner = MediaQuery(
      data: media.copyWith(
        padding: media.paddingAboveKeyboard.copyWith(top: 0),
        viewPadding: media.viewPadding.copyWith(top: 0),
        viewInsets: EdgeInsets.zero,
      ),
      child: content,
    );
    return _SheetScope(
      state: this,
      child: _DetentScope(
        state: this,
        detent: _detent,
        child: LayoutBuilder(
          // It only builds: fitted content lays out in the container's
          // height less the safe area, which only layout knows.
          builder: (context, constraints) => MotionMeasure(
            onSize: _sized,
            child: Stack(
              children: [
                Positioned.fill(
                  key: const ValueKey('sheet'),
                  child: _SheetBox(
                    frame: _frame,
                    child: Semantics(
                      explicitChildNodes: true,
                      child: InputRegion(
                        interactions: _interactions,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            MotionVisibility(
                              visible: _glass,
                              child: const GlassSurface(
                                shape: LiquidRoundedSuperellipse(
                                  radius: _SheetLook.topRadius,
                                ),
                                role: GlassRole.panel,
                                child: SizedBox.expand(),
                              ),
                            ),
                            MotionVisibility(
                              visible: _opaque,
                              child: ColoredBox(color: docked),
                            ),
                            MotionVisibility(
                              visible: _fading,
                              child: MotionTransition(
                                opacity: _fill,
                                child: ColoredBox(color: docked),
                              ),
                            ),
                            // Fitted content lays out up to the maximum, not
                            // the sheet's height, so content that grows is
                            // measured at its new height in the frame it
                            // grows, while the sheet follows a frame later.
                            if (detents.any((d) => d.isFitted))
                              OverflowBox(
                                alignment: Alignment.topLeft,
                                minHeight: 0,
                                maxHeight: math.max(
                                  0,
                                  constraints.maxHeight -
                                      media.padding.top -
                                      media.padding.bottom,
                                ),
                                child: inner,
                              )
                            else
                              inner,
                            if (_spec.showDragHandle || detents.length > 1)
                              _grabber(context, grabber),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
