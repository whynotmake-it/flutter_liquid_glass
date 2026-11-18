import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/src/presentation/presentation.dart';
import 'package:kinesis/src/presentation/session.dart';
import 'package:kinesis/widgets.dart';
import 'package:meta/meta.dart';

// A mixin, not a base class: the two shells must be a PopupRoute and a
// PageRoute, which the navigator, HeroController and RouteObserver check.
mixin _PresentationEngine<T> on ModalRoute<T> {
  /// The presentation the route shows.
  Presentation<T, Presented> get presentation;

  /// The name screen readers announce for the presented content.
  String? get semanticsLabel;

  late final PresentationSession _session = PresentationSession(
    presentation: () => presentation,
    scopeClock: () => MotionClockScope.of(navigator!.context),
    leave: leave,
    ended: (result) => didFinish(result as T?),
  );
  late final _RouteShell<T> _shell = _RouteShell(this);

  late final _StatusProjection _projection = _StatusProjection();
  Ticker? _settle;
  DismissTrigger _trigger = DismissTrigger.programmatic;
  bool _removeAtEnd = false;
  bool _popped = false;
  CapturedThemes? _themes;

  /// Builds the content, which runs the [presentation]'s motion and reports
  /// [didOpen] and [didLeave]; a subclass wraps it.
  @protected
  Widget buildContent(BuildContext context) => PresentedContent(
    presentation: presentation,
    motion: _session.motion!,
    shell: _shell,
  );

  /// Starts the content's close after a dismissal by [trigger]; false when
  /// there is nothing to close, which ends the route at once.
  @protected
  bool leave(DismissTrigger trigger) =>
      _session.motion?.leave(_session.clock.now, trigger) ?? false;

  bool _allows(DismissTrigger trigger) => presentation.dismiss.allows(trigger);

  T? _resultFor(T? result) => _session.resultOf(result) as T?;

  /// Called when the route is presented, by a push or without one, before
  /// its content builds: the [presentation]'s motion is made and opened at
  /// the clock's time, and its source leased.
  @protected
  @mustCallSuper
  void didPresent() {
    final navigator = this.navigator;
    if (navigator == null || _session.motion != null) return;
    _session.commit(PresentationEnvironment.of(navigator.context));
  }

  /// Whether the route is modal now: its barrier absorbs taps and hides
  /// the routes below from screen readers. A sheet resting at a detent that
  /// does not dim is not; call [modalityChanged] when the answer changes.
  @protected
  bool get modal {
    final motion = _session.motion;
    return motion == null || presentation.modalOf(motion);
  }

  /// Applies a change of [modal] to the barrier; one reported while the
  /// frame builds, lays out or paints applies in the motion clock's coming
  /// publish phase, before the next frame builds.
  void modalityChanged() => _session.modalityChanged();

  /// Called once, when the route's close has finished or the route was
  /// disposed before that, with the result the route completed with.
  @protected
  void didFinish(T? result) => presentation.dismissed(result);

  /// Whether the route was dismissed and its content closes.
  bool get isLeaving => _session.isLeaving;

  bool _interacting = false;

  /// Shows the routes below while a gesture of the content moves it toward
  /// its dismissal, as an interactive pop does: they stay built and painted
  /// until [endInteraction], and the navigator knows a user gesture runs.
  void beginInteraction() {
    if (!isActive || isLeaving || _interacting) return;
    _interacting = true;
    navigator?.didStartUserGesture();
    _projection.update(AnimationStatus.forward);
  }

  /// Ends what [beginInteraction] began; a route the gesture did not
  /// dismiss rests again. Call it once the content has come back, or after
  /// the dismissal the gesture made.
  ///
  /// The focus ends where it would without the gesture: in the content,
  /// at what had it, when the gesture gave up, and in the route the
  /// dismissal revealed, at what had it there, as after a pop.
  void endInteraction() {
    if (!_interacting) return;
    _interacting = false;
    navigator?.didStopUserGesture();
    // The status, not isLeaving: once a popped route's close has ended the
    // navigator holds it dismissed, and the gesture's end leaves it alone.
    if (_projection.status == AnimationStatus.reverse) {
      if (_previous case final ModalRoute<Object?> revealed) {
        _focusRoute(revealed);
      }
      return;
    }
    _projection.update(AnimationStatus.completed);
    _focusRoute(this);
  }

  Route<Object?>? _previous;

  @override
  void didChangePrevious(Route<Object?>? previousRoute) {
    _previous = previousRoute;
    super.didChangePrevious(previousRoute);
  }

  // While a user gesture runs, the navigator makes every route's scope
  // unfocusable and skips the focus a route takes when it becomes current;
  // the scope turns focusable again only when the route rebuilds. This
  // does now what the route would have done without the gesture.
  static void _focusRoute(ModalRoute<Object?> route) {
    final navigator = route.navigator;
    final context = route.subtreeContext;
    if (navigator == null ||
        context == null ||
        !route.isCurrent ||
        !route.requestFocus) {
      return;
    }
    final scope = FocusScope.of(context, createDependency: false);
    scope.canRequestFocus = true;
    navigator.focusNode.enclosingScope?.setFirstFocus(scope);
  }

  /// Reports that the content's open came to rest: the push completes.
  void didOpen() {
    if (!isActive || isLeaving) return;
    _projection.update(AnimationStatus.completed);
    _completeSettle();
  }

  /// Reports that the content's close reached its end: the route goes.
  /// Later reports change nothing.
  void didLeave() {
    if (_session.ended) return;
    _completeSettle();
    if (_removeAtEnd) {
      // removeRoute disposes the route itself; a dismissed status would ask
      // the navigator to finalize a route it no longer has.
      _removeAtEnd = false;
      if (isActive) _remove();
    } else if (_popped) {
      _projection.update(AnimationStatus.dismissed);
    }
    _finish();
  }

  /// Whether a dismissal by [trigger] would close the presentation now:
  /// the [presentation]'s [Presentation.dismiss] lets it, no `PopScope` of
  /// the content vetoes it and no local history entry takes it first. A
  /// programmatic one always goes while the route is presented.
  bool canDismiss(DismissTrigger trigger) =>
      isActive &&
      !isLeaving &&
      (trigger == DismissTrigger.programmatic ||
          (_allows(trigger) &&
              !willHandlePopInternally &&
              super.popDisposition == RoutePopDisposition.pop));

  /// Dismisses the presentation for [trigger] with [result].
  ///
  /// A [DismissTrigger.programmatic] dismissal pops at once; any other
  /// goes through the [presentation]'s [Presentation.dismiss] and the
  /// content's `PopScope`s first, and a refusal by either calls its
  /// [Presentation.onVeto].
  void dismiss(DismissTrigger trigger, [T? result]) {
    final nav = navigator;
    if (nav == null || !isActive || isLeaving) return;
    if (trigger != DismissTrigger.programmatic) {
      if (!_session.admits(trigger)) return;
      if (super.popDisposition != RoutePopDisposition.pop) {
        super.onPopInvokedWithResult(false, result);
        presentation.onVeto?.call(trigger);
        return;
      }
    }
    _trigger = trigger;
    if (isCurrent) {
      nav.pop<T>(result);
      return;
    }
    final resolved = _resultFor(result);
    _completeSettle();
    _projection.update(AnimationStatus.reverse);
    if (_session.leave(trigger, resolved)) {
      _removeAtEnd = true;
    } else {
      _remove();
      _finish();
    }
  }

  // The back gesture under way, and its last sample for its velocity.
  bool _backing = false;
  double _backTime = 0;
  double _backProgress = 0;
  double _backVelocity = 0;
  VoidCallback? _cancelReturn;

  /// Whether Android's predictive back gesture may start on this route: its
  /// motion is [PredictiveBack], it rests open as the navigator's top route
  /// above another, no gesture runs already and nothing would refuse its
  /// pop: the [presentation]'s [Presentation.dismiss] lets Back through and
  /// no `PopScope` or local history entry takes it.
  @override
  bool get popGestureEnabled {
    final navigator = this.navigator;
    return _session.motion is PredictiveBack &&
        navigator != null &&
        !navigator.userGestureInProgress &&
        isCurrent &&
        !isFirst &&
        _projection.status == AnimationStatus.completed &&
        canDismiss(DismissTrigger.back);
  }

  /// Starts the presentation's interactive dismissal under Android's
  /// predictive back gesture; [progress] is the route's, 1 open and 0
  /// gone, as `PredictiveBackRoute` counts it.
  @override
  void handleStartBackGesture({double progress = 0}) {
    final motion = _session.motion;
    if (motion is! PredictiveBack || _backing) return;
    _cancelReturn?.call();
    _cancelReturn = null;
    _backing = true;
    beginInteraction();
    final t = motion.clock.now;
    _backTime = t;
    _backProgress = 1 - progress;
    _backVelocity = 0;
    motion.backStarted(t);
    motion.backMoved(t, _backProgress);
  }

  /// Moves the presentation with the gesture.
  @override
  void handleUpdateBackGestureProgress({required double progress}) {
    final motion = _session.motion;
    if (!_backing || motion is! PredictiveBack) return;
    final t = motion.clock.now;
    final p = 1 - progress;
    if (t > _backTime) {
      _backVelocity = (p - _backProgress) / (t - _backTime);
      _backTime = t;
    }
    _backProgress = p;
    motion.backMoved(t, p);
  }

  /// Dismisses the presentation for [DismissTrigger.back], its motion
  /// continuing from the gesture with the gesture's velocity.
  @override
  void handleCommitBackGesture() => _endBack(commits: true);

  /// Returns the presentation to rest open.
  @override
  void handleCancelBackGesture() => _endBack(commits: false);

  void _endBack({required bool commits}) {
    final motion = _session.motion;
    if (!_backing || motion is! PredictiveBack) return;
    _backing = false;
    final t = motion.clock.now;
    final goes = commits && isCurrent && canDismiss(DismissTrigger.back);
    motion.backEnded(
      t,
      commits: goes,
      velocity: _backVelocity,
    );
    if (goes) {
      dismiss(DismissTrigger.back);
      endInteraction();
    } else {
      _awaitReturn(motion, t);
    }
  }

  // What is below stays shown until the presentation is back at rest.
  void _awaitReturn(Presented motion, double t) {
    final rest = motion.restTime();
    if (!isActive || isLeaving || (rest != null && rest <= t)) {
      endInteraction();
      return;
    }
    final clock = motion.clock;
    _cancelReturn = clock.schedule(
      rest ?? t + (clock.framePeriod ?? 1 / 60),
      (time) {
        _cancelReturn = null;
        _awaitReturn(motion, time);
      },
    );
  }

  /// Notes where the route is shown from: the content carries the themes
  /// around [from], as a presentation shown from a source carries the
  /// source's look, and a presentation that asks for it goes when the
  /// scrollable around [from] starts to scroll.
  @internal
  void presentFrom(BuildContext from, NavigatorState to) {
    _themes = InheritedTheme.capture(from: from, to: to.context);
    if (!presentation.dismissesOnScroll) return;
    _session.followScroll(Scrollable.maybeOf(from)?.position, _scrolled);
  }

  void _scrolled() => dismiss(DismissTrigger.scroll);

  bool get _trapsFocus => false;

  /// How focus traversal behaves at the content's edges: as given, or a
  /// closed loop while a popup presentation is [modal], as in a dialog.
  @override
  TraversalEdgeBehavior? get traversalEdgeBehavior =>
      super.traversalEdgeBehavior ??
      (_trapsFocus && modal ? TraversalEdgeBehavior.closedLoop : null);

  @override
  @nonVirtual
  Color? get barrierColor => null;

  @override
  @nonVirtual
  bool get barrierDismissible => false;

  /// What screen readers call the barrier: the [presentation]'s
  /// [Presentation.barrierLabel] by default.
  @override
  String? get barrierLabel => presentation.barrierLabel;

  @override
  @nonVirtual
  Duration get transitionDuration => Duration.zero;

  @override
  @nonVirtual
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  @nonVirtual
  Animation<double> createAnimation() => _projection;

  @override
  @nonVirtual
  bool get finishedWhenPopped => false;

  // While presented, Back reaches the gate through onPopInvokedWithResult
  // instead of popping the route under the Navigator's own check.
  @override
  @nonVirtual
  RoutePopDisposition get popDisposition {
    final base = super.popDisposition;
    return isActive && !isLeaving && base != RoutePopDisposition.bubble
        ? RoutePopDisposition.doNotPop
        : base;
  }

  @override
  @nonVirtual
  void onPopInvokedWithResult(bool didPop, T? result) {
    if (didPop) {
      super.onPopInvokedWithResult(didPop, result);
    } else {
      dismiss(DismissTrigger.back, result);
    }
  }

  @override
  @nonVirtual
  TickerFuture didPush() {
    didPresent();
    _projection.update(AnimationStatus.forward);
    final settle = _settle = Ticker((_) {});
    settle.muted = true;
    final opened = settle.start();
    super.didPush();
    return opened;
  }

  @override
  @nonVirtual
  void didAdd() {
    didPresent();
    super.didAdd();
    _projection.update(AnimationStatus.completed);
  }

  @override
  @nonVirtual
  void didReplace(Route<Object?>? oldRoute) {
    didPresent();
    super.didReplace(oldRoute);
    _projection.update(AnimationStatus.completed);
  }

  @override
  @nonVirtual
  bool didPop(T? result) {
    final trigger = _trigger;
    _trigger = DismissTrigger.programmatic;
    // A route already closing under its cover keeps its result and its
    // close; the pop only makes it leave as a popped route.
    final closing = _removeAtEnd;
    final resolved = closing ? _session.result as T? : _resultFor(result);
    if (!super.didPop(resolved)) return false;
    _popped = true;
    _removeAtEnd = false;
    _completeSettle();
    _projection.update(AnimationStatus.reverse);
    if (!closing && !_session.leave(trigger, resolved)) didLeave();
    return true;
  }

  @override
  @nonVirtual
  Widget buildModalBarrier() => PresentationInert(
    isLeaving: () => isLeaving,
    leaving: _session.inert,
    child: ValueListenableBuilder<bool>(
      valueListenable: _session.modal,
      builder: (context, modal, _) => modal
          ? presentationBarrier(
              dismissible: _allows(DismissTrigger.outsideTap),
              label: barrierLabel,
              onTap: () => dismiss(DismissTrigger.outsideTap),
            )
          : const SizedBox.shrink(),
    ),
  );

  // The content root sits outside the page's repaint boundary, so the
  // content repainting every frame of its motion does not repaint it.
  @override
  @nonVirtual
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _ContentRoot(route: this, child: child);

  @override
  @nonVirtual
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final content = Builder(builder: buildContent);
    return _themes?.wrap(content) ?? content;
  }

  // A route removed from under others still tells its PopScopes it went.
  void _remove() {
    final result = _session.result as T?;
    super.onPopInvokedWithResult(true, result);
    navigator?.removeRoute(this, result);
  }

  void _completeSettle() {
    final settle = _settle;
    if (settle != null && settle.isActive) settle.stop();
  }

  void _finish() {
    _session.followScroll(null, _scrolled);
    _session.end();
  }

  @override
  void dispose() {
    _cancelReturn?.call();
    _settle?.dispose();
    _finish();
    super.dispose();
    _projection.dispose();
    _session.dispose();
  }
}

