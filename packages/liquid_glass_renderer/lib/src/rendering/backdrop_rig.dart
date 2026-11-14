import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/composer.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_frost.dart';
import 'package:liquid_glass_renderer/src/rendering/follower_transform.dart';
import 'package:liquid_glass_renderer/src/rendering/read.dart';

/// The shift from [anchor]'s coordinates to the screen's, in logical pixels,
/// or null when a transform above it scales or turns it.
@internal
Offset? screenOffsetOf(Layer anchor, double devicePixelRatio) {
  final m = _toScreen(anchor, devicePixelRatio).storage;
  if ((m[0] - 1).abs() > 1e-6 ||
      (m[5] - 1).abs() > 1e-6 ||
      m[1].abs() > 1e-6 ||
      m[4].abs() > 1e-6) {
    return null;
  }
  return Offset(m[12], m[13]);
}

Matrix4 _toScreen(Layer anchor, double devicePixelRatio) {
  final toScreen = Matrix4.diagonal3Values(
    1 / devicePixelRatio,
    1 / devicePixelRatio,
    1,
  );
  final chain = <Layer>[];
  for (Layer? node = anchor; node != null; node = node.parent) {
    chain.add(node);
  }
  for (var i = chain.length - 1; i > 0; i--) {
    applyTransformNow(chain[i] as ContainerLayer, chain[i - 1], toScreen);
  }
  return toScreen;
}

/// How a surface reads its backdrop: live, as a backdrop filter in a clip, or
/// over a copy of what lies under it, as the frame's plan says.
///
/// The clip is the surface's outline, or a rect, and the rig keeps its
/// layers from frame to frame.
@internal
class BackdropRig {
  /// Creates a rig whose live reads share the backdrop of [key], if any.
  BackdropRig({this.key});

  /// The backdrop this rig reads live, shared with every other rig of the key,
  /// when the frame's plan gives it no other.
  final BackdropKey? key;

  final _filter = LayerHandle<BackdropFilterLayer>();
  final _clipPath = LayerHandle<ClipPathLayer>();
  final _clipRect = LayerHandle<ClipRectLayer>();

  final _slot = LayerHandle<GlassSlotLayer>();
  final _read = LayerHandle<ReadLayer>();
  final _page = LayerHandle<PictureLayer>();
  Object? _pageKey;

  // What the last [paint] read, for a copy to stand in for. Null when the
  // rig takes no copies.
  _Asked? _asked;
  ui.FragmentShader? _frostShader;

  Path? _outline;

  /// The filter layer the rig reads the backdrop with.
  BackdropFilterLayer? get filterLayer => _filter.layer;

  /// Whether the rig has painted its clip.
  bool get hasClip => _clipRect.layer != null || _clipPath.layer != null;

  /// Whether the last paint left room for a picture over a copy (see
  /// [paintSite]).
  bool get hasSlot => _slot.layer != null;

  /// Paints the live read with [live]. With a [site], it paints in a slot the
  /// site's fate can fill with a read of a copy instead.
  void paintSite(
    PaintingContext context,
    Offset offset, {
    required PlanSite? site,
    required PaintingContextCallback live,
  }) {
    if (site != null) {
      final slot = (_slot.layer ??= GlassSlotLayer())..site = site;
      context.pushLayer(slot, live, offset);
      return;
    }
    _slot.layer = null;
    live(context, offset);
  }

  /// The layer a read of the scene shows in.
  ReadLayer get readLayer => _read.layer ??= ReadLayer();

  /// The picture [record] draws, kept while [key] stays equal.
  PictureLayer pagePicture(
    Object key,
    Rect bounds,
    ui.Picture Function() record,
  ) {
    final previous = _page.layer;
    if (previous != null && _pageKey == key) return previous;
    final picture = PictureLayer(bounds)..picture = record();
    _page.layer = picture;
    _pageKey = key;
    return picture;
  }

