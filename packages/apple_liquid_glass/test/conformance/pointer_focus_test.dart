import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';

import 'harness.dart';
import 'registry.dart';

/// The controls that break the invariant today, each with what the check
/// observes. A control leaves the list when it passes.
const Map<String, String> known = {};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(MotionClock.debugReset);

  for (final entry in registry) {
    if (!_takesPointerFocus(entry)) continue;
    testWidgets(
      '${entry.id}: a pointer never lights focus, the keyboard does',
      (tester) async {
        final reason = await _observe(tester, () => _invariant(tester, entry));
        _judge(entry.id, reason);
      },
      variant: TargetPlatformVariant.desktop(),
      experimentalLeakTesting: LeakTesting.settings.withIgnoredAll(),
    );
  }

  // Flutter's FocusableActionDetector follows FocusManager.highlightMode,
  // which stays traditional on a desktop after a click; the check must see
  // the ring that lights.
  testWidgets(
    'the check sees a ring a click lights',
    (tester) async {
      final entry = registry.firstWhere(
        (e) => e.id == 'reference.good.button',
      );
      final reason = await _observe(tester, () => _invariant(tester, entry));
      expect(reason, 'a click that focuses lights focus');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    experimentalLeakTesting: LeakTesting.settings.withIgnoredAll(),
  );
}

// A text field shows its caret when a click focuses it, as it should; an
// overlay entry's opener is the harness's own button; a search field's
// clear button leaves the field with the text its click clears, so a click
// cannot leave it focused.
bool _takesPointerFocus(Entry e) =>
    e.kind != Kind.overlay &&
    e.kind != Kind.textInput &&
    e.id != 'GlassSearchField.clear' &&
    !e.id.startsWith('reference.');

void _judge(String id, String? reason) {
  final listed = known[id];
  if (listed == null) {
    if (reason != null) fail('$id: $reason');
    return;
  }
  if (reason == null) fail('$id passes now; remove it from `known`');
  expect(reason, listed, reason: '$id fails for another reason');
}

Future<String?> _observe(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  try {
    await body();
    return null;
  } on TestFailure catch (failure) {
    return reasonOf(failure);
  } finally {
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
  }
}

Future<void> _invariant(WidgetTester tester, Entry entry) async {
  final probe = await pumpEntry(tester, entry);
  final stop = await _stopUnderPart(tester, entry);
  FocusManager.instance.primaryFocus?.unfocus();
  await settle(tester, 10);

  await _click(tester, entry, stop);
  if (await _lit(tester, entry, probe, stop)) {
    throw TestFailure('a click that focuses lights focus');
  }

  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  stop.requestFocus();
  await settle(tester, 30);
  if (!await _lit(tester, entry, probe, stop)) {
    throw TestFailure('focus with the keyboard in use shows nothing');
  }

  await _click(tester, entry, stop);
  if (await _lit(tester, entry, probe, stop)) {
    throw TestFailure('a click after the keyboard leaves focus lit');
  }
}

Offset _aim(WidgetTester tester, Entry entry) =>
    tester.getCenter((entry.part ?? subject).first);

Rect _boxOf(FocusNode node) {
  final box = node.context?.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return Rect.zero;
  return node.rect;
}

// Found by Tab before any click: the click that follows is what the
// invariant asks about, and it comes after the keys.
Future<FocusNode> _stopUnderPart(WidgetTester tester, Entry entry) async {
  final stops = await tabStops(tester);
  if (stops.isEmpty) throw TestFailure('Tab reaches no part of it');
  if (entry.part == null) return stops.first;
  final aim = _aim(tester, entry);
  final under = stops.where((node) => _boxOf(node).contains(aim)).toList();
  if (under.isEmpty) throw TestFailure('Tab does not reach the part');
  return under.reduce(
    (a, b) => _boxOf(a).size.longestSide <= _boxOf(b).size.longestSide ? a : b,
  );
}

// A click with the mouse; an overlay it opens is closed with the mouse too,
// so no key reaches the keyboard's use.
Future<void> _click(WidgetTester tester, Entry entry, FocusNode stop) async {
  await tester.tapAt(_aim(tester, entry), kind: PointerDeviceKind.mouse);
  await settle(tester);
  final marker = entry.marker;
  if (entry.presents && marker != null && marker.evaluate().isNotEmpty) {
    await tester.tapAt(const Offset(8, 860), kind: PointerDeviceKind.mouse);
    await settle(tester, 90);
  }
  if (!stop.hasPrimaryFocus) {
    stop.requestFocus();
    await settle(tester, 30);
  }
}

// What the conformance suite compares: the states a raw core hands its
// builder, or for a control that draws itself, the screen with focus
// against the screen without it.
Future<bool> _lit(
  WidgetTester tester,
  Entry entry,
  Probe probe,
  FocusNode stop,
) async {
  if (entry.look == Look.builder) {
    return probe.states?.contains(WidgetState.focused) ?? false;
  }
  final focused = await screenshot(tester);
  stop.unfocus();
  await settle(tester, 30);
  final unfocused = await screenshot(tester);
  stop.requestFocus();
  await settle(tester, 30);
  return differs(focused, unfocused);
}
