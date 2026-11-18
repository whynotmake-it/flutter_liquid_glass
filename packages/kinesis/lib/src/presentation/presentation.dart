import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/src/presentation/route.dart';
import 'package:kinesis/src/presentation/source_follower.dart';
import 'package:kinesis/widgets.dart';

/// Where and how big a presentation may be, read from the place it shows
/// in when it commits.
@immutable
final class PresentationEnvironment {
  /// Describes the place a presentation commits into.
  const PresentationEnvironment({
    required this.clock,
    required this.time,
    required this.bounds,
    required this.padding,
    required this.traits,
  });

  /// The environment of [context] now: on the clock of the motions there
  /// (`MotionClockScope`), at its time.
  factory PresentationEnvironment.of(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final clock = MotionClockScope.of(context);
    return PresentationEnvironment(
      clock: clock,
      time: clock.now,
      bounds: media?.size ?? Size.zero,
      padding:
          (media?.viewPadding ?? EdgeInsets.zero) +
          (media?.viewInsets ?? EdgeInsets.zero),
      traits: MotionTraitsOverride.of(context),
    );
  }

  /// The clock the presentation's motion runs on: give it to the motion
  /// (`Motion(clock: ...)`).
  final MotionClock clock;

  /// The commit's time: the stamp of the input that presented it.
  final double time;

  /// The size of the place the presentation shows in.
  final Size bounds;

  /// What covers its edges: the safe area and the keyboard.
  final EdgeInsets padding;

  /// The motion preferences there.
  final MotionTraits traits;
}

/// A presentation: the motion it plays and the content over it. One
/// description runs in a route ([PresentationRoute], [PresentationPageRoute])
/// or a portal (`PresentationPortal`, for a touch that must not be
/// cancelled).
///
/// The shell commands the motion at stamped times: it opens it at the
/// commit and starts its leave at the dismissal's stamp. It completes the
/// push once the motion's presence is shown and ends once it is hidden
/// after a leave. A motion that starts leaving on its own dismisses the
/// presentation programmatically; its [Presented.leave] then answers true
/// for the leave already under way. The shell draws the [dim], owns the
/// barrier, Back, Escape, focus and the screen reader's dismiss, and holds
/// the [source] while it shows; a [Sourced] motion hears where the source
/// is in every frame.
///
/// ```dart
/// final alert = Presentation<bool, AlertMotion>(
///   motion: (environment) => AlertMotion(),
///   builder: (context, motion) => AlertCard(motion: motion),
///   dismiss: DismissPolicy.modal,
///   dim: (motion) => 0.2 * motion.dimming,
/// );
/// showPresentation(context, PresentationRoute(presentation: alert));
/// ```
@immutable
final class Presentation<T, M extends Presented> {
  /// Describes a presentation.
  const Presentation({
    required this.motion,
    required this.builder,
    this.source,
    this.dismiss = const DismissPolicy(),
    this.dim,
    this.dimColor = const Color(0xFF000000),
    this.modal,
    this.result,
    this.onVeto,
    this.onDismissed,
    this.semanticsLabel,
    this.barrierLabel,
    this.initialFocus,
    this.semanticsRole,
    this.dismissesOnScroll = false,
    this.dismissesOnOutsideTap = false,
  });

  /// Makes the motion at the commit, or hands over one the caller keeps
  /// for longer (a menu's lives with its anchor).
  final M Function(PresentationEnvironment environment) motion;

  /// Builds the content over [motion].
  final Widget Function(BuildContext context, M motion) builder;

  /// What the presentation grows out of, hidden while it shows.
  final MotionSource? source;

  /// Which user dismissals go through.
  final DismissPolicy dismiss;

  /// The opacity of the dim behind the content, 0 to 1; none when null.
  final double Function(M motion)? dim;

  /// The color of the dim at opacity 1, black by default.
  final Color dimColor;

  /// Whether the presentation is modal now (its barrier absorbs taps and
  /// hides what is below from screen readers); always when null.
  final bool Function(M motion)? modal;

