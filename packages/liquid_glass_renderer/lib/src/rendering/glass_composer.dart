import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:liquid_glass_renderer/composer.dart';
import 'package:liquid_glass_renderer/src/rendering/backdrop_filter_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/follower_transform.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_form.dart';
import 'package:liquid_glass_renderer/src/rendering/read.dart';
import 'package:liquid_glass_renderer/src/rendering/transform_tracking_render_object_mixin.dart';

/// The glass of one view, seen once a frame between paint and compositing.
///
/// A child [PipelineOwner] of the view's owner. Flutter flushes a child
/// owner after the parent's own nodes, phase by phase, and paints every view
/// before the first scene is built, so [flushCompositingBits] runs after
/// layout and before paint, and [flushPaint] after paint and before any
/// scene. Layer mutations made there are propagated by the update pass that
/// follows.
///
/// Before paint it polls where each site is on the screen, so glass that
/// moved past what its retained layers can follow repaints in this frame,
/// and asks each site with a repaint boundary marked under it whether it
/// would paint late ([TransformTrackingRenderObjectMixin.paintsLate]), and
/// marks it to paint in this frame if so. After paint it lowers the view's
/// layers into a [GlassForm], asks every site for its facts, compiles the
/// frame's [GlassPlan] and draws it, before any scene is built. Then it submits
/// the frame's flutter_gpu passes.
///
/// What cannot be known before paint stays a frame late: a shape under a
/// [RenderFollowerLayer] whose leader moved this frame, as the leader's
/// offset exists only after paint. Such a mark is counted apart, in
/// [GlassWork.lateMarks].
///
/// One composer per view owner, adopted by the first render object holding
/// a composed layer that attaches there, a site ([track]) or a host ([host]),
/// and dropped and disposed when the last one detaches, so a view owner that
/// is disposed never holds one.
@internal
final class GlassComposer extends PipelineOwner {
  GlassComposer._(this._view) : super(onSemanticsUpdate: _noSemantics);

  factory GlassComposer._adopt(PipelineOwner owner) {
    if (_of(owner) case final composer?) return composer;
    final composer = GlassComposer._(owner);
    owner.adoptChild(composer);
    return composer;
  }

  // The view's owner, which adopted this composer and holds its sites.
  final PipelineOwner _view;

  // Counts the passes that ask sites before paint; a site holds the pass
  // that last asked it.
  int _pass = 0;

  // A composer owns no render object; with semantics enabled it still gets
  // a semantics owner, which never has anything to send.
  static void _noSemantics(SemanticsUpdate update) => update.dispose();

  /// Starts following [site] on the composer of [owner], adopting one under
  /// [owner] if it has none. Call from a render object's `attach`.
  static void track(
    PipelineOwner owner,
    TransformTrackingRenderObjectMixin site,
  ) {
    GlassComposer._adopt(owner)._sites.add(site);
  }

  /// Stops following [site]. The last site or host to leave drops the
  /// composer. Call from a render object's `detach`, before `super.detach`.
  static void untrack(
    PipelineOwner owner,
    TransformTrackingRenderObjectMixin site,
  ) {
    final composer = _of(owner);
    if (composer == null || !composer._sites.remove(site)) return;
    composer._dropIfEmpty(owner);
  }

  /// Plans the scenes of [owner]'s view for [holder], a render object that
  /// holds a composed layer without being a site, adopting a composer under
  /// [owner] if it has none. Call from a render object's `attach`.
  static void host(PipelineOwner owner, LiquidGlassBackdropFilterHost holder) {
    GlassComposer._adopt(owner)._hosts.add(holder);
  }

  /// Stops planning for [holder]. The last site or host to leave drops the
  /// composer. Call from a render object's `detach`, before `super.detach`.
  static void unhost(
    PipelineOwner owner,
    LiquidGlassBackdropFilterHost holder,
  ) {
    final composer = _of(owner);
    if (composer == null || !composer._hosts.remove(holder)) return;
    composer._dropIfEmpty(owner);
  }