/// A presented route whose motion lives in its content: a sheet, an alert,
/// a popover, a menu.
///
/// UIKit: a presented `UIViewController` with a custom transition.
/// SwiftUI: `.sheet`, `.alert`, `.popover`. Flutter: a [PopupRoute].
///
/// The route owns the lifecycle and the content owns the motion. The
/// content reports [didOpen] when the open comes to rest and [didLeave]
/// when the close first reaches its end; the route starts the close
/// through [leave] once it is popped. Only the status of [animation]
/// follows the motion, its value stays 1, so nothing the route builds
/// rebuilds as the motion runs. The push's transition completes at the
/// open's rest, so a `pushReplacement` keeps the replaced route until the
/// new one is in place. The future of `Navigator.push` completes at the
/// pop, as the close starts; for a route dismissed under another, when it
/// leaves the navigator.
///
/// Every user dismissal (an outside tap, Escape, Back, a screen reader's
/// dismiss, a gesture of the content) goes through one gate: the
/// [Presentation.dismiss] policy for the trigger, then the content's
/// `PopScope`s. A `PopScope` veto tells the `PopScope`s with `didPop`
/// false, as a blocked Back does, and calls [Presentation.onVeto], as a
/// trigger the policy refuses does. On the first route of its navigator
/// Back goes on to whatever is outside the navigator. A dismissal always
/// pops this route, never whatever is on top: one under another route
/// closes under it and leaves the navigator when its close ends.
/// `Navigator.pop` is programmatic and consults nothing.
///
/// While [modal], the barrier absorbs taps and hides the routes below from
/// screen readers; with a [barrierLabel] and a policy that lets an outside
/// tap through it is a labelled dismiss target, read after the content.
///
/// The focus moves into the content at the open (see
/// [Presentation.initialFocus]), Tab stays inside while it is [modal]
/// unless a `traversalEdgeBehavior` is given, and the navigator hands the
/// focus back to the route below, to what had it there, at the pop.
class PresentationRoute<T> extends PopupRoute<T> with _PresentationEngine<T> {
  /// Creates a route that shows [presentation].
  PresentationRoute({
    required this.presentation,
    super.settings,
    super.requestFocus,
    super.traversalEdgeBehavior,
    this._semanticsLabel,
  });