  /// The result a dismissal with [result] completes with: an alert's
  /// cancel action for a dismissal without one.
  final T? Function(T? result)? result;

  /// Called when [dismiss] or a `PopScope` refused a dismissal.
  final void Function(DismissTrigger trigger)? onVeto;

  /// Called once the presentation has gone, with what it completed with, as
  /// UIKit calls a dismissal's completion: an alert runs the chosen
  /// action's handler here.
  final void Function(T? result)? onDismissed;

  /// The name screen readers announce for the content.
  ///
  /// The content's root is a route of its own to screen readers
  /// (`SemanticsProperties.scopesRoute`); with a label it also names it
  /// (`namesRoute`), and screen readers announce the label when the
  /// presentation opens. Without one, VoiceOver plays its sound and
  /// TalkBack says nothing, as for a route.
  final String? semanticsLabel;

  /// Whether the presentation goes, as a menu of `RawMenuAnchor` does, when
  /// the nearest scrollable around where it was shown from starts to
  /// scroll: around a portal's anchor, or around the context a route was
  /// shown from with `showPresentation` (a route pushed otherwise has none).
  /// The dismissal is a [DismissTrigger.scroll] through [dismiss]; scrolls
  /// inside the content do not count.
  final bool dismissesOnScroll;

  /// Whether a tap outside the content dismisses the presentation while it
  /// is not modal, as a tap outside a `RawMenuAnchor`'s menu closes it; the
  /// tap still reaches what it lands on. A portal's anchor counts as
  /// inside. While the presentation is modal its barrier takes every tap
  /// outside instead. The dismissal is a [DismissTrigger.outsideTap]
  /// through [dismiss].
  final bool dismissesOnOutsideTap;

  /// What the content is to assistive technology: `SemanticsRole.dialog`,
  /// `SemanticsRole.alertDialog` or `SemanticsRole.menu` (whose children
  /// then must be menu items), set on the content's root; none when null.
  final SemanticsRole? semanticsRole;

  /// What screen readers call the barrier behind the content while the
  /// presentation is modal and an outside tap may dismiss it, such as
  /// "Dismiss menu"; the barrier then offers that dismissal and comes after
  /// the content in the reading order. Without a label, or where the
  /// platform does not dismiss through a barrier (Linux, Windows, Fuchsia),
  /// the barrier is silent. In a route it hides what is below from screen
  /// readers either way. The presentation has no words of its own: pass the
  /// app's localized string, as `ModalRoute.barrierLabel` takes one.
  final String? barrierLabel;

  /// The node that takes the focus when the presentation opens, such as the
  /// field of a sheet that asks for a name. Without one, the first
  /// focusable node of the content takes it while the keyboard is in use
  /// ([KeyboardUse]) and the presentation itself otherwise, so a touch
  /// never brings up the keyboard for a field it did not tap and a click
  /// lights no focus ring. Either way Escape reaches the presentation.
  final FocusNode? initialFocus;

  // The calls below take the motion as a Presented and the result as an
  // Object?, so a shell holding a Presentation<Object?, Presented> calls
  // the functions of a Presentation<T, M> without a covariance error.

  /// Makes the motion for [environment].
  @internal
  Presented create(PresentationEnvironment environment) => motion(environment);

  /// Builds the content over [motion].
  @internal
  Widget build(BuildContext context, Presented motion) =>
      builder(context, motion as M);

  /// The dim's opacity for [motion], or null for none.
  @internal
  MotionSelection<double>? dimOf(Presented motion) {
    final dim = this.dim;
    if (dim == null) return null;
    return motion.select((m) => dim(m as M).clamp(0.0, 1.0));
  }

  /// Whether [modal] can change while the presentation shows.
  @internal
  bool get changesModality => modal != null;

  /// Whether the presentation is modal for [motion] now.
  @internal
  bool modalOf(Presented motion) => modal?.call(motion as M) ?? true;

  /// Tells [onDismissed] the presentation has gone with [result].
  @internal
  void dismissed(Object? result) => onDismissed?.call(result as T?);

