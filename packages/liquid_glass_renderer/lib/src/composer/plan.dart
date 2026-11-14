import 'dart:math' as math;
import 'dart:ui';

import 'package:liquid_glass_renderer/src/composer/geometry.dart';
import 'package:liquid_glass_renderer/src/composer/geometry_renderer_limits.dart';
import 'package:liquid_glass_renderer/src/composer/plan_ledger.dart';
import 'package:liquid_glass_renderer/src/composer/plan_result.dart';
import 'package:liquid_glass_renderer/src/composer/plan_scenery.dart';
import 'package:liquid_glass_renderer/src/composer/plan_site.dart';

part 'package:liquid_glass_renderer/src/composer/plan_tuning.dart';

/// The cost of drawing [site] with [read], minus that of one more read, in GPU
/// ms equivalents. Below zero, sharing pays.
///
/// Signs the record on the Pixel: 12 scattered buttons merge (-0.78 against
/// -0.9..-1.7 measured), a whole-screen group is rejected (+0.26 against
/// +0.6..+0.7), a band under glass joins it (about -0.1 against 0..-0.1) and
/// any dead area in a menu at full resolution loses (+0.43 against about +1).
/// The magnitudes disagree, so this is a join rule, not a prediction.
double _mergeDelta(GlassRead read, SiteFacts site, PlanPrices prices) {
  final share = math.min(read.share, site.ask.look.need.share);
  final band = read.band.expandToInclude(site.ask.reads);
  final quad = read.quad.expandToInclude(site.ask.drawn);
  double area(Rect rect) => rect.width * rect.height;
  double copy(Rect rect, int scale) =>
      prices.copyGpuPerMpx * prices._mpx(area(rect)) / (scale * scale);
  final together = copy(band, share);
  final apart =
      copy(read.band, read.share) +
      copy(site.ask.reads, site.ask.look.need.share);
  final dead =
      prices.deadGpuPerMpx *
      prices._mpx(
        math.max(0, area(quad) - area(read.quad) - area(site.ask.drawn)),
      );
  return together -
      apart +
      dead -
      prices.passGpu -
      prices.rasterWeight * prices.passRaster;
}

// A filter draws under its lead's clips, so the glass it draws must lie inside
// them, and inside its own, which the filter does not apply. Under the same
// clip the filter cuts it as it would itself.
bool _insideClips(GlassRead read, SiteFacts site) {
  final lead = read.lead.clip;
  final own = site.clip;
  if (lead == own) return true;
  return (lead == null || encloses(lead, site.ask.drawn)) &&
      (own == null || encloses(own, site.ask.drawn));
}

bool _lookFits(GlassRead read, SiteFacts site) {
  final lead = read.lead.ask.look;
  final look = site.ask.look;
  if (site.isBand) return false;
  if (read.lead.isBand) {
    return look.drawsBand &&
        site.ask.drawn.overlaps(read.lead.ask.drawn) &&
        lead.need.bandFits(look.need) &&
        (read.members.length == 1 ||
            read.members[1].ask.look.key == look.key &&
                read.members[1].ask.look.tint == look.tint);
  }
  return lead.key == look.key;
}

// Why a site does not join a read: of itself, whatever the read, or of the
// read it was held against. The verdict and the frame report's note are both
// read off one of these.
enum _Apart {
  noJoin,
  turned,
  limited,
  page,
  leadNoJoin,
  bandsApart,
  leadPage,
  leadLive,
  paintedOver,
  otherState,
  clipCut,
  otherLook,
  matteFull,
  costsMore,
}

// Why [site], over content that leaves its read [limit], never joins a read,
// or null where it may.
_Apart? _alone(SiteFacts site, ReadLimit limit) {
  if (site.ask.noJoin != null) return _Apart.noJoin;
  if (limit == ReadLimit.liveOnly) {
    return site.ask.turned ? _Apart.turned : _Apart.limited;
  }
  if (site.ask.look.page != null) return _Apart.page;
  return null;
}

