part of 'date_picker.dart';

/// The largest text scale the overlay's fixed-size content follows.
const double _overlayMaxTextScale = 1.2;

class _OverlayView extends StatefulWidget {
  const _OverlayView({
    required this.config,
    required this.labelRect,
    required this.onSwitched,
    required this.onChanged,
    required this.motion,
    required this.part,
    required this.label,
    required this.days,
  });

  final ValueListenable<_PickerConfig?> config;
  final Rect? Function(_Part part) labelRect;
  final ValueChanged<_Part> onSwitched;
  final ValueChanged<DateTime> onChanged;
  final DatePickerMotion motion;
  final _Part part;
  final Rect label;
  final FocusNode days;

  @override
  State<_OverlayView> createState() => _OverlayViewState();
}

/// Hears where a touch outside the overlay's box lifts, in global
/// coordinates.
final class _OutsideTap extends Interaction {
  _OutsideTap(this.onTap);

  final void Function(Offset position) onTap;
  Offset Function(Offset local) _toGlobal = _same;
  int? _pointer;

  static Offset _same(Offset local) => local;

  @override
  bool accepts(PointerDownInput down) => true;

  @override
  void bindRegion(Offset Function(Offset local) toGlobal) =>
      _toGlobal = toGlobal;

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput():
        _pointer = input.pointer;
      case PointerUpInput() when input.pointer == _pointer:
        _pointer = null;
        onTap(_toGlobal(input.position));
      case PointerCancelInput() when input.pointer == _pointer:
        _pointer = null;
      default:
    }
    return InteractionUpdate.none;
  }
}

class _OverlayViewState extends State<_OverlayView> {
  // The picker as the overlay opened, kept once the picker is gone.
  late _PickerConfig _config = widget.config.value!;
  late DateTime _value = _bounded(_picker.value);
  late _Part _part = widget.part;
  late Rect _label = widget.label;
  _Part? _fromPart;
  Rect? _fromLabel;
  late final List<Interaction> _outside = [_OutsideTap(_tappedOutside)];

  // The tree rebuilds only when this flips; every other frame reads the
  // motion through render objects.
  late final _switching = _motion.select((m) => m.switching);
  late final _swap = _motion.select((m) => m.swap.clamp(0.0, 1.0));
  late final _unswap = _motion.select((m) => 1 - m.swap.clamp(0.0, 1.0));
  late final _opacity = _motion.select((m) => m.opacity);
  late final _glass = _motion.select(
    (m) => GlassFrame(
      shape: const LiquidRoundedSuperellipse(
        radius: _DatePickerLook.cornerRadius,
      ),
      opacity: m.opacity,
    ),
  );

  // Safe one frame late: the overlay stays transparent for at least the
  // reopen delay after the lift.
  bool _contentReady = false;
  VoidCallback? _cancelReady;
  VoidCallback? _cancelReconcile;
  GlassCompactDatePicker? _shown;
  bool? _shownTwentyFour;

  DatePickerMotion get _motion => widget.motion;

  GlassCompactDatePicker get _picker => _config.picker;

  bool get _twentyFour => _config.twentyFour;

  bool get _hostGone => widget.config.value == null;

  bool get _enabled => !_hostGone && _picker.onChanged != null;

  double get _now => _motion.clock.now;

  @override
  void initState() {
    super.initState();
    widget.config.addListener(_hostChanged);
    _cancelReady = _motion.clock.schedulePublish(() {
      _cancelReady = null;
      if (mounted) setState(() => _contentReady = true);
    });
  }

  @override
  void dispose() {
    _cancelReady?.call();
    _cancelReconcile?.call();
    widget.config.removeListener(_hostChanged);
    super.dispose();
  }

  // The host's build is not this route's, so its change reaches the
  // overlay in the next publish phase, before that frame's build.
  void _hostChanged() {
    _cancelReconcile ??= _motion.clock.schedulePublish(() {
      _cancelReconcile = null;
      _reconcile();
    });
  }

  _Part? _otherLabelAt(Offset position) {
    for (final part in _Part.values) {
      if (part == _part) continue;
      final rect = widget.labelRect(part);
      if (rect != null && rect.contains(position)) return part;
    }
    return null;
  }

  void _tappedOutside(Offset position) {
    final other = _otherLabelAt(position);
    if (other == null) {
      _close(DismissTrigger.outsideTap);
    } else {
      _switchTo(other);
    }
  }

  void _switchTo(_Part part) {
    final label = widget.labelRect(part);
    if (label == null || !_motion.isOpen) return;
    _motion.switchPicker(_now, back: _switching.value && part == _fromPart);
    setState(() {
      _fromPart = _part;
      _fromLabel = _label;
      _part = part;
      _label = label;
    });
    widget.onSwitched(part);
  }

  void _close(DismissTrigger trigger) {
    if (!_motion.isOpen) return;
    PresentationHandle.of(context).dismiss(trigger);
  }

  DateTime _bounded(DateTime value) =>
      GlassDateBounds(_picker.minimumDate, _picker.maximumDate).clamp(value);

  void _pick(DateTime value) {
    if (!_enabled) return;
    final next = _bounded(value);
    setState(() => _value = next);
    widget.onChanged(next);
  }

  void _reconcile() {
    final config = widget.config.value;
    if (!mounted || config == null) return;
    _config = config;
    if (!_enabled) {
      _close(DismissTrigger.programmatic);
      return;
    }
    final value = _bounded(_picker.value);
    final shown = _shown;
    if (_value == value &&
        _twentyFour == _shownTwentyFour &&
        shown != null &&
        _showsAlike(shown, _picker)) {
      return;
    }
    setState(() => _value = value);
  }

