import 'dart:ui' show Tristate;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

/// One rule of the bar, run for every entry it applies to.
final class Check {
  /// A check named [name] that runs [run] on the entries [applies] accepts.
  const Check(this.name, this.applies, this.run);

  /// The stable name used in `known_failures.txt`.
  final String name;

  /// Whether the check applies to an entry.
  final bool Function(Entry entry) applies;

  /// Throws when the entry fails the check.
  final Future<void> Function(WidgetTester tester, Entry entry) run;
}

/// The checks, in the order they are reported.
const List<Check> checks = [
  Check('zero-size', _all, _zeroSize),
  Check('rtl-text-scale-2', _all, _rtlTextScale),
  Check('semantics-label', _all, _label),
  Check('semantics-role', _all, _role),
  Check('semantics-disabled', _disables, _disabled),
  Check('semantics-actions', _acts, _actions),
  Check('tap-target', _all, _tapTarget),
  Check('focus-disabled', _disables, _focusDisabled),
  Check('tab-stops', _inline, _tabStops),
  Check('focus-indicator', _inline, _focusIndicator),
  Check('key-activate', _keyActivates, _keyActivate),
  Check('key-remap', _keyRemaps, _keyRemap),
  Check('key-arrows', _steps, _keyArrows),
  Check('key-arrows-rtl', _steps, _keyArrowsRtl),
  Check('key-home-end', _steps, _keyHomeEnd),
  Check('key-arrows-edge', _pages, _keyArrowsEdge),
  Check('key-escape', _presents, _keyEscape),
  Check('key-remap-dismiss', _presents, _keyRemapDismiss),
  Check('key-context-menu', _contextMenu, _keyContextMenu),
  Check('mouse-cursor', _inline, _cursor),
  Check('mouse-hover', _inline, _hover),
  Check('mouse-secondary-click', _contextMenu, _secondaryClick),
  Check('mouse-wheel', _values, _wheel),
  Check('haptics-gesture-only', _acts, _hapticsGestureOnly),
  Check('contrast-light', _ownLook, _contrastLight),
  Check('contrast-dark', _ownLook, _contrastDark),
  Check('overlay-focus-in', _presents, _overlayFocusIn),
  Check('overlay-focus-return', _presents, _overlayFocusReturn),
  Check('barrier-hides-behind', _presents, _barrierHides),
  Check('barrier-label', _dismissible, _barrierLabel),
  Check('overlay-inert-closing', _presents, _inertClosing),
];

/// The name of the leak check, run apart because leaks are collected after
/// every test of the file has run.
const String leakCheck = 'no-leaks';

bool _all(Entry e) => true;

bool _inline(Entry e) => e.kind != Kind.overlay;

bool _ownLook(Entry e) => e.look == Look.own;

bool _disables(Entry e) => e.canDisable && e.kind != Kind.overlay;

bool _acts(Entry e) => e.kind != Kind.overlay && e.kind != Kind.textInput;

bool _keyActivates(Entry e) =>
    (e.activates || e.kind == Kind.value) && !e.contextMenu;

bool _keyRemaps(Entry e) => e.activates && !e.contextMenu;

bool _steps(Entry e) =>
    e.kind == Kind.value || e.kind == Kind.selection || e.kind == Kind.grid;

bool _pages(Entry e) => e.kind == Kind.grid && e.pages;

bool _values(Entry e) => e.kind == Kind.value;

bool _presents(Entry e) => e.presents;

bool _dismissible(Entry e) => e.presents && e.dismissible;

bool _contextMenu(Entry e) => e.contextMenu;

Future<Probe> _fresh(
  WidgetTester tester,
  Entry entry, {
  bool enabled = true,
  Brightness brightness = Brightness.light,
  TextDirection direction = TextDirection.ltr,
  double textScale = 1,
  Map<ShortcutActivator, Intent>? shortcuts,
}) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
  return pumpEntry(
    tester,
    entry,
    enabled: enabled,
    brightness: brightness,
    direction: direction,
    textScale: textScale,
    shortcuts: shortcuts,
  );
}

Offset _aim(WidgetTester tester, Entry entry) =>
    tester.getCenter((entry.part ?? subject).first);

bool _activated(Entry entry, Probe probe) => entry.kind == Kind.opener
    ? entry.marker!.evaluate().isNotEmpty
    : probe.events.isNotEmpty;

Rect _boxOf(FocusNode node) {
  final box = node.context?.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return Rect.zero;
  // A zone's stop is an empty box whose paint bounds are the zone's rect.
  return node.rect;
}

/// Focuses the Tab stop under the entry's part, or its first Tab stop.
Future<bool> _focus(WidgetTester tester, Entry entry) async {
  final stops = await tabStops(tester);
  if (stops.isEmpty) return false;
  var stop = stops.first;
  if (entry.part != null) {
    final aim = _aim(tester, entry);
    final under = stops.where((node) => _boxOf(node).contains(aim));
    if (under.isEmpty) return false;
    stop = under.reduce(
      (a, b) =>
          _boxOf(a).size.longestSide <= _boxOf(b).size.longestSide ? a : b,
    );
  }
  stop.requestFocus();
  await settle(tester, 10);
  return true;
}

Future<void> _focusOrFail(WidgetTester tester, Entry entry) async {
  if (!await _focus(tester, entry)) {
    throw TestFailure(
      entry.part == null
          ? 'Tab reaches no part of it'
          : 'Tab does not reach the part',
    );
  }
}

SemanticsNode? _nodeAt(WidgetTester tester, Offset point, {bool tap = true}) {
  SemanticsNode? best;
  for (final node in subjectNodes(tester)) {
    final data = node.getSemanticsData();
    final acts = tap
        ? data.hasAction(SemanticsAction.tap) ||
              data.hasAction(SemanticsAction.longPress)
        : data.hasAction(SemanticsAction.increase) ||
              data.hasAction(SemanticsAction.decrease);
    if (!acts) continue;
    final rect = globalRect(tester, node);
    if (!rect.contains(point)) continue;
    if (best == null ||
        rect.size.longestSide < globalRect(tester, best).size.longestSide) {
      best = node;
    }
  }
  return best;
}

