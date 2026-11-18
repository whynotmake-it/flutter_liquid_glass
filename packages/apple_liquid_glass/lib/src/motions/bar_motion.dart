import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:apple_liquid_glass/src/motions/bar_frames.dart';
import 'package:apple_liquid_glass/src/motions/bar_transition_spec.dart';
import 'package:apple_liquid_glass/src/motions/glass_press.dart';
import 'package:flutter/painting.dart';
import 'package:kinesis/motion.dart';

// A capsule's identity across layouts: the key of its item in the
// capsules' layout motion.
final class _Capsule {
  _Capsule(this.id, this.segment, {required this.anonymous});

  Object id;
  final Object? segment;
  final bool anonymous;

  bool apart = false;
}

final class _Planner extends LayoutPlanner {
  _Planner(this._plan);

  final Map<Object, LayoutPlan> Function(LayoutChange change) _plan;

  @override
  Map<Object, LayoutPlan> plan(LayoutChange change) => _plan(change);
}

/// The motion of a glass bar whose items change: iOS 27's toolbar and
/// navigation bar item transition.
///
/// Feed it layouts with [setLayout]. A capsule that keeps its identity
/// moves and resizes to its new box on [GlassBarTransitionSpec.frameSpring]
/// and, when its items changed, swells by up to 16 points (20 percent at
/// most) and settles back - the height first, then the width. Items that
/// stay travel to their new place; new items appear at the old center of
/// their capsule, at a fifth of their size, blurred and transparent, and
/// grow into place; leaving items shrink, blur and fade into the new
/// center of their capsule. An item that takes the place of another, in a
/// capsule whose other items stay where they stand, changes with it in
/// place instead: each blurs, shrinks and fades where the other stands.
/// Every value retargets from its current state,
/// so a change in the middle of another change is continuous.
///
/// Capsules change only within their [GlassBarCapsuleLayout.segment]: the
/// leading groups of a bar into leading groups, the trailing ones into
/// trailing ones. A capsule with an id continues the capsule of its
/// segment with that id; an [GlassBarCapsuleLayout.anonymous] one the
/// nearest anonymous capsule of its segment.
///
/// One law places every capsule that comes or goes. A new capsule grows
/// out of the nearest capsule of its segment that stays: its own box
/// fitted inside that survivor's box before the change, at a fifth of the
/// fitted size; a capsule that goes shrinks into the survivor's box after
/// the change the same way, so it vanishes inside it. The survivor swells
/// as if its items changed. A capsule with no survivor on its side - and,
/// with [GlassBarTransitionSpec.oversizedInPlace], one too large for its
/// survivor - appears in place, swollen, blurred and transparent, settling
/// in, or swells and fades where it stands (see
/// [GlassBarTransitionSpec.segmentDelay]). Such capsules are
/// [GlassBarCapsuleFrame.apart]: they never fuse with the others.
///
/// The capsules and the items are two [LayoutMotion]s: the capsules' plan
/// is the law above, the items' follows it, and a frame composes an item
/// with its capsule's swell, lean and presence.
///
/// [setDrift] leans the capsules part of the way toward another layout
/// without changing the layout itself, as a navigation bar does during an
/// interactive pop; the next [setLayout] starts from where the drift put
/// them.
///
/// Times are seconds, positions logical pixels in the bar's own space.
final class GlassBarMotion extends Motion {
  /// Creates the motion with [spec].
  GlassBarMotion({this.spec = GlassBarTransitionSpec.standard});

  /// The tuning of the latest change.
  GlassBarTransitionSpec spec;

  late final LayoutMotion _capsules = own(
    LayoutMotion(planner: _Planner(_planCapsules)),
  );
  late final LayoutMotion _items = own(
    LayoutMotion(planner: _Planner(_planItems)),
  );
  final Map<Object, _Capsule> _capsuleOf = {};
  bool _hasLayout = false;
  Map<Object, Rect> _driftTo = const {};
  List<GlassBarCapsuleLayout>? _driftPaired;
  double _drift = 0;

  // Valid only inside setLayout: the planners run inside its two layout
  // calls and read what it paired.
  Map<_Capsule, GlassBarCapsuleLayout> _layoutOf = const {};
  Map<Object, _Capsule> _nextCapsuleOf = const {};
  Map<_Capsule, Offset> _births = const {};
  Map<_Capsule, Offset> _deaths = const {};
  Map<_Capsule, Offset> _oldCenters = const {};
  Set<_Capsule> _bornInPlace = const {};
  Map<Object, Offset> _swapCenters = const {};

