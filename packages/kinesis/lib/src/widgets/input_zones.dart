import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/src/widgets/control_states.dart';
import 'package:kinesis/src/widgets/input_shared.dart';
import 'package:kinesis/src/widgets/input_target.dart';
import 'package:kinesis/src/widgets/input_zone.dart';
import 'package:kinesis/src/widgets/keyboard_use.dart';
import 'package:kinesis/src/widgets/pointer_line.dart';
import 'package:kinesis/src/widgets/scope.dart';
import 'package:kinesis/src/widgets/source.dart';

part 'package:kinesis/src/widgets/input_zones_zone.dart';
part 'package:kinesis/src/widgets/input_zones_targets.dart';
part 'package:kinesis/src/widgets/input_zones_render.dart';

/// The states of an [InputZones] host's zones, and its focus.
///
/// UIKit: each control's `state`. Flutter: one `WidgetStatesController`
/// per zone.
///
/// The controller is the one place a zone's states live, by the zone's
/// id: a zone that rebuilds keeps them, and a zone that leaves the host
/// drops them. The zone is their only writer: it publishes what its
/// control says ([InputZone.states]), disabled while it is not enabled,
/// and while it is the states input keeps (pressed, dragged, hovered, and
/// focused while focus should show, as `InputRegion` does). The controller
/// notifies its listeners, and those of the zone's [states], on every
/// change input makes; what a zone's build says notifies nobody.
///
/// A controller serves one host at a time. While two hosts hold it, as when
/// a date picker builds the next month's grid before the old one leaves,
/// the newest host wins: it drives [zoneAt], [requestFocus] and [sourceOf],
/// and the host that leaves afterwards changes nothing it wrote.
class InputZonesController<T extends Object> extends ChangeNotifier {
  /// Creates a controller with no states.
  InputZonesController();

  final Map<T, Set<WidgetState>> _states = {};
  final Map<T, List<VoidCallback>> _zoneListeners = {};
  final Map<T, MotionSource> _sources = {};
  _InputZonesState<T>? _host;
  T? _focused;

  /// The states of [zone] as they change: empty while the host holds no
  /// such zone. It notifies when input changes that zone's states alone,
  /// and keeps nothing once nobody listens.
  ValueListenable<Set<WidgetState>> states(T zone) =>
      _ZoneStates<T>(this, zone);

  Set<WidgetState> _statesOf(T zone) {
    final states = _states[zone];
    return states == null ? const {} : UnmodifiableSetView(states);
  }

  /// The zone that has the primary focus, or null.
  T? get focusedZone => _focused;

  /// The zone that takes input under [position], in the host's
  /// coordinates, as a touch landing there finds it (its rect, else its
  /// hit extension); null between and beyond the zones, on a disabled
  /// zone, and while no host holds the controller.
  ///
  /// What a host interaction (`InputZones.interactions`) asks as the
  /// finger moves: a menu's finger over its rows.
  T? zoneAt(Offset position) {
    final zone = _host?._zoneAt(position);
    return zone != null && zone.takesInput ? zone.id : null;
  }

  /// Moves focus to [zone]; false when the host holds no such zone or it
  /// cannot take focus now.
  bool requestFocus(T zone) {
    final state = _host?._zones[zone];
    if (state == null || !state.node.canRequestFocus) return false;
    state.node.requestFocus();
    return true;
  }

  /// What a presentation grows out of when it grows out of [zone]: a menu
  /// from a bar item, a popover from a segment. Pass it as the
  /// presentation's `source`.
  ///
  /// The same source is answered for a zone every time. Its geometry is
  /// the zone's frame where the host paints it now, in global coordinates
  /// (`InputZones.frameOf`, read again in every frame the presentation
  /// shows), and null while no host holds the controller or the zone is
  /// not painted. While a presentation holds it, [MotionSource.isHidden]
  /// is true and the controller notifies, so the control paints the zone
  /// hidden, as a `MotionSourceBox` does.
  MotionSource sourceOf(T zone) => _sources.putIfAbsent(zone, () {
    final source = MotionSource(debugLabel: 'zone $zone');
    source.showIn(_ZoneSource<T>(this, zone));
    return source;
  });