int _compare(Object? a, Object? b) => (a! as Comparable<Object?>).compareTo(b);

List<SemanticsNode> _items(WidgetTester tester) => [
  for (final node in subjectNodes(tester))
    if (node.getSemanticsData().flagsCollection.isSelected != Tristate.none &&
        node.getSemanticsData().hasAction(SemanticsAction.tap))
      node,
];

String _guidelineReason(String reason) {
  final first = reason.split('\n').first;
  final label = RegExp('label: "([^"]*)"').firstMatch(first)?.group(1);
  final flat = reason.replaceAll(RegExp(r'\s+'), ' ');
  final at = flat.indexOf('xpected');
  var text = at > 0 ? 'e${flat.substring(at)}' : flat;
  final end = text.indexOf(RegExp(r'\.( |$)| See also'));
  if (end > 0) text = text.substring(0, end);
  return label == null ? text : '"$label": $text';
}

Future<void> _guideline(
  WidgetTester tester,
  AccessibilityGuideline guideline,
) async {
  final result = await guideline.evaluate(tester);
  if (!result.passed) throw TestFailure(_guidelineReason(result.reason!));
}

Future<void> _zeroSize(WidgetTester tester, Entry entry) async {
  usePhone(tester);
  for (final size in const [Size.zero, Size(1, 1)]) {
    await tester.pumpWidget(app(entry, Probe(), box: size));
    await settle(tester, 10);
  }
}

Future<void> _rtlTextScale(WidgetTester tester, Entry entry) async {
  final probe = await pumpEntry(
    tester,
    entry,
    direction: TextDirection.rtl,
    textScale: 2,
  );
  if (entry.presents) await present(tester, entry, probe);
}

Future<void> _label(WidgetTester tester, Entry entry) async {
  final probe = await pumpEntry(tester, entry);
  if (entry.presents) await present(tester, entry, probe);
  await _guideline(tester, labeledTapTargetGuideline);
  for (final node in subjectNodes(tester)) {
    final data = node.getSemanticsData();
    if ((data.hasAction(SemanticsAction.increase) ||
            data.hasAction(SemanticsAction.decrease)) &&
        data.label.isEmpty) {
      throw TestFailure(
        'an adjustable node valued "${data.value}" has no semantic label',
      );
    }
  }
}

Future<void> _tapTarget(WidgetTester tester, Entry entry) async {
  final probe = await pumpEntry(tester, entry);
  if (entry.presents) await present(tester, entry, probe);
  await _guideline(tester, iOSTapTargetGuideline);
  for (final node in subjectNodes(tester)) {
    final data = node.getSemanticsData();
    if (!data.hasAction(SemanticsAction.increase) &&
        !data.hasAction(SemanticsAction.decrease)) {
      continue;
    }
    final size = globalRect(tester, node).size;
    if (size.width < 44 - _slack || size.height < 44 - _slack) {
      throw TestFailure(
        '"${data.label}": expected an adjustable target of at least '
        'Size(44.0, 44.0), but found $size',
      );
    }
  }
}

const double _slack = 0.01;

Future<void> _contrast(
  WidgetTester tester,
  Entry entry,
  Brightness brightness,
) async {
  final probe = await pumpEntry(tester, entry, brightness: brightness);
  if (entry.presents) await present(tester, entry, probe);
  final result = await textContrastGuideline.evaluate(tester);
  if (result.passed) return;
  final failures = [
    for (final failure in result.reason!.split(
      RegExp(r'\n(?=SemanticsNode#)'),
    ))
      if (!_boldEnough(tester, failure)) failure,
  ];
  if (failures.isNotEmpty) {
    throw TestFailure(_guidelineReason(failures.join('\n')));
  }
}

// Apple's minimum text contrast (Human Interface Guidelines, Accessibility:
// the WCAG AA values Accessibility Inspector applies) is 4.5 up to 17
// points and 3 from 18 points and for bold text at any size. Flutter's
// guideline grants 3 to bold text only at exactly FontWeight.bold from 14
// points, while Apple's type styles carry their emphasis as semibold (the
// Headline style, a grouped list's header): such text is held to 3 here.
const double _boldContrast = 3;

bool _boldEnough(WidgetTester tester, String failure) {
  final label = RegExp('label: "([^"]*)"').firstMatch(failure)?.group(1);
  final found = double.tryParse(
    RegExp(r'but found ([\d.]+)').firstMatch(failure)?.group(1) ?? '',
  );
  if (label == null || found == null || found < _boldContrast) return false;
  final texts = find.text(label).evaluate();
  if (texts.isEmpty) return false;
  for (final element in texts) {
    final style = switch (element.widget) {
      Text(:final style) when style != null && !style.inherit => style,
      Text(:final style) => DefaultTextStyle.of(element).style.merge(style),
      _ => null,
    };
    final weight = style?.fontWeight ?? FontWeight.normal;
    if (weight.value < FontWeight.w600.value) return false;
  }
  return true;
}

Future<void> _contrastLight(WidgetTester tester, Entry entry) =>
    _contrast(tester, entry, Brightness.light);

Future<void> _contrastDark(WidgetTester tester, Entry entry) =>
    _contrast(tester, entry, Brightness.dark);