  Iterable<_Capsule> get _all => _capsules.ids.cast<_Capsule>();

  GlassPress? _press;

  /// The press lifting a capsule, owned from the finger's touch until it
  /// settles; null while no capsule is lifted.
  GlassPress? get press => _press;

  bool _touching = false;

  /// Lifts a capsule on [press], in place of the press before, as a finger
  /// touches it at [position] at time [t].
  void pressDown(GlassPress press, double t, Offset position) {
    if (!identical(press, _press)) {
      if (_press case final before?) disown(before);
      _press = own(press);
    }
    // The touch advances the press before it holds; a press at rest then
    // is not let go.
    _touching = true;
    press.pointerDown(t, position);
    _touching = false;
  }

  @override
  void didAdvance(double t) {
    if (_press case final press? when !_touching && press.isAtRest) {
      disown(press);
      _press = null;
    }
    for (final c in _all) {
      if (c.apart && !_capsules.isLeaving(c) && _capsules.presenceRests(c)) {
        c.apart = false;
      }
    }
  }

  /// Pairs the capsules of [layout] (all but [skip]) with the [candidates]
  /// that continue into them: a capsule with an id continues the
  /// candidate of its segment with that id, an anonymous one the anonymous
  /// candidate of its segment whose place ([from]) lies nearest, nearest
  /// pairs first.
  Map<int, _Capsule> _pair(
    List<GlassBarCapsuleLayout> layout,
    List<_Capsule> candidates,
    Rect Function(_Capsule c) from, {
    Set<int> skip = const {},
  }) {
    final out = <int, _Capsule>{};
    final taken = <_Capsule>{};
    for (var k = 0; k < layout.length; k++) {
      final c = layout[k];
      if (c.anonymous || skip.contains(k)) continue;
      for (final candidate in candidates) {
        if (!candidate.anonymous &&
            candidate.id == c.id &&
            candidate.segment == c.segment &&
            !taken.contains(candidate)) {
          out[k] = candidate;
          taken.add(candidate);
          break;
        }
      }
    }
    final pairs = <(double, int, int)>[];
    for (var k = 0; k < layout.length; k++) {
      final c = layout[k];
      if (!c.anonymous || skip.contains(k)) continue;
      for (var n = 0; n < candidates.length; n++) {
        final candidate = candidates[n];
        if (!candidate.anonymous || candidate.segment != c.segment) continue;
        pairs.add(((from(candidate).center - c.rect.center).distance, k, n));
      }
    }
    pairs.sort(
      (a, b) => switch (a.$1.compareTo(b.$1)) {
        0 => a.$2 != b.$2 ? a.$2.compareTo(b.$2) : a.$3.compareTo(b.$3),
        final order => order,
      },
    );
    for (final (_, k, n) in pairs) {
      final candidate = candidates[n];
      if (out.containsKey(k) || taken.contains(candidate)) continue;
      out[k] = candidate;
      taken.add(candidate);
    }
    return out;
  }

  /// The box of [size] at [center] moved and cut to lie inside [into]:
  /// each axis at most as long as [into]'s, as near [center] as it fits.
  static Rect _inside(Size size, Offset center, Rect into) {
    final w = math.min(size.width, into.width);
    final h = math.min(size.height, into.height);
    double fit(double v, double lo, double hi) =>
        math.min(math.max(v, lo), math.max(lo, hi));
    return Rect.fromCenter(
      center: Offset(
        fit(center.dx, into.left + w / 2, into.right - w / 2),
        fit(center.dy, into.top + h / 2, into.bottom - h / 2),
      ),
      width: w,
      height: h,
    );
  }

  /// Whether a capsule of [size] grows out of (or shrinks into) a survivor
  /// whose box is [into] rather than appearing (or leaving) in place.
  bool _fits(Size size, Rect into) =>
      !spec.oversizedInPlace ||
      (size.width <= into.width + 1e-6 && size.height <= into.height + 1e-6);

  Rect _shrunk(Rect box) => Rect.fromCenter(
    center: box.center,
    width: box.width * spec.appearScale,
    height: box.height * spec.appearScale,
  );

