import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/painting/impeller_blur.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_backdrop_filter.dart';
import 'package:liquid_glass_renderer/src/painting/screen_place.dart';
import 'package:liquid_glass_renderer/src/painting/view_pixels.dart';
import 'package:liquid_glass_renderer/src/plan/band_look.dart';
import 'package:liquid_glass_renderer/src/plan/plan_scenery.dart';
import 'package:liquid_glass_renderer/src/plan/plan_site.dart';
import 'package:liquid_glass_renderer/src/plan/read_layout.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_frost.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_read.dart';
import 'package:liquid_glass_renderer/src/rendering/follower_transform.dart';
import 'package:liquid_glass_renderer/src/rendering/read.dart';

part 'package:liquid_glass_renderer/src/rendering/fake_backdrop_rig.dart';

/// How [anchor]'s coordinates lie on the screen, in logical pixels.
@internal
ScreenPlace screenPlaceOf(Layer anchor, double devicePixelRatio) =>
    ScreenPlace.of(_toScreen(anchor, devicePixelRatio));

/// The ask of a backdrop filter drawn in [clip] with [blendMode], in the
/// coordinates of a layer at [place] on the screen, which [toScreen] maps
/// where the place is not [Shifted]: [filter] blurs by [sigma] logical
/// pixels, or by [frost]'s, which a shader may draw over a copy instead.
///
/// A filter [inScene] is a layer of the scene: a copy can replay it, and its
/// frosted reads join only each other's. Otherwise a frosted read comes from
/// an image. [band], given what the filter shows and the place's offset,
/// makes a filter that draws over its backdrop a band the glass over it can
/// draw.
@internal
SiteAsk backdropFilterAsk({
  required Rect clip,
  required ScreenPlace place,
  required Matrix4 Function() toScreen,
  required ui.ImageFilter filter,
  required double devicePixelRatio,
  required BlendMode blendMode,
  double sigma = 0,
  LiquidGlassBackdropFrost? frost,
  bool inScene = false,
  BandLook? Function(Rect shown, Offset origin)? band,
  Object? paints,
}) {
  final dpr = devicePixelRatio;
  final reach = ImpellerBlur.reach(frost?.sigma ?? sigma, dpr);
  if (place is! Shifted) {
    final drawn = MatrixUtils.transformRect(toScreen(), clip);
    return SiteAsk(
      drawn: drawn,
      reads: drawn.inflate(reach),
      noJoin: NoJoin.noGeometry,
      groupsBackdrop: false,
      place: const Turned(),
      paints: paints,
    );
  }
  final origin = place.offset;
  final shown = clip.shift(origin);
  final need = frost == null
      ? null
      : frostNeed(frost.sigma, devicePixelRatio: dpr);
  if (need == null) {
    return SiteAsk(
      drawn: shown,
      reads: shown.inflate(reach),
      look: FilterLook(
        key: null,
        need: const CopyNeed(),
        imageRead: ImageReadFilter(
          filter: filter,
          clip: shown,
          blendMode: blendMode,
        ),
      ),
      noJoin: NoJoin.noGeometry,
      groupsBackdrop: false,
      place: place,
      paints: paints,
    );
  }
  final over = blendMode == BlendMode.srcOver;
  final bandLook = over ? band?.call(shown, origin) : null;
  return SiteAsk(
    drawn: shown,
    reads: shown.inflate(need.reachAt(dpr)),
    look: FilterLook(
      key: inScene ? 'band' : null,
      need: need,
      imageRead: inScene && over ? null : ImageReadFilter.none,
    ),
    role: bandLook == null ? null : BandSiteRole(bandLook),
    noJoin: bandLook == null ? NoJoin.noGeometry : null,
    groupsBackdrop: bandLook != null,
    place: place,
    paints: paints,
  );
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

/// How a surface reads its backdrop: directly, as a backdrop filter in a clip,
/// or over a copy of what lies under it, as the frame's plan says.
@internal
class BackdropRig {
  /// Creates a rig whose backdrop reads share the backdrop of [key], if any.
  BackdropRig({this.key});

  /// The backdrop this rig reads directly, shared with every other rig of the
  /// key, when the frame's plan gives it no other.
  final BackdropKey? key;

  final _filter = LayerHandle<BackdropFilterLayer>();
  final _clipPath = LayerHandle<ClipPathLayer>();
  final _clipRect = LayerHandle<ClipRectLayer>();

  final _slot = LayerHandle<GlassSlotLayer>();
  final _read = LayerHandle<ReadLayer>();
  final _imageLayer = LayerHandle<PictureLayer>();
  Object? _imageKey;

  /// The filter layer the rig reads the backdrop with.
  BackdropFilterLayer? get filterLayer => _filter.layer;

  /// Whether the rig has painted its clip.
  bool get hasClip => _clipRect.layer != null || _clipPath.layer != null;

  /// Whether the last paint left room for a picture over a copy (see
  /// [paintSite]).
  bool get hasSlot => _slot.layer != null;

  /// Paints the backdrop read with [backdrop]. With a [site], it paints in a
  /// slot the site's fate can fill with a read of a copy instead.
  void paintSite(
    PaintingContext context,
    Offset offset, {
    required PlanSite? site,
    required PaintingContextCallback backdrop,
  }) {
    if (site != null) {
      final slot = (_slot.layer ??= GlassSlotLayer())..site = site;
      context.pushLayer(slot, backdrop, offset);
      return;
    }
    _slot.layer = null;
    backdrop(context, offset);
  }

  /// The layer a read of the scene shows in.
  ReadLayer get readLayer => _read.layer ??= ReadLayer();

  /// The picture [record] draws, kept while [key] stays equal.
  PictureLayer imagePicture(
    Object key,
    Rect bounds,
    ui.Picture Function() record,
  ) {
    final previous = _imageLayer.layer;
    if (previous != null && _imageKey == key) return previous;
    final picture = PictureLayer(bounds)..picture = record();
    _imageLayer.layer = picture;
    _imageKey = key;
    return picture;
  }

  // Its picture holds the image it reads, an atlas other glass may have left.
  void _dropImage() {
    _imageLayer.layer = null;
    _imageKey = null;
  }

  /// The picture [imagePicture] last drew.
  ui.Picture? get imageShown => _imageLayer.layer?.picture;

  /// Shows the backdrop read, taken from the backdrop of [group] where the
  /// frame's plan shares one between reads.
  void showBackdrop(BackdropKey? group) {
    _filter.layer?.backdropKey = group ?? key;
    show(null);
  }

  /// Leaves no slot until the next [paintSite].
  void releaseSlot() {
    _slot.layer = null;
  }

  /// Fills the slot with [served] over [under], or with the backdrop read
  /// without [served].
  void show(Layer? served, {Layer? under}) {
    assert(under == null || served != null, 'Only a copy covers [under].');
    if (!identical(served, _imageLayer.layer)) _dropImage();
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
    _dropImage();
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
  void paintBackdrop(
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
    }
  }

  /// Sets the clip rect the rig has in place of an outline.
  void clipTo(Rect bounds) {
    final clip = _clipRect.layer;
    if (clip != null && clip.clipRect != bounds) clip.clipRect = bounds;
  }

  /// Releases every layer but the picture over the copy.
  void clear() {
    _slot.layer = null;
    _filter.layer = null;
    _clipPath.layer = null;
    _clipRect.layer = null;
  }

  /// Releases every layer.
  void dispose() {
    clear();
    _imageLayer.layer = null;
    _read.layer = null;
  }
}
