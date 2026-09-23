import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/internal/ancestor_clip.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';
import 'package:meta/meta.dart';

/// A retained clip + identity backdrop filter that starts a render pass of
/// exactly the region the glass inside needs, seeded with the backdrop.
///
/// Impeller derives a backdrop pass's coverage from the enclosing clips, so
/// the pixel-snapped clip rect pushed here is what determines the pass origin
/// the glass shaders observe. Recomputing the region from
/// [Layer.updateSubtreeNeedsAddToScene] — parent-first, before descendants'
/// compositor hooks — keeps [captureRect] fresh on frames where the owning
/// render object does not repaint (paint-only changes below a repaint
/// boundary never mark it dirty).
@internal
class CapturePass {
  RenderBox? _owner;
  EdgeInsets? _bleed;

  /// Whether the pass clips and seeds; stored so [syncRegion] can refresh
  /// between paints. Also assigned by [paint].
  bool enabled = false;

  final _clipHandle = LayerHandle<_CaptureClipLayer>();
  Offset _paintOffset = Offset.zero;

  /// The region covered at the last region computation, in owner-local
  /// coordinates. Retains its previous value while the pass is clipped away.
  Rect? get captureRect => _captureRect;
  Rect? _captureRect;

  /// Origin of the pass in owner-local coordinates.
  Offset? get passOrigin => _captureRect?.topLeft;

  /// The [owner]'s layout box grown to cover every glass layer inside — or
  /// [bleed] when given — intersected with the screen clip and snapped
  /// outward to whole device pixels. Returns `null` when the region is
  /// clipped away entirely.
  Rect? computeRegion(RenderBox owner, {EdgeInsets? bleed}) {
    final box = Offset.zero & owner.size;
    final local = switch (bleed) {
      final bleed? => bleed.inflateRect(box),
      null => _glassRegion(owner, box),
    };
    final toGlobal = owner.getTransformTo(null);
    var region = MatrixUtils.transformRect(toGlobal, local);
    // Impeller covers the clip intersected with every enclosing clip and the
    // screen; stay inside them so the origin handed to the glass shaders is
    // the origin the pass actually gets.
    if (screenClipAbove(owner) case final outer?) {
      region = region.intersect(outer);
      if (region.isEmpty) return null;
    }
    // Snap outward to device pixels so the pass origin Impeller derives from
    // the rounded coverage matches ours.
    final dpr = _devicePixelRatioOf(owner);
    final snapped = Rect.fromLTRB(
      (region.left * dpr).floorToDouble() / dpr,
      (region.top * dpr).floorToDouble() / dpr,
      (region.right * dpr).ceilToDouble() / dpr,
      (region.bottom * dpr).ceilToDouble() / dpr,
    );
    return MatrixUtils.transformRect(Matrix4.inverted(toGlobal), snapped);
  }

  /// [box] grown by the `effectBounds` of [owner] itself (when it is a glass
  /// layer) and of every glass layer below it.
  Rect _glassRegion(RenderBox owner, Rect box) {
    var region = box;
    void visit(RenderObject node) {
      if (node is LiquidGlassLayerRenderObject) {
        final bounds = (node as LiquidGlassLayerRenderObject).effectBounds;
        if (bounds != null) {
          region = region.expandToInclude(
            MatrixUtils.transformRect(node.getTransformTo(owner), bounds),
          );
        }
      }
      node.visitChildren(visit);
    }

    visit(owner);
    return region;
  }

  /// Paints [painter] inside the captured pass when [enabled], or directly
  /// (no clip, no backdrop) when disabled. A `null` region under an enabled
  /// pass is treated like a disabled pass; callers that must paint nothing
  /// when clipped away check [computeRegion] themselves first.
  void paint(
    PaintingContext context,
    Offset offset,
    RenderBox owner,
    PaintingContextCallback painter, {
    required bool enabled,
    EdgeInsets? bleed,
  }) {
    _owner = owner;
    _bleed = bleed;
    _paintOffset = offset;
    this.enabled = enabled;
    final clip = _clipHandle.layer ??= (_CaptureClipLayer().._pass = this);
    _apply(clip, enabled ? computeRegion(owner, bleed: bleed) : null);
    // The pass layer is always in the tree; whether it clips and seeds is
    // decided when the scene is built, so enabling it needs no repaint.
    context.pushLayer(clip, painter, offset);
  }

  void _apply(_CaptureClipLayer clip, Rect? region) {
    if (region != null) _captureRect = region;
    clip
      ..enabled = region != null
      ..rect = region?.shift(_paintOffset);
  }

  /// Recomputes the region while retained-rendering dirtiness is propagated,
  /// before any descendant layer's compositor hooks run. Called from the
  /// retained clip layer; callers that own a compositor hook may also call it
  /// directly to refresh [captureRect] mid-frame. Safe to call when nothing
  /// has changed.
  void syncRegion() {
    final owner = _owner;
    final clip = _clipHandle.layer;
    if (owner == null || !owner.attached || clip == null) return;
    _apply(clip, enabled ? computeRegion(owner, bleed: _bleed) : null);
  }

  /// Releases the retained layers.
  void dispose() {
    _clipHandle.layer = null;
  }

  static double _devicePixelRatioOf(RenderObject node) {
    for (
      var ancestor = node.parent;
      ancestor != null;
      ancestor = ancestor.parent
    ) {
      if (ancestor is RenderView) {
        return ancestor.configuration.devicePixelRatio;
      }
    }
    return 1;
  }
}

/// Clip plus identity backdrop filter that starts the seeded pass. When
/// disabled, or while its region is clipped away, its children composite
/// directly, so turning the pass on and off never changes the layer tree.
class _CaptureClipLayer extends ContainerLayer {
  static const _identity = ColorFilter.matrix(<double>[
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  CapturePass? _pass;

  /// Re-adding every frame lets [CapturePass.syncRegion] change the rect or
  /// the enabled state during compositing without marking anything dirty.
  bool enabled = false;
  Rect? rect;

  ui.BackdropFilterEngineLayer? _backdropEngineLayer;

  @override
  bool get alwaysNeedsAddToScene => true;

  @override
  void updateSubtreeNeedsAddToScene() {
    // Parents run before children, so refreshing here gives descendant glass
    // layers' onCompositing hooks the current pass origin in the same frame.
    _pass?.syncRegion();
    super.updateSubtreeNeedsAddToScene();
  }

  @override
  void addToScene(ui.SceneBuilder builder) {
    final rect = this.rect;
    if (!enabled || rect == null) {
      engineLayer = null;
      _backdropEngineLayer = null;
      addChildrenToScene(builder);
      return;
    }
    final oldClip = engineLayer;
    engineLayer = builder.pushClipRect(
      rect,
      clipBehavior: ui.Clip.hardEdge,
      oldLayer: oldClip is ui.ClipRectEngineLayer ? oldClip : null,
    );
    _backdropEngineLayer = builder.pushBackdropFilter(
      _identity,
      oldLayer: _backdropEngineLayer,
    );
    addChildrenToScene(builder);
    builder
      ..pop()
      ..pop();
  }
}
