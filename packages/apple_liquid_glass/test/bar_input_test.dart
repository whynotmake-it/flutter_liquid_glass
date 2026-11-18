import 'dart:ui' show SemanticsAction, Tristate;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';

import 'conformance/harness.dart' show globalRect;
import 'presentations/support.dart' show focusedLabel, perform;

const _frame = Duration(milliseconds: 16);

Future<void> _settle(WidgetTester tester, [int frames = 90]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(_frame);
  }
}

Widget _app(
  Widget page, {
  TextDirection direction = TextDirection.ltr,
  Map<ShortcutActivator, Intent>? shortcuts,
}) {
  Widget app = WidgetsApp(
    color: const Color(0xFFFFFFFF),
    builder: (context, child) =>
        Directionality(textDirection: direction, child: child!),
    pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
      settings: settings,
      pageBuilder: (context, _, _) => builder(context),
    ),
    home: page,
  );
  if (shortcuts != null) app = Shortcuts(shortcuts: shortcuts, child: app);
  return MediaQuery(
    data: const MediaQueryData(
      size: Size(402, 874),
      devicePixelRatio: 3,
      padding: EdgeInsets.only(top: 62, bottom: 34),
    ),
    child: Directionality(
      textDirection: direction,
      child: GlassScope(renderer: const FlatGlassRenderer(), child: app),
    ),
  );
}

final _presses = <String>[];

GlassBarItem _item(String label) => GlassBarItem(
  key: ValueKey(label),
  icon: SizedBox.square(key: Key(label), dimension: 22),
  semanticLabel: label,
  onPressed: () => _presses.add(label),
);

Widget _page({List<GlassBarItem>? trailing}) => GlassPageScaffold(
  navigationBar: GlassNavigationBar(
    title: const Text('Page'),
    leading: [_item('A')],
    trailing:
        trailing ??
        [
          GlassBarItem(
            icon: const SizedBox.square(key: Key('Look'), dimension: 22),
            semanticLabel: 'Look',
            menuChildren: [
              GlassMenuItem(title: 'First', onPressed: () {}),
              const GlassMenuItem(title: 'Second'),
            ],
          ),
          _item('Edit'),
        ],
  ),
  child: const SizedBox.expand(),
);

