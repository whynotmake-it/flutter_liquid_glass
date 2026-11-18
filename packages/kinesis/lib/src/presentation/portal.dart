import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/src/presentation/presentation.dart';
import 'package:kinesis/src/presentation/session.dart';
import 'package:kinesis/widgets.dart';

/// Presents and dismisses the presentation of a [PresentationPortal].
final class PresentationPortalController {
  /// Creates a controller for one portal.
  PresentationPortalController();

  _PresentationPortalState? _portal;

  /// Whether the presentation shows, leaving included.
  bool get isPresented => _portal?._session.motion != null;

  /// Presents at the clock's time: inside an input, the input's stamp. A
  /// presentation on its way out comes back: its motion opens again from
  /// where it is.
  void present() => _portal?._present();

  /// Dismisses for [trigger], through the policy unless it is
  /// programmatic.
  void dismiss(DismissTrigger trigger) => _portal?.dismiss(trigger);
}

/// The overlay shell: the [presentation] shows on the root overlay over
/// [child], with the dismissal policy, dim, barrier, focus, Escape, Back and
/// the screen reader's dismiss of a route, but nothing is pushed, so the
/// touch that presented it is never cancelled: a hold that opens a context
/// menu keeps its finger on the rows. The content's `PopScope`s are not
/// asked. As on a route, new touches reach what is below as soon as the
/// presentation leaves, while its close plays on.
///
/// Unlike a route's, its barrier does not hide what is below from screen
/// readers: Flutter puts the semantics of an overlay portal's child under
/// its anchor, so screen readers find the presentation right after [child],
/// as they find the menu of a `RawMenuAnchor`. The labelled barrier is
/// there as on a route.
///
/// The focus moves in at the open (see [Presentation.initialFocus]), Tab
/// stays inside while the presentation is modal, and the focus goes back
/// to what had it as soon as the presentation starts to leave, or to what
/// had it before that when it is gone.
class PresentationPortal extends StatefulWidget {
  /// Shows [presentation] over [child] when [controller] presents it.
  const PresentationPortal({
    required this.controller,
    required this.presentation,
    required this.child,
    super.key,
  });

  /// Presents and dismisses.
  final PresentationPortalController controller;

  /// What is presented.
  final Presentation<Object?, Presented> presentation;

  /// What the portal sits on: the source of the presentation.
  final Widget child;

  @override
  State<PresentationPortal> createState() => _PresentationPortalState();
}