// Why [site] does not join [read], or null where it joins.
_Apart? _apart(
  GlassRead read,
  SiteFacts site,
  PlanPrices prices,
  PlanPolicy policy,
) {
  final band = read.lead.isBand;
  if (read.lead.ask.noJoin != null) return _Apart.leadNoJoin;
  if (band && !policy.bands) return _Apart.bandsApart;
  if (read.lead.ask.look.page != null) return _Apart.leadPage;
  if (read.source is LiveRead) return _Apart.leadLive;
  if (read.lead.order < site.floor) return _Apart.paintedOver;
  if (!site.state.same(read.lead.state)) return _Apart.otherState;
  if (!_insideClips(read, site)) return _Apart.clipCut;
  if (!_lookFits(read, site)) return _Apart.otherLook;
  if (read.shapes + site.ask.look.shapes > policy.maxShapes) {
    return _Apart.matteFull;
  }
  if (!band && !(_mergeDelta(read, site, prices) < 0)) return _Apart.costsMore;
  return null;
}

// The frame report's note of [why] for [site], held against [read] where
// that is why.
String _note(
  _Apart why,
  SiteFacts site,
  GlassRead? read,
  PlanScenery scene,
  PlanPrices prices,
) {
  final text = switch (why) {
    _Apart.noJoin => 'never joins: ${site.ask.noJoin!.name}',
    _Apart.turned => 'never joins: turned',
    _Apart.limited =>
      'never joins: ${scene.whyLimited(site) ?? 'over glass that reads live'}',
    _Apart.page => 'never joins: reads a page',
    _Apart.leadNoJoin => 'its lead never joins: ${read!.lead.ask.noJoin!.name}',
    _Apart.bandsApart => 'bands stay apart',
    _Apart.leadPage => 'its lead reads a page',
    _Apart.leadLive => 'its lead reads live',
    _Apart.paintedOver => 'painted over after its lead',
    _Apart.otherState => 'other clip, alpha or filter',
    _Apart.clipCut => 'a clip would cut it',
    _Apart.otherLook => 'other look',
    _Apart.matteFull => 'matte is full',
    _Apart.costsMore =>
      'costs more together: '
          '${_mergeDelta(read!, site, prices).toStringAsFixed(2)}',
  };
  return '${site.id}: $text';
}

/// The one decision function: every route is an output of it.
///
/// Sites are read in paint order, so when one is reached every lower site's
/// fate is decided, which is what lets a read know whether it holds glass.
/// First fit, because the cleverer groupings measured worse on the phone
/// (closest_groups +31.7 %, dead_free +27 % on the menu).
///
/// Same inputs, same plan and same edits.
(GlassPlan, PlanLedgerEdits) compilePlan(
  PlanScenery scene,
  PlanLedger ledger,
  PlanPrices prices,
  PlanPolicy policy,
  int frame, {
  bool explain = false,
}) {
  final notes = <String>[];
  final reads = <GlassRead>[];
  final fates = <SiteFate>[];
  final edits = PlanLedgerEdits();
  _decideFates(scene, prices, policy, reads, fates, explain ? notes : null);
  for (final read in reads) {
    read.geometryKind = geometryKindOf(read.glass);
  }
  _resolveGeometry(scene, policy, reads);
  final dueAt = _chooseSources(scene, ledger, prices, frame, reads, edits);
  final issued = _keepBudget(
    scene,
    ledger,
    prices,
    policy,
    frame,
    reads,
    edits,
    explain ? notes : null,
  );
  _groupLiveReads(reads);
  return (
    GlassPlan(
      reads,
      fates,
      issuedTargets: issued,
      dueAt: dueAt,
      notes: notes,
    ),
    edits,
  );
}