  /// The result a dismissal with [popped] completes with.
  @internal
  Object? resultOf(Object? popped) {
    final result = this.result;
    return result == null ? popped : result(popped as T?);
  }
}

/// Commits [presentation]: makes its motion for [environment], leases the
/// source and tells a [Sourced] motion where it is, then opens the motion
/// at the environment's time. The shell calls the lease's callback when it
/// lets the source go.
@internal
(Presented, VoidCallback?) commitPresentation(
  Presentation<Object?, Presented> presentation,
  PresentationEnvironment environment,
) {
  final motion = presentation.create(environment);
  final source = presentation.source;
  final lease = source?.lease();
  if (source != null && motion is Sourced) {
    (motion as Sourced).sourceMoved(environment.time, source.geometry);
  }
  motion.open(environment.time);
  return (motion, lease);
}

/// The content's hold on its shell.
abstract interface class PresentationHandle {
  /// The handle of the presentation around [context].
  static PresentationHandle of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_HandleScope>();
    assert(scope != null, 'No presentation around $context.');
    return scope!.handle;
  }

  /// Dismisses the presentation for [trigger] with [result]. Unless
  /// [trigger] is programmatic it goes through the policy and, in a route,
  /// the content's `PopScope`s.
  void dismiss(DismissTrigger trigger, [Object? result]);

  /// Whether a dismissal by [trigger] would go through now: a sheet asks
  /// before a drag whether the drag may take it away.
  bool canDismiss(DismissTrigger trigger);

  /// Shows what is below while a gesture of the content moves it toward
  /// its dismissal; [endInteraction] ends it.
  void beginInteraction();

  /// Ends what [beginInteraction] began.
  void endInteraction();
}

/// What a shell does for the content it presents.
@internal
abstract interface class PresentationShell implements PresentationHandle {
  /// The motion's open came to rest.
  void didOpen();

  /// The motion's leave reached its end.
  void didLeave();

  /// The answer of [Presentation.modal] may have changed.
  void modalityChanged();

  /// Whether the presentation was dismissed and its motion leaves.
  bool get isLeaving;
}

/// The barrier of a modal presentation: it absorbs every tap and hands it
/// to [onTap], which goes through the dismissal gate, and hides what is
/// below from screen readers. With a [label] and an outside tap the gate
/// may let through ([dismissible]), screen readers find it after the
/// content as a dismiss target where the platform offers one.
@internal
Widget presentationBarrier({
  required bool dismissible,
  required String? label,
  required VoidCallback onTap,
}) {
  final Widget barrier = ModalBarrier(
    barrierSemanticsDismissible: dismissible,
    semanticsLabel: label,
    // Every tap goes through the gate, so a refused one is reported as a
    // veto, as UIKit reports a tap on the dimming of a sheet that may not
    // leave.
    onDismiss: onTap,
  );
  if (!dismissible || label == null) return barrier;
  return Semantics(sortKey: const OrdinalSortKey(1), child: barrier);
}

/// The root every shell puts around a presentation's content: it names it
/// to screen readers as a route of its own with [label], offers their dismiss
/// and maps Escape (`DismissIntent`) to [dismiss] where [allows] lets the
/// trigger through, and moves the focus in when the shell's scope gets it.
@internal
class PresentationRoot extends StatelessWidget {
  /// The root around [child].
  const PresentationRoot({
    required this.isLeaving,
    required this.allows,
    required this.dismiss,
    required this.label,
    required this.role,
    required this.initialFocus,
    required this.child,
    this.tapRegion,
    this.onTapOutside,
    super.key,
  });

  /// Whether the presentation leaves now.
  final bool Function() isLeaving;

  /// Whether the policy lets a trigger through.
  final bool Function(DismissTrigger trigger) allows;

  /// Dismisses through the shell's gate.
  final void Function(DismissTrigger trigger) dismiss;

  /// The name screen readers announce.
  final String? label;

  /// What the content is to assistive technology.
  final SemanticsRole? role;

  /// The node that takes the focus at the open.
  final FocusNode? initialFocus;