  void _dropIfEmpty(PipelineOwner owner) {
    if (_sites.isNotEmpty || _hosts.isNotEmpty) return;
    owner.dropChild(this);
    dispose();
  }

  static GlassComposer? _of(PipelineOwner owner) {
    GlassComposer? found;
    owner.visitChildren((child) {
      if (child is GlassComposer) found = child;
    });
    return found;
  }

  /// The composers under [root] and its descendant owners, for benches and
  /// tests.
  @visibleForTesting
  static List<GlassComposer> debugAllUnder(PipelineOwner root) {
    final all = <GlassComposer>[];
    void visit(PipelineOwner owner) {
      if (owner is GlassComposer) all.add(owner);
      owner.visitChildren(visit);
    }

    visit(root);
    return all;
  }

  /// Marks [node] to paint again from a decision made between paint and the
  /// scene. While its view's composer composes, the frame's paint is over
  /// and the node paints in the next frame, as a mark made while the scene
  /// is built would.
  static void repaint(RenderObject node) {
    if (!kReleaseMode) GlassWork.marks++;
    final owner = node.owner;
    if (owner == null || !(_of(owner)?._composing ?? false)) {
      node.markNeedsPaint();
      return;
    }
    if (!kReleaseMode) GlassWork.lateMarks++;
    // After the frame: paint is over, so the mark is the next frame's.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (node.attached) node.markNeedsPaint();
    });
  }

  final Set<TransformTrackingRenderObjectMixin> _sites = Set.identity();

  final Set<LiquidGlassBackdropFilterHost> _hosts = Set.identity();

  final _composition = _Composition();

  bool _composing = false;

  // Whether glass painted since the last plan: it paints a slot the plan fills.
  bool _painted = true;

  /// Notes that a site of [owner]'s composer painted this frame.
  static void sitePainted(PipelineOwner owner) {
    _of(owner)?._painted = true;
  }

  // The frame this composer planned the scene of.
  Duration? _planned;

  /// What this composer saw since it was adopted.
  @visibleForTesting
  final ComposerCensus census = ComposerCensus();

  @override
  void flushCompositingBits() {
    super.flushCompositingBits();
    for (final site in _sites) {
      if (site.repaintsOnMove) site.layer?.pollTransform();
    }
    _askOverDirtyBoundaries();
  }

  // Asks the nearest site above each boundary the view is about to paint
  // whether it would paint late. A layout may run this again in the frame
  // (a resolve phase), which asks again.
  void _askOverDirtyBoundaries() {
    final dirty = _view.nodesNeedingPaint;
    if (dirty.isEmpty || _sites.isEmpty) return;
    final pass = ++_pass;
    var shallowest = -1;
    for (final site in _sites) {
      if (shallowest < 0 || site.depth < shallowest) shallowest = site.depth;
    }
    var marks = false;
    for (final node in dirty) {
      for (
        var parent = node.parent;
        parent != null && parent.depth >= shallowest;
        parent = parent.parent
      ) {
        if (parent is! TransformTrackingRenderObjectMixin) continue;
        if (parent.composerAsked != pass) {
          parent.composerAsked = pass;
          if (parent.paintsLate()) {
            parent.composerMarks = pass;
            marks = true;
          }
        }
        break;
      }
    }
    // Marking adds to the list walked above.
    if (!marks) return;
    for (final site in _sites) {
      if (site.composerMarks == pass) repaint(site);
    }
  }

  @override
  void flushPaint() {
    super.flushPaint();
    census.frames++;
    census.sites += _sites.length;
    final root = _root();
    if (root == null) return;
    _composing = true;
    try {
      // A site's poll may paint it again while the plan's facts are filled.
      _composition.run(root, painted: () => _painted);
      _painted = false;
      _planned = SchedulerBinding.instance.currentFrameTimeStamp;
    } finally {
      _composing = false;
    }
  }

  @override
  void dispose() {
    _composition.dispose();
    super.dispose();
  }

  /// Handed each frame's plan, with its reasons, while set.
  @visibleForTesting
  static void Function(GlassForm form, GlassPlan plan)? debugOnPlan;

  /// Sites that rested since this was last cleared.
  @internal
  static int debugRests = 0;

  ContainerLayer? _root() {
    for (final site in _sites) {
      if (_rootOf(site.layer) case final root?) return root;
    }
    for (final host in _hosts) {
      if (_rootOf(host.composedLayer) case final root?) return root;
    }
    return null;
  }

  static ContainerLayer? _rootOf(Layer? layer) =>
      layer == null || !layer.attached ? null : _topOf(layer);

  static bool _plannedAhead(Layer layer) {
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      return false;
    }
    final view = layer.owner;
    if (view is! RenderView) return false;
    final owner = view.owner;
    if (owner == null) return false;
    final composer = _of(owner);
    return composer != null &&
        composer._planned == SchedulerBinding.instance.currentFrameTimeStamp;
  }

  // The roots a scene no composer planned was composed for, until the scene's
  // update pass is over: every composed layer of the scene asks.
  static final _composedRoots = Set<ContainerLayer>.identity();

  /// Scenes composed alone since this was last cleared.
  @visibleForTesting
  static int debugComposedAlone = 0;

  // A scene the view's composer did not plan: an image of a subtree taken
  // outside a frame, which plans once from nothing held. What it draws stands
  // until the next plan.
  static void _composeAlone(Layer layer) {
    final root = _topOf(layer);
    if (!_composedRoots.add(root)) return;
    if (_composedRoots.length == 1) {
      scheduleMicrotask(_composedRoots.clear);
    }
    assert(
      !_inFrameUnregistered(root),
      '$layer is composited in a frame, but no render object of its view is '
      "registered with the view's GlassComposer, so nothing planned the "
      'scene ahead. A render object that holds a '
      'LiquidGlassBackdropFilterLayer mixes in LiquidGlassBackdropFilterHost '
      'and returns the layer from composedLayer.',
    );
    if (!kReleaseMode) debugComposedAlone++;
    final composition = _Composition();
    try {
      composition.run(root);
    } finally {
      composition.dispose();
    }
  }

  static ContainerLayer _topOf(Layer layer) {
    var top = layer;
    while (top.parent != null) {
      top = top.parent!;
    }
    return top as ContainerLayer;
  }

  static bool _inFrameUnregistered(ContainerLayer root) =>
      SchedulerBinding.instance.schedulerPhase ==
          SchedulerPhase.persistentCallbacks &&
      switch (root.owner) {
        RenderView(:final owner?) => _of(owner) == null,
        _ => false,
      };
}