  LayoutAccent _pulse(Size size) => LayoutAccent(
    scale: Size(
      spec.pulseScaleFor(size.width),
      spec.pulseScaleFor(size.height),
    ),
    up: spec.pulseUpSpring,
    delay: spec.pulseDelay,
    widthDown: spec.pulseWidthDownSpring,
    widthDownDelay: spec.pulseWidthDownDelay,
    heightDown: spec.pulseHeightDownSpring,
    heightDownDelay: spec.pulseHeightDownDelay,
  );

  /// Leans every capsule that [toward] also has (paired as [setLayout]
  /// pairs them) [amount] of the way from where it is toward its box there,
  /// its items riding along; null or 0 removes the lean at once.
  ///
  /// The lean is drawn on top of the motion, a pure function of [amount];
  /// a [setLayout] while leaning starts from the leaning capsules. The
  /// pairing is kept while [toward] is the same list and the layout has
  /// not changed, so a lean that follows a gesture pairs once.
  void setDrift(List<GlassBarCapsuleLayout>? toward, double amount) {
    if (toward == null || amount == 0) {
      _driftTo = const {};
      _driftPaired = null;
      _drift = 0;
      _capsules.lean(null, 0);
      return;
    }
    if (!identical(toward, _driftPaired)) {
      _driftPaired = toward;
      final live = [
        for (final c in _all)
          if (!_capsules.isLeaving(c)) c,
      ];
      _driftTo = {
        for (final MapEntry(key: k, value: c) in _pair(
          toward,
          live,
          (c) => _capsules.laidOut(c)!,
        ).entries)
          c: toward[k].rect,
      };
    }
    _drift = amount;
    _capsules.lean(_driftTo, amount);
  }

  /// Whether capsules lean toward a [setDrift] layout.
  bool get isDrifting => _drift != 0 && _driftTo.isNotEmpty;

  /// Ends a [setDrift] lean at time [t] without a jump: the capsules spring
  /// home on [GlassBarTransitionSpec.frameSpring] from where they lean.
  void endDrift(double t) {
    advance(t);
    _keepDrift(t, commit: false);
  }

  void _keepDrift(double t, {required bool commit}) {
    _driftPaired = null;
    if (isDrifting) {
      final riding = <Object, Rect>{
        for (final id in _items.ids)
          if (!_items.isLeaving(id))
            if (_capsuleOf[id] case final c?)
              if (_capsules.leanOf(c) case final d when d != Offset.zero)
                id: _items.itemAt(id).rect.shift(d),
      };
      _items.lean(riding, 1);
      _items.endLean(t, commit: commit);
      _capsules.endLean(t, commit: commit);
    } else {
      _capsules.lean(null, 0);
    }
    _driftTo = const {};
    _drift = 0;
  }

  /// Shows [layout] from time [t], under [transition] when given; with
  /// [animated] false (and on the first layout) everything snaps.
  void setLayout(
    double t,
    List<GlassBarCapsuleLayout> layout, {
    bool animated = true,
    GlassBarTransitionSpec? transition,
  }) {
    if (transition != null) spec = transition;
    advance(t);
    _capsuleOf.removeWhere((id, _) => !_items.contains(id));
    if (!_hasLayout || !animated || traits.reduceMotion) {
      _hasLayout = true;
      _snap(t, layout);
      return;
    }
    _keepDrift(t, commit: true);
    final live = [
      for (final c in _all)
        if (!_capsules.isLeaving(c)) c,
    ];
    final paired = _pair(layout, live, (c) => _capsules.laidOut(c)!);
    final leaving = [
      for (final c in _all)
        if (_capsules.isLeaving(c)) c,
    ];
    paired.addAll(
      _pair(
        layout,
        leaving,
        (c) => _capsules.itemAt(c).rect,
        skip: paired.keys.toSet(),
      ),
    );
    final resolved = [
      for (var k = 0; k < layout.length; k++)
        if (paired[k] case final existing?)
          existing
        else
          _Capsule(
            layout[k].id,
            layout[k].segment,
            anonymous: layout[k].anonymous,
          ),
    ];
    for (var k = 0; k < layout.length; k++) {
      if (resolved[k].anonymous) resolved[k].id = layout[k].id;
    }
    final liveIds = {for (final c in resolved) c.id};
    for (final c in _all) {
      if (!resolved.contains(c) && liveIds.contains(c.id)) {
        c.id = GlassBarDepartedId(c.id);
      }
    }
    _layoutOf = {
      for (var k = 0; k < layout.length; k++) resolved[k]: layout[k],
    };
    _nextCapsuleOf = {
      for (var k = 0; k < layout.length; k++)
        for (final item in layout[k].items) item.id: resolved[k],
    };
    _swapCenters = _swaps(layout, paired);
    _capsules.layout(t, {
      for (var k = 0; k < layout.length; k++) resolved[k]: layout[k].rect,
    }, spring: spec.frameSpring);
    _items.layout(t, {
      for (final c in layout)
        for (final item in c.items) item.id: item.rect,
    }, spring: spec.contentSpring);
    _capsuleOf.addAll(_nextCapsuleOf);
    _layoutOf = const {};
    _nextCapsuleOf = const {};
    _swapCenters = const {};
  }

