import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/src/raw/mirror.dart';
import 'package:apple_liquid_glass/src/raw/selector_values.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/widgets.dart';

part 'package:apple_liquid_glass/src/raw/selector_inputs.dart';
part 'package:apple_liquid_glass/src/raw/selector_frames.dart';
part 'package:apple_liquid_glass/src/raw/selector_nodes.dart';
part 'package:apple_liquid_glass/src/raw/selector_render.dart';
part 'package:apple_liquid_glass/src/raw/selector_row.dart';

/// A pick-one control with the measured selection lens of iOS 27 and no
/// look of its own: [builder] decides how it looks.
///
/// UIKit: `UISegmentedControl`, `UITabBar`. SwiftUI: `Picker` with
/// `.segmented`, `TabView`. Flutter: `CupertinoSlidingSegmentedControl`,
/// `NavigationBar`.
///
/// [motion] picks the UIKit control whose motion and geometry it takes. A
/// tap selects on release; a finger that drags lifts the lens into glass
/// and carries it, and the release selects where it lands. Everything the
/// lens does reaches the look through [GlassSelectorDetails.lens], so its
/// motion rebuilds neither builder; [itemBuilder] runs again for an item
/// whose own states change.
///
/// Each item is a target of its own for the keyboard and assistive
/// technology, 44 points tall at least: a button in a group of one choice
/// on a segmented control, a tab on a tab bar, read by [itemLabels]. The
/// group is one Tab stop, entered at the selected item; an arrow key moves
/// focus to the neighbouring item and selects it, mirrored in a
/// right-to-left context and skipping [disabledItems], and Home and End
/// move to the first and last item and select it. Space and Enter on the
/// focused item, which is the selected one, report [onReselected]. A tap
/// in an item's 44 point extension above or below the look reaches that
/// item. [focusNode] stands for the selector: focusing it focuses the
/// selected item. In a right-to-left context the items run from the right.
class RawGlassSelector extends StatefulWidget {
  /// Creates a selector of [itemCount] items.
  const RawGlassSelector({
    required this.itemCount,
    required this.selectedIndex,
    required this.onChanged,
    required this.itemBuilder,
    required this.builder,
    this.motion = GlassSelectorMotion.segmented,
    this.onReselected,
    this.disabledItems = const {},
    this.itemKeys,
    this.itemWidths,
    this.proportionalWidth = false,
    this.statesController,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    this.itemLabels,
    this.collapse,
    @internal this.hosted = false,
    super.key,
  }) : assert(
         itemKeys == null || itemKeys.length == itemCount,
         'One key per item.',
       ),
       assert(
         itemLabels == null || itemLabels.length == itemCount,
         'One label per item.',
       );

  /// The number of items.
  final int itemCount;

  /// What identifies each item across changes of the items, or null to
  /// identify them by position.
  ///
  /// When the items change inside `withSpring`, the items that stay slide
  /// to their new slots, new ones fade in, the ones that go fade out where
  /// they were, and the lens moves with its item; outside one the change
  /// jumps. Not measured: UIKit's animated `insertSegment`,
  /// `removeSegment` and `setItems` were not captured.
  final List<Object>? itemKeys;

  /// The selected item, clamped to the items, or null for none
  /// (`UISegmentedControl.noSegment`): the lens is hidden, and a tap
  /// selects on release and shows the lens at rest on its item, without
  /// travel or lift (how UIKit shows a first selection is not measured).
  final int? selectedIndex;

  /// Called with the item the user selects; with [onReselected] null too,
  /// the selector is disabled. A selector whose [selectedIndex] does not
  /// follow returns to it.
  final ValueChanged<int>? onChanged;

  /// Builds each item.
  final GlassSelectorItemBuilder itemBuilder;

  /// Builds the selector's look.
  final GlassSelectorBuilder builder;

  /// The UIKit control whose motion and geometry the selector takes.
  final GlassSelectorMotion motion;

  /// Called with the selected item when the user selects it again (UIKit's
  /// `tabBarController(_:didSelect:)` for the selected tab): a touch that
  /// lifts on it (on a tab bar, one that also went down on it), Space,
  /// Enter, or an accessibility tap.
  final ValueChanged<int>? onReselected;

  /// The items a touch, a key or accessibility cannot select (UIKit
  /// `setEnabled(_:forSegmentAt:)`).
  final Set<int> disabledItems;

  /// The width of each segment in points, or null in a slot to share the
  /// room with the others (UIKit `setWidth(_:forSegmentAt:)`); segmented
  /// only.
  final List<double?>? itemWidths;

  /// Whether segments are as wide as their items rather than equal (UIKit
  /// `apportionsSegmentWidthsByContent`); segmented only.
  final bool proportionalWidth;

  /// Where the selector publishes its states, or null for its own. The
  /// selector is its only writer: what else writes to it is written over.
  final WidgetStatesController? statesController;