// Decides each site's fate in paint order: hidden, follower or lead.
void _decideFates(
  PlanScenery scene,
  PlanPrices prices,
  PlanPolicy policy,
  List<GlassRead> reads,
  List<SiteFate> fates,
  List<String>? notes,
) {
  final screen = scene.screen;
  final sites = scene.sites;
  for (var at = 0; at < sites.length; at++) {
    final site = sites[at];
    if (site.ask.hidden ||
        !site.ask.drawn.overlaps(screen) ||
        (site.clip != null &&
            !site.clip!.overlaps(site.ask.drawn.intersect(screen)))) {
      fates.add(const HiddenFate());
      continue;
    }
    final limit = _limitOf(site, reads, scene, policy);
    final pageOnly = site.ask.look.page != null;
    GlassRead? joined;
    if (_alone(site, limit) case final why?) {
      notes?.add(_note(why, site, null, scene, prices));
    } else {
      for (var i = reads.length - 1; i >= 0; i--) {
        final read = reads[i];
        final band = read.lead.isBand;
        final overGlass = read.members
            .skip(band ? 1 : 0)
            .any((m) => m.ask.drawn.overlaps(site.ask.drawn));
        if (overGlass) {
          notes?.add('${site.id}: overlaps');
          break;
        }
        final why = _apart(read, site, prices, policy);
        if (why == null) {
          joined = read;
          break;
        }
        notes?.add(_note(why, site, read, scene, prices));
        // Joining a read further down would draw this glass under the band.
        if (band && read.lead.ask.drawn.overlaps(site.ask.drawn)) break;
      }
    }
    if (joined != null) {
      joined.members.add(site);
      joined.shapes += site.ask.look.shapes;
      joined.band = joined.band.expandToInclude(site.ask.reads);
      joined.quad = joined.quad.expandToInclude(site.ask.drawn);
      joined.share = math.min(joined.share, site.ask.look.need.share);
      fates.add(FollowFate(joined));
      continue;
    }
    final read = GlassRead(site)..limit = limit;
    // A filter of a page has no scene read to fall back on.
    if (limit == ReadLimit.liveOnly || (pageOnly && limit != ReadLimit.none)) {
      read.source = const LiveRead();
    }
    reads.add(read);
    fates.add(LeadFate(read));
  }
}

// Decides the reads each copy holds and its lattice, rects and frost.
void _resolveGeometry(
  PlanScenery scene,
  PlanPolicy policy,
  List<GlassRead> reads,
) {
  for (var i = 0; i < reads.length; i++) {
    final read = reads[i];
    if (read.source is LiveRead) continue;
    var frostLeftOut = 0.0;
    for (var j = 0; j < i; j++) {
      final below = reads[j];
      if (below.source is LiveRead || !_under(below, read)) continue;
      if (policy.dropsFrost &&
          below.lead.isBand &&
          below.members.length == 1 &&
          read.leadShaderFrost > 0 &&
          below.lead.ask.look.need.shaderFrost <= read.leadShaderFrost) {
        frostLeftOut = math.max(
          frostLeftOut,
          below.lead.ask.look.need.shaderFrost,
        );
        continue;
      }
      read.holds.add(below);
      read.level = math.max(read.level, below.level + 1);
    }
    final lead = read.lead.ask.look;
    final page = lead.page;
    read.geometry = ReadGeometry.resolve(
      devicePixelRatio: scene.devicePixelRatio,
      share: read.share,
      atScreen: !_holdsAtOwnGrid(read),
      reads: read.band,
      screen: scene.screen,
      clip: read.lead.clip,
      holdsGlass: read.holds.isNotEmpty,
      glassFrost: read.lead.isBand
          ? (read.members.length > 1
                ? read.members[1].ask.look.need.shaderFrost
                : 0)
          : lead.need.shaderFrost,
      bandFrost: read.lead.isBand ? lead.need.shaderFrost : null,
      frostLeftOut: frostLeftOut,
      filter: page == null ? null : (page.key, page.blendMode),
      haze: read.lead.isBand ? null : lead.need.haze,
    );
  }
}