  /// Where the items that change in place meet: in a capsule that
  /// continues with as many items as before, of which some stay where
  /// they stand in its row, an item that takes the place of one that
  /// leaves appears where that one stood, and the one that leaves fades
  /// where the new one stands - a button whose icon changed, beside
  /// buttons that did not. Keyed by both items' ids.
  Map<Object, Offset> _swaps(
    List<GlassBarCapsuleLayout> layout,
    Map<int, _Capsule> paired,
  ) {
    final out = <Object, Offset>{};
    for (final MapEntry(key: k, value: capsule) in paired.entries) {
      final before = [
        for (final MapEntry(key: id, value: c) in _capsuleOf.entries)
          if (c == capsule && !_items.isLeaving(id)) (id, _items.laidOut(id)!),
      ]..sort((a, b) => a.$2.left.compareTo(b.$2.left));
      final after = [
        for (final item in layout[k].items) (item.id, item.rect),
      ]..sort((a, b) => a.$2.left.compareTo(b.$2.left));
      if (before.length != after.length) continue;
      final was = {for (final (id, _) in before) id};
      final now = {for (final (id, _) in after) id};
      final swaps = <Object, Offset>{};
      var stays = false;
      var inOrder = true;
      for (var i = 0; i < before.length; i++) {
        final (old, from) = before[i];
        final (next, to) = after[i];
        if (old == next) {
          stays = true;
        } else if (now.contains(old) || was.contains(next)) {
          inOrder = false;
        } else {
          swaps[next] = from.center;
          swaps[old] = to.center;
        }
      }
      if (stays && inOrder) out.addAll(swaps);
    }
    return out;
  }

