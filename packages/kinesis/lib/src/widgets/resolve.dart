import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:kinesis/motion.dart';

/// A render object that places its presentation from this frame's layout,
/// in the frame's resolve phase: after the whole view is laid out, before
/// paint.
///
/// [resolve] may retarget values and mark paint, composited layers and
/// layout. Values it changes, on any clock, publish at once
/// ([MotionClock.resolve]), so what draws them shows this frame's
/// presentation, never the previous one. What it and the values' render
/// listeners mark for layout is laid out again in the same frame, and the
/// hosts that this layout schedules resolve again, a few rounds at most: a
/// value that one subtree's layout computes reaches another subtree's
/// layout in the frame that computed it.
///
/// A host's [resolve] runs in a frame for one of three reasons: its layout
/// in this frame called [scheduleResolve]; it [resolvesEveryFrame]; or a
/// resolve round marked it for layout and that layout called
/// [scheduleResolve] again, which runs it in the next round of the same
/// frame. A round resolves its hosts from the shallowest down; after
/// eight rounds the rest waits for the next frame.
///
/// ```text
/// build -> layout (hosts call scheduleResolve)
///   -> resolve phase, one round after another:
///        + hosts that resolve every frame (first round only)
///        resolve the scheduled hosts, shallowest first; values publish
///        lay out again what the round marked
///        (scheduleResolve here schedules the next round)
///   -> compositing bits -> paint
/// ```
///
/// A render object that animates its own layout reads the app's
/// `withSpring` and `withoutAnimation` around a change through
/// [layoutSpring].
mixin MotionResolveHost on RenderObject {
  /// Places the presentation from this frame's layout.
  void resolve();

  /// The spring of this frame's layout changes: the spring of the latest
  /// outermost `withSpring` that closed since the previous frame drew,
  /// [Spring.immediate] for a `withoutAnimation`, or null when neither
  /// did. A host jumps on null unless it has a spring of its own.
  Spring? get layoutSpring => MotionTransaction.layout?.spring;

  /// Whether [resolve] runs in every frame's resolve phase while the host
  /// is attached, not only after [scheduleResolve]: for what follows
  /// something that moves without laying the host out, such as a source
  /// under a scroll. It asks for no frames.
  bool get resolvesEveryFrame => false;

  /// Asks for [resolve] in this frame's resolve phase; call it from layout.
  void scheduleResolve() {
    final owner = this.owner;
    if (owner != null) _ResolveOwner.of(owner)._schedule(this);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _ResolveOwner.of(owner)._hosts.add(this);
  }

  @override
  void detach() {
    final owner = this.owner;
    if (owner != null) _ResolveOwner._release(owner, this);
    super.detach();
  }
}

/// The resolve phase of one view: a child of the view's pipeline owner,
/// which Flutter flushes after the view's own phases. It resolves with the
/// view's compositing bits, when the view's layout, its child owners'
/// included, has finished and marking layout is allowed again, and lays
/// out again what the resolve marked.
///
/// It stays adopted while hosts are attached to the view and drops and
/// disposes itself with the last one, so the view's owner has no children
/// when it is disposed, and the semantics owner Flutter made for it once
/// semantics turned on goes with it.
final class _ResolveOwner extends PipelineOwner {
  factory _ResolveOwner.of(PipelineOwner view) {
    final existing = _owners[view];
    if (existing != null) return existing;
    final owner = _ResolveOwner._(view);
    _owners[view] = owner;
    _live++;
    MotionTransaction.onLayoutTransaction = _clearAfterFrame;
    view.adoptChild(owner);
    return owner;
  }

  // It owns no render objects, so it never has semantics to send; Flutter
  // still asks for the callback once semantics turn on.
  _ResolveOwner._(this._view) : super(onSemanticsUpdate: (_) {});

  static final Expando<_ResolveOwner> _owners = Expando<_ResolveOwner>();
  static int _live = 0;

  final PipelineOwner _view;
  final Set<MotionResolveHost> _hosts = {};
  final Set<MotionResolveHost> _scheduled = {};

  static void _release(PipelineOwner view, MotionResolveHost host) {
    final owner = _owners[view];
    if (owner == null) return;
    owner._hosts.remove(host);
    owner._scheduled.remove(host);
    if (owner._hosts.isNotEmpty) return;
    _owners[view] = null;
    view.dropChild(owner);
    owner.dispose();
    if (--_live == 0) MotionTransaction.onLayoutTransaction = null;
  }

  static bool _clearing = false;

  // The transaction belongs to the layout of every view in the frame, and
  // each view resolves on its own after its layout.
  static void _clearAfterFrame() {
    if (_clearing) return;
    _clearing = true;
    final scheduler = SchedulerBinding.instance;
    // After the frame: only its end comes after the last view's layout.
    scheduler.addPostFrameCallback((_) {
      _clearing = false;
      MotionTransaction.clearLayout();
    }, debugLabel: 'MotionTransaction.clearLayout');
    scheduler.scheduleFrame();
  }

  void _schedule(MotionResolveHost host) => _scheduled.add(host);

  // Layouts that keep scheduling each other's resolve finish in the next
  // frame.
  static const _rounds = 8;

  bool _resolving = false;

  @override
  void flushCompositingBits() {
    // The view's flush below calls back into this owner.
    if (_resolving) return;
    _resolving = true;
    try {
      _resolveRounds();
    } finally {
      _resolving = false;
    }
    super.flushCompositingBits();
  }

  void _resolveRounds() {
    for (final host in _hosts) {
      if (host.resolvesEveryFrame) _scheduled.add(host);
    }
    if (_scheduled.isEmpty) return;
    for (var round = 0; _scheduled.isNotEmpty; round++) {
      if (round == _rounds) {
        SchedulerBinding.instance.scheduleFrame();
        break;
      }
      final hosts = List<MotionResolveHost>.of(_scheduled);
      _scheduled.clear();
      hosts.sort((a, b) => a.depth - b.depth);
      MotionClock.resolve([
        for (final host in hosts)
          if (host.attached && identical(host.owner, _view)) host.resolve,
      ], 'while resolving a layout motion');
      _view.flushLayout();
    }
    _view.flushCompositingBits();
  }
}