Future<void> _role(WidgetTester tester, Entry entry) async {
  final probe = await pumpEntry(tester, entry);
  if (entry.kind == Kind.overlay) await present(tester, entry, probe);
  final nodes = subjectNodes(tester);
  final data = [for (final node in nodes) node.getSemanticsData()];
  final header = entry.header;
  if (header != null &&
      !data.any(
        (d) => d.label.contains(header) && d.flagsCollection.isHeader,
      )) {
    throw TestFailure('"$header" is not announced as a header');
  }
  switch (entry.kind) {
    case Kind.pressable || Kind.opener:
      if (entry.contextMenu) {
        if (!data.any((d) => d.hasAction(SemanticsAction.longPress))) {
          throw TestFailure('nothing offers the long press that opens it');
        }
        return;
      }
      final tappable = [
        for (final d in data)
          if (d.hasAction(SemanticsAction.tap)) d,
      ];
      if (tappable.isEmpty) throw TestFailure('nothing offers a tap');
      for (final d in tappable) {
        final f = d.flagsCollection;
        if (!f.isButton && !f.isTextField && !f.isLink) {
          throw TestFailure('"${d.label}" offers a tap but is not a button');
        }
      }
    case Kind.toggle:
      if (!data.any((d) => d.flagsCollection.isToggled != Tristate.none)) {
        throw TestFailure('nothing is announced as toggled or not');
      }
    case Kind.value:
      final adjustable = data.where(
        (d) =>
            d.value.isNotEmpty &&
            d.hasAction(SemanticsAction.increase) &&
            d.hasAction(SemanticsAction.decrease),
      );
      if (adjustable.isEmpty) {
        throw TestFailure('no node has a value with increase and decrease');
      }
    case Kind.selection:
      final items = _items(tester);
      if (items.length < 2) {
        throw TestFailure('fewer than two items announce a selected state');
      }
      final flags = [
        for (final node in items) node.getSemanticsData().flagsCollection,
      ];
      if (flags.where((f) => f.isSelected == Tristate.isTrue).length != 1) {
        throw TestFailure('not exactly one item is announced as selected');
      }
      final roles = [for (final node in items) node.getSemanticsData().role];
      for (var i = 0; i < items.length; i++) {
        if (!flags[i].isInMutuallyExclusiveGroup &&
            roles[i] != SemanticsRole.tab) {
          throw TestFailure(
            '"${items[i].label}" is not in a mutually exclusive group',
          );
        }
      }
    case Kind.grid:
      final items = _items(tester);
      if (items.length < 2) {
        throw TestFailure('fewer than two items announce a selected state');
      }
      for (final node in items) {
        final d = node.getSemanticsData();
        if (d.label.isEmpty) throw TestFailure('an item has no label');
        if (!d.flagsCollection.isButton) {
          throw TestFailure('"${d.label}" is not announced as a button');
        }
      }
      final selected = items.where(
        (node) =>
            node.getSemanticsData().flagsCollection.isSelected ==
            Tristate.isTrue,
      );
      if (selected.length != 1) {
        throw TestFailure('not exactly one item is announced as selected');
      }
    case Kind.textInput:
      if (!data.any((d) => d.flagsCollection.isTextField)) {
        throw TestFailure('nothing is announced as a text field');
      }
    case Kind.overlay:
      if (!data.any(
        (d) => d.flagsCollection.scopesRoute && d.flagsCollection.namesRoute,
      )) {
        throw TestFailure('the overlay is not announced as a named route');
      }
    case Kind.actions:
      final count = data.fold<int>(
        0,
        (sum, d) => sum + (d.customSemanticsActionIds?.length ?? 0),
      );
      if (count < 2) {
        throw TestFailure('it offers $count custom actions, expected 2');
      }
  }
}

Future<void> _disabled(WidgetTester tester, Entry entry) async {
  await pumpEntry(tester, entry, enabled: false);
  final data = [
    for (final node in subjectNodes(tester)) node.getSemanticsData(),
  ];
  if (!data.any((d) => d.flagsCollection.isEnabled == Tristate.isFalse)) {
    throw TestFailure('nothing is announced as disabled');
  }
  for (final d in data) {
    if (d.hasAction(SemanticsAction.tap) ||
        d.hasAction(SemanticsAction.increase) ||
        d.hasAction(SemanticsAction.decrease)) {
      throw TestFailure('"${d.label}" still offers an action when disabled');
    }
  }
}