// One view's frame: the form of its layers, what the plan keeps between frames
// and what its reads hold.
final class _Composition {
  final _form = GlassForm();
  final _ledger = PlanLedger();
  final _emit = GlassEmit();

  // The last plan and what it was compiled under.
  ({
    GlassPlan plan,
    PlanPolicy policy,
    PlanPrices prices,
    Rect screen,
    bool explained,
  })?
  _last;

  // Whether the last plan stands: nothing asked anew or changed and no read is
  // due an image. A paint empties the slots it fills, so it is shown again;
  // nothing it decided changes.
  bool _stands(PlanPolicy policy, PlanPrices prices, bool explain) {
    final form = _form;
    return switch (_last) {
      final last? =>
        form.sitesHeld &&
            !form.asksChanged &&
            form.dirty.isEmpty &&
            form.frame < last.plan.dueAt &&
            identical(policy, last.policy) &&
            identical(prices, last.prices) &&
            explain == last.explained &&
            form.screen == last.screen,
      null => false,
    };
  }

  void run(ContainerLayer root, {bool Function()? painted}) {
    final view = root.owner;
    if (view is! RenderView) return;
    final flutterView = view.flutterView;
    final dpr = flutterView.devicePixelRatio;
    final listening = GlassFrameReport.listening;
    final clock = Stopwatch();
    if (listening) clock.start();
    FrameAncestors.current = FrameAncestors();
    try {
      final form = _form..lower(root, dpr, flutterView.physicalSize);
      for (final node in form.siteNodes) {
        form.noteAsk(node.facts, node.site.ask());
      }
      form
        ..noteSitesGone()
        ..settleFloors();
      final walk = clock.elapsed;
      final policy = GlassCopies.enabled
          ? debugGlassPolicy
          : const PlanPolicy(copies: false);
      final prices = debugGlassPrices;
      final explain = listening || GlassComposer.debugOnPlan != null;
      // Without a word of what painted, every frame plans.
      final stands = painted != null && _stands(policy, prices, explain);
      final shows = painted == null || !stands || painted();
      if (!stands) {
        final (plan, edits) = compilePlan(
          form,
          _ledger,
          prices,
          policy,
          form.frame,
          explain: explain,
        );
        GlassComposer.debugOnPlan?.call(form, plan);
        edits.applyTo(_ledger, form.frame);
        _last = (
          plan: plan,
          policy: policy,
          prices: prices,
          screen: form.screen,
          explained: explain,
        );
      }
      final planned = clock.elapsed;
      if (shows) _emit.emit(_last!.plan, form, again: stands);
      for (final node in form.siteNodes) {
        node.site.endFrame();
      }
      if (listening) {
        _report(
          form,
          _last!.plan,
          policy,
          walk,
          planned,
          clock.elapsed,
          stands,
        );
      }
    } finally {
      FrameAncestors.current = null;
      // The atlases of a frame that emits nothing.
      FlutterGpuGeometryRenderer.flush();
    }
  }

