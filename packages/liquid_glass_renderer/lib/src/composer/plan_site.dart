import 'dart:math' as math;
import 'dart:ui';

import 'package:liquid_glass_renderer/src/composer/band_look.dart';
import 'package:liquid_glass_renderer/src/composer/geometry.dart';
import 'package:liquid_glass_renderer/src/composer/plan.dart';
import 'package:liquid_glass_renderer/src/composer/plan_result.dart';
import 'package:liquid_glass_renderer/src/composer/plan_scenery.dart';
import 'package:meta/meta.dart';

/// What a glass is, as far as where the final shader takes its geometry from
/// goes: how many shapes it draws, and whether they fuse into a field or
/// carry looks of their own.
@immutable
final class GlassBody {
  /// Creates the body of glass of [shapes] shapes.
  const GlassBody({
    required this.shapes,
    this.field = false,
    this.looks = false,
    this.leans = false,
  });

  /// Glass with no geometry yet.
  static const GlassBody none = GlassBody(shapes: 0);

  /// One plain shape.
  static const GlassBody one = GlassBody(shapes: 1);

  /// How many shapes it draws.
  final int shapes;

  /// Whether its shapes fuse into a field.
  final bool field;

  /// Whether its shapes carry looks of their own.
  final bool looks;

  /// Whether its shapes turn their normals toward their centers, as large
  /// iOS 27 regular glass does.
  final bool leans;

  @override
  bool operator ==(Object other) =>
      other is GlassBody &&
      other.shapes == shapes &&
      other.field == field &&
      other.looks == looks &&
      other.leans == leans;

  @override
  int get hashCode => Object.hash(shapes, field, looks, leans);
}

/// Where the final shader takes the geometry of a draw from.
///
/// What the glass a draw holds is decides it, never whether it moves:
/// [geometryKindOf] is the one place that does.
sealed class GeometryKind {
  const GeometryKind();
}

/// One shape of one look, which the final shader works out at each fragment.
final class ComputedShape extends GeometryKind {
  /// Creates the kind.
  const ComputedShape();
}

/// The atlas of one glass: several shapes, a fused field, shapes with looks
/// of their own, or a shape whose normals lean to its center.
final class OwnAtlas extends GeometryKind {
  /// Creates the kind.
  const OwnAtlas();
}

/// One atlas of all the glass one filter draws.
final class SharedAtlas extends GeometryKind {
  /// Creates the kind.
  const SharedAtlas();
}

/// Where the geometry of one filter drawing [glass] comes from.
///
/// Glass encodes its own geometry as `geometryKindOf([body])` when it paints,
/// before the frame is planned; [compilePlan] gives every read the kind of the
/// glass it draws, so a read of one glass draws the geometry that glass
/// encoded.
GeometryKind geometryKindOf(List<GlassBody> glass) => switch (glass) {
  // The shader that works one shape out has no work register left on a
  // Mali-G78 for a lean; an atlas costs a pass where the glass changes shape
  // and no more to draw.
  [GlassBody(shapes: 1, field: false, looks: false, leans: false)] =>
    const ComputedShape(),
  [] || [_] => const OwnAtlas(),
  _ => const SharedAtlas(),
};

/// What one filter's uniforms must share.
@immutable
final class FilterLook {
  /// Creates a look.
  const FilterLook({
    required this.key,
    required this.need,
    this.drawsBand = false,
    this.tint,
    this.body = GlassBody.one,
    this.page,
    this.anyGrid = false,
  });

  /// No look: a site that draws nothing through a filter.
  static const FilterLook none = FilterLook(key: null, need: CopyNeed(1));

  /// Equal for glass one shader's uniforms can draw, its tint aside.
  final Object? key;

  /// What its read's copy has to be.
  final CopyNeed need;

  /// Whether this glass's shader can draw a scroll edge beside it.
  final bool drawsBand;

  /// The tint, which one filter can draw per shape, but not beside a band.
  final Object? tint;

  /// What its glass is, if it is glass.
  final GlassBody body;

  /// How many shapes it adds to a shared matte.
  int get shapes => body.shapes;

  /// What a read of this site that can only come from an image does to it,
  /// or null for glass that frosts a copy by itself.
  final PageFilter? page;

  /// Whether its shader draws it at the pixels of a coarser copy holding it,
  /// taking each fragment for as many device pixels.
  final bool anyGrid;

  /// The sigma, in logical pixels, it frosts what it shows by, whichever way:
  /// its copy's frost or its page's blur, the lesser axis of one.
  double get frostSigma => switch (page?.blur) {
    (final x, final y) => math.max(need.shaderFrost, math.min(x, y)),
    null => need.shaderFrost,
  };

  @override
  bool operator ==(Object other) =>
      other is FilterLook &&
      other.key == key &&
      other.need == need &&
      other.drawsBand == drawsBand &&
      other.tint == tint &&
      other.body == body &&
      other.page == page &&
      other.anyGrid == anyGrid;

  @override
  int get hashCode =>
      Object.hash(key, need, drawsBand, tint, body, page, anyGrid);
}