Future<void> _actions(WidgetTester tester, Entry entry) async {
  switch (entry.kind) {
    case Kind.pressable || Kind.toggle || Kind.opener:
      final byGesture = await _fresh(tester, entry);
      if (entry.openGesture == OpenGesture.longPress) {
        await hold(tester, _aim(tester, entry));
      } else {
        await tester.tapAt(_aim(tester, entry));
      }
      await settle(tester, 90);
      final gestured = _activated(entry, byGesture);
      final gestureEvents = [...byGesture.events];
      final bySemantics = await _fresh(tester, entry);
      final node = _nodeAt(tester, _aim(tester, entry));
      if (node == null) throw TestFailure('nothing under the finger acts');
      tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
        node.id,
        entry.openGesture == OpenGesture.longPress
            ? SemanticsAction.longPress
            : SemanticsAction.tap,
      );
      await settle(tester, 90);
      if (!gestured) throw TestFailure('the gesture did nothing');
      if (!_activated(entry, bySemantics)) {
        throw TestFailure('the semantic action did nothing');
      }
      if (entry.kind != Kind.opener &&
          '${bySemantics.events}' != '$gestureEvents') {
        throw TestFailure(
          'the semantic action gave ${bySemantics.events}, '
          'the gesture $gestureEvents',
        );
      }
    case Kind.value:
      for (final up in [true, false]) {
        final probe = await _fresh(tester, entry);
        final before = probe.value;
        final node = subjectNodes(tester).where((node) {
          final data = node.getSemanticsData();
          return data.hasAction(
            up ? SemanticsAction.increase : SemanticsAction.decrease,
          );
        }).firstOrNull;
        if (node == null) {
          throw TestFailure('nothing offers ${up ? 'increase' : 'decrease'}');
        }
        tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
          node.id,
          up ? SemanticsAction.increase : SemanticsAction.decrease,
        );
        await settle(tester, 30);
        final moved = _compare(probe.value, before);
        if (up ? moved <= 0 : moved >= 0) {
          throw TestFailure(
            '${up ? 'increase' : 'decrease'} did not '
            '${up ? 'raise' : 'lower'} the value',
          );
        }
      }
    case Kind.selection || Kind.grid:
      final byGesture = await _fresh(tester, entry);
      final items = _items(tester);
      final index = items.indexWhere(
        (node) =>
            node.getSemanticsData().flagsCollection.isSelected ==
            Tristate.isFalse,
      );
      if (index < 0) throw TestFailure('no unselected item to choose');
      final before = byGesture.value;
      await tester.tapAt(globalRect(tester, items[index]).center);
      await settle(tester);
      final gestured = byGesture.value;
      final bySemantics = await _fresh(tester, entry);
      final again = _items(tester);
      tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
        again[index].id,
        SemanticsAction.tap,
      );
      await settle(tester);
      if (gestured == before) throw TestFailure('a tap on an item did nothing');
      if (bySemantics.value != gestured) {
        throw TestFailure(
          'a semantic tap chose ${bySemantics.value}, the gesture $gestured',
        );
      }
    case Kind.actions:
      final probe = await _fresh(tester, entry);
      final node = subjectNodes(tester).where(
        (node) =>
            node.getSemanticsData().customSemanticsActionIds?.isNotEmpty ??
            false,
      );
      if (node.isEmpty) throw TestFailure('no custom actions');
      final ids = node.first.getSemanticsData().customSemanticsActionIds!;
      for (final id in ids) {
        tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
          node.first.id,
          SemanticsAction.customAction,
          id,
        );
        await settle(tester, 30);
      }
      if (probe.events.length != ids.length) {
        throw TestFailure(
          '${ids.length} custom actions ran ${probe.events} handlers',
        );
      }
    case Kind.textInput || Kind.overlay:
      break;
  }
}

Future<void> _focusDisabled(WidgetTester tester, Entry entry) async {
  await pumpEntry(tester, entry, enabled: false);
  final stops = await tabStops(tester);
  if (stops.isNotEmpty) {
    throw TestFailure('Tab reaches ${stops.length} parts while disabled');
  }
}

Future<void> _tabStops(WidgetTester tester, Entry entry) async {
  await pumpEntry(tester, entry);
  final stops = await tabStops(tester);
  if (stops.isEmpty) throw TestFailure('Tab reaches no part of it');
  if (stops.length != entry.focusStops) {
    throw TestFailure(
      'Tab stops at ${stops.length} parts, expected ${entry.focusStops}',
    );
  }
}

Future<void> _focusIndicator(WidgetTester tester, Entry entry) async {
  final probe = await pumpEntry(tester, entry);
  await _focusOrFail(tester, entry);
  final stop = FocusManager.instance.primaryFocus!;
  await settle(tester, 30);
  final keyboard = await _look(tester, entry, probe);
  stop.unfocus();
  await settle(tester, 30);
  final none = await _look(tester, entry, probe);
  if (!differs(keyboard, none)) {
    throw TestFailure(
      entry.look == Look.own
          ? 'keyboard focus draws nothing'
          : 'keyboard focus does not reach the builder as focused',
    );
  }
  if (entry.kind == Kind.textInput) return;
  await tester.tapAt(const Offset(4, 870));
  await settle(tester, 30);
  final rest = await _look(tester, entry, probe);
  stop.requestFocus();
  await settle(tester, 30);
  final touch = await _look(tester, entry, probe);
  if (differs(touch, rest)) {
    throw TestFailure(
      entry.look == Look.own
          ? 'focus after a touch draws the keyboard indication'
          : 'focus after a touch reaches the builder as focused',
    );
  }
}

/// What a check compares: the screen for a control that draws itself, the
/// state the builder sees for a raw core.
Future<Uint8List> _look(WidgetTester tester, Entry entry, Probe probe) async {
  if (entry.look == Look.own) return screenshot(tester);
  final states = probe.states ?? const <WidgetState>{};
  return Uint8List.fromList([
    if (states.contains(WidgetState.focused)) 1,
    if (states.contains(WidgetState.hovered)) 2,
  ]);
}

Future<void> _keyActivate(WidgetTester tester, Entry entry) async {
  for (final key in [LogicalKeyboardKey.space, LogicalKeyboardKey.enter]) {
    final probe = await _fresh(tester, entry);
    if (entry.kind == Kind.grid) {
      await _gridActivate(tester, probe, key);
      continue;
    }
    await _focusOrFail(tester, entry);
    final before = probe.value;
    await tester.sendKeyEvent(key);
    await settle(tester);
    if (entry.kind == Kind.value) {
      if (probe.value != before || probe.events.isNotEmpty) {
        throw TestFailure(
          '${key.debugName} changes it; a value control takes no Space or '
          'Enter',
        );
      }
      continue;
    }
    if (!_activated(entry, probe)) {
      throw TestFailure('${key.debugName} does not activate it');
    }
  }
}

Future<void> _gridActivate(
  WidgetTester tester,
  Probe probe,
  LogicalKeyboardKey key,
) async {
  await _enterGrid(tester);
  await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
  await settle(tester, 30);
  final focused = _focusedItem(tester);
  if (focused == null) throw TestFailure('no item is focused');
  final label = focused.label;
  final before = probe.value;
  await tester.sendKeyEvent(key);
  await settle(tester, 30);
  final picked = _items(tester).where((node) => node.label == label);
  if (probe.value == before ||
      picked.isEmpty ||
      picked.first.getSemanticsData().flagsCollection.isSelected !=
          Tristate.isTrue) {
    throw TestFailure('${key.debugName} does not pick the focused item');
  }
}