  @override
  final Presentation<T, Presented> presentation;

  final String? _semanticsLabel;

  @override
  String? get semanticsLabel => _semanticsLabel ?? presentation.semanticsLabel;

  @override
  bool get _trapsFocus => true;
}

/// A page whose motion lives in its content, such as a page that zooms out
/// of its source.
///
/// UIKit: a pushed `UIViewController` whose transition the content drives
/// (a slide, `.zoom`). Flutter: a [PageRoute].
///
/// It has the lifecycle, the dismissal gate and the barrier of
/// [PresentationRoute], and is a [PageRoute] to `RouteAware` observers and
/// to its neighbours. Its [animation]'s value stays 1: a neighbour's
/// secondary transition jumps to its end (a page below that should stay
/// put returns false from `canTransitionTo` for it), and no `Hero` flies.
///
/// A subclass describes its [presentation], as a [PageRoute] describes its
/// page in `buildPage`: a page's motion often needs the route itself.
abstract class PresentationPageRoute<T> extends PageRoute<T>
    with _PresentationEngine<T> {
  /// Creates a page route; [semanticsLabel] names it to screen readers in
  /// place of the [presentation]'s [Presentation.semanticsLabel].
  PresentationPageRoute({
    super.settings,
    super.requestFocus,
    this._semanticsLabel,
  });

  final String? _semanticsLabel;

  @override
  String? get semanticsLabel => _semanticsLabel ?? presentation.semanticsLabel;

  @override
  bool get maintainState => true;
}