  Map<Object, LayoutPlan> _planCapsules(LayoutChange change) {
    if (change.spring == null) return const {};
    final spring = spec.frameSpring;
    final entries = change.entries;
    final survivors = {
      for (final MapEntry(:key, :value) in entries.entries)
        if (value.phase == LayoutPhase.staying) key as _Capsule: value,
    };
    (_Capsule, Rect)? nearestSurvivor(
      Object? segment,
      Offset from, {
      required bool after,
    }) {
      (_Capsule, Rect)? best;
      var distance = double.infinity;
      for (final MapEntry(key: c, value: entry) in survivors.entries) {
        if (c.segment != segment) continue;
        final d = (entry.to!.center - from).distance;
        if (d < distance) {
          distance = d;
          best = (c, after ? entry.to! : entry.shown!);
        }
      }
      return best;
    }

    final plans = <Object, LayoutPlan>{};
    final births = <_Capsule, Offset>{};
    final bornInPlace = <_Capsule>{};
    final hosts = <_Capsule>{};
    final birthSegments = <Object?>{};
    for (final MapEntry(:key, value: entry) in entries.entries) {
      if (entry.phase != LayoutPhase.entering || entry.shown != null) continue;
      final c = key as _Capsule;
      final to = entry.to!;
      final (host, source) =
          nearestSurvivor(c.segment, to.center, after: false) ??
          (null, Rect.zero);
      if (host != null && _fits(to.size, source)) {
        final box = _inside(to.size, to.center, source);
        births[c] = box.center;
        hosts.add(host);
        birthSegments.add(c.segment);
        plans[c] = LayoutPlan(
          spring: spring,
          delay: spec.frameDelay,
          origin: _shrunk(box),
          accent: _pulse(to.size),
        );
      } else {
        c.apart = true;
        bornInPlace.add(c);
        plans[c] = LayoutPlan(spring: spring, delay: spec.segmentDelay);
      }
    }
    final deaths = <_Capsule, Offset>{};
    for (final MapEntry(:key, value: entry) in entries.entries) {
      if (entry.phase != LayoutPhase.leaving) continue;
      final c = key as _Capsule;
      final here = entry.shown!.center;
      final size = entry.from!.size;
      final (host, sink) =
          nearestSurvivor(c.segment, here, after: true) ?? (null, Rect.zero);
      if (host == null || !_fits(size, sink)) {
        c.apart = true;
        plans[c] = LayoutPlan(spring: spring, delay: spec.segmentDelay);
        continue;
      }
      final box = _inside(size, here, sink);
      deaths[c] = box.center;
      hosts.add(host);
      plans[c] = LayoutPlan(
        spring: spring,
        delay: spec.frameDelay,
        destination: _shrunk(box),
        rest: _landing,
      );
    }
    for (final MapEntry(:key, value: entry) in entries.entries) {
      if (entry.phase == LayoutPhase.leaving || plans.containsKey(key)) {
        continue;
      }
      final c = key as _Capsule;
      final target = _layoutOf[c]!;
      final moves = _capsules.laidOut(c) != target.rect;
      final changed = hosts.contains(c) || _itemsChanged(c, target.items);
      plans[c] = LayoutPlan(
        spring: spring,
        delay: entry.phase == LayoutPhase.entering && c.apart
            ? spec.segmentDelay
            : birthSegments.contains(c.segment) && moves
            ? spec.birthStaggerDelay
            : spec.frameDelay,
        accent: changed ? _pulse(target.rect.size) : null,
      );
    }
    _births = births;
    _deaths = deaths;
    _bornInPlace = bornInPlace;
    _oldCenters = {
      for (final MapEntry(key: c, value: entry) in survivors.entries)
        c: entry.shown!.center,
    };
    return plans;
  }

  // Finer than the visible rest: the device replacement replay keeps the
  // remaining capsules' centers within 1.2 pt rms only when a shrunk
  // capsule is dropped at a 0.05 pt landing or later (0.1 pt gives 1.31).
  static const double _landing = 0.05;

  bool _itemsChanged(_Capsule capsule, List<GlassBarItemLayout> items) {
    final next = {for (final i in items) i.id};
    final before = [
      for (final id in _items.ids)
        if (identical(_capsuleOf[id], capsule) &&
            (!_items.isLeaving(id) || next.contains(id)))
          id,
    ];
    if (before.length != items.length) return true;
    for (var k = 0; k < items.length; k++) {
      if (before[k] != items[k].id) return true;
    }
    return false;
  }

  Map<Object, LayoutPlan> _planItems(LayoutChange change) {
    if (change.spring == null) return const {};
    final spring = spec.contentSpring;
    final delay = spec.contentDelay;
    final plans = <Object, LayoutPlan>{};
    for (final MapEntry(key: id, value: entry) in change.entries.entries) {
      switch (entry.phase) {
        case LayoutPhase.leaving:
          final c = _capsuleOf[id];
          final end =
              _swapCenters[id] ??
              (c == null ? null : _deaths[c] ?? _layoutOf[c]?.rect.center) ??
              entry.shown!.center;
          plans[id] = LayoutPlan(
            spring: spring,
            delay: delay,
            destination: Rect.fromCenter(
              center: end,
              width: entry.from!.width,
              height: entry.from!.height,
            ),
          );
        case LayoutPhase.entering when entry.shown == null:
          final c = _nextCapsuleOf[id]!;
          final to = entry.to!;
          if (_bornInPlace.contains(c)) {
            plans[id] = const LayoutPlan();
            continue;
          }
          final start =
              _swapCenters[id] ?? _oldCenters[c] ?? _births[c] ?? to.center;
          plans[id] = LayoutPlan(
            spring: spring,
            delay: delay,
            origin: Rect.fromCenter(
              center: start,
              width: to.width,
              height: to.height,
            ),
          );
        case LayoutPhase.entering || LayoutPhase.staying:
          plans[id] = LayoutPlan(spring: spring, delay: delay);
      }
    }
    return plans;
  }