  /// The content.
  final Widget child;

  /// The tap region group of the content and what counts as inside it.
  final Object? tapRegion;

  /// Called for a tap outside the content; none when null.
  final VoidCallback? onTapOutside;

  @override
  Widget build(BuildContext context) {
    final onTapOutside = this.onTapOutside;
    final root = _semantics();
    if (onTapOutside == null) return root;
    return TapRegion(
      groupId: tapRegion,
      onTapOutside: (_) => onTapOutside(),
      child: root,
    );
  }

  Widget _semantics() => Semantics(
    scopesRoute: true,
    namesRoute: label != null,
    explicitChildNodes: true,
    label: label,
    role: role,
    onDismiss: allows(DismissTrigger.accessibility)
        ? () => dismiss(DismissTrigger.accessibility)
        : null,
    child: Actions(
      actions: <Type, Action<Intent>>{DismissIntent: _DismissAction(this)},
      child: _FocusIn(initialFocus: initialFocus, child: child),
    ),
  );
}

class _DismissAction extends DismissAction {
  _DismissAction(this.root);

  final PresentationRoot root;

  // A disabled action still ends the search, so Escape on a presentation
  // that may not leave by it never reaches one below.
  @override
  bool isEnabled(DismissIntent intent) =>
      !root.isLeaving() && root.allows(DismissTrigger.escape);

  @override
  void invoke(DismissIntent intent) => root.dismiss(DismissTrigger.escape);
}

/// Moves the focus into the content whenever the shell's scope holds it
/// itself: to the named node, to the first focusable one while the
/// keyboard is in use, or to a node of its own, so Escape reaches the
/// presentation. What the content focuses itself wins.
class _FocusIn extends StatefulWidget {
  const _FocusIn({required this.initialFocus, required this.child});

  final FocusNode? initialFocus;
  final Widget child;

  @override
  State<_FocusIn> createState() => _FocusInState();
}

class _FocusInState extends State<_FocusIn> {
  final FocusNode _own = FocusNode(
    debugLabel: 'Presentation',
    skipTraversal: true,
  );

  FocusScopeNode? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = Focus.maybeOf(
      context,
      scopeOk: true,
      createDependency: false,
    )?.nearestScope;
    if (identical(scope, _scope)) return;
    _scope?.removeListener(_caught);
    _scope = scope;
    scope?.addListener(_caught);
  }

  // The scope gets the focus after the frame that built the content, so
  // the content's nodes are in the focus tree by then.
  void _caught() {
    final scope = _scope;
    if (scope == null || !scope.hasPrimaryFocus) return;
    final named = widget.initialFocus;
    if (named != null && named.context != null && named.canRequestFocus) {
      named.requestFocus();
      return;
    }
    if (KeyboardUse.inUse) {
      final policy =
          FocusTraversalGroup.maybeOf(context) ?? ReadingOrderTraversalPolicy();
      final first = policy.findFirstFocus(scope, ignoreCurrentFocus: true);
      if (first != null && !identical(first, scope)) {
        first.requestFocus();
        return;
      }
    }
    _own.requestFocus();
  }

  @override
  void dispose() {
    _scope?.removeListener(_caught);
    _own.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Focus(focusNode: _own, includeSemantics: false, child: widget.child);
}

/// Makes [child] inert from the moment its presentation starts to leave:
/// it takes no new touch ([isLeaving] is asked at each touch, as a close
/// can start in any phase of a frame, and a finger already down stays with
/// what it touched), holds no focus and leaves the semantics tree once
/// [leaving] turns true.
@internal
class PresentationInert extends StatelessWidget {
  /// Makes [child] inert while [isLeaving].
  const PresentationInert({
    required this.isLeaving,
    required this.leaving,
    required this.child,
    super.key,
  });

  /// Whether the presentation leaves now.
  final bool Function() isLeaving;

  /// Turns true once the presentation leaves, for what only a rebuild
  /// changes.
  final ValueListenable<bool> leaving;

  /// The content.
  final Widget child;

