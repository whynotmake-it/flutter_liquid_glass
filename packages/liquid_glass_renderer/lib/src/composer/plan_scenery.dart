import 'dart:math' as math;
import 'dart:ui';

import 'package:liquid_glass_renderer/src/composer/plan.dart';
import 'package:liquid_glass_renderer/src/composer/plan_site.dart';
import 'package:meta/meta.dart';

/// All [compilePlan] needs of a frame. A form answers from a layer tree; a test
/// answers from a generated scene, ten thousand scenes in seconds.
abstract interface class PlanScenery {
  /// The frame's sites in paint order.
  List<SiteFacts> get sites;

  /// What changed this frame.
  DirtyLog get dirty;

  /// The screen in logical pixels, the most room an image can take.
  Rect get screen;

  /// The screen's device pixels per logical pixel.
  double get devicePixelRatio;

  /// What the content under [site] allows a read over it to be.
  ReadLimit limitUnder(SiteFacts site);

  /// What makes [limitUnder] of [site] what it is, for a person, if anything.
  String? whyLimited(SiteFacts site);

  /// The frame something meeting [band] before [order] last changed, or the
  /// frame the scenery began.
  int lastChangedUnder(int order, Rect band);

  /// The passes a copy of [band] takes for what lies in it before [order],
  /// beyond its own: each opacity, filter or mask there is a layer drawn
  /// apart. A [flat] copy leaves out what its glass's frost hides.
  int savedUnder(int order, Rect band, {required bool flat});
}

/// What a kind of layer lets a read over it be.
enum ReadLimit {
  /// Anything: pictures and known containers.
  none,

  /// Added to the scene again but not recorded: a texture.
  sceneOnly,

  /// Cannot be drawn twice: a platform view, a foreign backdrop filter or a
  /// layer type the composer does not know.
  liveOnly,
}

/// Order and rect of what changed this frame: old and new bounds of a changed
/// leaf, every volatile leaf and a site whose output moved.
///
/// A read over the frame is unchanged when no span before its lead meets its
/// band and no read it holds changed. Past [capacity] spans merge, which only
/// ever says more changed than did.
final class DirtyLog {
  /// Spans kept before they merge.
  static const int capacity = 16;

  final _orders = List<int>.filled(capacity, 0);
  final _rects = List<Rect>.filled(capacity, Rect.zero);
  int _count = 0;

  /// Whether nothing changed.
  bool get isEmpty => _count == 0;

  /// How many spans are kept.
  int get length => _count;

  /// Forgets the last frame.
  void clear() => _count = 0;

  /// Notes that what lies at [order] changed inside [rect].
  void add(int order, Rect rect) {
    if (rect.isEmpty) return;
    if (_count < capacity) {
      _orders[_count] = order;
      _rects[_count] = rect;
      _count++;
      return;
    }
    final last = _count - 1;
    _orders[last] = math.min(_orders[last], order);
    _rects[last] = _rects[last].expandToInclude(rect);
  }

  /// Whether a span before [before] meets [band].
  bool meets(int before, Rect band) {
    for (var i = 0; i < _count; i++) {
      if (_orders[i] >= before) continue;
      if (_rects[i].overlaps(band)) return true;
    }
    return false;
  }
}

/// Inherited alpha, filters and clips, one link per layer that adds any.
///
/// Links are shared while a layer's value holds, so siblings compare by
/// identity first.
final class StateChain {
  /// Adds [token] under [parent].
  const StateChain(this.parent, this.token);

  /// The state outside every layer.
  static const StateChain root = StateChain(null, null);

  /// The link above.
  final StateChain? parent;

  /// The value this link adds.
  final Object? token;

  /// Whether both chains hold equal values in the same order.
  bool same(StateChain other) {
    StateChain? a = this;
    StateChain? b = other;
    while (true) {
      if (identical(a, b)) return true;
      if (a == null || b == null) return false;
      if (a.token != b.token) return false;
      a = a.parent;
      b = b.parent;
    }
  }
}

/// Why a site can never share a filter.
enum NoJoin {
  /// Part of a fused field, or its shapes have appearances of their own.
  field,

  /// Its glow is drawn per surface.
  glow,

  /// Its backdrop shrinks towards its own center.
  shrink,

  /// Its shadows fade with their shape, cut outside a filter drawn later.
  fadingShadows,

  /// It has no matte yet, or draws through no filter it could share.
  noMatte,

  /// Scaled, so its shapes lie in no matte the others share.
  scaled,
}

/// What a read that can only come from an image does to it, past the plain
/// copy glass frosts by itself.
@immutable
final class PageFilter {
  /// Creates the filter of a page.
  const PageFilter({
    this.filter,
    this.blur,
    this.clip,
    this.blendMode = BlendMode.src,
  });

  /// A plain copy, which what reads it composites as it needs to.
  static const PageFilter none = PageFilter();

  /// A filter applied as a backdrop filter over the page.
  final ImageFilter? filter;

  /// A mirrored Gaussian blur by these sigmas in logical pixels, standing for
  /// [filter].
  final (double, double)? blur;

  /// Where [filter] applies, the whole page when null, on the screen.
  final Rect? clip;

  /// How [filter]'s output composites over the page.
  final BlendMode blendMode;

  /// What pages under one filter share.
  Object? get key => blur ?? filter;

  @override
  bool operator ==(Object other) =>
      other is PageFilter &&
      other.filter == filter &&
      other.blur == blur &&
      other.clip == clip &&
      other.blendMode == blendMode;

  @override
  int get hashCode => Object.hash(filter, blur, clip, blendMode);
}