/// What a site asks of a frame, in the screen's logical pixels.
///
/// A site makes one each frame and the form keeps the last while they are
/// equal, so the plan's inputs from a site changed exactly when its ask did.
@immutable
final class SiteAsk {
  /// Creates the ask of a site that draws this frame.
  const SiteAsk({
    required this.drawn,
    required this.reads,
    this.look = FilterLook.none,
    this.role,
    this.noJoin,
    this.turned = false,
    this.paints,
  }) : hidden = false;

  const SiteAsk._none()
    : drawn = Rect.zero,
      reads = Rect.zero,
      look = FilterLook.none,
      role = null,
      noJoin = null,
      turned = false,
      paints = null,
      hidden = true;

  /// A site that draws nothing this frame.
  static const SiteAsk none = SiteAsk._none();

  /// What it paints.
  final Rect drawn;

  /// What it reads.
  final Rect reads;

  /// What its filter must share.
  final FilterLook look;

  /// What the other sites of its read use of it, if they can use any.
  final SiteRole? role;

  /// What keeps it out of every group, if anything does.
  final NoJoin? noJoin;

  /// Whether a read of it must stay live: it is turned or skewed.
  final bool turned;

  /// Equal while what it paints is the same in place: what a read over it
  /// holds of it.
  final Object? paints;

  /// Whether it draws nothing this frame.
  final bool hidden;

  @override
  bool operator ==(Object other) =>
      other is SiteAsk &&
      other.drawn == drawn &&
      other.reads == reads &&
      other.look == look &&
      other.role == role &&
      other.noJoin == noJoin &&
      other.turned == turned &&
      other.paints == paints &&
      other.hidden == hidden;

  @override
  int get hashCode =>
      Object.hash(drawn, reads, look, role, noJoin, turned, paints, hidden);
}

/// What the other sites of a read use of one of them.
@immutable
sealed class SiteRole {
  const SiteRole();
}

/// Glass, which draws the read it is the first glass of, with every site the
/// read holds.
///
/// What draws the read is the renderer's, which extends this role: the plan
/// tells one glass from another and nothing more.
abstract base class GlassSiteRole extends SiteRole {
  /// Creates the role.
  const GlassSiteRole();
}

/// A scroll edge that the glass over it can draw in its own filter.
final class BandSiteRole extends SiteRole {
  /// Creates the role of a band that looks like [look].
  const BandSiteRole(this.look);

  /// How it looks where it lies this frame.
  final BandLook look;

  @override
  bool operator ==(Object other) => other is BandSiteRole && other.look == look;

  @override
  int get hashCode => look.hashCode;
}

/// One site of the frame: where the form found it and what it asks.
///
/// The plan only reads it. The form, which walks the frame, is its one
/// writer, through the methods named for the step of its walk that learned
/// each fact.
final class SiteFacts {
  /// Creates the facts of the site known as [id].
  SiteFacts(this.id);

  /// Stable while the site lives; the ledger's key.
  final Object id;

  /// Its place in paint order.
  int get order => _order;
  int _order = 0;

  /// The order of the last thing painted under its body.
  int get floor => _floor;
  int _floor = -1;

  /// Inherited alpha, filters and clips.
  StateChain get state => _state;
  StateChain _state = StateChain.root;

  /// The clip around it on the screen, if any.
  Rect? get clip => _clip;
  Rect? _clip;

  /// Its index in the frame's sites and in [GlassPlan.fates].
  int get index => _index;
  int _index = 0;

  /// What its site asks this frame.
  SiteAsk get ask => _ask;
  SiteAsk _ask = SiteAsk.none;

  // Glass draws no picture, so a fade or a clip around it reaches the dirty
  // log only through what was last noted here.
  StateChain _notedState = StateChain.root;
  Rect? _notedClip;
  bool _notedHidden = false;

  /// Whether it is a scroll edge glass over it can draw.
  bool get isBand => ask.role is BandSiteRole;

  /// Takes its place in the walk: its [order] in paint order, its [index] in
  /// the frame's sites, and the [state] and [clip] it inherits.
  @internal
  void placeInWalk({
    required int order,
    required int index,
    required StateChain state,
    required Rect? clip,
  }) {
    _order = order;
    _index = index;
    _state = state;
    _clip = clip;
  }

  /// Takes what its site asks this frame; true when it differs from the last
  /// ask.
  @internal
  bool takeAsk(SiteAsk ask) {
    if (ask == _ask) return false;
    _ask = ask;
    return true;
  }

  /// Notes the [state], [clip] and hiding the dirty log now knows, after
  /// [takeAsk]; true when they are what it knew before.
  @internal
  bool noteForLog() {
    final hidden = _ask.hidden;
    final same =
        _state.same(_notedState) &&
        _clip == _notedClip &&
        hidden == _notedHidden;
    _notedState = _state;
    _notedClip = _clip;
    _notedHidden = hidden;
    return same;
  }

  /// Takes its [floor], once every rect of the frame is known.
  @internal
  void settleFloor(int floor) {
    assert(floor < _order, 'A floor lies under its site in paint order.');
    _floor = floor;
  }
}