Future<void> _keyRemap(WidgetTester tester, Entry entry) async {
  final probe = await _fresh(
    tester,
    entry,
    shortcuts: {
      ...WidgetsApp.defaultShortcuts,
      const SingleActivator(LogicalKeyboardKey.keyA): const ActivateIntent(),
    },
  );
  if (entry.kind == Kind.grid) {
    await _enterGrid(tester);
  } else {
    await _focusOrFail(tester, entry);
  }
  await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
  await settle(tester);
  if (!_activated(entry, probe)) {
    throw TestFailure('a key the app maps to ActivateIntent does nothing');
  }
}

Future<void> _arrows(
  WidgetTester tester,
  Entry entry,
  TextDirection direction,
) async {
  if (entry.kind == Kind.grid) return _gridArrows(tester, entry, direction);
  final probe = await _fresh(tester, entry, direction: direction);
  await _focusOrFail(tester, entry);
  final ltr = direction == TextDirection.ltr || !entry.mirrors;
  final forward = ltr
      ? LogicalKeyboardKey.arrowRight
      : LogicalKeyboardKey.arrowLeft;
  final back = ltr
      ? LogicalKeyboardKey.arrowLeft
      : LogicalKeyboardKey.arrowRight;
  final before = probe.value;
  await tester.sendKeyEvent(forward);
  await settle(tester, 30);
  if (_compare(probe.value, before) <= 0) {
    throw TestFailure('${forward.debugName} does not step it forward');
  }
  await tester.sendKeyEvent(back);
  await settle(tester, 30);
  if (_compare(probe.value, before) != 0) {
    throw TestFailure('${back.debugName} does not step it back');
  }
}

Future<void> _keyArrows(WidgetTester tester, Entry entry) =>
    _arrows(tester, entry, TextDirection.ltr);

Future<void> _keyArrowsRtl(WidgetTester tester, Entry entry) =>
    _arrows(tester, entry, TextDirection.rtl);

Future<void> _keyHomeEnd(WidgetTester tester, Entry entry) async {
  if (entry.kind == Kind.grid) return _gridHomeEnd(tester, entry);
  final probe = await _fresh(tester, entry);
  await _focusOrFail(tester, entry);
  final before = probe.value;
  await tester.sendKeyEvent(LogicalKeyboardKey.home);
  await settle(tester, 30);
  if (_compare(probe.value, before) >= 0) {
    throw TestFailure('Home does not reach the start');
  }
  await tester.sendKeyEvent(LogicalKeyboardKey.end);
  await settle(tester, 30);
  final end = probe.value;
  if (_compare(end, before) <= 0) {
    throw TestFailure('End does not reach the end');
  }
  await tester.sendKeyEvent(LogicalKeyboardKey.end);
  await settle(tester, 30);
  if (_compare(probe.value, end) != 0) {
    throw TestFailure('End does not stop at the end');
  }
}

/// The items of a grid in reading order: rows from the top, each row in
/// the reading direction.
List<SemanticsNode> _gridItems(WidgetTester tester, TextDirection direction) {
  final items = [
    for (final node in _items(tester)) (node, globalRect(tester, node).center),
  ];
  items.sort((a, b) {
    final dy = a.$2.dy - b.$2.dy;
    if (dy.abs() > 1) return dy.sign.toInt();
    final dx = (a.$2.dx - b.$2.dx).sign.toInt();
    return direction == TextDirection.ltr ? dx : -dx;
  });
  return [for (final (node, _) in items) node];
}

SemanticsNode? _focusedItem(WidgetTester tester) => _items(tester)
    .where(
      (node) =>
          node.getSemanticsData().flagsCollection.isFocused == Tristate.isTrue,
    )
    .firstOrNull;

/// Tabs into a grid and checks that the focus lands on the picked item.
Future<String> _enterGrid(WidgetTester tester) async {
  final selected = _items(tester).where(
    (node) =>
        node.getSemanticsData().flagsCollection.isSelected == Tristate.isTrue,
  );
  if (selected.isEmpty) throw TestFailure('no item is announced as selected');
  final picked = selected.first.label;
  final at = globalRect(tester, selected.first).center;
  final stops = await tabStops(tester);
  final under = stops.where((node) => _boxOf(node).contains(at));
  if (under.isEmpty) throw TestFailure('Tab does not reach the picked item');
  under
      .reduce(
        (a, b) =>
            _boxOf(a).size.longestSide <= _boxOf(b).size.longestSide ? a : b,
      )
      .requestFocus();
  await settle(tester, 10);
  final focused = _focusedItem(tester)?.label;
  if (focused != picked) {
    throw TestFailure(
      'Tab enters the items at ${focused == null ? 'none' : '"$focused"'}, '
      'not at the picked "$picked"',
    );
  }
  return picked;
}

Future<String?> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await settle(tester, 30);
  return _focusedItem(tester)?.label;
}

/// The label of the item a row below [label], in the same column.
String? _below(WidgetTester tester, String label) {
  final items = _items(tester);
  final from = items.where((node) => node.label == label).firstOrNull;
  if (from == null) return null;
  final at = globalRect(tester, from).center;
  SemanticsNode? best;
  var bestY = double.infinity;
  for (final node in items) {
    final center = globalRect(tester, node).center;
    if ((center.dx - at.dx).abs() > 1 || center.dy <= at.dy + 1) continue;
    if (center.dy < bestY) {
      best = node;
      bestY = center.dy;
    }
  }
  return best?.label;
}