  // A presentation may let go of a zone's source after the control that
  // painted the zone disposed of its controller.
  bool _disposed = false;

  void _sourceHiddenChanged() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sources.clear();
    super.dispose();
  }

  void _publish(T zone, Set<WidgetState> states, {required bool notify}) {
    if (setEquals(_states[zone], states)) return;
    _states[zone] = states;
    if (!notify) return;
    notifyListeners();
    final listeners = _zoneListeners[zone];
    if (listeners == null) return;
    for (final listener in List.of(listeners)) {
      listener();
    }
  }

  void _forget(T zone) => _states.remove(zone);

  void _focus(T zone, {required bool focused}) {
    final now = focused ? zone : (_focused == zone ? null : _focused);
    if (now == _focused) return;
    _focused = now;
    notifyListeners();
  }
}

@immutable
final class _ZoneStates<T extends Object>
    implements ValueListenable<Set<WidgetState>> {
  const _ZoneStates(this._controller, this._zone);

  final InputZonesController<T> _controller;
  final T _zone;

  @override
  Set<WidgetState> get value => _controller._statesOf(_zone);

  @override
  void addListener(VoidCallback listener) =>
      _controller._zoneListeners.putIfAbsent(_zone, () => []).add(listener);

  @override
  void removeListener(VoidCallback listener) {
    final listeners = _controller._zoneListeners[_zone];
    if (listeners == null || !listeners.remove(listener)) return;
    if (listeners.isEmpty) _controller._zoneListeners.remove(_zone);
  }

  @override
  bool operator ==(Object other) =>
      other is _ZoneStates<T> &&
      identical(other._controller, _controller) &&
      other._zone == _zone;

  @override
  int get hashCode => Object.hash(identityHashCode(_controller), _zone);
}

/// Shows a zone's [MotionSource]: the zone's frame where its host paints
/// it now.
final class _ZoneSource<T extends Object> implements SourceView {
  _ZoneSource(this.controller, this.zone);

  final InputZonesController<T> controller;
  final T zone;

  @override
  SourceGeometry? get sourceGeometry {
    final host = controller._host;
    final box = host?._box;
    if (host == null || box == null || !box.attached || !box.hasSize) {
      return null;
    }
    final frame = host._frameOf(zone);
    if (frame == null ||
        frame.opacity < InputZoneFrame.minimumOpacity ||
        frame.rect.isEmpty) {
      return null;
    }
    return SourceGeometry(
      rect: MatrixUtils.transformRect(box.getTransformTo(null), frame.rect),
      radius: frame.radius,
    );
  }

  @override
  void sourceHiddenChanged() => controller._sourceHiddenChanged();
}

