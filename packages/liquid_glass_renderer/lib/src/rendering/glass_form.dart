import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/composer.dart';
import 'package:liquid_glass_renderer/src/rendering/backdrop_filter_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/follower_transform.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_composition_probe.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_underlay.dart';
import 'package:liquid_glass_renderer/src/rendering/read.dart';
import 'package:liquid_glass_renderer/src/rendering/retained_glass_clip.dart';
import 'package:liquid_glass_renderer/src/rendering/scene_out.dart';
import 'package:liquid_glass_renderer/src/rendering/transform_tracking_render_object_mixin.dart';

part 'package:liquid_glass_renderer/src/rendering/glass_form_layers.dart';
part 'package:liquid_glass_renderer/src/rendering/glass_form_nodes.dart';
part 'package:liquid_glass_renderer/src/rendering/glass_form_open.dart';

const Rect _everywhere = Rect.largest;

Rect _union(Rect a, Rect b) {
  if (a.isEmpty) return b;
  if (b.isEmpty) return a;
  return a.expandToInclude(b);
}

/// The frame in paint order, retained and compared with the layer tree once a
/// frame.
///
/// A layer keeps its dirty bit private and a composited property update changes
/// a layer without touching its children, so the walk visits every layer. An
/// unchanged layer costs a few compares and allocates nothing.
///
/// After [lower], everything here equals what a fresh [GlassForm] of the same
/// tree would hold. The soundness test asserts it after every generated
/// mutation.
@internal
final class GlassForm implements PlanScenery {
  @override
  final DirtyLog dirty = DirtyLog();

  /// This frame's number.
  int frame = 0;

  /// Layers visited by the last [lower], for tests.
  int get length => _count;

  /// The sites of the last [lower], in paint order.
  @override
  List<SiteFacts> get sites => _sites;
  List<SiteFacts> _sites = [];
  List<SiteFacts> _lastSites = [];

  /// Whether the sites are those of the last frame, in that order.
  bool get sitesHeld => _sitesHeld;
  bool _sitesHeld = false;

  /// Whether a site asks this frame what it did not ask the last.
  bool get asksChanged => _asksChanged;
  bool _asksChanged = false;

  final List<SiteNode> _siteNodes = [];

  /// The site nodes, parallel to [sites].
  List<SiteNode> get siteNodes => _siteNodes;

  @override
  Rect get screen => _screen;
  Rect _screen = Rect.zero;

  @override
  double get devicePixelRatio => _dpr;

  Layer? _root;
  double _dpr = 0;
  OpenNode? _top;
  late FormWorld _outside;

  final List<FormNode> _flat = [];
  int _count = 0;
  final List<VolatileNode> _volatile = [];
  int _volatileCount = 0;

  // The containers a copy draws as a layer apart, each after what it holds.
  final List<OpenNode> _saving = [];

  int _suppress = 0;
  int _next = 0;
  OpenNode? _owner;

  /// Compares [root]'s tree with the last frame's.
  void lower(ContainerLayer root, double devicePixelRatio, Size physicalSize) {
    frame++;
    dirty.clear();
    _asksChanged = false;
    _next = 0;
    _count = 0;
    _volatileCount = 0;
    _saving.clear();
    final recycled = _lastSites;
    _lastSites = _sites;
    _sites = recycled;
    _sites.length = 0;
    _siteNodes.length = 0;
    _screen = Offset.zero & (physicalSize / devicePixelRatio);
    if (!identical(root, _root) || devicePixelRatio != _dpr) {
      _root = root;
      _dpr = devicePixelRatio;
      _outside = FormWorld(
        Matrix4.diagonal3Values(1 / devicePixelRatio, 1 / devicePixelRatio, 1),
      );
      _top = switch (_nodeOf(root)) {
        final OpenNode node => node,
        _ => PlainNode(root),
      };
      dirty.add(0, _everywhere);
    }
    _top!.refreshIn(this, _outside);
    _flat.length = _count;
    _volatile.length = _volatileCount;
    assert(
      _sites.length == _siteNodes.length,
      'Every site has exactly one site node.',
    );
  }