  // Its picture holds the image it reads, an atlas other glass may have left.
  void _dropPage() {
    _page.layer = null;
    _pageKey = null;
  }

  /// The picture [pagePicture] last drew.
  ui.Picture? get pageShown => _page.layer?.picture;

  /// Shows the live read, taken from the backdrop of [group] where the frame's
  /// plan shares one between reads.
  void showLive(BackdropKey? group) {
    _filter.layer?.backdropKey = group ?? key;
    show(null);
  }

  /// Leaves no slot until the next [paintSite].
  void releaseSlot() {
    _slot.layer = null;
  }

  /// Fills the slot with [served] over [under], or with the live read
  /// without [served].
  void show(Layer? served, {Layer? under}) {
    assert(under == null || served != null, 'Only a copy covers [under].');
    if (!identical(served, _page.layer)) _dropPage();
    final slot = _slot.layer;
    if (slot == null) return;
    final child = served ?? _clipRect.layer ?? _clipPath.layer;
    if (child == null) {
      slot.removeAllChildren();
      return;
    }
    final first = under ?? child;
    if (identical(slot.firstChild, first) &&
        identical(first.nextSibling, under == null ? null : child) &&
        child.nextSibling == null) {
      return;
    }
    slot.removeAllChildren();
    if (under != null) {
      under.remove();
      slot.append(under);
    }
    child.remove();
    slot.append(child);
  }

  /// Leaves the slot empty: another layer draws this glass.
  void hide() {
    _dropPage();
    final slot = _slot.layer;
    if (slot?.firstChild != null) slot!.removeAllChildren();
  }

  /// Hands [filter] to the filter layer.
  void bindFilter(ui.ImageFilter filter) {
    (_filter.layer ??= _newFilterLayer())
      ..filter = filter
      ..backdropKey ??= key;
  }

  // A filter made after the clip was painted goes into the clip: a retained
  // refresh does not paint.
  BackdropFilterLayer _newFilterLayer() {
    final backdrop = BackdropFilterLayer();
    (_clipRect.layer ?? _clipPath.layer)?.append(backdrop);
    return backdrop;
  }

  /// Takes the filter layer out of the tree.
  void releaseFilter() {
    _filter.layer?.remove();
    _filter.layer = null;
  }

  /// Paints the clip [outline] (or the rect [bounds] without one) and the
  /// filter in it, [offset] from [context]'s layer. Without [drawsFilter] the
  /// clip is empty.
  void paintLive(
    PaintingContext context,
    Offset offset, {
    required Rect bounds,
    Path? outline,
    bool drawsFilter = true,
  }) {
    void paintFilter(PaintingContext clipContext, Offset clipOffset) {
      final backdrop = _filter.layer;
      if (!drawsFilter || backdrop == null) return;
      clipContext.pushLayer(backdrop, (_, _) {}, clipOffset);
    }

    if (outline == null) {
      _clipPath.layer = null;
      _clipRect.layer = context.pushClipRect(
        true,
        offset,
        bounds,
        paintFilter,
        oldLayer: _clipRect.layer,
      );
    } else {
      _clipRect.layer = null;
      final layer = context.pushClipPath(
        true,
        offset,
        bounds,
        outline,
        paintFilter,
        oldLayer: _clipPath.layer,
      );
      _clipPath.layer = layer;
      _outline = layer?.clipPath;
    }
  }

  /// Paints [filter] over the backdrop inside [outline], whose bounds are
  /// [bounds], reading [reach] past them. With a [site], its fate can draw the
  /// filter over a copy of what lies under [outline] instead: where [frost]
  /// stands for [filter], an unblurred copy frosted by a shader.
  void paint(
    PaintingContext context,
    Offset offset, {
    required ui.ImageFilter filter,
    required Rect bounds,
    required Path outline,
    required double reach,
    required double devicePixelRatio,
    PlanSite? site,
    LiquidGlassBackdropFrost? frost,
  }) {
    bindFilter(filter);
    _asked = site != null
        ? (
            filter: filter,
            frost: frost,
            clip: bounds.shift(offset),
            reach: reach,
            devicePixelRatio: devicePixelRatio,
          )
        : null;
    paintSite(
      context,
      offset,
      site: site,
      live: (liveContext, liveOffset) =>
          paintLive(liveContext, liveOffset, bounds: bounds, outline: outline),
    );
  }

