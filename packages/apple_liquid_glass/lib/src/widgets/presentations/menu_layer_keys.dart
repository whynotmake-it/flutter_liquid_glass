import 'dart:ui' as ui;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/src/widgets/presentations/menu_entries.dart';
import 'package:apple_liquid_glass/src/widgets/presentations/menu_layer_scope.dart';
import 'package:apple_liquid_glass/src/widgets/presentations/menu_layer_scroll.dart';
import 'package:apple_liquid_glass/src/widgets/presentations/menu_zone_ids.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

/// The keyboard and focus of an open menu's top card: its rows as zones,
/// the focus that highlights a row, choosing and going back, and the row
/// the focus moves to when a key changes the card.
@internal
class MenuLayerKeys {
  /// Creates the keys of the layer it is given, whose top card's rows are
  /// the zones of [zones] under [ids].
  MenuLayerKeys(
    this._layer, {
    required this.zones,
    required this.ids,
    required this.scroll,
  });

  final MenuLayerScope _layer;

  /// The zones of the top card's rows.
  final InputZonesController<int> zones;

  /// The ids of those zones.
  final MenuZoneIds ids;

  /// The root list's scrolling, which reveals the focused row.
  final MenuLayerScroll scroll;

  // The row of the next top card the keyboard moves to: -1 for its first
  // row, else a target index; null when no key changed the card.
  int? _pending;
  int? _lastFocused;

  /// The top card is now [top]: the focus a key asked for moves onto its
  /// row, carried by the zone that has the focus.
  void cardChanged(int top) {
    final pending = _pending;
    _pending = null;
    final focused = zones.focusedZone;
    ids.clear();
    if (pending == null || focused == null) return;
    final targets = _layer.motion.cards[top].layout.targets;
    var target = pending;
    if (pending < 0) {
      target = targets.indexWhere(
        (MenuTarget t) => t.kind != MenuTargetKind.back,
      );
      if (target < 0) target = 0;
    }
    if (target >= targets.length || target == focused) return;
    ids.swap(focused, target);
  }

  /// Chooses [index] of the top card; [pending] is where the focus moves
  /// when that changes the card, or null to leave it.
  void choose(int index, {int? pending}) {
    if (!_layer.current) return;
    final built = _layer.built;
    final target = built.targetAt(index);
    if (target == null) return;
    _pending = switch (target.kind) {
      MenuTargetKind.submenu => pending,
      MenuTargetKind.back =>
        pending == null ? null : _layer.motion.cards[built.top].source,
      MenuTargetKind.action => null,
    };
    _layer.command((motion, t) => motion.select(t, index));
  }

  /// Sends the top submenu card back; with [keys] the focus moves to the
  /// row it grew out of.
  void back({required bool keys}) {
    final top = _layer.built.top;
    if (!_layer.current || top == 0) return;
    if (keys) _pending = _layer.motion.cards[top].source;
    _layer.command((motion, t) => motion.back(t));
  }

  /// The focus moved among the zones: the motion highlights the focused
  /// row, which the root list reveals.
  void focusMoved() {
    final id = zones.focusedZone;
    if (id == _lastFocused) return;
    _lastFocused = id;
    if (id == null || !_layer.current) return;
    final index = ids.targetOf(id);
    final motion = _layer.motion;
    if (motion.highlighted != index ||
        motion.highlightedCard != _layer.built.top) {
      _layer.command((motion, t) => motion.highlight(t, index));
    }
    scroll.reveal(index);
  }

  /// The menu took the focus: under the keyboard its first row has it.
  void menuFocused() {
    if (!KeyboardUse.inUse) return;
    final built = _layer.built;
    if (built.layouts[built.top].targets.isEmpty) return;
    zones.requestFocus(ids.idOf(0));
  }

  /// An arrow past zone [id] toward [direction]: the one toward the
  /// trailing edge opens a submenu row's card, the one toward the leading
  /// edge goes back; past the first or the last row the focus stays.
  bool edge(int id, TraversalDirection direction) {
    final rtl = _layer.content.rtl;
    final into = rtl ? TraversalDirection.left : TraversalDirection.right;
    final out = rtl ? TraversalDirection.right : TraversalDirection.left;
    final index = ids.targetOf(id);
    if (direction == into &&
        _layer.built.targetAt(index)?.kind == MenuTargetKind.submenu) {
      choose(index, pending: -1);
    } else if (direction == out) {
      back(keys: true);
    }
    return true;
  }

  /// Where zone [id] is now, or null while it stands for no row.
  InputZoneFrame? frameOf(int id) {
    if (!_layer.current) return null;
    final rect = _layer.motion.targetRect(ids.targetOf(id));
    return rect == null ? null : InputZoneFrame(rect);
  }

  /// The zones of [layout]'s rows, each with the interactions [inputsOf]
  /// gives its id and the semantics of its entry.
  List<InputZone<int>> zonesOf(
    MenuLayout layout,
    List<Interaction> Function(int id) inputsOf,
  ) {
    final result = <InputZone<int>>[];
    for (var i = 0; i < layout.targets.length; i++) {
      final target = layout.targets[i];
      final element = target.element < 0
          ? null
          : layout.elements[target.element];
      final id = ids.idOf(i);
      final entry = target.entry;
      final (String label, String? value) = switch (entry) {
        GlassMenuItem(:final title, :final subtitle) ||
        GlassSubmenu(:final title, :final subtitle) => (title, subtitle),
        _ => (element?.title ?? '', null),
      };
      final state = entry is GlassMenuItem ? entry.state : null;
      final checkable = state != null && state != GlassMenuItemState.off;
      result.add(
        InputZone<int>(
          id: id,
          interactions: inputsOf(id),
          reach: glassTargetReach,
          semantics: SemanticsProperties(
            label: label,
            value: value,
            button: true,
            checked: checkable ? state == GlassMenuItemState.on : null,
            mixed:
                target.kind == MenuTargetKind.action &&
                    state == GlassMenuItemState.mixed
                ? true
                : null,
            expanded: switch (target.kind) {
              MenuTargetKind.submenu => false,
              MenuTargetKind.back => true,
              MenuTargetKind.action => null,
            },
            role: checkable
                ? ui.SemanticsRole.menuItemCheckbox
                : ui.SemanticsRole.menuItem,
          ),
        ),
      );
    }
    return result;
  }
}