  void _snap(double t, List<GlassBarCapsuleLayout> layout) {
    setDrift(null, 0);
    final capsules = [
      for (final c in layout) _Capsule(c.id, c.segment, anonymous: c.anonymous),
    ];
    _capsules.layout(t, {
      for (var k = 0; k < layout.length; k++) capsules[k]: layout[k].rect,
    }, jump: true);
    _items.layout(t, {
      for (final c in layout)
        for (final item in c.items) item.id: item.rect,
    }, jump: true);
    _capsuleOf.clear();
    for (var k = 0; k < layout.length; k++) {
      for (final item in layout[k].items) {
        _capsuleOf[item.id] = capsules[k];
      }
    }
  }

  /// The capsules at the current time, leaving ones included.
  List<GlassBarCapsuleFrame> get capsules => [
    for (final c in _all) _capsuleFrame(c),
  ];

  /// The capsule [item] stands in at the current time, or null when it stands
  /// in none.
  GlassBarCapsuleFrame? capsuleOf(Object item) {
    final capsule = _capsuleOf[item];
    return capsule != null && _capsules.contains(capsule)
        ? _capsuleFrame(capsule)
        : null;
  }

  GlassBarCapsuleFrame _capsuleFrame(_Capsule c) => GlassBarCapsuleFrame(
    c.id,
    _drawn(c),
    leaving: _capsules.isLeaving(c),
    segment: c.segment,
    opacity: c.apart ? _capsules.presenceAt(c).clamp(0.0, 1.0) : 1,
    apart: c.apart,
  );

  /// The swell of a capsule that appears or leaves in place, per axis.
  Offset _apartScale(_Capsule c) {
    if (!c.apart) return const Offset(1, 1);
    final rest = 1 - _capsules.presenceAt(c);
    final target = _capsules.laidOut(c)!;
    return Offset(
      1 + (spec.pulseScaleFor(target.width) - 1) * rest,
      1 + (spec.pulseScaleFor(target.height) - 1) * rest,
    );
  }

  Rect _drawn(_Capsule c) {
    final rect = _capsules.itemAt(c).rect;
    final apart = _apartScale(c);
    return Rect.fromCenter(
      center: rect.center,
      width: math.max(0, rect.width * apart.dx),
      height: math.max(0, rect.height * apart.dy),
    );
  }

  /// The items at the current time, leaving ones included.
  List<GlassBarItemFrame> get items => [
    for (final id in _items.ids)
      if (_frameOf(id) case final frame?) frame,
  ];

  GlassBarItemFrame? _frameOf(Object id) {
    final capsule = _capsuleOf[id];
    if (capsule == null) return null;
    final present = _capsules.contains(capsule);
    if (capsule.apart && !present) return null;
    final leaving = _items.isLeaving(id);
    final riding = present && !_capsules.isLeaving(capsule);
    final p = _items.presenceAt(id);
    var center =
        _items.itemAt(id).rect.center +
        (riding && !leaving ? _capsules.leanOf(capsule) : Offset.zero);
    var scale =
        lerpDouble(spec.appearScale, 1, p)! *
        (riding ? _capsules.accentAt(capsule).height : 1);
    var presence = p.clamp(0.0, 1.0);
    var blur = math.max<double>(0, spec.appearBlur * (1 - p));
    if (capsule.apart) {
      final q = _capsules.presenceAt(capsule);
      final f = _apartScale(capsule);
      final origin = _capsules.itemAt(capsule).rect.center;
      center =
          origin +
          Offset(
            (center.dx - origin.dx) * f.dx,
            (center.dy - origin.dy) * f.dy,
          );
      scale *= f.dy;
      presence *= q.clamp(0.0, 1.0);
      blur = math.max(blur, spec.appearBlur * (1 - q));
    }
    return GlassBarItemFrame(
      id,
      center: center,
      size: _items.laidOut(id)!.size,
      scale: math.max(0, scale),
      presence: presence,
      blur: blur,
      leaving: leaving,
    );
  }

  /// The frame of the item [id], or null when it is not in the bar.
  GlassBarItemFrame? itemFrame(Object id) =>
      _items.contains(id) ? _frameOf(id) : null;

  /// The frame of the capsule [id], or null when it is not in the bar.
  GlassBarCapsuleFrame? capsuleFrame(Object id) {
    for (final c in _all) {
      if (c.id == id) return _capsuleFrame(c);
    }
    return null;
  }
}