class _PresentationPortalState extends State<PresentationPortal>
    implements PresentationShell, PopEntry<Object?> {
  final OverlayPortalController _overlay = OverlayPortalController();
  final ValueNotifier<bool> _canPop = ValueNotifier<bool>(true);
  final FocusScopeNode _scope = FocusScopeNode(
    debugLabel: 'PresentationPortal',
  );
  late final PresentationSession _session;
  ModalRoute<Object?>? _route;
  FocusNode? _restore;

  @override
  void initState() {
    super.initState();
    final clock = MotionClockScope.of(context);
    _session = PresentationSession(
      presentation: () => widget.presentation,
      scopeClock: () => clock,
    );
    _session.modal.addListener(_trap);
    widget.controller._portal = this;
  }

  @override
  void didUpdateWidget(PresentationPortal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller._portal = null;
      widget.controller._portal = this;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _session.followScroll(Scrollable.maybeOf(context)?.position, _scrolled);
    final route = ModalRoute.of(context);
    if (identical(route, _route)) return;
    _route?.unregisterPopEntry(this);
    _route = route;
    route?.registerPopEntry(this);
  }

  void _scrolled() {
    if (widget.presentation.dismissesOnScroll) dismiss(DismissTrigger.scroll);
  }

  void _tappedOutside() {
    if (!_session.modal.value) dismiss(DismissTrigger.outsideTap);
  }

  @override
  void dispose() {
    if (identical(widget.controller._portal, this)) {
      widget.controller._portal = null;
    }
    _route?.unregisterPopEntry(this);
    _session.modal.removeListener(_trap);
    _end();
    _session.dispose();
    _canPop.dispose();
    _scope.dispose();
    super.dispose();
  }

  void _present() {
    if (_session.motion != null) {
      if (!_session.isLeaving) return;
      _session.reopen();
      _canPop.value = false;
      _scope.requestFocus();
      return;
    }
    _session.commit(PresentationEnvironment.of(context));
    final motion = _session.motion;
    _restore = FocusManager.instance.primaryFocus;
    _canPop.value = false;
    _trap();
    _overlay.show();
    // After the frame: the scope's node joins the focus tree only in the
    // build that shows the overlay, and a scope node asked before that drops
    // the request; the clock's publish phase may come before that build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (identical(_session.motion, motion) && !_session.isLeaving) {
        _scope.requestFocus();
      }
    });
  }

  void _end() {
    if (_session.motion == null) return;
    _session.end();
    _canPop.value = true;
  }

  @override
  void dismiss(DismissTrigger trigger, [Object? result]) {
    if (_session.motion == null || _session.isLeaving) return;
    if (!_session.admits(trigger)) return;
    final resolved = _session.resultOf(result);
    _restoreFocus();
    if (!_session.leave(trigger, resolved)) didLeave();
  }

  // An opener that is gone hands the focus to the scope around the portal,
  // which gives it to what had it before.
  void _restoreFocus() {
    if (!_scope.hasFocus) return;
    final restore = _restore;
    if (restore != null &&
        (restore.context?.mounted ?? false) &&
        restore.canRequestFocus) {
      restore.requestFocus();
    } else {
      _scope.unfocus(disposition: UnfocusDisposition.previouslyFocusedChild);
    }
  }

  @override
  bool canDismiss(DismissTrigger trigger) =>
      _session.motion != null &&
      !_session.isLeaving &&
      widget.presentation.dismiss.allows(trigger);

  @override
  void didOpen() {}

  @override
  void didLeave() {
    if (_session.motion == null) return;
    _end();
    _restoreFocus();
    _restore = null;
    if (mounted) _overlay.hide();
  }

  @override
  void modalityChanged() => _session.modalityChanged();

  // Tab stays inside a modal presentation, as in a dialog.
  void _trap() => _scope.traversalEdgeBehavior = _session.modal.value
      ? TraversalEdgeBehavior.closedLoop
      : TraversalEdgeBehavior.parentScope;

  @override
  bool get isLeaving => _session.isLeaving;

  @override
  void beginInteraction() {}

  @override
  void endInteraction() {}

  @override
  ValueListenable<bool> get canPopNotifier => _canPop;

  @override
  void onPopInvoked(bool didPop) {}

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {
    if (!didPop) dismiss(DismissTrigger.back, result);
  }

  // Screen readers find an overlay portal's child under the node of the
  // portal's own child, among that node's children in an order they read by
  // geometry, where a full-screen presentation comes first. A node of its own
  // after the source, with nothing else under it, carries the presentation.
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    explicitChildNodes: true,
    child: Stack(
      fit: StackFit.passthrough,
      children: [
        Semantics(
          container: true,
          sortKey: const OrdinalSortKey(0),
          child: widget.presentation.dismissesOnOutsideTap
              ? TapRegion(groupId: this, child: widget.child)
              : widget.child,
        ),
        Positioned.fill(
          child: OverlayPortal(
            controller: _overlay,
            overlayLocation: OverlayChildLocation.rootOverlay,
            overlayChildBuilder: _content,
            child: Semantics(sortKey: const OrdinalSortKey(1)),
          ),
        ),
      ],
    ),
  );

  Widget _content(BuildContext context) {
    final motion = _session.motion;
    if (motion == null) return const SizedBox.shrink();
    final presentation = widget.presentation;
    final content = Stack(
      fit: StackFit.expand,
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: _session.modal,
          builder: (context, modal, _) => modal
              ? presentationBarrier(
                  dismissible: presentation.dismiss.allows(
                    DismissTrigger.outsideTap,
                  ),
                  label: presentation.barrierLabel,
                  onTap: () => dismiss(DismissTrigger.outsideTap),
                )
              : const SizedBox.shrink(),
        ),
        Semantics(
          sortKey: const OrdinalSortKey(0),
          child: FocusScope(
            node: _scope,
            child: PresentationRoot(
              isLeaving: () => _session.isLeaving,
              allows: presentation.dismiss.allows,
              dismiss: dismiss,
              label: presentation.semanticsLabel,
              role: presentation.semanticsRole,
              initialFocus: presentation.initialFocus,
              tapRegion: this,
              onTapOutside: presentation.dismissesOnOutsideTap
                  ? _tappedOutside
                  : null,
              child: PresentedContent(
                presentation: presentation,
                motion: motion,
                shell: this,
              ),
            ),
          ),
        ),
      ],
    );
    // An overlay portal's child joins the semantics tree under its anchor,
    // so a barrier blocking what was painted before it would drop the whole
    // screen, the presentation and its anchor included; in a container of
    // its own it blocks nothing, and what is below stays readable.
    return PresentationInert(
      isLeaving: () => _session.isLeaving,
      leaving: _session.inert,
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        child: content,
      ),
    );
  }
}
