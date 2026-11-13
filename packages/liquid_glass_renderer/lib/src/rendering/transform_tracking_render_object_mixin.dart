import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/composer.dart';
import 'package:liquid_glass_renderer/src/rendering/follower_transform.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_composer.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_form.dart';
import 'package:liquid_glass_renderer/src/rendering/read.dart';
import 'package:liquid_glass_renderer/src/rendering/scene_out.dart';
import 'package:meta/meta.dart';

@internal
mixin TransformTrackingRenderObjectMixin on RenderProxyBox {
  @override
  GeometryTransformTrackingLayer? get layer =>
      super.layer as GeometryTransformTrackingLayer?;

  @override
  @nonVirtual
  bool get isRepaintBoundary => false;

  @override
  bool get alwaysNeedsCompositing => true;

  @mustCallSuper
  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    GlassComposer.track(owner, this);
  }

  @mustCallSuper
  @override
  void detach() {
    GlassComposer.untrack(owner!, this);
    super.detach();
  }

  /// This object's transform to the screen. While its layer composites, the
  /// transform the layer read for this frame, without another walk to the
  /// root: nothing moves a render object between paint and the scene.
  Matrix4 transformToScreen() =>
      layer?._composited?.clone() ?? transformToNow(this);

  @mustCallSuper
  @override
  void paint(PaintingContext context, ui.Offset offset) {
    GlassComposer.sitePainted(owner!);
    final tracking = (layer ??= GeometryTransformTrackingLayer())
      .._site = this
      .._paintOffset = offset;
    context.pushLayer(tracking, (context, offset) {}, offset);
    super.paint(context, offset);
  }

  /// The transform to the screen changed. Runs before paint when the view's
  /// composer polls, where a repaint lands in the same frame, and otherwise
  /// while the layer composites (see [GlassComposer.repaint]).
  void onTransformChanged();

  /// What this site asks of the frame (see [PlanSite.ask]).
  SiteAsk ask() => SiteAsk.none;

  /// Whether [onTransformChanged] would repaint, so that it must run before
  /// paint for the repaint to land in the same frame.
  bool get repaintsOnMove => false;

  /// Whether, as things stand before paint, this glass would find after
  /// paint that what it retained no longer matches its shapes and could not
  /// take them in place, so that it would paint a frame late.
  ///
  /// The view's [GlassComposer] asks it before paint, at most once a pass,
  /// of a site with a repaint boundary marked under it, and marks the site
  /// on yes. It records nothing and may be asked more than once a frame.
  bool paintsLate() => false;

  /// The composer pass that last asked [paintsLate].
  int composerAsked = 0;

  /// The composer pass whose [paintsLate] said yes.
  int composerMarks = 0;

  /// Runs every frame, before the frame's plan, including frames where the
  /// tracked transform is unchanged: where the glass polls its retained motion.
  /// Repaints from here go through [GlassComposer.repaint].
  void onPreparing() {}

  /// Whether this frame may run [onResting] in place of [onPreparing] when
  /// nothing changed around the object.
  bool get mayRest => true;

  /// Runs in place of [onPreparing] on a frame that changed nothing around the
  /// object: its layers, and so where its glass lies, are as they were.
  void onResting() => onPreparing();

  /// This frame's [fate], in paint order, before any read of the frame is
  /// drawn (see [PlanSite.beginFate]).
  void beginFate(SiteFate fate) {}

  /// See [PlanSite.show].
  void show(GlassRead read, ReadPixels pixels) {}

  /// See [PlanSite.addOutput].
  void addOutput(SceneOut out, ReadCopy outer) {}
}

@internal
class GeometryTransformTrackingLayer extends OffsetLayer
    with ComposedLayer
    implements PlanSite {
  // The render object whose transform the layer tracks.
  TransformTrackingRenderObjectMixin? _site;
  Matrix4? _lastTransform;
  Matrix4? _composited;
  // Where the render object paints in the coordinates of this layer.
  Offset _paintOffset = Offset.zero;

  @override
  SiteNode? formNode;

  /// The render object whose transform the layer tracks.
  @visibleForTesting
  TransformTrackingRenderObjectMixin? get trackedSite => _site;

  bool get _live {
    final site = _site;
    return site != null && site.attached;
  }

  @override
  SiteAsk ask() {
    final site = _site;
    if (site == null || !site.attached) return SiteAsk.none;
    final last = _lastTransform;
    final node = formNode;
    if (last != null && site.mayRest && (node?.rests ?? false)) {
      assert(
        _near(transformToNow(site), last),
        'A site moved with no layer around it changing.',
      );
      GlassComposer.debugRests++;
      _composited = last;
      site.onResting();
    } else {
      final fromForm = node?.screenTransform(_paintOffset);
      assert(
        fromForm == null ||
            transformToNowOrLast(site).last ||
            _near(transformToNow(site), fromForm),
        'The form says the site lies elsewhere than its render objects do.',
      );
      final now = fromForm ?? transformToNow(site);
      _composited = now;
      if (!MatrixUtils.matrixEquals(now, last)) {
        site.onTransformChanged();
        _lastTransform = now;
      }
      site.onPreparing();
    }
    return site.ask();
  }

  static bool _near(Matrix4 a, Matrix4 b) {
    final x = a.storage;
    final y = b.storage;
    for (var i = 0; i < 16; i++) {
      if ((x[i] - y[i]).abs() > 1e-3) return false;
    }
    return true;
  }

  /// Reads the tracked object's transform before paint and reports a
  /// change, so that a repaint it asks for lands in the same frame.
  void pollTransform() {
    final site = _site;
    if (!attached || site == null || !site.attached) return;
    final now = transformToNow(site);
    final last = _lastTransform;
    if (last != null && _near(now, last)) return;
    _composited = now;
    site.onTransformChanged();
    _lastTransform = now;
    _composited = null;
  }

  @override
  void beginFate(SiteFate fate) {
    if (_live) _site!.beginFate(fate);
  }

  @override
  void show(GlassRead read, ReadPixels pixels) {
    if (_live) _site!.show(read, pixels);
  }

  @override
  void addOutput(SceneOut out, ReadCopy outer) {
    if (_live) _site!.addOutput(out, outer);
  }

  // The slot it is shown in holds what it draws; the tracking layer holds only
  // where it lies.
  @override
  bool get drawsOwnChildren => false;

  @override
  bool get outputsInPlace => false;

  @override
  void endFrame() => _composited = null;

  // It draws nothing: where it lies is all the site reads.
  @override
  void addToScene(ui.SceneBuilder builder) {
    if (firstChild != null) super.addToScene(builder);
  }
}
