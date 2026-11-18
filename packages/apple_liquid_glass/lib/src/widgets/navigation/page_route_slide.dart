part of 'page_route.dart';

class _Slide extends StatefulWidget {
  const _Slide({
    required this.route,
    required this.motion,
    required this.child,
  });

  final GlassPageRoute<Object?> route;
  final PageSlideMotion motion;
  final Widget child;

  @override
  State<_Slide> createState() => _SlideState();
}

/// The page's slide, its cross-fade for Prefer Cross-Fade Transitions and its
/// interactive pop.
class _SlideState extends State<_Slide> {
  late final _input = _SwipePop(this);
  late final List<Interaction> _interactions = [_input];

  GlassPageRoute<Object?> get route => widget.route;
  PageSlideMotion get motion => widget.motion;

  VoidCallback? _cancelStart;

  @override
  void initState() {
    super.initState();
    motion.onReturned = route.endInteraction;
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
    motion.onReturned = null;
    super.dispose();
  }

  bool get _canPop =>
      motion.takesSwipe &&
      route.isCurrent &&
      route.canDismiss(DismissTrigger.interaction);

  void _dragStarted(double t) {
    motion.hold(t);
    route.beginInteraction();
  }

  void _released(double t, {required bool pops, required double velocity}) {
    motion.release(t, pops: pops, velocity: velocity);
    if (!pops && motion.isShown) return;
    if (motion.isShown) {
      route._lifted = t;
      route.dismiss(DismissTrigger.interaction);
    }
    route.endInteraction();
    if (motion.isShown) {
      // A PopScope vetoed the pop: the page returns.
      motion.stay(t);
      route.beginInteraction();
    }
  }

  // The page builds in the build phase, never under a LayoutBuilder: what
  // it declares to the shared bar is in place before any layout.
  @override
  Widget build(BuildContext context) {
    motion.width = MediaQuery.sizeOf(context).width;
    motion.crossFades = GlassTraits.of(context).prefersCrossFade;
    _input.rtl = context.isRightToLeft;
    return InputRegion(
      interactions: _interactions,
      child: _Card(
        presence: route._progress,
        fades: route._fades,
        top: true,
        child: _Covered(
          cover: route._cover,
          child: RepaintBoundary(child: widget.child),
        ),
      ),
    );
  }
}

/// The share of the page the page underneath keeps on screen: it moves by
/// the width less 0.7 of it, rounded (read from UIKit).
const double _underneathKeeps = 0.7;

/// The opacity of the black over the page underneath when the page on top
/// covers it fully; it follows the top page's progress linearly (read from
/// UIKit; iPhone 16 Pro held edge samples agree).
const double _underDimOpacity = 0.1;

/// The shadow of a sliding card: black at 4 percent, radius 12, offset
/// (0, -3) (read from UIKit; not filmed).
const double _cardShadowOpacity = 0.04;
const double _cardShadowRadius = 12;
const double _cardShadowOffset = -3;

BorderRadius _cardRadius(BuildContext context) =>
    MediaQuery.maybeDisplayCornerRadiiOf(context) ??
    const BorderRadius.all(Radius.circular(SheetMotion.fallbackDisplayRadius));

/// The interactive pop: a touch on the page that moves along it toward
/// the trailing side drags the page, and its release pops or returns the
/// page as UIKit predicts. A touch on the leading edge begins after
/// [NavigationPopMotion.edgeHysteresis]; one elsewhere, UIKit's content
/// swipe, after [NavigationPopMotion.contentHysteresis] inside its funnel, so
/// the page's own drags and scrolls take the touches they claim first.
final class _SwipePop extends Interaction {
  _SwipePop(this._slide) : super(role: InteractionRole.gesture);

  final _SlideState _slide;
  double _width = 400;
  bool rtl = false;
  int? _pointer;
  Offset _start = Offset.zero;
  bool _fromEdge = false;
  bool _dragging = false;
  late NavigationPopMotion _predictor;

  double _along(Offset position) => rtl ? -position.dx : position.dx;

  @override
  bool get dragged => _dragging;

  @override
  bool accepts(PointerDownInput down) =>
      super.accepts(down) && _pointer == null && _slide._canPop;

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput() when _pointer == null && accepts(input):
        _width = input.regionSize.width;
        _pointer = input.pointer;
        _start = input.position;
        final x = rtl ? _width - input.position.dx : input.position.dx;
        _fromEdge = x <= _width * NavigationPopMotion.edgeShare;
        _dragging = false;
        _predictor = NavigationPopMotion(_width);
        _predictor.addPosition(input.time, _along(input.position));
      case PointerMoveInput() when input.pointer == _pointer:
        final along = _along(input.position);
        final predictor = _predictor;
        predictor.addPosition(input.time, along);
        final travel = along - _along(_start);
        if (!_dragging) {
          if (_fromEdge) {
            if (travel.abs() < NavigationPopMotion.edgeHysteresis) break;
          } else {
            final across = (input.position.dy - _start.dy).abs();
            if (across >= NavigationPopMotion.contentFunnel(travel) ||
                travel <= -NavigationPopMotion.contentHysteresis) {
              _pointer = null;
              return const InteractionUpdate(fails: true);
            }
            if (travel < NavigationPopMotion.contentHysteresis) break;
          }
          _dragging = true;
          _start = input.position;
          _slide._dragStarted(input.time);
          predictor.begin(input.time);
          return const InteractionUpdate(recognizes: true);
        }
        final progress = travel / _width;
        _slide.motion.drag(input.time, progress);
        predictor.update(input.time, progress);
      case PointerUpInput() when input.pointer == _pointer:
        _pointer = null;
        if (!_dragging) return const InteractionUpdate(fails: true);
        _dragging = false;
        final predictor = _predictor;
        final progress = (_along(input.position) - _along(_start)) / _width;
        predictor.update(input.time, progress, ending: true);
        _slide._released(
          input.time,
          pops: predictor.shouldPop(progress),
          velocity: predictor.settleVelocity,
        );
      case PointerCancelInput() when input.pointer == _pointer:
        _pointer = null;
        if (_dragging) {
          _dragging = false;
          _slide._released(input.time, pops: false, velocity: 0);
        }
        return const InteractionUpdate(fails: true);
      default:
    }
    return InteractionUpdate.none;
  }
}