// Decides each copy's source (scene, held or new image) and its memo.
int _chooseSources(
  PlanScenery scene,
  PlanLedger ledger,
  PlanPrices prices,
  int frame,
  List<GlassRead> reads,
  PlanLedgerEdits edits,
) {
  final screen = scene.screen;
  var dueAt = _never;
  for (final read in reads) {
    if (read.source is LiveRead) {
      read.changed = true;
      continue;
    }
    final id = read.lead.id;
    final memo = ledger.reads[id];
    final next = ReadMemo()
      ..seenAt = frame
      ..lastBand = read.band;
    final holds = [for (final held in read.holds) held.lead.id];
    next.holds = holds;
    final geometry = read.geometry;
    final last = memo?.geometry;
    var room = last?.room;
    final watched = room ?? read.band;
    final changed =
        scene.dirty.meets(read.lead.order, watched) ||
        read.holds.any((held) => held.changed) ||
        (last != null && !last.drawsLike(geometry));
    read.changed = changed;
    next
      ..changedAt = changed
          ? frame
          : memo?.changedAt ??
                scene.lastChangedUnder(read.lead.order, read.band)
      ..misses = memo?.misses ?? 0
      ..forBudget = memo?.forBudget ?? false;
    read.inside = scene.savedUnder(
      read.lead.order,
      read.band,
      flat: read.flat,
    );
    final rent = prices.rent(
      read.band,
      read.share,
      targets: read.sceneTargets,
    );
    var boughtAt = memo?.boughtAt;
    if (room != null &&
        (changed ||
            !last!.servesAsImage(geometry) ||
            !_sameIds(memo!.holds, holds))) {
      // A hold that ended before it paid makes the next wait longer, unless
      // the budget bought the image.
      final held = frame - boughtAt!;
      if (held >= rent) {
        next.misses = 0;
      } else if (!next.forBudget) {
        next.misses = math.min(next.misses + 1, 6);
      }
      next.forBudget = false;
      room = null;
      boughtAt = null;
    }
    final pageOnly = read.lead.ask.look.page != null;
    final need = rent << next.misses;
    final allowed = read.limit == ReadLimit.none;
    if (room != null) {
      read.source = const ImageRead(held: true);
    } else if (allowed &&
        (pageOnly || (!changed && frame - next.changedAt >= need))) {
      read.source = const ImageRead(held: false);
      room = _withRoom(read, memo, rent, screen);
      boughtAt = frame;
    } else if (allowed) {
      dueAt = math.min(dueAt, next.changedAt + need);
    }
    if (room != null) {
      read.geometry = geometry.withRoom(room, screen);
    }
    next
      ..geometry = read.geometry
      ..boughtAt = boughtAt;
    edits.writes[id] = next;
  }
  return dueAt;
}

// Decides which scene reads become images to keep within the target budget.
int _keepBudget(
  PlanScenery scene,
  PlanLedger ledger,
  PlanPrices prices,
  PlanPolicy policy,
  int frame,
  List<GlassRead> reads,
  PlanLedgerEdits edits,
  List<String>? notes,
) {
  var issued = _targets(reads);
  if (issued <= policy.maxTargets) return issued;
  final screen = scene.screen;
  // The deepest read another holds first: doubling becomes linear. Then the
  // last in paint order, so the same frame always moves the same reads.
  final deepest = reads.where((read) => read.level > 0).toList()
    ..sort((a, b) => b.level.compareTo(a.level));
  final order = [...deepest, ...reads.reversed];
  for (final read in order) {
    if (issued <= policy.maxTargets) break;
    if (read.source is! SceneRead || read.limit != ReadLimit.none) continue;
    final id = read.lead.id;
    final rent = prices.rent(
      read.band,
      read.share,
      targets: read.sceneTargets,
    );
    read.source = const ImageRead(held: false);
    read.geometry = read.geometry.withRoom(
      _withRoom(read, ledger.reads[id], rent, screen),
      screen,
    );
    edits.writes[id]!
      ..geometry = read.geometry
      ..boughtAt = frame
      ..forBudget = true;
    issued = _targets(reads);
    notes?.add('${read.lead.id}: over budget, reads an image');
  }
  if (issued > policy.maxTargets) {
    notes?.add('over budget at $issued: what is left can not use an image');
  }
  return issued;
}

int _targets(List<GlassRead> reads) {
  var sum = 0;
  for (final read in reads) {
    sum += read.targets;
  }
  return sum;
}

// No frame comes this far.
const _never = 1 << 52;