// The arrows of a grid follow Flutter's CalendarDatePicker: they move the
// focus, a day along the reading order and a week down or up, and leave
// the pick alone; in right-to-left the items are mirrored and so are the
// horizontal arrows.
Future<void> _gridArrows(
  WidgetTester tester,
  Entry entry,
  TextDirection direction,
) async {
  final rtl = direction == TextDirection.rtl;
  List<String>? ltrOrder;
  if (rtl) {
    await _fresh(tester, entry);
    ltrOrder = [
      for (final node in _gridItems(tester, TextDirection.ltr)) node.label,
    ];
  }
  final probe = await _fresh(tester, entry, direction: direction);
  final order = [for (final node in _gridItems(tester, direction)) node.label];
  if (ltrOrder != null && !listEquals(order, ltrOrder)) {
    throw TestFailure('the items keep their order on screen in right-to-left');
  }
  final start = await _enterGrid(tester);
  final before = probe.value;
  final index = order.indexOf(start);
  if (index < 0 || index + 1 >= order.length) {
    throw TestFailure('the picked item has no item after it');
  }
  final forward = rtl
      ? LogicalKeyboardKey.arrowLeft
      : LogicalKeyboardKey.arrowRight;
  final back = rtl
      ? LogicalKeyboardKey.arrowRight
      : LogicalKeyboardKey.arrowLeft;
  final next = await _press(tester, forward);
  if (next != order[index + 1]) {
    throw TestFailure(
      '${forward.debugName} moves the focus to ${next ?? 'nothing'}, not to '
      'the next item "${order[index + 1]}"',
    );
  }
  if (probe.value != before) {
    throw TestFailure(
      '${forward.debugName} changes the pick; it only moves the focus',
    );
  }
  if (await _press(tester, back) != start) {
    throw TestFailure('${back.debugName} does not move the focus back');
  }
  final below = _below(tester, start);
  if (below == null) throw TestFailure('the picked item has no row below');
  final down = await _press(tester, LogicalKeyboardKey.arrowDown);
  if (down != below) {
    throw TestFailure(
      'Arrow Down moves the focus to ${down ?? 'nothing'}, not to the item '
      'below, "$below"',
    );
  }
  if (await _press(tester, LogicalKeyboardKey.arrowUp) != start) {
    throw TestFailure('Arrow Up does not move the focus back');
  }
  if (probe.value != before) {
    throw TestFailure('the arrows change the pick; they only move the focus');
  }
}

Future<void> _gridHomeEnd(WidgetTester tester, Entry entry) async {
  final probe = await _fresh(tester, entry);
  final order = [
    for (final node in _gridItems(tester, TextDirection.ltr)) node.label,
  ];
  await _enterGrid(tester);
  final before = probe.value;
  if (await _press(tester, LogicalKeyboardKey.home) != order.first) {
    throw TestFailure('Home does not move the focus to the first item');
  }
  if (await _press(tester, LogicalKeyboardKey.end) != order.last) {
    throw TestFailure('End does not move the focus to the last item');
  }
  if (probe.value != before) {
    throw TestFailure('Home and End change the pick; they only move the focus');
  }
}

// A calendar's arrows cross into the neighbouring month: six weeks down
// from any day leave every month, so the focus must keep moving to a new
// item all the way.
Future<void> _keyArrowsEdge(WidgetTester tester, Entry entry) async {
  final probe = await _fresh(tester, entry);
  final seen = {await _enterGrid(tester)};
  final before = probe.value;
  for (var i = 0; i < 6; i++) {
    final at = await _press(tester, LogicalKeyboardKey.arrowDown);
    if (at == null) {
      throw TestFailure(
        'Arrow Down past the last row takes the focus off the items',
      );
    }
    if (!seen.add(at)) {
      throw TestFailure(
        'Arrow Down past the last row stops at "$at" instead of turning '
        'the page',
      );
    }
  }
  if (probe.value != before) {
    throw TestFailure('turning the page changes the pick');
  }
}

Future<void> _keyEscape(WidgetTester tester, Entry entry) async {
  final probe = await pumpEntry(tester, entry);
  await present(tester, entry, probe);
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await settle(tester, 90);
  if (entry.marker!.evaluate().isNotEmpty) {
    throw TestFailure('Escape leaves it open');
  }
}

Future<void> _keyRemapDismiss(WidgetTester tester, Entry entry) async {
  final probe = await pumpEntry(
    tester,
    entry,
    shortcuts: {
      ...WidgetsApp.defaultShortcuts,
      const SingleActivator(LogicalKeyboardKey.keyQ): const DismissIntent(),
    },
  );
  await present(tester, entry, probe);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
  await settle(tester, 90);
  if (entry.marker!.evaluate().isNotEmpty) {
    throw TestFailure('a key the app maps to DismissIntent leaves it open');
  }
}

Future<void> _keyContextMenu(WidgetTester tester, Entry entry) async {
  await pumpEntry(tester, entry);
  await _focusOrFail(tester, entry);
  await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
  await settle(tester, 90);
  if (entry.marker!.evaluate().isEmpty) {
    throw TestFailure('the context menu key does not open it');
  }
}

const int _mouse = 77;

Future<MouseCursor?> _cursorAt(WidgetTester tester, Offset at) async {
  final gesture = await tester.createGesture(
    kind: PointerDeviceKind.mouse,
    pointer: _mouse,
  );
  await gesture.addPointer(location: at);
  await tester.pump();
  final cursor = RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(
    1,
  );
  await gesture.removePointer();
  await tester.pump();
  return cursor;
}

/// The cursor the first annotation at [at] that does not defer declares,
/// as the mouse tracker picks it, or null when every one defers.
MouseCursor? _declaredCursorAt(WidgetTester tester, Offset at) {
  final result = HitTestResult();
  tester.binding.hitTestInView(result, at, tester.view.viewId);
  for (final hit in result.path) {
    if (hit.target case final MouseTrackerAnnotation target
        when target.validForMouseTracker &&
            target.cursor != MouseCursor.defer) {
      return target.cursor;
    }
  }
  return null;
}