/// Gives each of the interactive [zones] a control paints inside [child]
/// what an `InputRegion` gives a box: touch, mouse, focus, keys,
/// semantics, states and haptics, while the zones move every frame.
///
/// UIKit: the controls and gesture recognizers of a view's subviews, hit
/// tested where their layers are. Flutter: no equivalent; a widget per
/// part with its own `InputRegion` comes closest, but its box only moves
/// with a relayout.
///
/// For the author of a control whose parts live in one render object that
/// moves them without rebuilding (a bar's items, an alert's actions, a
/// selector's segments, a menu's rows, a calendar's days, a row's swipe
/// buttons). The control names its parts once as [zones] and answers
/// [frameOf] from the same motion it paints with; [frames] notifies when
/// that motion moves, and the host then only refreshes the semantics and
/// focus rectangles: a frame of motion rebuilds no widget and lays out
/// nothing.
///
/// ```dart
/// InputZones<int>(
///   zones: [
///     for (final (i, item) in items.indexed)
///       InputZone(
///         id: i,
///         interactions: presses[i],
///         semantics: SemanticsProperties(label: item.label, button: true),
///         reach: const PressReach(minimumHit: Size.square(44)),
///       ),
///   ],
///   frameOf: (i) => InputZoneFrame(
///     motion.rectOf(i),
///     opacity: motion.alphaOf(i),
///   ),
///   frames: motion,
///   controller: zones,
///   child: CustomPaint(painter: ItemsPainter(motion, zones)),
/// )
/// ```
///
/// Touch: a pointer that lands on a zone (its rect, or its extension to
/// [InputZone.reach]) goes to that zone's interactions, mapped
/// into the zone's coordinates with the zone's rect at each event, so a
/// finger that rests on a moving zone stays inside it. Touches are stamped,
/// heard and taken to the gesture arena exactly as an `InputRegion`'s are:
/// one mechanism serves both. With [slides], a finger that moves onto
/// another zone moves the touch there: the zone it leaves gets a cancel,
/// the zone it enters a down at the finger, and [feedback] hears a
/// `ScrubChangeEvent` with the new zone; the touch then ends where the
/// finger lifts. This is how an alert's actions, a menu's rows and a tab
/// bar's items are scrubbed. With a [port], touches handed on from another
/// region arrive the same way, also onto no zone at first. The host's own
/// [interactions] hear each touch on the host whole, from down to up,
/// wherever the finger goes, and ask [InputZonesController.zoneAt] what
/// lies under it.
///
/// Mouse: each zone has its own cursor and hovered state, and hears hover
/// as `PointerHoverInput`s; a zone that moves under a resting mouse is
/// entered and left with the next frame. The secondary button and the
/// scroll wheel reach a zone's interactions that take them.
///
/// Focus: each zone has a focus node, made and disposed with the zone. A
/// zone can take focus while it is [InputZone.focusable] and takes input
/// now, and is a focus target for the keys while an interaction also
/// activates or adjusts. With [stops] at [InputZoneStops.each], Tab visits
/// the targets in the order of [zones] (other focusable widgets inside
/// [child] come after them); at [InputZoneStops.one] the host is a single
/// stop that Tab enters at [current] or at the zone focused last. Assistive
/// technology reaches every zone that can take focus either way. The arrows
/// move between targets: along [axis] in the order of [zones], mirrored in
/// right-to-left for a horizontal axis, or to the nearest zone on screen
/// when [axis] is null; Home and End reach the first and the last target.
/// With [activatesOnMove], the zone an arrow, Home or End moves to is also
/// activated, as a keyboard activation: a selection that follows focus. An
/// arrow with no zone in its direction (past the last one, or across
/// [axis]) asks [onEdge], then moves focus as Flutter's directional focus
/// does, which may leave the host. A zone whose interaction adjusts keeps
/// the arrows, Home and End for its value
/// (`AdjustValueIntent.defaultShortcuts`). Space and Enter activate the
/// focused zone through `ActivateIntent`, and the context menu key and
/// Shift+F10 open the context menu of a focused zone that has a secondary
/// click (`ContextMenuIntent`, at the zone's centre), which an app
/// overrides with `Actions` above the host, as for `InputRegion`; a region
/// around the host does not take them from a focused zone.
///
/// Semantics: each zone that is [InputZoneFrame.live] is one semantics
/// node over its hit rectangle, which follows [frameOf], with its label,
/// value, flags, enabled state, tap, increase and decrease, and focus. The
/// semantics of [child] are dropped unless [excludeChildSemantics] is
/// false, since the zones describe what the child paints.
///
/// Each zone is a render box of its hit rectangle's size, placed on the
/// zone by the host's paint transform: tests and tools find a zone where it
/// is painted (`tester.tap(find.bySemanticsLabel('Edit'))` taps it), and
/// its focus node reports its rectangle. A frame in which the zones only
/// move rebuilds and lays out nothing: the host refreshes the zones'
/// semantics and focus state, and the transform is read when a hit test,
/// the semantics or the focus ask. A zone that appears or changes size
/// lays out its own box alone (each is its own relayout boundary) at the
/// start of the next frame; until then the transform scales the box to the
/// zone, and a box still empty reports the zone's bounds to semantics and
/// focus.
///
/// A zone that is disabled takes nothing; a zone whose frame is null or
/// not [InputZoneFrame.live] is not hit, not focusable and not in the
/// semantics tree.
class InputZones<T extends Object> extends StatefulWidget {
  /// Hosts [zones] over [child].
  const InputZones({
    required this.zones,
    required this.frameOf,
    required this.frames,
    required this.child,
    this.controller,
    this.axis = Axis.horizontal,
    this.stops = InputZoneStops.each,
    this.current,
    this.activatesOnMove = false,
    this.slides = false,
    this.feedback,
    this.onEdge,
    this.port,
    this.excludeChildSemantics = true,
    this.interactions = const [],
    this.hostFeedback,
    super.key,
  });