  /// Logs what glass that left drew. A layer holding it may cover nothing of
  /// its own, and what reads over it holds its glass.
  void noteSitesGone() {
    final last = _lastSites;
    var held = last.length == _sites.length;
    for (var i = 0; held && i < last.length; i++) {
      held = identical(last[i], _sites[i]);
    }
    _sitesHeld = held;
    if (held) return;
    final kept = Set<SiteFacts>.identity()..addAll(_sites);
    for (final site in last) {
      if (!kept.contains(site)) dirty.add(-1, site.ask.drawn);
    }
  }

  void _enter(FormNode node) {
    node
      ..order = _next++
      ..owner = _owner;
    if (_count == _flat.length) {
      _flat.add(node);
    } else {
      _flat[_count] = node;
    }
    _count++;
  }

  void _log(int order, Rect rect) {
    if (_suppress == 0) dirty.add(order, rect);
  }

  // A node that left has no order this frame. Its place is where the walk
  // stands: what comes next, the first that painted over it, gets [_next].
  void _logGone(Rect rect) => _log(_next - 1, rect);

  /// The root's node, once a [lower] found one.
  FormNode? get top => _top;

  /// The node at [order] in paint order.
  FormNode nodeAt(int order) => _flat[order];

  /// Takes what [site] asks this frame, and logs where its glass moved or
  /// changed, which what lies over it reads.
  void noteAsk(SiteFacts site, SiteAsk ask) {
    final last = site.ask;
    if (site.takeAsk(ask)) _asksChanged = true;
    final around = site.noteForLog();
    if (around && last.drawn == ask.drawn && last.paints == ask.paints) return;
    dirty.add(site.order, _union(last.drawn, ask.drawn));
  }

  /// Finds where each site may share a filter, once its rects are known.
  void settleFloors() {
    for (final site in _sites) {
      site.settleFloor(site.ask.hidden ? -1 : floorOf(site));
    }
  }

  /// The order of the last thing painted under [site]'s body: a leaf meeting
  /// what it draws, or anything that can't be replayed meeting what it reads.
  ///
  /// Walks back from the site, skipping groups its rects miss, so it usually
  /// stops at the card under the glass a few nodes back.
  ///
  /// A leaf's bounds are its layer's canvas bounds, the whole repaint boundary
  /// for a picture that shares one, so labels beside glass in one boundary
  /// count as under it.
  int floorOf(SiteFacts site) {
    final drawn = site.ask.drawn;
    final reads = site.ask.reads;
    var i = site.order - 1;
    while (i >= 0) {
      final node = _flat[i];
      // What another site paints with its glass moves back with it or lies
      // over it, as the plan decides from that site's own facts.
      final other = node.owner;
      if (other != null && other.end <= site.order) {
        i = other.order - 1;
        continue;
      }
      final parent = node.parent;
      if (parent != null &&
          parent.end <= site.order &&
          !parent.bounds.overlaps(reads) &&
          !parent.bounds.overlaps(drawn)) {
        i = parent.order - 1;
        continue;
      }
      switch (node) {
        case PictureNode(:final screen):
          if (screen.overlaps(drawn)) return i;
        case VolatileNode(:final screen):
          if (screen.overlaps(reads)) return i;
        case OpenNode() || OutputNode():
          break;
      }
      i--;
    }
    return -1;
  }

  @override
  ReadLimit limitUnder(SiteFacts site) {
    var limit = ReadLimit.none;
    for (var i = 0; i < _volatileCount; i++) {
      final node = _volatile[i];
      if (node.order >= site.order || !node.screen.overlaps(site.ask.reads)) {
        continue;
      }
      if (node.limit == ReadLimit.liveOnly) return ReadLimit.liveOnly;
      limit = ReadLimit.sceneOnly;
    }
    return limit;
  }

  @override
  String? whyLimited(SiteFacts site) {
    for (var i = 0; i < _volatileCount; i++) {
      final node = _volatile[i];
      if (node.order >= site.order || !node.screen.overlaps(site.ask.reads)) {
        continue;
      }
      final layer = node.layer;
      return switch (layer) {
        TextureLayer() => 'a texture lies under it',
        PlatformViewLayer() => 'a platform view lies under it',
        BackdropFilterLayer() => 'a backdrop filter lies under it',
        _ =>
          '${layer.runtimeType} (unregistered) reaches its band -> '
              'LiquidGlassUnderlay.registerLayer',
      };
    }
    return null;
  }