// Off the web Flutter's adaptive click cursor is the basic arrow, so a
// declared basic cursor stands for it; the mouse tracker's own fallback,
// when nothing declares a cursor, does not.
Future<void> _cursor(WidgetTester tester, Entry entry) async {
  final accepted = entry.kind == Kind.textInput
      ? {SystemMouseCursors.text}
      : {
          SystemMouseCursors.click,
          WidgetStateMouseCursor.adaptiveClickable.resolve(const {}),
        };
  await pumpEntry(tester, entry);
  final active = await _cursorAt(tester, _aim(tester, entry));
  final declared = _declaredCursorAt(tester, _aim(tester, entry));
  if (declared == null) {
    throw TestFailure('it declares no cursor; the cursor over it is $active');
  }
  if (!accepted.contains(declared)) {
    throw TestFailure(
      'the cursor over it is $declared, expected one of $accepted',
    );
  }
  if (!entry.canDisable) return;
  await _fresh(tester, entry, enabled: false);
  final disabled = _declaredCursorAt(tester, _aim(tester, entry));
  final clickable = entry.kind == Kind.textInput
      ? SystemMouseCursors.text
      : SystemMouseCursors.click;
  if (disabled == clickable) {
    throw TestFailure('the cursor stays $clickable while disabled');
  }
}

Future<void> _hover(WidgetTester tester, Entry entry) async {
  final probe = await pumpEntry(tester, entry);
  final rest = await _look(tester, entry, probe);
  final gesture = await tester.createGesture(
    kind: PointerDeviceKind.mouse,
    pointer: _mouse,
  );
  await gesture.addPointer(location: _aim(tester, entry));
  await settle(tester, 30);
  final hovered = await _look(tester, entry, probe);
  await gesture.removePointer();
  await tester.pump();
  if (!differs(rest, hovered)) {
    throw TestFailure(
      entry.look == Look.own
          ? 'hover draws nothing'
          : 'hover does not reach the builder as hovered',
    );
  }
}

Future<void> _secondaryClick(WidgetTester tester, Entry entry) async {
  await pumpEntry(tester, entry);
  await tester.tapAt(
    _aim(tester, entry),
    buttons: kSecondaryMouseButton,
    kind: PointerDeviceKind.mouse,
  );
  await settle(tester, 90);
  if (entry.marker!.evaluate().isEmpty) {
    throw TestFailure('a secondary click does not open its context menu');
  }
}

Future<void> _wheel(WidgetTester tester, Entry entry) async {
  final probe = await pumpEntry(tester, entry);
  final before = probe.value;
  final pointer = TestPointer(_mouse, PointerDeviceKind.mouse);
  final at = _aim(tester, entry);
  await tester.sendEventToBinding(pointer.hover(at));
  await tester.sendEventToBinding(pointer.scroll(const Offset(0, -40)));
  await settle(tester, 30);
  await tester.sendEventToBinding(pointer.removePointer());
  final stepped = _compare(probe.value, before) != 0;
  if (stepped && !entry.wheel) {
    throw TestFailure('the wheel steps it, but it does not declare that');
  }
  if (!stepped && entry.wheel) throw TestFailure('the wheel does not step it');
}

Future<void> _hapticsGestureOnly(WidgetTester tester, Entry entry) async {
  final log = FeedbackLog(tester);
  try {
    final probe = await _fresh(tester, entry);
    var aim = _aim(tester, entry);
    if (entry.kind == Kind.selection || entry.kind == Kind.grid) {
      final items = _items(tester);
      final unselected = items.where(
        (node) =>
            node.getSemanticsData().flagsCollection.isSelected ==
            Tristate.isFalse,
      );
      if (unselected.isNotEmpty) {
        aim = globalRect(tester, unselected.first).center;
      }
    }
    if (entry.kind == Kind.actions) {
      await tester.dragFrom(aim, const Offset(-300, 0));
    } else if (entry.openGesture == OpenGesture.longPress) {
      await hold(tester, aim);
    } else {
      await tester.tapAt(aim);
    }
    await settle(tester);
    if (probe.events.isEmpty && entry.kind != Kind.opener) return;
    final gesture = log.count > 0;
    await _fresh(tester, entry);
    log.count = 0;
    if (await _focus(tester, entry)) {
      final key = switch (entry.kind) {
        Kind.value || Kind.selection => LogicalKeyboardKey.arrowRight,
        _ => LogicalKeyboardKey.space,
      };
      await tester.sendKeyEvent(key);
      await settle(tester);
      if (log.count > 0) {
        throw TestFailure(
          gesture
              ? 'the keyboard plays the feedback the gesture plays'
              : 'the keyboard plays feedback',
        );
      }
    }
    await _fresh(tester, entry);
    log.count = 0;
    final owner = tester.binding.renderViews.first.owner!.semanticsOwner!;
    final tap = _nodeAt(tester, _aim(tester, entry));
    final adjust = _nodeAt(tester, _aim(tester, entry), tap: false);
    if (entry.kind == Kind.value && adjust != null) {
      owner.performAction(adjust.id, SemanticsAction.increase);
    } else if (tap != null) {
      owner.performAction(
        tap.id,
        tap.getSemanticsData().hasAction(SemanticsAction.tap)
            ? SemanticsAction.tap
            : SemanticsAction.longPress,
      );
    }
    await settle(tester);
    if (log.count > 0) {
      throw TestFailure(
        gesture
            ? 'assistive activation plays the gesture feedback'
            : 'assistive activation plays feedback',
      );
    }
  } finally {
    log.dispose();
  }
}

bool _movedIn(FocusNode? before) {
  final now = FocusManager.instance.primaryFocus;
  if (now == null || now == before) return false;
  if (now == FocusManager.instance.rootScope) return false;
  if (before != null && before.ancestors.contains(now)) return false;
  return true;
}

Future<FocusNode?> _openFocused(
  WidgetTester tester,
  Entry entry,
  Probe probe,
) async {
  if (entry.kind == Kind.opener) await _focus(tester, entry);
  if (entry.kind == Kind.overlay) {
    Focus.of(tester.element(find.text(openerLabel))).requestFocus();
    await tester.pump();
  }
  final before = FocusManager.instance.primaryFocus;
  await present(tester, entry, probe);
  return before;
}