  /// The zones, in their reading order.
  final List<InputZone<T>> zones;

  /// Where a zone lies now, in the host's coordinates, or null when it is
  /// not shown. Read at hit testing, for pointer events, and for the focus
  /// and semantics rectangles.
  ///
  /// The host reads each zone's frame once and keeps it until [frames]
  /// notifies or the host is built again, so a pointer event asks for a
  /// zone's frame at most once; while a frame lays out, paints and builds
  /// the semantics, it reads afresh at every use.
  final InputZoneFrame? Function(T zone) frameOf;

  /// Notifies when what [frameOf] answers changes: the motion the control
  /// paints with.
  final Listenable frames;

  /// What paints the zones.
  final Widget child;

  /// Where the host writes the zones' states and keeps their focus, or
  /// null for one of its own.
  final InputZonesController<T>? controller;

  /// The axis the arrows move along in the order of [zones], or null for a
  /// grid: an arrow then moves to the nearest zone it points at in the same
  /// row or column, one that overlaps the focused zone across the arrow by
  /// more than half. With none there (the blank cells before the first day
  /// of a month) the arrow asks [onEdge], which is where a grid carries on
  /// in reading order.
  final Axis? axis;

  /// Whether every zone that takes a key is a Tab stop, or the host is one.
  final InputZoneStops stops;

  /// The zone Tab enters a host of [InputZoneStops.one] at, such as the
  /// selected item; null, or a zone that cannot take focus now, enters at
  /// the zone focused last, else at the first.
  final T? current;

  /// Whether the zone an arrow, Home or End moves focus to is activated
  /// too, as a keyboard activation: a selection that follows focus, as in
  /// a radio group or a segmented control.
  final bool activatesOnMove;

  /// Whether a finger moves its touch onto the zone it slides onto.
  final bool slides;

  /// The haptic for an event of a zone, or null for none.
  ///
  /// As `InputRegion.feedback`: played as the event happens, never for a
  /// keyboard or accessibility activation, and not below a
  /// `MotionHapticScope` that turns haptics off.
  final MotionHaptic? Function(T zone, InteractionEvent event)? feedback;

  /// Called when an arrow finds no zone in its direction, with the focused
  /// zone; true when the control handled it (a calendar turning its
  /// month), false to let Flutter's directional focus move on.
  final bool Function(T zone, TraversalDirection direction)? onEdge;

  /// Where touches handed on from another region arrive, or null.
  final InputPort? port;

  /// Whether the semantics of [child] are dropped, leaving the zones'.
  final bool excludeChildSemantics;