// Live reads with nothing painted under the later ones since the first share
// its copy of the backdrop: Impeller flips to a new target once, not per read
// (BackdropKey). A read over another's glass has to see that glass, so it
// starts a group of its own. Scroll edges and fake glass filter through a
// layer of their own, with no key to take.
void _groupLiveReads(List<GlassRead> reads) {
  var groups = 0;
  final open = <GlassRead>[];
  void close() {
    if (open.length > 1) {
      for (final read in open) {
        read.liveGroup = groups;
      }
      groups++;
    }
    open.clear();
  }

  for (final read in reads) {
    final lead = read.lead;
    if (read.source is! LiveRead ||
        lead.isBand ||
        lead.ask.noJoin == NoJoin.noMatte) {
      continue;
    }
    if (open.isNotEmpty) {
      final first = open.first;
      final apart =
          first.lead.order >= lead.floor &&
          lead.state.same(first.lead.state) &&
          !open.any((other) => other.lead.ask.drawn.overlaps(lead.ask.reads));
      if (!apart) close();
    }
    open.add(read);
  }
  close();
}

// What the content and the glass under [site] allow a read of it to be. A
// read over a live read has to read live too: only the frame's own pass holds
// what that one drew.
ReadLimit _limitOf(
  SiteFacts site,
  List<GlassRead> reads,
  PlanScenery scene,
  PlanPolicy policy,
) {
  if (site.ask.turned || !policy.copies) return ReadLimit.liveOnly;
  for (final read in reads) {
    if (read.source is! LiveRead) continue;
    for (final member in read.members) {
      if (member.ask.drawn.overlaps(site.ask.reads)) return ReadLimit.liveOnly;
    }
  }
  return scene.limitUnder(site);
}

// Whether [below]'s glass lies under [read]'s rather than beside it: glass
// beside it stays out of what it reads, NEAR: it does not show a neighbour in
// what it reads at its rim.
bool _under(GlassRead below, GlassRead read) {
  for (final held in below.members) {
    for (final member in read.members) {
      if (held.ask.drawn.overlaps(member.ask.drawn)) return true;
    }
  }
  return false;
}

/// Whether [read]'s copy holds the glass under it at the copy's own pixels,
/// the glass's shader drawing a fragment for each of them, rather than at
/// the screen's: glass holding more glass in turn takes its fragments for
/// device pixels.
///
/// NEAR, judged by eye on the iPhone 16 Pro over the gallery's controls and
/// cards under the tab bar: the held glass's bevel squeezes what it refracts
/// past what one fragment per copy pixel resolves, and the copy's frost
/// hides it. Against the glass held at the screen's pixels under Impeller's
/// blur (host, dpr 2 and 3, clear glass held): 5 to 13 levels off under a
/// frost of 12 and 20 logical pixels, 40 to 51 under 6; drawn at the
/// screen's pixels and as a picture, 4 to 35. It saves 12 % of the fragment
/// work of a scroll with glass under the tab bar on the Pixel 6a. Glass that
/// frosts its own copy keeps it at the coarser of the two grids
/// ([Lattice.inside]).
bool _holdsAtOwnGrid(GlassRead read) => read.holds.every(
  (held) => held.holds.isEmpty && held.members.every((m) => m.ask.look.anyGrid),
);

bool _sameIds(List<Object> a, List<Object> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!identical(a[i], b[i])) return false;
  }
  return true;
}

// An image takes room for glass that moves in it: what the band moved in a
// frame times the frames the image has to hold to pay, at least twice the
// room that last ran out.
Rect _withRoom(GlassRead read, ReadMemo? memo, int rent, Rect screen) {
  final last = memo?.lastBand;
  var room = 0.0;
  if (read.changed || read.lead.ask.look.page?.clip != null) return read.band;
  if (last != null) {
    final moved = math.max(
      (last.left - read.band.left).abs(),
      (last.top - read.band.top).abs(),
    );
    room = moved * rent;
  }
  if (memo?.geometry?.room case final previous?) {
    room = math.max(room, 2 * (previous.width - read.band.width).abs());
  }
  return read.band.inflate(room).intersect(screen);
}