Future<void> _overlayFocusIn(WidgetTester tester, Entry entry) async {
  final probe = await pumpEntry(tester, entry);
  final before = await _openFocused(tester, entry, probe);
  if (!_movedIn(before)) throw TestFailure('opening leaves focus outside');
}

Future<void> _overlayFocusReturn(WidgetTester tester, Entry entry) async {
  final probe = await pumpEntry(tester, entry);
  final before = await _openFocused(tester, entry, probe);
  await close(tester, entry);
  if (entry.marker!.evaluate().isNotEmpty) {
    throw TestFailure('it could not be closed');
  }
  final now = FocusManager.instance.primaryFocus;
  if (now != before) {
    throw TestFailure('closing does not return focus to the opener');
  }
}

// A menu in an overlay portal is read right after its anchor and leaves
// the page readable, as Flutter's RawMenuAnchor does; for such a menu the
// check holds that order instead of hiding.
Future<void> _barrierHides(WidgetTester tester, Entry entry) async {
  final probe = await pumpEntry(tester, entry);
  if (!semanticsNodes(tester).any((node) => node.label == behindLabel)) {
    throw TestFailure('the content behind is not in the tree to begin with');
  }
  await present(tester, entry, probe);
  final marker = entry.marker!.evaluate().firstOrNull;
  if (entry.kind == Kind.opener &&
      marker != null &&
      isInside(marker, find.byWidgetPredicate((w) => w is OverlayPortal))) {
    _readAfterAnchor(tester, entry);
    return;
  }
  final behind = semanticsNodes(
    tester,
  ).where((node) => node.label == behindLabel && !node.isInvisible);
  if (behind.isNotEmpty) {
    throw TestFailure('assistive technology still reaches what is behind it');
  }
}

void _readAfterAnchor(WidgetTester tester, Entry entry) {
  // A part drawn under a sibling node (a zone of an input host) is named by
  // the node at its centre, not by its own render object's ancestors.
  final anchor =
      _nodeAt(tester, _aim(tester, entry)) ??
      tester.getSemantics((entry.part ?? subject).first);
  final item = tester.getSemantics(entry.marker!.first);
  final anchorLine = <SemanticsNode>{};
  for (SemanticsNode? node = anchor; node != null; node = node.parent) {
    anchorLine.add(node);
  }
  var menu = item;
  while (menu.parent != null && !anchorLine.contains(menu.parent)) {
    menu = menu.parent!;
  }
  bool under(SemanticsNode node, SemanticsNode root) {
    for (SemanticsNode? at = node; at != null; at = at.parent) {
      if (at == root) return true;
    }
    return false;
  }

  final read = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    if (!node.isInvisible &&
        !node.isMergedIntoParent &&
        (data.label.isNotEmpty || data.value.isNotEmpty)) {
      read.add(node);
    }
    for (final child in node.debugListChildrenInOrder(
      DebugSemanticsDumpOrder.traversalOrder,
    )) {
      visit(child);
    }
  }

  final root =
      tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode;
  if (root != null) visit(root);
  final last = read.lastIndexWhere(
    (node) => under(node, anchor) && !under(node, menu),
  );
  final first = read.indexWhere((node) => under(node, menu));
  if (last < 0) {
    throw TestFailure('assistive technology does not read its anchor');
  }
  if (first < 0) throw TestFailure('assistive technology does not read it');
  if (first < last) {
    throw TestFailure('assistive technology reads it before its anchor');
  }
  if (first != last + 1) {
    throw TestFailure(
      'assistive technology reads "${read[last + 1].label}" between its '
      'anchor and it',
    );
  }
}

Future<void> _barrierLabel(WidgetTester tester, Entry entry) async {
  final probe = await pumpEntry(tester, entry);
  await present(tester, entry, probe);
  final screen = phone.width * phone.height;
  final barrier = semanticsNodes(tester).where((node) {
    final data = node.getSemanticsData();
    final acts =
        data.hasAction(SemanticsAction.tap) ||
        data.hasAction(SemanticsAction.dismiss);
    final rect = globalRect(tester, node);
    return acts &&
        !node.hasChildren &&
        rect.width * rect.height >= screen * 0.9;
  });
  if (barrier.isEmpty) {
    throw TestFailure('no barrier is offered to assistive technology');
  }
  if (barrier.every((node) => node.label.isEmpty)) {
    throw TestFailure('the barrier has no label');
  }
}

Future<void> _inertClosing(WidgetTester tester, Entry entry) async {
  final probe = await pumpEntry(tester, entry);
  final before = await _openFocused(tester, entry, probe);
  final marker = tester.widget<Text>(entry.marker!.first).data!;
  await _startClosing(tester);
  final problems = <String>[];
  if (semanticsNodes(
    tester,
  ).any((node) => node.label.contains(marker) && !node.isInvisible)) {
    problems.add('its content stays in the semantics tree while it closes');
  }
  if (_movedIn(before)) problems.add('focus stays inside while it closes');
  await settle(tester, 120);
  if (entry.marker!.evaluate().isNotEmpty) {
    throw TestFailure('Escape does not close it, so closing is not checked');
  }
  final inside = entry.inside;
  if (inside != null) {
    final again = await _fresh(tester, entry);
    await present(tester, entry, again);
    final at = tester.getCenter(inside.first);
    await _startClosing(tester);
    final events = again.events.length;
    await tester.tapAt(at);
    await tester.pump();
    if (again.events.length != events) {
      problems.add('it takes taps while it closes');
    }
  }
  if (problems.isNotEmpty) throw TestFailure(problems.first);
}

Future<void> _startClosing(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pump(const Duration(milliseconds: 16));
  await tester.pump(const Duration(milliseconds: 16));
}