  void _report(
    GlassForm form,
    GlassPlan plan,
    PlanPolicy policy,
    Duration walk,
    Duration planned,
    Duration done,
    bool stands,
  ) {
    final frame = form.frame;
    final reads = [
      for (final read in plan.reads)
        GlassFrameReport.readOf(read, stands: stands),
    ];
    GlassFrameReport.deliver(
      () => GlassFrameReport(
        frame: frame,
        planned: !stands,
        reads: reads,
        targetBudget: policy.maxTargets,
        issuedTargets: plan.issuedTargets,
        walk: walk,
        compile: planned - walk,
        emit: done - planned,
        filtersBuilt: GlassWork.filters,
        picturesRecorded: GlassWork.pictures,
        imagesDrawn: GlassWork.images,
        layersReplayed: GlassWork.replayed,
        repaintsAsked: GlassWork.marks,
        lateRepaints: GlassWork.lateMarks,
        notes: plan.notes,
      ),
    );
  }

  void dispose() => _emit.dispose();
}

/// A layer whose decisions for a frame are the frame's plan's.
///
/// A scene the view's [GlassComposer] did not plan, an image of a subtree
/// taken outside a frame, plans in the update pass that builds the scene. In
/// a frame the composer plans ahead for the render object that holds the
/// layer, registered as a site or a [LiquidGlassBackdropFilterHost].
@internal
mixin ComposedLayer on ContainerLayer {
  /// Whether the view's composer planned the scene being built.
  @protected
  bool get composedAhead => GlassComposer._plannedAhead(this);

  @override
  void updateSubtreeNeedsAddToScene() {
    if (!composedAhead) GlassComposer._composeAlone(this);
    super.updateSubtreeNeedsAddToScene();
  }
}

/// Counts of a [GlassComposer]'s frames.
@internal
final class ComposerCensus {
  /// Frames painted while the composer had a site or a host.
  int frames = 0;

  /// Sites summed over [frames].
  int sites = 0;
}

/// What the frame's plan pays for what it weighs. A test or a bench sets it
/// and puts it back.
PlanPrices debugGlassPrices = const PlanPrices();

/// The decisions the frame's plan keeps to; a bench swaps it for a window. A
/// test or a bench sets it and puts it back.
PlanPolicy debugGlassPolicy = const PlanPolicy();