  // Counts what a read's replay enters: a container before the lead that
  // meets the band, holds the lead or holds what the frame composes.
  @override
  int savedUnder(int order, Rect band, {required bool flat}) {
    var total = 0;
    for (final node in _saving) {
      if (node.order >= order) continue;
      if (node.end > order ||
          node.holdsComposed ||
          node.bounds.overlaps(band)) {
        total += node.saves(flat: flat);
      }
    }
    return total;
  }

  @override
  int lastChangedUnder(int order, Rect band) {
    var latest = 0;
    var i = 0;
    while (i < order && i < _count) {
      final node = _flat[i];
      if (node is OpenNode &&
          node.end <= order &&
          !node.bounds.overlaps(band)) {
        i = node.end;
        continue;
      }
      if (node.changedAt > latest && node.extent.overlaps(band)) {
        latest = node.changedAt;
      }
      i++;
    }
    return latest;
  }
}

/// What a container gives its children. Retained: an unchanged frame writes
/// nothing and allocates nothing.
@internal
final class FormWorld {
  /// Creates the world outside everything, under [base].
  FormWorld(this.base);

  /// The transform to the screen, without [dx] and [dy].
  Matrix4 base;

  /// The horizontal translation after [base].
  double dx = 0;

  /// The vertical translation after [base].
  double dy = 0;

  /// The clip on the screen, if any.
  Rect? clip;

  /// Inherited alpha, filters and clips.
  StateChain state = StateChain.root;

  /// How far, in the units [reaching] answers in, a filter above may spread
  /// what is drawn here: the reach of a blur, or infinity for a filter that
  /// may move it anywhere. Under one, [clip] holds only the clips inside it,
  /// which it spreads as well.
  double spread = 0;

  /// Whether a filter above may move what is drawn anywhere.
  bool get filtered => spread == double.infinity;

  /// Bumped when anything above changed.
  int stamp = 1;

  /// Where [local] lands on the screen.
  Rect reaching(Rect local) {
    if (filtered) return _everywhere;
    final shifted = local.shift(Offset(dx, dy));
    final bounds = MatrixUtils.transformRect(base, shifted);
    final held = clip;
    final cut = held == null ? bounds : held.intersect(bounds);
    return spread == 0 || cut.isEmpty ? cut : cut.inflate(spread);
  }

  /// Takes the values of [outside]; true when any differs.
  bool inherit(FormWorld outside) => set(
    outside.base,
    outside.dx,
    outside.dy,
    outside.clip,
    outside.state,
    spread: outside.spread,
  );

  /// Writes the values; true when any differs.
  ///
  /// An equal [base] counts as the same and the held one stays, so a producer
  /// that builds an equal matrix each frame changes nothing below it.
  bool set(
    Matrix4 base,
    double dx,
    double dy,
    Rect? clip,
    StateChain state, {
    required double spread,
  }) {
    final sameBase = _sameMatrix(this.base, base);
    if (sameBase &&
        this.dx == dx &&
        this.dy == dy &&
        (identical(this.clip, clip) || this.clip == clip) &&
        identical(this.state, state) &&
        this.spread == spread) {
      return false;
    }
    // Nodes below compare the base by identity to keep their own matrices.
    if (!sameBase) this.base = base;
    this.dx = dx;
    this.dy = dy;
    this.clip = clip;
    this.state = state;
    this.spread = spread;
    stamp++;
    return true;
  }

  // Producers keep their matrix while its value holds, so identity settles
  // nearly every compare; the 16 doubles are read only for a new instance.
  static bool _sameMatrix(Matrix4 a, Matrix4 b) {
    if (identical(a, b)) return true;
    final x = a.storage;
    final y = b.storage;
    for (var i = 0; i < 16; i++) {
      if (x[i] != y[i]) return false;
    }
    return true;
  }
}
