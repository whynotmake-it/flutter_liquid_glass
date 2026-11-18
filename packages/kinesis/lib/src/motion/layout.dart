import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:kinesis/src/motion/effect.dart';
import 'package:kinesis/src/motion/motion.dart';
import 'package:kinesis/src/motion/rect.dart';
import 'package:kinesis/src/motion/rest.dart';
import 'package:kinesis/src/motion/spring.dart';
import 'package:kinesis/src/motion/value.dart';

/// The motion of a keyed layout, pure: feed it layouts at explicit times
/// and read where each item is drawn.
///
/// `MotionLayout` is its screen host; a bar, a list or a test drives it
/// directly. Each item is a rect on springs (its center, width and height)
/// and a presence from 0 to 1 that its effect reads. [layout] plans every
/// change through [planner]: items that moved head to their new rects,
/// items that arrived enter and items that left stay drawn while they
/// leave, then go. Each item's rect rests within its plan's
/// [LayoutPlan.rest] ([MotionRest.length] by default), its presence within
/// [MotionRest.opacity] and an accent's swell within [MotionRest.scale] of
/// its size.
final class LayoutMotion extends Motion {
  /// Creates a layout motion that plans its changes with [planner], on
  /// [clock] (`MotionClock.instance` when null).
  LayoutMotion({this.planner = const LayoutPlanner.flip(), super.clock});

  /// Plans each change of layout.
  LayoutPlanner planner;

  final Map<Object, _Slot> _slots = {};
  bool _laidOut = false;

  // Debug only: ids asked for before they were laid out, checked at the
  // next layout, and every id ever laid out, so that an id that has gone
  // is not taken for one that never was.
  final Set<Object> _debugAsked = {};
  final Set<Object> _debugSeen = {};

  void _debugAsk(Object id) {
    if (!_slots.containsKey(id)) _debugAsked.add(id);
  }