  /// The selector's focus node, or null for its own.
  final FocusNode? focusNode;

  /// Whether the selector takes focus when it first appears.
  final bool autofocus;

  /// What accessibility reads for the selector as a whole.
  final String? semanticLabel;

  /// What accessibility reads for each item, or null for none; the items'
  /// own semantics are not read.
  final List<String?>? itemLabels;

  /// What collapses a tab bar into a circle, or null; a bar under one has a
  /// box as wide as it is given and draws its glass where the collapse
  /// says.
  final GlassSelectorCollapse? collapse;

  /// Whether a tab bar hosts an accessory or a search, which makes it span
  /// the width it is given whatever its tabs.
  @internal
  final bool hosted;

  // The app's selection among the items; what the selector shows is its
  // motion's.
  int? get _selected {
    final index = selectedIndex;
    if (index == null || itemCount == 0) return null;
    return index.clamp(0, itemCount - 1);
  }

  @override
  State<RawGlassSelector> createState() => _RawGlassSelectorState();
}

class _RawGlassSelectorState extends State<RawGlassSelector>
    with ControlStates<RawGlassSelector>, ControlledValue<RawGlassSelector> {
  late SelectorMotion _motion = _create(widget.selectedIndex ?? 0);
  late _SelectorFrames _frames = _SelectorFrames(
    _motion,
    mirrored: false,
    collapse: widget.collapse,
  );
  late Listenable _zoneFrames = _zoneFramesOf(_frames);
  bool _fingerOnCircle = false;
  late final _SelectorInput _input = _SelectorInput(this);
  late final List<Interaction> _interactions = [_input];
  final _zones = InputZonesController<Object>();
  final Map<Object, List<Interaction>> _presses = {};
  bool _rtl = false;
  final _lensContent = ValueNotifier<GlassLensContent?>(null);
  late List<Object> _keys = _keysOf(widget);
  // Items gone from the widget that still fade out where they were, and
  // the last children each item built, which a fading item keeps.
  final List<Object> _ghosts = [];
  final Map<Object, List<Widget>> _built = {};
  bool _noneDown = false;
  PressReach _reach = PressReach.box;
  int? _downSlot;
  int? _downSelected;

  @override
  WidgetStatesController? get givenStates => widget.statesController;

  @override
  MotionClock get valueClock => _motion.clock;

  @override
  bool get userLeads => _input.active;

  @override
  void followWidget() {
    final selected = widget._selected;
    if (selected != null && _motion.selected != selected) {
      _motion.choose(_now, selected, notify: false);
    }
  }

  bool get _segmented => widget.motion == GlassSelectorMotion.segmented;

  bool _selectable(int index) =>
      enabled &&
      index >= 0 &&
      index < widget.itemCount &&
      !widget.disabledItems.contains(index);

  static List<Object> _keysOf(RawGlassSelector widget) =>
      widget.itemKeys ?? [for (var i = 0; i < widget.itemCount; i++) i];

  SelectorMotion _create(int selected) => SelectorMotion(
    kind: widget.motion,
    selected: selected,
    isSelectable: _selectable,
    onEvent: _deliver,
  );

  static Listenable _zoneFramesOf(_SelectorFrames frames) => Listenable.merge([
    _HeardInResolve(frames.items),
    ?frames.collapse?.morph,
  ]);

  double get _now => _motion.clock.now;

  @override
  void initState() {
    super.initState();
    _zones.addListener(_restateParts);
    _frames.placed.addListener(_placedChanged);
  }

  @override
  void didUpdateWidget(RawGlassSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.motion != _motion.kind) {
      _motion = _create(_motion.selected);
      _setFrames(_frames.mirrored);
    } else if (!identical(widget.collapse, _frames.collapse)) {
      _setFrames(_frames.mirrored);
    }
    final keys = _keysOf(widget);
    final wasNone = oldWidget.selectedIndex == null;
    if (listEquals(keys, _keys)) {
      _sync(wasNone);
    } else {
      final present = keys.toSet();
      for (final key in _keys) {
        if (!present.contains(key) &&
            _built.containsKey(key) &&
            !_ghosts.contains(key)) {
          _ghosts.add(key);
        }
      }
      _ghosts.removeWhere(present.contains);
      _built.removeWhere(
        (key, _) => !present.contains(key) && !_ghosts.contains(key),
      );
      _presses.removeWhere((key, _) => !present.contains(key));
      _keys = keys;
      final selected = widget._selected;
      if (selected != null && !wasNone) {
        _motion.selected = selected;
      } else {
        _sync(wasNone);
      }
    }
  }

  @override
  void dispose() {
    _zones.removeListener(_restateParts);
    _zones.dispose();
    _frames.placed.removeListener(_placedChanged);
    _lensContent.dispose();
    super.dispose();
  }

  @override
  bool get enabled => widget.onChanged != null || widget.onReselected != null;

  void _restateParts() => restate(
    live: {
      if (_input.pressed) WidgetState.pressed,
      if (_input.dragged) WidgetState.dragged,
      for (final key in _keys)
        for (final state in _zones.states(key).value)
          if (state == WidgetState.hovered || state == WidgetState.focused)
            state,
    },
  );

  // An item that faded out leaves the children it kept: once, when the
  // motion lets it go, not each frame.
  void _placedChanged() {
    if (_ghosts.any((key) => !_motion.items.contains(key))) setState(() {});
  }

  void _setFrames(bool mirrored) {
    _frames.placed.removeListener(_placedChanged);
    _frames = _SelectorFrames(
      _motion,
      mirrored: mirrored,
      collapse: widget.collapse,
    );
    _zoneFrames = _zoneFramesOf(_frames);
    _frames.placed.addListener(_placedChanged);
  }

  void _sync(bool wasNone) {
    final selected = widget._selected;
    if (selected == null) return;
    if (wasNone) {
      _motion.place(_now, selected);
    } else if (_motion.selected != selected) {
      _motion.choose(_now, selected, notify: false);
    }
  }

  void _deliver(LensEvent event) {
    switch (event) {
      case LensSelected(:final index):
        _chosen(index);
    }
  }

  void _chosen(int index) => tellApp(() {
    if (index != widget.selectedIndex) widget.onChanged?.call(index);
  });

  void _select(int index) {
    if (!_selectable(index)) return;
    final selected = widget._selected;
    if (selected == null) {
      _motion.place(_now, index);
      _chosen(index);
    } else if (index == selected) {
      widget.onReselected?.call(index);
    } else {
      _motion.choose(_now, index);
    }
  }

  double _x(Offset position) =>
      _rtl ? _motion.size.width - position.dx : position.dx;

  bool _releaseSelects(PointerUpInput input) =>
      !_segmented || _reach.holds(input.regionBox, input.position);

  void _down(PointerDownInput input) {
    _reach = input.reach;
    final collapse = widget.collapse;
    if (collapse != null && collapse.takesFinger) {
      _fingerOnCircle = true;
      collapse.pressDown(input.time, input.position.dx);
      return;
    }
    final x = _x(input.position);
    final slot = _motion.slotAt(x);
    final selected = widget._selected;
    if (_segmented && _selectable(slot) && slot != selected) {
      _motion.highlight.press(input.time, slot);
    }
    if (selected == null) {
      _noneDown = true;
      return;
    }
    _downSlot = slot;
    _downSelected = _motion.selected;
    _motion.down(input.time, x, input.position, glows: _selectable(slot));
  }

  void _move(PointerMoveInput input) {
    if (_fingerOnCircle) {
      if (!widget.collapse!.pressMove(input.time, input.position.dx)) return;
      _fingerOnCircle = false;
      _motion.drag(input.time, _x(input.position), input.position);
    }
    if (_noneDown) return;
    _motion.move(input.time, _x(input.position), input.position);
  }

  void _up(PointerUpInput input) {
    returnUnlessFollowed();
    if (_fingerOnCircle) {
      _fingerOnCircle = false;
      widget.collapse!.pressUp(input.time);
      return;
    }
    final x = _x(input.position);
    final slot = _motion.slotAt(x);
    final before = _downSelected;
    final down = _downSlot;
    _downSlot = null;
    _downSelected = null;
    if (_noneDown) {
      _noneDown = false;
      _motion.cancel(input.time);
      if (_releaseSelects(input)) _select(slot);
      return;
    }
    if (!_releaseSelects(input)) {
      _motion.cancel(input.time);
      return;
    }
    _motion.up(input.time, x);
    final reselected =
        before != null &&
        slot == before &&
        _motion.selected == before &&
        (_segmented || down == before);
    if (reselected && _selectable(before)) widget.onReselected?.call(before);
  }

  void _cancel(double time) {
    returnUnlessFollowed();
    if (_fingerOnCircle) {
      _fingerOnCircle = false;
      widget.collapse!.pressCancel(time);
      return;
    }
    _noneDown = false;
    _downSlot = null;
    _downSelected = null;
    _motion.cancel(time);
  }

  void _activate(Object key) {
    final collapse = widget.collapse;
    if (collapse != null && collapse.takesFinger) {
      collapse.activate();
      return;
    }
    final index = _keys.indexOf(key);
    if (index >= 0) _select(index);
  }

  void _focusSelected(bool focused) {
    if (!focused || !(widget.focusNode?.hasPrimaryFocus ?? false)) return;
    final selected = widget._selected;
    final index = selected != null && _selectable(selected)
        ? selected
        : Iterable<int>.generate(widget.itemCount)
              .where(_selectable)
              .firstOrNull;
    if (index != null) _zones.requestFocus(_keys[index]);
  }

  // The selected item is the one the lens shows; when a collapse holds the
  // finger, it is the circle and the only item there is.
  InputZoneFrame? _zoneFrame(Object key) {
    final collapse = widget.collapse;
    if (collapse != null && collapse.takesFinger) {
      final selected = widget._selected;
      if (selected == null || _keys[selected] != key) return null;
      return InputZoneFrame(collapse.circleIn(_motion.size));
    }
    final drawn = _motion.drawn(key);
    if (drawn == null) return null;
    final (rect, opacity) = drawn;
    return InputZoneFrame(rect, opacity: opacity);
  }

  List<InputZone<Object>> _zoneList() {
    final selected = widget._selected;
    return [
      for (final (i, key) in _keys.indexed)
        InputZone<Object>(
          id: key,
          interactions: _presses[key] ??= [_ItemPress(() => _activate(key))],
          enabled: _selectable(i),
          reach: glassTargetReach,
          autofocus: widget.autofocus && i == (selected ?? 0),
          semantics: SemanticsProperties(
            label: widget.itemLabels?[i],
            button: _segmented ? true : null,
            selected: i == selected,
            inMutuallyExclusiveGroup: _segmented ? true : null,
            role: _segmented ? null : SemanticsRole.tab,
          ),
        ),
    ];
  }

  Widget _item(BuildContext context, int index, {required bool selected}) =>
      _ItemStates(
        zones: _zones,
        id: _keys[index],
        own: {
          if (selected) WidgetState.selected,
          if (!_selectable(index)) WidgetState.disabled,
        },
        builder: (context, states) =>
            Center(child: widget.itemBuilder(context, index, states)),
      );

  List<Widget> _build(BuildContext context, int index) {
    final key = _keys[index];
    return _built[key] = [
      RepaintBoundary(
        key: ValueKey((0, key)),
        child: _item(context, index, selected: false),
      ),
      RepaintBoundary(
        key: ValueKey((1, key)),
        child: _item(context, index, selected: true),
      ),
    ];
  }

  Widget _items(BuildContext context, Widget? lens) {
    final selected = widget._selected;
    final zones = InputZones<Object>(
      zones: _zoneList(),
      frameOf: _zoneFrame,
      frames: _zoneFrames,
      controller: _zones,
      stops: InputZoneStops.one,
      current: selected == null ? null : _keys[selected],
      activatesOnMove: true,
      child: _SelectorRow(
        motion: _motion,
        frames: _frames,
        kind: widget.motion,
        keys: _keys,
        ghosts: List.of(_ghosts),
        itemWidths: widget.itemWidths,
        proportional: widget.proportionalWidth,
        collapse: widget.collapse,
        hosted: widget.hosted,
        showsLens: selected != null,
        hasLens: lens != null,
        lensContent: _lensContent,
        children: [
          for (var i = 0; i < _keys.length; i++) ..._build(context, i),
          for (final key in _ghosts) ..._built[key]!,
          ?lens,
        ],
      ),
    );
    if (_segmented) return zones;
    return _TabBarNode(
      frames: _zoneFrames,
      hasTabs: () => _keys.any((key) => _zoneFrame(key)?.live ?? false),
      child: zones,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    if (_rtl != _frames.mirrored) _setFrames(_rtl);
  }

  @override
  Widget buildControl(BuildContext context) {
    _ghosts.removeWhere((key) {
      if (_motion.items.contains(key)) return false;
      _built.remove(key);
      return true;
    });
    final look = widget.builder(
      context,
      GlassSelectorDetails(
        body: _frames.body,
        lens: _frames.lens,
        items: (lens) => _items(context, lens),
        selectedIndex: widget._selected,
        states: {...widgetStates.value},
        lensContent: _lensContent,
      ),
    );
    // The lens drag lies above the look, so its 44 point target reaches
    // past the look's box and hands an item the nearest point of it; it
    // takes no key, so the focused item keeps Space and Enter.
    final dragged = InputRegion(
      interactions: _interactions,
      enabled: enabled && widget.itemCount > 0,
      reach: glassButtonReach,
      child: look,
    );
    Widget child = _SelectorBox(
      frame: widget.collapse == null ? null : _frames.body,
      label: widget.semanticLabel,
      child: _segmented
          ? dragged
          : MotionTransition(
              offset: _frames.drift,
              scaleX: _frames.scaleX,
              scaleY: _frames.scaleY,
              child: dragged,
            ),
    );
    if (widget.focusNode case final node?) {
      // The app's node stands for the selector: focusing it focuses the
      // selected item.
      child = Focus(
        focusNode: node,
        skipTraversal: true,
        includeSemantics: false,
        onFocusChange: _focusSelected,
        child: child,
      );
    }
    return MotionScope(motion: _motion, child: child);
  }
}