  /// What hears the touches on the host as a whole, in the host's
  /// coordinates; when two recognize on one input, the first wins.
  ///
  /// They hear a touch that lands anywhere on the host, on a zone or
  /// between the zones, or arrives through [port], from its down to its
  /// release wherever the finger goes, beyond the host too, beside the
  /// zone the touch lands on. They hold or give up the touch in the gesture
  /// arena as an `InputRegion`'s interactions do, and hear the arena give
  /// it to the host ([PointerAcceptedInput]); an observer
  /// ([InteractionRole.observer]) stays out of it. A host interaction asks
  /// [InputZonesController.zoneAt] which zone lies under the finger: a
  /// finger that opened a menu slides over its rows and beyond its edge,
  /// and the menu follows it. They also hear the mouse moving over the
  /// host, as `PointerHoverInput`s with `inside` true. When one
  /// [Interaction.contendsWithControls], the controls inside [child] start
  /// their touches contested, as below an `InputRegion`. Keys and
  /// accessibility stay the zones'; the haptics of the host's interactions
  /// are [hostFeedback]'s.
  final List<Interaction> interactions;

  /// The haptic for an event of [interactions], or null for none.
  ///
  /// As [feedback]: played as the event happens, never for a keyboard or
  /// accessibility input, and not below a `MotionHapticScope` that turns
  /// haptics off. A menu plays its selection haptic for the row a sliding
  /// finger reaches this way.
  final MotionHaptic? Function(InteractionEvent event)? hostFeedback;

  @override
  State<InputZones<T>> createState() => _InputZonesState<T>();
}

class _InputZonesState<T extends Object> extends State<InputZones<T>> {
  InputZonesController<T>? _ownController;
  final Map<T, _ZoneState<T>> _zones = {};
  _RenderZones<T>? _box;
  late final _HostTarget<T> _base = _HostTarget<T>(this);
  late final _ZonesLine<T> _line = _ZonesLine<T>(this);
  late final FocusTraversalPolicy _policy = _ZonesTraversal<T>(this);
  NavigationMode? _navigation;
  T? _lastFocused;

  // The clock of the motions around the zones, so a touch's stamps and the
  // motions it drives share one time.
  late MotionClock _clock;

  InputZonesController<T> get controller =>
      widget.controller ?? (_ownController ??= InputZonesController<T>());

  @override
  void initState() {
    super.initState();
    controller._host = this;
    widget.frames.addListener(_framesChanged);
    FocusManager.instance.addHighlightModeListener(_highlightModeChanged);
    KeyboardUse.changes.addListener(_publish);
    _line.port = widget.port;
    _scheduleResize();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _clock = MotionClockScope.of(context);
    final navigation = MediaQuery.maybeNavigationModeOf(context);
    if (navigation == _navigation) return;
    _navigation = navigation;
    for (final zone in _zones.values) {
      zone._publishQuietly();
    }
  }

  @override
  void didUpdateWidget(InputZones<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _frames.clear();
    _scheduleResize();
    if (oldWidget.frames != widget.frames) {
      oldWidget.frames.removeListener(_framesChanged);
      widget.frames.addListener(_framesChanged);
    }
    if (oldWidget.controller != widget.controller) {
      final old = oldWidget.controller ?? _ownController;
      if (old != null && identical(old._host, this)) old._host = null;
      if (widget.controller != null) {
        _ownController?.dispose();
        _ownController = null;
      }
      controller._host = this;
      for (final zone in _zones.values) {
        zone._publishQuietly();
      }
    }
    _line.port = widget.port;
    _base.interactions = widget.interactions;
    assert(
      widget.zones.map((zone) => zone.id).toSet().length == widget.zones.length,
      'Every zone of an InputZones has its own id.',
    );
  }

