import 'dart:ui';

import 'package:liquid_glass_renderer/src/composer/geometry.dart';
import 'package:liquid_glass_renderer/src/composer/plan_scenery.dart';
import 'package:liquid_glass_renderer/src/composer/plan_site.dart';

/// Where a read's backdrop comes from.
sealed class ReadSource {
  const ReadSource();
}

/// The copy's layers added again inside the read's filter: one target.
final class SceneRead extends ReadSource {
  /// Creates the source.
  const SceneRead();
}

/// An image: none in the frame's scene. A new one costs its own submit.
final class ImageRead extends ReadSource {
  /// Creates the source.
  const ImageRead({required this.held});

  /// Whether the image of an earlier frame still holds.
  final bool held;
}

/// A backdrop filter: the frame goes offscreen, and splits once per read.
final class LiveRead extends ReadSource {
  /// Creates the source.
  const LiveRead();
}

/// One backdrop and all the glass drawn from it.
final class GlassRead {
  /// Opens a read at [lead].
  GlassRead(this.lead)
    : band = lead.ask.reads,
      quad = lead.ask.drawn,
      share = lead.ask.look.need.share,
      shapes = lead.isBand ? 0 : lead.ask.look.shapes {
    members.add(lead);
  }

  /// The shapes in its members' shared matte.
  int shapes;

  /// The first member in paint order; the filter draws at its place.
  final SiteFacts lead;

  /// Everything drawn from this read, in paint order.
  final List<SiteFacts> members = [];

  /// What this read holds of what lies under it.
  Rect band;

  /// What its filter draws over.
  Rect quad;

  /// The most device pixels along each side one pixel of its copy can stand
  /// for, for every member.
  int share;

  /// Where the backdrop comes from.
  ReadSource source = const SceneRead();

  /// What the layers under its lead leave it.
  ReadLimit limit = ReadLimit.none;

  /// Earlier reads whose glass lies in [band]: each is drawn again inside this
  /// read, so nesting doubles a read's targets.
  final List<GlassRead> holds = [];

  /// Zero over pictures alone, else one more than the highest read it holds.
  int level = 0;

  /// Where its backdrop's pixels lie, for a read that does not read live.
  late ReadGeometry geometry;

  /// Where its filter takes the geometry of the glass it draws from.
  GeometryKind geometryKind = const OwnAtlas();

  /// What the glass it draws is, its band left out, in paint order.
  List<GlassBody> get glass => [
    for (final member in members)
      if (member.ask.role is GlassSiteRole) member.ask.look.body,
  ];

  /// The frost the shader of the glass it leads draws over the copy, in
  /// logical pixels: 0 under a band.
  double get leadShaderFrost =>
      lead.isBand ? 0 : lead.ask.look.need.shaderFrost;

  /// Whether what it holds differs from the last frame.
  bool changed = false;

  /// Whether every glass drawn from it frosts what it shows by [flatFrost]
  /// or more, so its copy leaves out what that frost hides: a blur of what
  /// lies under it.
  bool get flat =>
      members.every((site) => site.ask.look.frostSigma >= flatFrost);

  /// The least frost, a sigma in logical pixels, that hides what a flat copy
  /// leaves out: a little under the 2.2 of a bar of regular glass. Glass
  /// turned toward clear shows what lies under it, and reads it whole.
  static const double flatFrost = 2;

  /// The passes its copy takes for what it draws of the page (see
  /// [PlanScenery.savedUnder]).
  int inside = 0;

  /// The group of live reads that share one copy of the backdrop, taken at the
  /// first of them, or null for a read on its own.
  int? liveGroup;

  /// The targets this read issues, each a pass of the frame: none for an
  /// image, else [sceneTargets].
  int get targets => source is ImageRead ? 0 : sceneTargets;

  /// The targets it issues drawn in the scene: its filter's layer, the layers
  /// that frost its copy and mix its haze, what its copy draws apart of the
  /// page, and all of that again for each read it holds that is no image. A
  /// pass costs the raster thread the same whatever its pixels (0.3 ms in a
  /// trace of a Pixel 6a), so the frost's passes count though they are a
  /// sixteenth of the band's.
  int get sceneTargets => source is LiveRead ? 1 : _drawnIn(1);

  // Drawn in a layer whose pixels stand for [scale] device pixels a side: a
  // copy inside a coarser one is frosted by its glass, not in place.
  int _drawnIn(int scale) {
    var total =
        1 + inside + geometry.frostLayersIn(scale) + geometry.hazeLayers;
    for (final held in holds) {
      if (held.source is ImageRead) continue;
      total += held._drawnIn(geometry.lattice.share);
    }
    return total;
  }
}

/// What a site does this frame.
sealed class SiteFate {
  const SiteFate();
}

/// Idle, off screen or outside its clips.
final class HiddenFate extends SiteFate {
  /// Creates the fate.
  const HiddenFate();
}

/// Draws [read]'s filter at its own place.
final class LeadFate extends SiteFate {
  /// Creates the fate.
  const LeadFate(this.read);

  /// The read it leads.
  final GlassRead read;
}

/// Another site's filter draws this glass.
final class FollowFate extends SiteFate {
  /// Creates the fate.
  const FollowFate(this.read);

  /// The read it follows.
  final GlassRead read;
}

/// One frame's plan. Every route the frame takes is a value in here.
final class GlassPlan {
  /// Creates a plan.
  GlassPlan(
    this.reads,
    this.fates, {
    required this.issuedTargets,
    required this.dueAt,
    required this.notes,
  });

  /// The frame's reads in paint order.
  final List<GlassRead> reads;

  /// Parallel to [PlanScenery.sites].
  final List<SiteFate> fates;

  /// Targets the frame issues, nested replays counted.
  final int issuedTargets;

  /// The first frame a read that holds still can buy its image, if none
  /// changes before it.
  final int dueAt;

  /// Why the frame is what it is; empty unless asked for.
  final List<String> notes;
}
