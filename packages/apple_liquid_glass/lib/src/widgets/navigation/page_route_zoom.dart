part of 'page_route.dart';

class _Zoom extends StatefulWidget {
  const _Zoom({required this.route, required this.motion, required this.child});

  final GlassPageRoute<Object?> route;
  final ZoomPageMotion motion;
  final Widget child;

  @override
  State<_Zoom> createState() => _ZoomState();
}

/// The page's zoom out of its source and back, and its drag to dismiss.
class _ZoomState extends State<_Zoom> {
  late final _input = _ZoomDrag(this);
  late final List<Interaction> _interactions = [_input];
  late final _dim = motion.select((m) => m.tuning.dimmingOpacity * m.dimming);
  late final _shadow = motion.select((m) => (m.rect, m.radius, m.dimming));
  late final _frame = motion.select((m) => (m.rect, m.radius));
  late final _fade = motion.select((m) => m.fade);
  late final _lookFade = motion.select((m) => 1 - m.fade);
  late final _scale = motion.select((m) => m.contentScale);
  late final _lookScale = motion.select((m) => m.lookScale);
  bool _begun = false;
  VoidCallback? _cancelStart;

  GlassPageRoute<Object?> get route => widget.route;
  ZoomPageMotion get motion => widget.motion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resize();
    if (_begun) return;
    _begun = true;
    // A page added without a push, as a navigator's first, stands in place.
    if (route.animation?.status == AnimationStatus.completed) {
      motion.showInPlace(motion.clock.now);
      return;
    }
    _cancelStart = route._startAfterFirstFrame();
  }

  @override
  void dispose() {
    _cancelStart?.call();
    super.dispose();
  }

  void _resize() {
    motion.displayRadius = _cardRadius(context).topLeft.x;
    motion.resize(motion.clock.now, MediaQuery.sizeOf(context));
  }

  bool get _canPop =>
      motion.takesDrag &&
      route.isCurrent &&
      route.canDismiss(DismissTrigger.interaction);

  void _dragStarted(double t, Offset from) {
    route.beginInteraction();
    motion.dragStart(t, from);
  }

  void _released(double t, Offset velocity) {
    final dismisses = motion.dragEnd(t, velocity);
    route.endInteraction();
    if (!dismisses) return;
    route._lifted = t;
    route.dismiss(DismissTrigger.interaction);
    // A PopScope vetoed the pop: the page returns.
    if (motion.isDragging) motion.stay(t);
  }

  @override
  Widget build(BuildContext context) {
    _input.rtl = context.isRightToLeft;
    final size = MediaQuery.sizeOf(context);
    final tuning = motion.tuning;
    final source = route.source;
    final look = source == null ? null : _looks[source];
    final sourceSize = motion.source.size;
    return InputRegion(
      interactions: _interactions,
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: MotionTransition(
              opacity: _dim,
              child: const ColoredBox(color: Color(0xFF000000)),
            ),
          ),
          IgnorePointer(
            child: CustomPaint(
              painter: _ZoomShadow(
                _shadow,
                color: Color.fromRGBO(0, 0, 0, tuning.shadowOpacity),
                sigma: tuning.shadowSigma,
                offset: tuning.shadowOffset,
              ),
            ),
          ),
          MotionDriven(
            template: () {
              final (rect, radius) = _frame.value;
              return CustomSingleChildLayout(
                delegate: _Place(rect),
                child: ClipRRect(
                  borderRadius: BorderRadius.all(Radius.circular(radius)),
                ),
              );
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                MotionTransition(
                  opacity: _fade,
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: size.width,
                    maxWidth: size.width,
                    minHeight: size.height,
                    maxHeight: size.height,
                    child: MotionDriven(
                      template: () => Transform.scale(
                        alignment: Alignment.topLeft,
                        scale: _scale.value,
                      ),
                      child: RepaintBoundary(child: widget.child),
                    ),
                  ),
                ),
                if (look != null)
                  IgnorePointer(
                    child: MotionTransition(
                      opacity: _lookFade,
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
                        minWidth: sourceSize.width,
                        maxWidth: sourceSize.width,
                        minHeight: sourceSize.height,
                        maxHeight: sourceSize.height,
                        child: MotionDriven(
                          template: () => Transform.scale(
                            alignment: Alignment.topLeft,
                            scale: _lookScale.value,
                          ),
                          child: look,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Place extends SingleChildLayoutDelegate {
  _Place(this.rect);

  final Rect rect;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.tight(rect.size);

  @override
  Offset getPositionForChild(Size size, Size childSize) => rect.topLeft;

  @override
  bool shouldRelayout(_Place oldDelegate) => oldDelegate.rect != rect;
}

/// The shadow the zooming card casts on the page underneath, faded with
/// the dimming.
class _ZoomShadow extends CustomPainter {
  _ZoomShadow(
    this.shadow, {
    required this.color,
    required this.sigma,
    required this.offset,
  }) : super(repaint: shadow);

  final ValueListenable<(Rect, double, double)> shadow;
  final Color color;
  final double sigma;
  final double offset;

  @override
  void paint(Canvas canvas, Size size) {
    final (rect, radius, shown) = shadow.value;
    if (shown <= 0) return;
    final paint = Paint();
    paint.color = color.withValues(alpha: color.a * shown);
    paint.maskFilter = MaskFilter.blur(BlurStyle.normal, sigma);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.shift(Offset(0, offset)),
        Radius.circular(radius),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ZoomShadow oldDelegate) =>
      !identical(oldDelegate.shadow, shadow) ||
      oldDelegate.color != color ||
      oldDelegate.sigma != sigma ||
      oldDelegate.offset != offset;
}

/// The drag that dismisses a zoomed page: a touch that moves down or
/// toward the trailing side past UIKit's slop takes the page, which
/// follows the finger and, on release, pops into its source or returns.
final class _ZoomDrag extends Interaction {
  _ZoomDrag(this._zoom) : super(role: InteractionRole.gesture);

  final _ZoomState _zoom;
  bool rtl = false;
  int? _pointer;
  Offset _start = Offset.zero;
  bool _dragging = false;

  @override
  bool get dragged => _dragging;

  @override
  bool accepts(PointerDownInput down) =>
      super.accepts(down) && _pointer == null && _zoom._canPop;

  @override
  InteractionUpdate handle(InteractionInput input) {
    final motion = _zoom.motion;
    switch (input) {
      case PointerDownInput() when _pointer == null && accepts(input):
        _pointer = input.pointer;
        _start = input.position;
        _dragging = false;
      case PointerMoveInput() when input.pointer == _pointer:
        final delta = input.position - _start;
        if (!_dragging) {
          final allowed = motion.allowsDrag(delta, rtl: rtl);
          if (allowed == null) break;
          if (!allowed) {
            _pointer = null;
            return const InteractionUpdate(fails: true);
          }
          _dragging = true;
          _zoom._dragStarted(input.time, _start);
          motion.dragUpdate(input.time, input.position);
          return const InteractionUpdate(recognizes: true);
        }
        motion.dragUpdate(input.time, input.position);
      case PointerUpInput() when input.pointer == _pointer:
        _pointer = null;
        if (!_dragging) return const InteractionUpdate(fails: true);
        _dragging = false;
        motion.dragUpdate(input.time, input.position);
        _zoom._released(input.time, input.velocity);
      case PointerCancelInput() when input.pointer == _pointer:
        _pointer = null;
        if (_dragging) {
          _dragging = false;
          _zoom._released(input.time, Offset.zero);
        }
        return const InteractionUpdate(fails: true);
      default:
    }
    return InteractionUpdate.none;
  }
}