  void _debugCheckAsked() {
    final unknown = _debugAsked.where((id) => !_debugSeen.contains(id));
    for (final id in unknown) {
      final key = _debugSeen
          .whereType<ValueKey<Object?>>()
          .where((key) => key.value == id)
          .firstOrNull;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: FlutterError.fromParts([
            ErrorSummary(
              'LayoutMotion was asked for $id, which it never laid out.',
            ),
            ErrorDescription(
              'A layout knows its items by the ids its layouts give: '
              "MotionLayout uses each child's key, or its type and index "
              'among the unkeyed children of that type.',
            ),
            if (key != null)
              ErrorHint('It lays out $key: ask for the key, not its value.')
            else
              ErrorHint('It lays out ${_slots.keys.take(3).join(', ')}.'),
          ]),
          library: 'kinesis',
          context: ErrorDescription('while checking a LayoutMotion'),
        ),
      );
    }
    _debugAsked.clear();
  }

  /// The keys of the items drawn, those leaving included.
  Iterable<Object> get ids => _slots.keys;

  /// Whether [id] is drawn.
  bool contains(Object id) => _slots.containsKey(id);

  /// Whether [id] left the layout and is drawn until its leave ends.
  bool isLeaving(Object id) => _slots[id]?.leaving ?? false;

  /// Where layout put [id], or null before its first layout.
  ///
  /// In debug mode an [id] the next [layout] does not have either, and
  /// never had, is reported as an error: `MotionLayout` knows its children
  /// by their keys, not by the values in them.
  Rect? laidOut(Object id) {
    if (kDebugMode) _debugAsk(id);
    return hostLaidOut(id);
  }

  /// [laidOut] without the check, for a host that asks about children its
  /// layouts may leave out, such as rows scrolled out of a sliver.
  @internal
  Rect? hostLaidOut(Object id) => _slots[id]?.model;

  /// Where [id] is drawn now: its springs, its accent and the lean; a rect
  /// of zero before its first layout. An unknown [id] is reported as for
  /// [laidOut].
  LayoutItem itemAt(Object id) {
    if (kDebugMode) _debugAsk(id);
    return hostItemAt(id);
  }

  /// [itemAt] without the check, as [hostLaidOut].
  @internal
  LayoutItem hostItemAt(Object id) {
    final slot = _slots[id];
    if (slot == null) return const LayoutItem(rect: Rect.zero);
    final p = slot.presence.valueAt(now);
    final effect = slot.effect;
    return LayoutItem(
      rect: _leant(id, slot, _accented(slot, slot.frame.valueAt(now))).shift(
        effect.offsetAt(p),
      ),
      scale: effect.scaleAt(p),
      opacity: effect.opacityAt(p),
      blur: effect.blurAt(p),
    );
  }

  Rect _accented(_Slot slot, Rect rect) {
    final w = slot.swellW;
    final h = slot.swellH;
    final model = slot.model;
    if (w == null || h == null || model == null) return rect;
    return Rect.fromCenter(
      center: rect.center,
      width: rect.width + (w.valueAt(now) - 1) * model.width,
      height: rect.height + (h.valueAt(now) - 1) * model.height,
    );
  }

  Rect _leant(Object id, _Slot slot, Rect rect) {
    final toward = _toward?[id];
    if (toward == null || slot.leaving || _amount == 0) return rect;
    return Rect.lerp(rect, toward, _amount)!;
  }

  Map<Object, Rect>? _toward;
  double _amount = 0;

  /// How present [id] is as its spring has it, overshoot included: 0 for
  /// an item that enters or has gone, 1 for one that is there.
  double presenceAt(Object id) => _slots[id]?.presence.valueAt(now) ?? 0;

  /// Whether [id]'s presence rests where it heads, within
  /// [MotionRest.opacity].
  bool presenceRests(Object id) {
    final presence = _slots[id]?.presence;
    return presence == null ||
        (presence.restsAt(now, MotionRest.opacity) && presence.nextDue == null);
  }

  /// The swell of [id]'s size by its accent, per axis, as a share of its
  /// laid out size: 1 by 1 at rest.
  Size accentAt(Object id) {
    final slot = _slots[id];
    final w = slot?.swellW;
    final h = slot?.swellH;
    if (w == null || h == null) return const Size(1, 1);
    return Size(w.valueAt(now), h.valueAt(now));
  }

  /// How far the lean moves [id]'s center.
  Offset leanOf(Object id) {
    final slot = _slots[id];
    final toward = _toward?[id];
    if (slot == null || toward == null || slot.leaving || _amount == 0) {
      return Offset.zero;
    }
    return (toward.center - slot.frame.valueAt(now).center) * _amount;
  }

  /// Leans the items [amount] of the way toward their rects in [toward],
  /// by key, as an interactive transition does: a pure function of
  /// [amount] over where the springs have them. Leaving items and items
  /// missing from [toward] do not lean; a null [toward] or an [amount] of 0
  /// removes the lean.
  void lean(Map<Object, Rect>? toward, double amount) {
    _toward = toward;
    _amount = toward == null ? 0 : amount;
    changed();
  }

  /// Ends the lean at [t] without a jump: each leaning item is put where it
  /// is drawn and springs home from there with the velocity its springs
  /// had, or, when [commit], rests there for the next [layout] to move on.
  void endLean(double t, {bool commit = false}) {
    advance(t);
    final toward = _toward;
    if (toward != null && _amount != 0) {
      for (final MapEntry(key: id, value: slot) in _slots.entries) {
        final to = toward[id];
        if (to == null || slot.leaving) continue;
        final drawn = Rect.lerp(slot.frame.valueAt(t), to, _amount)!;
        if (commit) {
          slot.frame.snap(t, drawn);
        } else {
          slot.frame.setPresentation(t, drawn);
        }
      }
    }
    _toward = null;
    _amount = 0;
    changed();
  }

  /// Drops [id] at once, without a leave: for a host whose item went out
  /// of view, as a lazy list's row scrolls away.
  void forget(Object id) {
    if (!_slots.containsKey(id)) return;
    _drop(id);
    changed();
  }

  /// Whether [id] rests where it is drawn.
  bool itemRests(Object id) {
    final slot = _slots[id];
    if (slot == null) return true;
    return slot.frame.restsAt(now, slot.rest) &&
        slot.presence.restsAt(now, MotionRest.opacity) &&
        slot.frame.nextDue == null &&
        slot.presence.nextDue == null &&
        (slot.swellW?.restsAt(now, _swellRest(slot.model?.width)) ?? true) &&
        (slot.swellH?.restsAt(now, _swellRest(slot.model?.height)) ?? true) &&
        !isScheduled((#swell, id));
  }

  /// The union of the drawn rects of the items that do not leave.
  Rect get bounds {
    Rect? union;
    for (final MapEntry(:key, :value) in _slots.entries) {
      if (value.leaving) continue;
      final rect = itemAt(key).rect;
      union = union == null ? rect : union.expandToInclude(rect);
    }
    return union ?? Rect.zero;
  }

  /// Shows the items at [rects], by key, from time [t], and returns the
  /// change it planned, or null when nothing changed.
  ///
  /// The change moves on [spring] unless [planner] has a spring of its
  /// own; with neither it jumps, except that with [carry] an item in
  /// flight keeps its course, moved by its change of layout. [jump] makes
  /// every item jump whatever the springs; the first layout puts every item
  /// in place. An item missing from [rects] leaves on its plan, or goes at
  /// once when the change jumps or it was never laid out; one that comes
  /// back while it leaves enters again from where it is drawn. Under
  /// Reduce Motion the effects are their `reduced` ones.
  LayoutChange? layout(
    double t,
    Map<Object, Rect> rects, {
    Spring? spring,
    bool carry = false,
    bool jump = false,
  }) {
    final change = _layout(
      t,
      rects,
      spring: spring,
      carry: carry,
      jump: jump,
    );
    if (kDebugMode) _debugCheckAsked();
    return change;
  }

  LayoutChange? _layout(
    double t,
    Map<Object, Rect> rects, {
    required Spring? spring,
    required bool carry,
    required bool jump,
  }) {
    advance(t);
    final jumps = jump || !_laidOut;
    final moving = jumps ? null : planner.spring ?? spring;
    _laidOut = true;
    final entries = <Object, LayoutEntry>{};
    var changed = false;
    for (final MapEntry(key: id, value: to) in rects.entries) {
      final slot = _slots[id];
      if (slot == null) {
        entries[id] = LayoutEntry(phase: LayoutPhase.entering, to: to);
        changed = true;
        continue;
      }
      final returning = slot.leaving || slot.presence.target != 1;
      if (returning || slot.model != to) changed = true;
      entries[id] = LayoutEntry(
        phase: returning ? LayoutPhase.entering : LayoutPhase.staying,
        from: returning ? null : slot.model,
        to: to,
        shown: slot.frame.valueAt(t),
      );
    }
    for (final MapEntry(key: id, value: slot) in _slots.entries.toList()) {
      if (rects.containsKey(id)) continue;
      if (slot.leaving && !jumps) continue;
      changed = true;
      if (moving == null || slot.model == null) {
        _drop(id);
        continue;
      }
      entries[id] = LayoutEntry(
        phase: LayoutPhase.leaving,
        from: slot.model,
        shown: slot.frame.valueAt(t),
      );
    }
    if (!changed) return null;
    final change = LayoutChange(time: t, entries: entries, spring: moving);
    final plans = planner.plan(change);
    for (final MapEntry(key: id, value: entry) in entries.entries) {
      final plan = plans[id] ?? LayoutPlan(spring: moving);
      _apply(id, entry, plan, t, jumps: jumps, carry: carry);
    }
    return change;
  }

  MotionEffect _effect(MotionEffect? effect) {
    final chosen = effect ?? MotionEffect.identity;
    return traits.reduceMotion ? chosen.reduced : chosen;
  }

  void _apply(
    Object id,
    LayoutEntry entry,
    LayoutPlan plan,
    double t, {
    required bool jumps,
    required bool carry,
  }) {
    final spring = jumps ? null : plan.spring;
    final springs = spring == null
        ? null
        : plan.springs ?? RectSprings.all(spring);
    _place(id, entry, plan, t, springs: springs, carry: carry && !jumps);
    final accent = plan.accent;
    if (accent != null &&
        springs != null &&
        entry.phase != LayoutPhase.leaving) {
      _swell(id, accent, t);
    }
  }

  void _place(
    Object id,
    LayoutEntry entry,
    LayoutPlan plan,
    double t, {
    required RectSprings? springs,
    required bool carry,
  }) {
    final spring = springs == null ? null : plan.spring;
    final delay = plan.delay;
    switch (entry.phase) {
      case LayoutPhase.entering:
        final to = entry.to!;
        final existing = _slots[id];
        final slot = existing ?? _own(id, plan.origin ?? to);
        slot.leaving = false;
        slot.rest = plan.rest;
        slot.model = to;
        slot.effect = _effect(plan.effect);
        if (springs == null) {
          slot.frame.snap(t, to);
          slot.presence.snap(t, 1);
          return;
        }
        if (existing == null) {
          slot.presence.snap(t, 0);
        }
        if (existing != null || plan.origin != null) {
          slot.frame.retarget(t, to, springs: springs, delay: delay);
        }
        slot.presence.retarget(t, 1, spring: spring, delay: delay);
      case LayoutPhase.staying:
        final slot = _slots[id]!;
        final from = entry.from!;
        final to = entry.to!;
        if (from == to) return;
        slot.model = to;
        if (springs != null) {
          slot.frame.retarget(t, to, springs: springs, delay: delay);
        } else if (!carry || slot.frame.restsAt(t, MotionRest.length)) {
          slot.frame.snap(t, to);
        } else {
          slot.frame.shift(from, to);
        }
      case LayoutPhase.leaving:
        final slot = _slots[id]!;
        slot.leaving = true;
        slot.rest = plan.rest;
        slot.effect = _effect(plan.effect);
        final destination = plan.destination;
        if (spring == null) {
          slot.presence.snap(t, 0);
        } else {
          if (destination != null) {
            slot.frame.retarget(
              t,
              destination,
              springs: springs,
              delay: delay,
            );
          }
          slot.presence.retarget(t, 0, spring: spring, delay: delay);
        }
    }
  }

  void _swell(Object id, LayoutAccent accent, double t) {
    final slot = _slots[id]!;
    final w = slot.swellW ??= own(
      MotionValue<double>(1),
      rest: () => _swellRest(slot.model?.width),
    );
    final h = slot.swellH ??= own(
      MotionValue<double>(1),
      rest: () => _swellRest(slot.model?.height),
    );
    unschedule((#swellH, id));
    unschedule((#swellW, id));
    final start = t + accent.delay;
    at(start, (t) {
      w.retarget(t, accent.scale.width, spring: accent.up);
      h.retarget(t, accent.scale.height, spring: accent.up);
      at(
        t + accent.heightDownDelay,
        (t) => h.retarget(t, 1, spring: accent.heightDown),
        slot: (#swellH, id),
      );
      at(
        t + accent.widthDownDelay,
        (t) => w.retarget(t, 1, spring: accent.widthDown),
        slot: (#swellW, id),
      );
    }, slot: (#swell, id));
  }

  static double _swellRest(double? extent) => MotionRest.scale(extent ?? 1);

  _Slot _own(Object id, Rect rect) {
    final slot = _Slot(
      MotionRect(rect, springs: const RectSprings.all(Spring.smooth)),
      MotionValue<double>(1),
    );
    own(slot.frame, rest: () => slot.rest);
    own(slot.presence, rest: _opacity);
    _slots[id] = slot;
    if (kDebugMode) _debugSeen.add(id);
    return slot;
  }

  void _drop(Object id) {
    final slot = _slots.remove(id);
    if (slot == null) return;
    disown(slot.frame);
    disown(slot.presence);
    if (slot.swellW case final w?) disown(w);
    if (slot.swellH case final h?) disown(h);
    unschedule((#swell, id));
    unschedule((#swellW, id));
    unschedule((#swellH, id));
  }

  static double _opacity() => MotionRest.opacity;

  @override
  void didAdvance(double t) {
    final gone = [
      for (final MapEntry(:key, :value) in _slots.entries)
        if (value.leaving &&
            value.presence.target == 0 &&
            value.presence.restsAt(t, MotionRest.opacity) &&
            value.presence.nextDue == null &&
            value.frame.restsAt(t, value.rest) &&
            value.frame.nextDue == null)
          key,
    ];
    gone.forEach(_drop);
  }
}

final class _Slot {
  _Slot(this.frame, this.presence);

  final MotionRect frame;
  final MotionValue<double> presence;
  MotionValue<double>? swellW;
  MotionValue<double>? swellH;
  MotionEffect effect = MotionEffect.identity;
  Rect? model;
  double rest = MotionRest.length;
  bool leaving = false;
}

/// Plans how a change of layout animates. Pure.
abstract class LayoutPlanner {
  /// Creates a planner.
  const LayoutPlanner();

  /// Moves each item from where it was drawn to where layout puts it,
  /// entering with [insert] and leaving with [remove] (fading in and out by
  /// default, as SwiftUI does), on [spring] or on the change's spring when
  /// [spring] is null.
  const factory LayoutPlanner.flip({
    Spring? spring,
    MotionEffect insert,
    MotionEffect remove,
  }) = _FlipPlanner;

  /// The spring every change moves on, or null to move on the change's own
  /// (a transaction's).
  Spring? get spring => null;

  /// The plan of each item of [change], by key. An item without a plan
  /// moves on the change's spring with no effect.
  Map<Object, LayoutPlan> plan(LayoutChange change);
}

final class _FlipPlanner extends LayoutPlanner {
  const _FlipPlanner({
    this.spring,
    this.insert = MotionEffect.fade,
    this.remove = MotionEffect.fade,
  });

  @override
  final Spring? spring;

  final MotionEffect insert;

  final MotionEffect remove;

  @override
  Map<Object, LayoutPlan> plan(LayoutChange change) => {
    for (final MapEntry(:key, :value) in change.entries.entries)
      key: LayoutPlan(
        spring: change.spring,
        effect: switch (value.phase) {
          LayoutPhase.entering => insert,
          LayoutPhase.leaving => remove,
          LayoutPhase.staying => null,
        },
      ),
  };
}

/// Where an item of a change of layout stands.
enum LayoutPhase {
  /// The item arrived in this change, or came back while it left.
  entering,

  /// The item was there before and is still there.
  staying,

  /// The item left in this change.
  leaving,
}

/// One item of a [LayoutChange].
@immutable
final class LayoutEntry {
  /// Describes one item of a change.
  const LayoutEntry({required this.phase, this.from, this.to, this.shown});

  /// Whether the item arrived, stayed or left.
  final LayoutPhase phase;

  /// Where layout put the item before, or null when it arrived.
  final Rect? from;

  /// Where layout puts the item now, or null when it left.
  final Rect? to;

  /// Where the item was drawn when the change came, or null when it
  /// arrived: what a planner pairing items by where they show reads.
  final Rect? shown;
}

/// What one layout did to the items of a [LayoutMotion].
@immutable
final class LayoutChange {
  /// Describes a change of layout.
  const LayoutChange({
    required this.time,
    required this.entries,
    this.spring,
  });

  /// The time of the change, in seconds.
  final double time;

  /// Every item laid out, by key, and the items that left: an item whose
  /// rect did not change stays with [LayoutEntry.from] equal to
  /// [LayoutEntry.to] and keeps its course.
  final Map<Object, LayoutEntry> entries;

  /// The spring of the change (the planner's or a transaction's), or null
  /// when it jumps.
  final Spring? spring;
}

/// How one item of a change animates.
@immutable
final class LayoutPlan {
  /// Describes how an item animates.
  const LayoutPlan({
    this.spring,
    this.springs,
    this.delay = 0,
    this.origin,
    this.destination,
    this.effect,
    this.accent,
    this.rest = MotionRest.length,
  });

  /// The spring of the presence and, without [springs], of the rect; null
  /// jumps.
  final Spring? spring;

  /// The springs of the rect's center, width and height, when they differ.
  final RectSprings? springs;

  /// Seconds the item keeps its course before it moves.
  final double delay;

  /// Where an entering item starts, instead of where layout puts it.
  final Rect? origin;

  /// Where a leaving item goes while it leaves, instead of staying where
  /// it was laid out.
  final Rect? destination;

  /// How the item enters or leaves.
  final MotionEffect? effect;

  /// A swell of the item's size over its move, or null for none.
  final LayoutAccent? accent;

  /// The distance, in logical pixels, within which the item's rect rests;
  /// a leaving item goes once its presence and its rect both rest, so a
  /// finer [rest] keeps an item that shrinks into a [destination] drawn
  /// until it lands.
  final double rest;
}

/// A transient swell of an item's size over a change, as a bar's capsule
/// swells when its content changes: both axes rise to [scale] of the laid
/// out size on [up] after [delay], then each falls back on its own spring
/// after its own delay, counted from the rise.
@immutable
final class LayoutAccent {
  /// Describes a swell.
  const LayoutAccent({
    required this.scale,
    required this.up,
    required this.widthDown,
    required this.heightDown,
    this.delay = 0,
    this.widthDownDelay = 0,
    this.heightDownDelay = 0,
  });

  /// The size the swell rises to, as a share of the laid out size per axis.
  final Size scale;

  /// The spring the swell rises on.
  final Spring up;

  /// Seconds after the change before the swell rises.
  final double delay;

  /// The spring the width falls back on.
  final Spring widthDown;

  /// Seconds after the rise before the width falls back.
  final double widthDownDelay;

  /// The spring the height falls back on.
  final Spring heightDown;

  /// Seconds after the rise before the height falls back.
  final double heightDownDelay;

  @override
  bool operator ==(Object other) =>
      other is LayoutAccent &&
      other.scale == scale &&
      other.up == up &&
      other.delay == delay &&
      other.widthDown == widthDown &&
      other.widthDownDelay == widthDownDelay &&
      other.heightDown == heightDown &&
      other.heightDownDelay == heightDownDelay;

  @override
  int get hashCode => Object.hash(
    scale,
    up,
    delay,
    widthDown,
    widthDownDelay,
    heightDown,
    heightDownDelay,
  );
}

/// Where an item of a [LayoutMotion] is drawn: its rect in the layout's
/// coordinates and its effect.
@immutable
final class LayoutItem {
  /// Describes where an item is drawn.
  const LayoutItem({
    required this.rect,
    this.scale = 1,
    this.opacity = 1,
    this.blur = 0,
  });

  /// The rect the item is drawn at, before [scale]: where its springs have
  /// it, size included.
  final Rect rect;

  /// The scale about the rect's center.
  final double scale;

  /// The opacity.
  final double opacity;

  /// The blur sigma.
  final double blur;

  @override
  bool operator ==(Object other) =>
      other is LayoutItem &&
      other.rect == rect &&
      other.scale == scale &&
      other.opacity == opacity &&
      other.blur == blur;

  @override
  int get hashCode => Object.hash(rect, scale, opacity, blur);
}