  @override
  void dispose() {
    _line.dispose();
    _base.dispose();
    widget.frames.removeListener(_framesChanged);
    FocusManager.instance.removeHighlightModeListener(_highlightModeChanged);
    KeyboardUse.changes.removeListener(_publish);
    if (_resize case final id?) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(id);
    }
    if (identical(controller._host, this)) controller._host = null;
    _ownController?.dispose();
    super.dispose();
  }

  void _framesChanged() {
    _frames.clear();
    // The frames may change inside a layout (a bar measures its items in
    // its own), where a control's frames cannot be read: they are compared
    // at the start of the next frame instead.
    final laying =
        SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks;
    var resized = laying;
    for (final zone in _zones.values) {
      zone._syncNode();
      final anchor = zone._anchor;
      if (anchor == null || !anchor.attached) continue;
      resized = resized || anchor.wanted != zone.bounds.size;
      // An absent zone is out of the semantics tree; the host's update
      // drops a zone that leaves, and one that appears is described anew.
      final present = zone.present;
      if (present || zone._described) anchor.markNeedsSemanticsUpdate();
      zone._described = present;
    }
    _box?.markNeedsSemanticsUpdate();
    if (resized) _scheduleResize();
  }

  // A pointer event asks for the frames many times over (its hit test, the
  // zone under the finger, the zone's coordinates): a hundred calls for a
  // calendar's 42 days. A frame's layout may still move what a control
  // reads its frames from, so the phases of the frame are never served
  // from what was kept.
  final Map<T, InputZoneFrame?> _frames = {};

  InputZoneFrame? _frameOf(T zone) {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      return widget.frameOf(zone);
    }
    if (_frames.containsKey(zone)) return _frames[zone];
    return _frames[zone] = widget.frameOf(zone);
  }

  int? _resize;

  // An anchor is laid out to the size its zone had when the frame began: a
  // control reads its frames from its own boxes, which nothing may read
  // while the frame lays out. The host's transform scales an anchor to its
  // zone until then.
  void _scheduleResize() {
    _resize ??= SchedulerBinding.instance.scheduleFrameCallback((_) {
      _resize = null;
      if (!mounted) return;
      for (final zone in _zones.values) {
        final anchor = zone._anchor;
        if (anchor == null || !anchor.attached) continue;
        final wanted = zone.bounds.size;
        if (anchor.wanted == wanted) continue;
        anchor.wanted = wanted;
        anchor.markNeedsLayout();
      }
    });
  }

  /// The node Tab enters a host of one stop at: the current zone's, else
  /// the one focused last, else the first target's.
  FocusNode? _entry() {
    _ZoneState<T>? first;
    _ZoneState<T>? last;
    for (final zone in widget.zones) {
      final state = _zones[zone.id];
      if (state == null || !_traversable(state)) continue;
      if (zone.id == widget.current) return state.node;
      first ??= state;
      if (zone.id == _lastFocused) last = state;
    }
    return (last ?? first)?.node;
  }

  void _highlightModeChanged(FocusHighlightMode mode) => _publish();

  void _publish() {
    for (final zone in _zones.values) {
      zone.target.publish();
    }
  }

  /// The zone at [position]: the last zone in [InputZones.zones] whose
  /// rect holds it, else the last whose hit extension does. Disabled zones
  /// count, so they keep a touch from what lies below.
  _ZoneState<T>? _zoneAt(Offset position) {
    _ZoneState<T>? extended;
    for (final zone in widget.zones.reversed) {
      final state = _zones[zone.id];
      final frame = _frameOf(zone.id);
      if (state == null || frame == null || !frame.live) continue;
      if (frame.rect.contains(position)) return state;
      if (extended == null && zone.reach.takes(frame.rect).contains(position)) {
        extended = state;
      }
    }
    return extended;
  }

  void _pointer(PointerEvent event) {
    if (event is! PointerHoverEvent) return _line.pointer(event);
    if (widget.interactions.isNotEmpty) {
      _base.hover(event.localPosition, inside: true);
    }
    final zone = _zoneAt(event.localPosition);
    if (zone != null && zone.takesInput) {
      zone.target.hover(event.localPosition, inside: true);
    }
  }

  // What can take focus for the keys, whether or not Tab visits it.
  bool _traversable(_ZoneState<T> zone) =>
      zone.node.canRequestFocus && zone.target.acts;

  void _moveTo(_ZoneState<T> zone) {
    zone.node.requestFocus();
    if (widget.activatesOnMove && zone.target.activates) {
      zone.target.activate(ActivationSource.keyboard);
    }
  }

  void _moveFocus(_ZoneState<T> from, TraversalDirection direction) {
    final next = switch (widget.axis) {
      null => _nearest(from, direction),
      final axis => _along(from, direction, axis),
    };
    if (next != null) {
      _moveTo(next);
      return;
    }
    if (widget.onEdge?.call(from.id, direction) ?? false) return;
    from.node.focusInDirection(direction);
  }

  _ZoneState<T>? _along(
    _ZoneState<T> from,
    TraversalDirection direction,
    Axis axis,
  ) {
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    final step = switch ((axis, direction)) {
      (Axis.horizontal, TraversalDirection.right) => rtl ? -1 : 1,
      (Axis.horizontal, TraversalDirection.left) => rtl ? 1 : -1,
      (Axis.vertical, TraversalDirection.down) => 1,
      (Axis.vertical, TraversalDirection.up) => -1,
      _ => 0,
    };
    if (step == 0) return null;
    final zones = widget.zones;
    final start = zones.indexWhere((zone) => zone.id == from.id);
    if (start < 0) return null;
    for (var i = start + step; i >= 0 && i < zones.length; i += step) {
      final zone = _zones[zones[i].id];
      if (zone != null && _traversable(zone)) return zone;
    }
    return null;
  }

  // The nearest zone the arrow points at in the row or the column of
  // [from]: one that overlaps it across the arrow by more than half of the
  // smaller of the two. A zone further along in another row is not the next
  // one in reading order, so the arrow finds nothing there and the host is
  // asked ([InputZones.onEdge]).
  _ZoneState<T>? _nearest(_ZoneState<T> from, TraversalDirection direction) {
    final origin = from.frame?.rect;
    if (origin == null) return null;
    final horizontal =
        direction == TraversalDirection.left ||
        direction == TraversalDirection.right;
    _ZoneState<T>? best;
    var bestAlong = double.infinity;
    var bestAcross = double.infinity;
    for (final zone in _zones.values) {
      if (identical(zone, from) || !_traversable(zone)) continue;
      final rect = zone.frame?.rect;
      if (rect == null) continue;
      final shared = horizontal
          ? math.min(rect.bottom, origin.bottom) -
                math.max(rect.top, origin.top)
          : math.min(rect.right, origin.right) -
                math.max(rect.left, origin.left);
      final smaller = horizontal
          ? math.min(rect.height, origin.height)
          : math.min(rect.width, origin.width);
      if (shared <= smaller / 2) continue;
      final d = rect.center - origin.center;
      final (along, across) = switch (direction) {
        TraversalDirection.up => (-d.dy, d.dx.abs()),
        TraversalDirection.down => (d.dy, d.dx.abs()),
        TraversalDirection.left => (-d.dx, d.dy.abs()),
        TraversalDirection.right => (d.dx, d.dy.abs()),
      };
      if (along <= precisionErrorTolerance) continue;
      if (along < bestAlong || (along == bestAlong && across < bestAcross)) {
        best = zone;
        bestAlong = along;
        bestAcross = across;
      }
    }
    return best;
  }

  void _toEnd(_ZoneState<T> from, {required bool last}) {
    final order = [
      for (final zone in widget.zones)
        if (_zones[zone.id] case final state? when _traversable(state)) state,
    ];
    final target = last ? order.lastOrNull : order.firstOrNull;
    if (target != null && !identical(target, from)) _moveTo(target);
  }

  @override
  Widget build(BuildContext context) {
    final contends = _base.contendsWithControls;
    return FocusTraversalGroup(
      policy: _policy,
      child: _ZonesHost<T>(
        state: this,
        excludeChildSemantics: widget.excludeChildSemantics,
        children: [
          ContestScope(
            contested: ContestScope.of(context) || contends,
            child: widget.child,
          ),
          for (final (order, zone) in widget.zones.indexed)
            _Zone<T>(
              key: _ZoneKey<T>(zone.id),
              host: this,
              zone: zone,
              order: order,
            ),
        ],
      ),
    );
  }
}