  static bool _showsAlike(GlassCompactDatePicker a, GlassCompactDatePicker b) =>
      a.mode == b.mode &&
      a.style == b.style &&
      a.minuteInterval == b.minuteInterval &&
      a.minimumDate == b.minimumDate &&
      a.maximumDate == b.maximumDate &&
      a.firstDayOfWeek == b.firstDayOfWeek &&
      a.today == b.today;

  Size _sizeFor(_Part part) => part == _Part.time
      ? DatePickerMotion.timeSize
      : DatePickerCalendarMotion.calendarSize;

  Widget _content(_Part part) => part == _Part.time
      ? GlassTimePicker(
          value: _value,
          minimumDate: _picker.minimumDate,
          maximumDate: _picker.maximumDate,
          minuteInterval: _picker.minuteInterval,
          use24HourFormat: _twentyFour,
          style: _picker.style,
          onChanged: _pick,
        )
      : GlassDatePicker(
          value: _value,
          onChanged: _pick,
          minimumDate: _picker.minimumDate,
          maximumDate: _picker.maximumDate,
          firstDayOfWeek: _picker.firstDayOfWeek,
          today: _picker.today,
          style: _picker.style,
          focusNode: widget.days,
          defersDays: !_contentReady,
        );

  @override
  Widget build(BuildContext context) {
    _shown = _picker;
    _shownTwentyFour = _twentyFour;
    final look = GlassDatePickerStyle.resolve(context, _picker.style);
    final media = MediaQuery.of(context);
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final origin = _origin(context);
    final padding = EdgeInsets.only(
      top: media.padding.top,
      bottom: media.bottomAboveKeyboard,
    );
    final part = _part;
    final size = _sizeFor(part);
    final from = _fromPart;
    final fromSize = from == null ? size : _sizeFor(from);
    final to = SizedBox.fromSize(
      key: ValueKey<_Part>(part),
      size: size,
      child: part == _Part.time && !_contentReady
          ? const SizedBox.shrink()
          : _content(part),
    );
    final text = GlassTextScale.of(context, max: _overlayMaxTextScale);
    Widget overlayFor({required bool below}) => text.apply(
      DefaultTextStyle(
        style: text.resolve(TextStyle(fontSize: 17, color: look.labelColor)),
        child: ListenableBuilder(
          listenable: _switching,
          builder: (BuildContext context, Widget? child) =>
              from == null || !_switching.value
              ? child!
              : _Crossfade(
                  alignment: below
                      ? AlignmentDirectional.topStart
                      : AlignmentDirectional.bottomStart,
                  fadeIn: _swap,
                  fadeOut: _unswap,
                  from: ExcludeSemantics(
                    child: SizedBox.fromSize(
                      size: fromSize,
                      child: _content(from),
                    ),
                  ),
                  to: child!,
                ),
          child: to,
        ),
      ),
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        DatePickerPlacement place(Size size, Rect label) => placeDatePicker(
          size: size,
          label: label.shift(-origin),
          screen: constraints.biggest,
          padding: padding,
          textDirection: direction,
        );
        final target = place(size, _label);
        final fromLabel = _fromLabel;
        final source = from == null || fromLabel == null
            ? null
            : place(fromSize, fromLabel);
        return Stack(
          children: [
            Positioned.fill(
              child: ExcludeSemantics(
                child: InputRegion(
                  interactions: _outside,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            _box(
              target: target,
              source: source,
              screen: constraints.biggest,
              child: overlayFor(below: target.below),
            ),
          ],
        );
      },
    );
  }

  // The overlay's box: placed, scaled, faded and clipped per frame from the
  // motion, around content built once.
  Widget _box({
    required DatePickerPlacement target,
    required DatePickerPlacement? source,
    required Size screen,
    required Widget child,
  }) {
    final below = target.below;
    final frame = _motion.select((m) {
      final q = m.swap;
      final placement = source == null
          ? target
          : DatePickerPlacement(
              rect: Rect.lerp(source.rect, target.rect, q)!,
              anchor: Offset.lerp(source.anchor, target.anchor, q)!,
            );
      return _BoxFrame.of(m, placement, below: below);
    });
    return Positioned.fill(
      child: MotionDriven(
        template: () {
          final f = frame.value;
          return Transform(
            transform: f.transform,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                f.box.left,
                f.box.top,
                screen.width - f.box.right,
                screen.height - f.box.bottom,
              ),
            ),
          );
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The menu's material: over black the native overlay reads
            // 32 gray on an iPhone 16 Pro film, as the native menu does.
            GlassSurface.live(
              role: GlassRole.panel,
              frame: _glass,
              child: const SizedBox.expand(),
            ),
            GlassClip(
              shape: const LiquidRoundedSuperellipse(
                radius: _DatePickerLook.cornerRadius,
              ),
              child: OverflowBox(
                alignment: below
                    ? AlignmentDirectional.topStart
                    : AlignmentDirectional.bottomStart,
                minWidth: 0,
                maxWidth: double.infinity,
                minHeight: 0,
                maxHeight: double.infinity,
                // The content keeps its size while the scale, clip and
                // opacity above it change every frame; its own layer,
                // below the clip, keeps its raster through a reclip.
                child: MotionTransition(
                  opacity: _opacity,
                  child: RepaintBoundary(child: child),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Offset _origin(BuildContext context) {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) return box.localToGlobal(Offset.zero);
    return Offset.zero;
  }
}