  /// What the frame's plan reads of the filter this rig last painted, which
  /// reads an image whenever it reads a copy: the live filter reads the whole
  /// backdrop, not the backdrop cut at the clip, so a filtered copy is
  /// filtered over all it holds.
  SiteAsk ask() {
    final asked = _asked;
    final anchor = _slot.layer;
    _frosts = false;
    if (anchor == null || asked == null || _outline == null) {
      return SiteAsk.none;
    }
    final origin = screenOffsetOf(anchor, asked.devicePixelRatio);
    _origin = origin;
    if (origin == null) {
      final drawn = MatrixUtils.transformRect(
        _toScreen(anchor, asked.devicePixelRatio),
        asked.clip,
      );
      return SiteAsk(
        drawn: drawn,
        reads: drawn.inflate(asked.reach),
        noJoin: NoJoin.noMatte,
        turned: true,
      );
    }
    final shifted = asked.clip.shift(origin);
    final dpr = asked.devicePixelRatio;
    if (asked.frost case final frost?) {
      if (frostNeed(frost.sigma, devicePixelRatio: dpr) case final need?) {
        _frosts = true;
        return SiteAsk(
          drawn: shifted,
          reads: shifted.inflate(need.reach),
          look: FilterLook(key: null, need: need, page: PageFilter.none),
          noJoin: NoJoin.noMatte,
        );
      }
    }
    final region = shifted.inflate(asked.reach);
    return SiteAsk(
      drawn: shifted,
      reads: region,
      look: FilterLook(
        key: null,
        need: CopyNeed(dpr),
        page: PageFilter(filter: asked.filter, clip: region),
      ),
      noJoin: NoJoin.noMatte,
    );
  }

  // Where the last [ask] found the clip's coordinates on the screen,
  // and whether a shader frosts the copy there.
  Offset? _origin;
  bool _frosts = false;

  /// Fills the slot with the filter drawn over [page].
  void showPage(PageCopy page) {
    final asked = _asked!;
    final outline = _outline!;
    final origin = _origin!;
    final frost = _frosts ? asked.frost : null;
    final shown = asked.clip.shift(origin).intersect(page.rect);
    show(
      pagePicture(
        (page.image, page.placement, shown, origin, outline, frost),
        asked.clip,
        () => switch (frost) {
          final frost? => recordFrostedCopy(
            page,
            shown,
            origin,
            frost: frost,
            shader: _frostShader ??= newFrostShader(),
            outline: outline,
          ),
          null => recordFilteredCopy(page, shown, origin, outline: outline),
        },
      ),
    );
  }

  /// Sets the clip rect the rig has in place of an outline.
  void clipTo(Rect bounds) {
    final clip = _clipRect.layer;
    if (clip != null && clip.clipRect != bounds) clip.clipRect = bounds;
  }

  /// Releases every layer but the picture over the copy.
  void clear() {
    _asked = null;
    _slot.layer = null;
    _filter.layer = null;
    _clipPath.layer = null;
    _clipRect.layer = null;
    _outline = null;
  }

  /// Releases every layer.
  void dispose() {
    clear();
    _page.layer = null;
    _read.layer = null;
    _frostShader?.dispose();
    _frostShader = null;
  }
}

// A read a copy can stand in for; the clip is in the slot's coordinates.
typedef _Asked = ({
  ui.ImageFilter filter,
  LiquidGlassBackdropFrost? frost,
  Rect clip,
  double reach,
  double devicePixelRatio,
});