  @override
  Widget build(BuildContext context) => _LeavingGate(
    isLeaving: isLeaving,
    child: ValueListenableBuilder<bool>(
      valueListenable: leaving,
      builder: (context, leaving, child) => ExcludeFocus(
        excluding: leaving,
        child: ExcludeSemantics(excluding: leaving, child: child),
      ),
      child: child,
    ),
  );
}

class _LeavingGate extends SingleChildRenderObjectWidget {
  const _LeavingGate({required this.isLeaving, required super.child});

  final bool Function() isLeaving;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLeavingGate(isLeaving);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderLeavingGate renderObject,
  ) {
    renderObject.isLeaving = isLeaving;
  }
}

class _RenderLeavingGate extends RenderProxyBox {
  _RenderLeavingGate(this.isLeaving);

  bool Function() isLeaving;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      !isLeaving() && super.hitTest(result, position: position);
}

class _HandleScope extends InheritedWidget {
  const _HandleScope({required this.handle, required super.child});

  final PresentationHandle handle;

  @override
  bool updateShouldNotify(_HandleScope oldWidget) =>
      !identical(handle, oldWidget.handle);
}

/// Runs a described presentation's motion inside a shell: holds it on the
/// clock, tells the shell when it opened and left, draws the dim and
/// follows the source.
@internal
class PresentedContent extends StatefulWidget {
  /// Shows [motion] of [presentation] in [shell].
  const PresentedContent({
    required this.presentation,
    required this.motion,
    required this.shell,
    super.key,
  });

  /// The description.
  final Presentation<Object?, Presented> presentation;

  /// The motion the shell committed.
  final Presented motion;

  /// The shell.
  final PresentationShell shell;

  @override
  State<PresentedContent> createState() => _PresentedContentState();
}

class _PresentedContentState extends State<PresentedContent> {
  late MotionSelection<PresenceStatus> _presence;
  late MotionSelection<bool>? _modal;
  late MotionSelection<double>? _dim;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(PresentedContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.motion, widget.motion)) return;
    _unbind();
    _bind();
  }

  @override
  void dispose() {
    _unbind();
    super.dispose();
  }

  void _bind() {
    final motion = widget.motion;
    _presence = motion.select((m) => m.presence);
    _presence.addListener(_heard);
    final presentation = widget.presentation;
    _modal = presentation.changesModality
        ? motion.select(presentation.modalOf)
        : null;
    _modal?.addListener(widget.shell.modalityChanged);
    _dim = presentation.dimOf(motion);
    _heard();
  }

  void _unbind() {
    _presence.removeListener(_heard);
    _modal?.removeListener(widget.shell.modalityChanged);
  }

  void _heard() {
    final shell = widget.shell;
    switch (_presence.value) {
      case PresenceStatus.shown when !shell.isLeaving:
        shell.didOpen();
      case PresenceStatus.hidden when shell.isLeaving:
        shell.didLeave();
      // A motion that leaves on its own, as a menu does once a row is
      // chosen, takes the shell with it.
      case PresenceStatus.leaving when !shell.isLeaving:
        shell.dismiss(DismissTrigger.programmatic);
      case PresenceStatus.shown ||
          PresenceStatus.hidden ||
          PresenceStatus.opening ||
          PresenceStatus.leaving:
    }
  }

  @override
  Widget build(BuildContext context) {
    final presentation = widget.presentation;
    final motion = widget.motion;
    Widget content = Builder(
      builder: (context) => presentation.build(context, motion),
    );
    final source = presentation.source;
    if (source != null && motion is Sourced) {
      content = SourceFollower(
        source: source,
        motion: motion as Sourced,
        child: content,
      );
    }
    final dim = _dim;
    if (dim != null) {
      content = Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: MotionTransition(
              opacity: dim,
              child: ColoredBox(color: presentation.dimColor),
            ),
          ),
          content,
        ],
      );
    }
    return _HandleScope(
      handle: widget.shell,
      child: MotionScope(motion: motion, child: content),
    );
  }
}