Future<void> _phone(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(402 * 3, 874 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  _presses.clear();
  await tester.pumpWidget(app);
  await tester.pump();
  await tester.pump();
}

Rect _rectOf(WidgetTester tester, String label) =>
    globalRect(tester, tester.getSemantics(find.bySemanticsLabel(label)));

// The items in reading order: left to right, or right to left.
List<String> _reading(WidgetTester tester, TextDirection direction) {
  final labels = ['A', 'Look', 'Edit'];
  labels.sort((a, b) {
    final x = _rectOf(tester, a).center.dx.compareTo(
      _rectOf(tester, b).center.dx,
    );
    return direction == TextDirection.ltr ? x : -x;
  });
  return labels;
}

Future<List<String?>> _tabs(WidgetTester tester, int count) async {
  final reached = <String?>[];
  for (var i = 0; i < count; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    reached.add(focusedLabel(tester));
  }
  return reached;
}

void main() {
  setUp(MotionClock.debugReset);

  for (final direction in TextDirection.values) {
    testWidgets('Tab stops at each item in reading order and the arrows move '
        'between neighbours, ${direction.name}', (tester) async {
      await _phone(tester, _app(_page(), direction: direction));
      final order = _reading(tester, direction);
      expect(await _tabs(tester, 3), order);

      final left = direction == TextDirection.ltr
          ? LogicalKeyboardKey.arrowLeft
          : LogicalKeyboardKey.arrowRight;
      final right = direction == TextDirection.ltr
          ? LogicalKeyboardKey.arrowRight
          : LogicalKeyboardKey.arrowLeft;
      await tester.sendKeyEvent(left);
      await tester.pump();
      expect(focusedLabel(tester), order[1]);
      await tester.sendKeyEvent(left);
      await tester.pump();
      expect(focusedLabel(tester), order[0]);
      await tester.sendKeyEvent(right);
      await tester.pump();
      expect(focusedLabel(tester), order[1]);
      expect(_presses, isEmpty);
    });
  }

  testWidgets('Space and Enter press the focused item', (tester) async {
    await _phone(tester, _app(_page()));
    final order = _reading(tester, TextDirection.ltr);
    await _tabs(tester, order.indexOf('Edit') + 1);
    expect(focusedLabel(tester), 'Edit');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await _settle(tester, 10);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _settle(tester, 10);
    expect(_presses, ['Edit', 'Edit']);
  });

  testWidgets('a key the app maps to ActivateIntent presses the focused '
      'item', (tester) async {
    await _phone(
      tester,
      _app(
        _page(),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.keyP): ActivateIntent(),
        },
      ),
    );
    final order = _reading(tester, TextDirection.ltr);
    await _tabs(tester, order.indexOf('A') + 1);
    expect(focusedLabel(tester), 'A');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await _settle(tester, 10);
    expect(_presses, ['A']);
  });

  testWidgets('a menu opened by keyboard grows out of its item', (
    tester,
  ) async {
    await _phone(tester, _app(_page()));
    final glyph = find.byKey(const Key('Look'));
    final original = glyph.evaluate().single;
    final source = tester.getCenter(glyph);
    final order = _reading(tester, TextDirection.ltr);
    await _tabs(tester, order.indexOf('Look') + 1);
    expect(focusedLabel(tester), 'Look');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.pump(_frame);
    final copy = glyph.evaluate().where((e) => !identical(e, original));
    expect(copy, hasLength(1));
    final near = (copy.single.renderObject! as RenderBox).localToGlobal(
      const Offset(11, 11),
    );
    expect((near - source).distance, lessThan(12));
    await _settle(tester);
    expect(find.text('First'), findsOneWidget);
    final look = tester.getSemantics(find.bySemanticsLabel('Look').first);
    expect(look.getSemanticsData().flagsCollection.isExpanded, Tristate.isTrue);
  });

  testWidgets('each item is one button node with its label, a tap and a '
      '44 point target', (tester) async {
    await _phone(tester, _app(_page()));
    for (final label in ['A', 'Look', 'Edit']) {
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      final data = tester
          .getSemantics(find.bySemanticsLabel(label))
          .getSemanticsData();
      final flags = data.flagsCollection;
      expect(flags.isButton, isTrue, reason: label);
      expect(flags.isEnabled, Tristate.isTrue, reason: label);
      expect(flags.isFocused, Tristate.isFalse, reason: label);
      expect(data.hasAction(SemanticsAction.tap), isTrue, reason: label);
      expect(data.hasAction(SemanticsAction.focus), isTrue, reason: label);
      expect(
        flags.isExpanded,
        label == 'Look' ? Tristate.isFalse : Tristate.none,
        reason: label,
      );
      final rect = _rectOf(tester, label);
      expect(rect.width, greaterThanOrEqualTo(44), reason: label);
      expect(rect.height, greaterThanOrEqualTo(44), reason: label);
    }
    perform(tester, find.bySemanticsLabel('Edit'), SemanticsAction.tap);
    await _settle(tester, 10);
    expect(_presses, ['Edit']);
  });

  testWidgets('a tap at the edge of the 44 point target presses the item', (
    tester,
  ) async {
    await _phone(tester, _app(_page()));
    final glyph = tester.getRect(find.byKey(const Key('Edit')));
    final target = _rectOf(tester, 'Edit');
    expect(target.bottom - glyph.bottom, greaterThan(8));
    await tester.tapAt(Offset(glyph.center.dx, target.bottom - 1));
    await _settle(tester, 30);
    expect(_presses, ['Edit']);
  });

  testWidgets('an item that leaves takes no input and is not read', (
    tester,
  ) async {
    late StateSetter set;
    var old = true;
    await _phone(
      tester,
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return _page(trailing: [_item(old ? 'Old' : 'New')]);
          },
        ),
      ),
    );
    final at = tester.getCenter(find.byKey(const Key('Old')));
    set(() => old = false);
    await tester.pump();
    await tester.pump(_frame);
    expect(find.byKey(const Key('Old')), findsOneWidget, reason: 'it fades');
    expect(find.bySemanticsLabel('Old'), findsNothing);
    await tester.tapAt(at);
    await _settle(tester);
    expect(_presses, isNot(contains('Old')));
  });

  testWidgets(
    'a bar taken off the screen leaks nothing',
    experimentalLeakTesting: LeakTesting.settings.withTrackedAll(),
    (tester) async {
      await _phone(tester, _app(_page()));
      await _settle(tester, 10);
      await tester.pumpWidget(const SizedBox());
      await _settle(tester, 10);
    },
  );
}