class _ContentRoot extends StatefulWidget {
  const _ContentRoot({required this.route, required this.child});

  final _PresentationEngine<Object?> route;
  final Widget child;

  @override
  State<_ContentRoot> createState() => _ContentRootState();
}

class _ContentRootState extends State<_ContentRoot>
    with WidgetsBindingObserver {
  FocusScopeNode? _scope;

  @override
  void initState() {
    super.initState();
    widget.route._session.modal.addListener(_trap);
    WidgetsBinding.instance.addObserver(this);
  }

  // Android's predictive back reaches routes only through binding
  // observers, as it reaches a page through its transitions builder.
  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    final route = widget.route;
    if (backEvent.isButtonEvent || !route.popGestureEnabled) return false;
    route.handleStartBackGesture(progress: 1 - backEvent.progress);
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) =>
      widget.route.handleUpdateBackGestureProgress(
        progress: 1 - backEvent.progress,
      );

  @override
  void handleCommitBackGesture() => widget.route.handleCommitBackGesture();

  @override
  void handleCancelBackGesture() => widget.route.handleCancelBackGesture();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scope = Focus.maybeOf(
      context,
      scopeOk: true,
      createDependency: false,
    )?.nearestScope;
    _trap();
  }

  // The route's scope reads the edge behaviour only when it builds; a
  // change of modality applies it at once.
  void _trap() {
    final scope = _scope;
    final navigator = widget.route.navigator;
    if (scope == null || navigator == null) return;
    scope.traversalEdgeBehavior =
        widget.route.traversalEdgeBehavior ??
        navigator.widget.routeTraversalEdgeBehavior;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.route._session.modal.removeListener(_trap);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.route;
    return PresentationInert(
      isLeaving: () => route.isLeaving,
      leaving: route._session.inert,
      child: PresentationRoot(
        isLeaving: () => route.isLeaving,
        allows: (trigger) => route.isActive && route._allows(trigger),
        dismiss: route.dismiss,
        label: route.semanticsLabel,
        role: route.presentation.semanticsRole,
        initialFocus: route.presentation.initialFocus,
        onTapOutside: route.presentation.dismissesOnOutsideTap
            ? () {
                if (!route.modal) route.dismiss(DismissTrigger.outsideTap);
              }
            : null,
        child: widget.child,
      ),
    );
  }
}

final class _StatusProjection extends Animation<double>
    with AnimationLocalListenersMixin, AnimationLocalStatusListenersMixin {
  AnimationStatus _status = AnimationStatus.dismissed;

  @override
  double get value => 1;

  @override
  AnimationStatus get status => _status;

  void update(AnimationStatus status) {
    if (status == _status) return;
    _status = status;
    notifyStatusListeners(status);
  }

  void dispose() {
    clearListeners();
    clearStatusListeners();
  }

  @override
  void didRegisterListener() {}

  @override
  void didUnregisterListener() {}
}

final class _RouteShell<T> implements PresentationShell {
  _RouteShell(this.route);

  final _PresentationEngine<T> route;

  @override
  void dismiss(DismissTrigger trigger, [Object? result]) =>
      route.dismiss(trigger, result as T?);

  @override
  bool canDismiss(DismissTrigger trigger) => route.canDismiss(trigger);

  @override
  void beginInteraction() => route.beginInteraction();

  @override
  void endInteraction() => route.endInteraction();

  @override
  void didOpen() => route.didOpen();

  @override
  void didLeave() => route.didLeave();

  @override
  void modalityChanged() => route.modalityChanged();

  @override
  bool get isLeaving => route.isLeaving;
}
