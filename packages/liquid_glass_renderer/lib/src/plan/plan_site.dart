import 'dart:math' as math;
import 'dart:ui';

import 'package:liquid_glass_renderer/src/painting/screen_place.dart';
import 'package:liquid_glass_renderer/src/plan/band_look.dart';
import 'package:liquid_glass_renderer/src/plan/plan_result.dart';
import 'package:liquid_glass_renderer/src/plan/plan_scenery.dart';
import 'package:liquid_glass_renderer/src/plan/read_layout.dart';
import 'package:meta/meta.dart';

/// What a glass is, as far as where the final shader takes its geometry from
/// goes: how many shapes it draws, and whether they fuse into a field or
/// carry looks of their own.
@immutable
final class ShapeCensus {
  /// Creates the census of glass of [shapes] shapes.
  const ShapeCensus({
    required this.shapes,
    this.field = false,
    this.looks = false,
    this.leans = false,
  });

  /// Glass with no geometry yet.
  static const ShapeCensus none = ShapeCensus(shapes: 0);

  /// One plain shape.
  static const ShapeCensus one = ShapeCensus(shapes: 1);

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
      other is ShapeCensus &&
      other.shapes == shapes &&
      other.field == field &&
      other.looks == looks &&
      other.leans == leans;

  @override
  int get hashCode => Object.hash(shapes, field, looks, leans);
}

/// Where the final shader takes the geometry of a draw from.
///
/// Decided by what glass a draw holds, never by whether it moves, in
/// [geometryKindOf] alone.
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
/// Glass encodes its own geometry as `geometryKindOf([census])` when it paints,
/// before the frame is planned; `compilePlan` gives every read the kind of the
/// glass it draws, so a read of one glass draws the geometry that glass
/// encoded.
GeometryKind geometryKindOf(List<ShapeCensus> glass) => switch (glass) {
  // The shader that works one shape out has no work register left on a
  // Mali-G78 for a lean; an atlas costs a pass where the glass changes shape
  // and no more to draw.
  [ShapeCensus(shapes: 1, field: false, looks: false, leans: false)] =>
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
    this.census = ShapeCensus.one,
    this.imageRead,
    this.anyGrid = false,
  });

  /// No look: a site that draws nothing through a filter.
  static const FilterLook none = FilterLook(key: null, need: CopyNeed());

  /// Equal for glass one shader's uniforms can draw, its tint aside.
  final Object? key;

  /// What its read's copy has to be.
  final CopyNeed need;

  /// Whether this glass's shader can draw a scroll edge beside it.
  final bool drawsBand;

  /// The tint, which one filter can draw per shape, but not beside a band.
  final Object? tint;

  /// What its glass is, if it is glass.
  final ShapeCensus census;

  /// How many shapes it adds to a shared atlas.
  int get shapes => census.shapes;

  /// What a read of this site that can only come from an image does to it,
  /// or null for glass that frosts a copy by itself.
  final ImageReadFilter? imageRead;

  /// Whether a read of it can only come from an image ([imageRead]).
  bool get imageOnly => imageRead != null;

  /// Whether its shader draws it at the pixels of a coarser copy holding it,
  /// taking each fragment for as many device pixels.
  final bool anyGrid;

  /// The sigma, in logical pixels, it frosts what it shows by, whichever way:
  /// its copy's frost or its image read's blur, the lesser axis of one.
  double get frostSigma => switch (imageRead?.blur) {
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
      other.census == census &&
      other.imageRead == imageRead &&
      other.anyGrid == anyGrid;

  @override
  int get hashCode =>
      Object.hash(key, need, drawsBand, tint, census, imageRead, anyGrid);
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
    required this.place,
    this.look = FilterLook.none,
    this.role,
    this.noJoin,
    this.groupsBackdrop = true,
    this.paints,
    this.clip,
  }) : hidden = false;

  const SiteAsk._none()
    : drawn = Rect.zero,
      reads = Rect.zero,
      look = FilterLook.none,
      role = null,
      noJoin = null,
      groupsBackdrop = false,
      place = const Shifted(Offset.zero),
      paints = null,
      clip = null,
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

  /// Whether its backdrop read may share one backdrop read with the glass
  /// beside it: it draws through its geometry or a band's paint that the shared
  /// filter takes.
  final bool groupsBackdrop;

  /// How it lies on the screen.
  final ScreenPlace place;

  /// Equal while what it paints is the same in place: what a read over it
  /// holds of it.
  final Object? paints;

  /// The clips between the site's layer and where it draws its read, which
  /// the walk does not pass on its way to the site, or null for none.
  final Rect? clip;

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
      other.groupsBackdrop == groupsBackdrop &&
      other.place == place &&
      other.paints == paints &&
      other.clip == clip &&
      other.hidden == hidden;

  @override
  int get hashCode => Object.hash(
    drawn,
    reads,
    look,
    role,
    noJoin,
    groupsBackdrop,
    place,
    paints,
    clip,
    hidden,
  );
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

/// A site: one layer of the frame whose drawing the plan decides, the glass
/// of one glass layer or one backdrop filter (a scroll edge's band, a frost,
/// fake glass drawn in a layer). It lives as long as its layer, under one
/// [id]. Each frame it is met once, in paint order, makes one [SiteAsk] and
/// is given one [SiteFate]: hidden, leading a read, or drawn by the read
/// another site leads.
///
/// These are its facts: where the form found it and what it asks. The plan
/// reads them; the form that walks the frame writes them.
abstract base class SiteFacts {
  /// Stable while the site lives; the ledger's key.
  Object get id;

  /// Its place in paint order.
  int get order;

  /// The order of the last thing painted under its body.
  int get floor;

  /// Inherited alpha, filters and clips.
  StateChain get state;

  /// The clip around what it draws on the screen, if any: the clips the walk
  /// found around it and those its [ask] names below it.
  Rect? get clip;

  /// Its index in the frame's sites and in [GlassPlan.fates].
  int get index;

  /// What its site asks this frame.
  SiteAsk get ask;

  /// Whether it is a scroll edge glass over it can draw.
  bool get isBand => ask.role is BandSiteRole;
}
