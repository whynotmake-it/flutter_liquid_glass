import 'dart:ui' show CheckedState, SemanticsRole, Tristate;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(
  Widget home, {
  TextDirection direction = TextDirection.ltr,
  Map<ShortcutActivator, Intent>? shortcuts,
}) => WidgetsApp(
  color: const Color(0xFF000000),
  shortcuts: shortcuts,
  pageRouteBuilder: <T>(settings, builder) =>
      GlassPageRoute<T>(builder: builder, settings: settings),
  builder: (context, child) => Directionality(
    textDirection: direction,
    child: GlassScope(renderer: const FlatGlassRenderer(), child: child!),
  ),
  home: Align(alignment: const Alignment(0, -0.6), child: home),
);

List<GlassMenuEntry> _entries(List<String> log) => [
  GlassMenuItem(title: 'Copy', onPressed: () => log.add('Copy')),
  GlassMenuItem(
    title: 'Pin',
    state: GlassMenuItemState.on,
    onPressed: () => log.add('Pin'),
  ),
  GlassSubmenu(
    title: 'Sort By',
    children: [
      GlassMenuItem(title: 'Name', onPressed: () => log.add('Name')),
      GlassMenuItem(title: 'Date', onPressed: () => log.add('Date')),
    ],
  ),
];

Widget _menu(List<String> log) => GlassMenuAnchor(
  key: const Key('source'),
  semanticLabel: 'More',
  menuChildren: _entries(log),
  builder: (context, controller, child) => RawGlassButton(
    onPressed: controller.open,
    semanticLabel: 'More',
    builder: (context, details) => details.label,
    child: child!,
  ),
  child: const SizedBox(width: 120, height: 44, child: Text('More')),
);

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(402, 874) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 90; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

SemanticsData _row(WidgetTester tester, String label) =>
    tester.getSemantics(find.bySemanticsLabel(label)).getSemanticsData();

bool _focused(WidgetTester tester, String label) =>
    _row(tester, label).flagsCollection.isFocused == Tristate.isTrue;

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
}

Future<void> _openByKeys(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.space);
  await _settle(tester);
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('the keys open the menu on its first row, move, open a '
      'submenu, choose in it and give the focus back', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    final log = <String>[];
    await tester.pumpWidget(_app(_menu(log)));
    await _openByKeys(tester);
    final opener = FocusManager.instance.primaryFocus;
    expect(find.text('Copy'), findsOneWidget);
    expect(_focused(tester, 'Copy'), isTrue);
    await _key(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused(tester, 'Pin'), isTrue);
    await _key(tester, LogicalKeyboardKey.end);
    expect(_focused(tester, 'Sort By'), isTrue);
    await _key(tester, LogicalKeyboardKey.home);
    expect(_focused(tester, 'Copy'), isTrue);
    await _key(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused(tester, 'Copy'), isTrue, reason: 'the first row stays');
    await _key(tester, LogicalKeyboardKey.end);
    await _key(tester, LogicalKeyboardKey.arrowRight);
    await _settle(tester);
    expect(find.text('Name'), findsOneWidget);
    expect(_focused(tester, 'Name'), isTrue);
    await _key(tester, LogicalKeyboardKey.arrowLeft);
    await _settle(tester);
    expect(find.text('Name'), findsNothing);
    expect(_focused(tester, 'Sort By'), isTrue, reason: 'back on its row');
    await _key(tester, LogicalKeyboardKey.enter);
    await _settle(tester);
    expect(_focused(tester, 'Name'), isTrue);
    await _key(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused(tester, 'Date'), isTrue);
    await _key(tester, LogicalKeyboardKey.space);
    await _settle(tester);
    expect(log, ['Date']);
    expect(find.text('Copy'), findsNothing);
    expect(
      FocusManager.instance.primaryFocus,
      isNot(opener),
      reason: 'the focus left the menu',
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('More'))
          .getSemanticsData()
          .flagsCollection
          .isFocused,
      Tristate.isTrue,
      reason: 'the opener has it back',
    );
    handle.dispose();
  });

  testWidgets('Escape goes back from a submenu, then closes the menu', (
    tester,
  ) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    final log = <String>[];
    await tester.pumpWidget(_app(_menu(log)));
    await _openByKeys(tester);
    await _key(tester, LogicalKeyboardKey.end);
    await _key(tester, LogicalKeyboardKey.arrowRight);
    await _settle(tester);
    expect(find.text('Name'), findsOneWidget);
    await _key(tester, LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(find.text('Name'), findsNothing);
    expect(find.text('Copy'), findsOneWidget);
    await _key(tester, LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(find.text('Copy'), findsNothing);
    expect(log, isEmpty);
    handle.dispose();
  });

  testWidgets('a menu opened again under a mouse that rests where a submenu '
      'row was opens on its root list', (tester) async {
    _phone(tester);
    final log = <String>[];
    await tester.pumpWidget(_app(_menu(log)));
    await _openByKeys(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('Sort By')));
    await _settle(tester);
    await _key(tester, LogicalKeyboardKey.escape);
    await _settle(tester);
    await _key(tester, LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(find.text('Copy'), findsNothing, reason: 'the menu closed');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await _settle(tester);
    expect(find.text('Copy'), findsOneWidget, reason: 'the menu is open');
    expect(find.text('Name'), findsNothing, reason: 'on its root list');
    expect(log, isEmpty);
  });

  testWidgets('right to left mirrors the arrows into and out of a submenu', (
    tester,
  ) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    final log = <String>[];
    await tester.pumpWidget(
      _app(_menu(log), direction: TextDirection.rtl),
    );
    await _openByKeys(tester);
    await _key(tester, LogicalKeyboardKey.end);
    await _key(tester, LogicalKeyboardKey.arrowRight);
    await _settle(tester);
    expect(find.text('Name'), findsNothing, reason: 'right leads out');
    await _key(tester, LogicalKeyboardKey.arrowLeft);
    await _settle(tester);
    expect(find.text('Name'), findsOneWidget);
    await _key(tester, LogicalKeyboardKey.arrowRight);
    await _settle(tester);
    expect(find.text('Name'), findsNothing);
    handle.dispose();
  });

  testWidgets('keys an app maps to the intents drive the menu', (
    tester,
  ) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    final log = <String>[];
    await tester.pumpWidget(
      _app(
        _menu(log),
        shortcuts: {
          ...WidgetsApp.defaultShortcuts,
          const SingleActivator(LogicalKeyboardKey.keyJ):
              const DirectionalFocusIntent(TraversalDirection.down),
          const SingleActivator(LogicalKeyboardKey.keyL):
              const DirectionalFocusIntent(TraversalDirection.right),
          const SingleActivator(LogicalKeyboardKey.keyO):
              const ActivateIntent(),
        },
      ),
    );
    await _openByKeys(tester);
    await _key(tester, LogicalKeyboardKey.keyJ);
    expect(_focused(tester, 'Pin'), isTrue);
    await _key(tester, LogicalKeyboardKey.keyJ);
    await _key(tester, LogicalKeyboardKey.keyL);
    await _settle(tester);
    expect(_focused(tester, 'Name'), isTrue);
    await _key(tester, LogicalKeyboardKey.keyO);
    await _settle(tester);
    expect(log, ['Name']);
    handle.dispose();
  });

  testWidgets('the rows are menu items with their roles and states, read '
      'after the source', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(_menu(<String>[])));
    await tester.tap(find.byKey(const Key('source')));
    await _settle(tester);
    final copy = _row(tester, 'Copy');
    expect(copy.role, SemanticsRole.menuItem);
    expect(copy.flagsCollection.isButton, isTrue);
    expect(copy.hasAction(SemanticsAction.tap), isTrue);
    final pin = _row(tester, 'Pin');
    expect(pin.role, SemanticsRole.menuItemCheckbox);
    expect(pin.flagsCollection.isChecked, CheckedState.isTrue);
    final sort = _row(tester, 'Sort By');
    expect(sort.role, SemanticsRole.menuItem);
    expect(sort.flagsCollection.isExpanded, Tristate.isFalse);
    final menu = tester.getSemantics(find.bySemanticsLabel('More').last);
    expect(menu.getSemanticsData().role, SemanticsRole.menu);
    expect(menu.flagsCollection.scopesRoute, isTrue);
    expect(tester.getRect(find.bySemanticsLabel('Copy')).height, 44);
    final owner = tester.binding.renderViews.first.owner!.semanticsOwner!;
    owner.performAction(
      tester.getSemantics(find.bySemanticsLabel('Sort By')).id,
      SemanticsAction.tap,
    );
    await _settle(tester);
    final header = _row(tester, 'Sort By');
    expect(header.flagsCollection.isExpanded, Tristate.isTrue);
    expect(find.bySemanticsLabel('Name'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the mouse highlights the row it rests on, opens a submenu '
      'with a click and not by resting on it, and closes it when it leaves '
      'the card', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    final log = <String>[];
    await tester.pumpWidget(_app(_menu(log)));
    await tester.tap(find.byKey(const Key('source')));
    await _settle(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('Pin')));
    await tester.pump();
    expect(_focused(tester, 'Pin'), isTrue);
    await mouse.moveTo(tester.getCenter(find.text('Copy')));
    await tester.pump();
    expect(_focused(tester, 'Copy'), isTrue);
    await mouse.moveTo(tester.getCenter(find.text('Sort By')));
    await _settle(tester);
    expect(_focused(tester, 'Sort By'), isTrue);
    expect(find.text('Name'), findsNothing, reason: 'resting opens nothing');
    await mouse.down(tester.getCenter(find.text('Sort By')));
    await mouse.up();
    await _settle(tester);
    expect(find.text('Name'), findsOneWidget, reason: 'the click opened it');
    await mouse.moveTo(tester.getCenter(find.text('Name')));
    await tester.pump();
    final card = tester.getRect(find.text('Name'));
    await mouse.moveTo(Offset(card.center.dx, card.top - 120));
    await _settle(tester);
    expect(find.text('Name'), findsNothing, reason: 'it left for the menu');
    expect(find.text('Copy'), findsOneWidget);
    await mouse.moveTo(tester.getCenter(find.text('Copy')));
    await tester.pump();
    await mouse.down(tester.getCenter(find.text('Copy')));
    await mouse.up();
    await _settle(tester);
    expect(log, ['Copy']);
    handle.dispose();
  });

  testWidgets('a moving highlight rebuilds no menu layer', (tester) async {
    _phone(tester);
    final log = <String>[];
    await tester.pumpWidget(_app(_menu(log)));
    await _openByKeys(tester);
    var builds = 0;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      if (element.widget.runtimeType.toString() == '_MenuLayer') builds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    for (final key in [
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.home,
    ]) {
      await _key(tester, key);
      await _settle(tester);
    }
    expect(builds, 0);
  });

  testWidgets('a finger sliding from the hold highlights the rows it '
      'crosses and chooses where it lifts', (tester) async {
    _phone(tester);
    final log = <String>[];
    await tester.pumpWidget(_app(_menu(log)));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('source'))),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('Copy'), findsOneWidget);
    for (final title in ['Copy', 'Pin', 'Copy']) {
      await gesture.moveTo(tester.getCenter(find.text(title)));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await _settle(tester);
    expect(log, ['Copy']);
  });

  testWidgets('a secondary click opens a context menu, whose rows the mouse '
      'then chooses', (tester) async {
    _phone(tester);
    final log = <String>[];
    await tester.pumpWidget(
      _app(
        GlassContextMenu(
          menuChildren: _entries(log),
          child: const SizedBox(
            key: Key('held'),
            width: 160,
            height: 100,
            child: Text('Photo'),
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await mouse.addPointer(location: Offset.zero);
    await mouse.down(tester.getCenter(find.byKey(const Key('held'))));
    await mouse.up();
    await mouse.removePointer();
    await _settle(tester);
    expect(find.text('Copy'), findsOneWidget);
    final click = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await click.addPointer(location: tester.getCenter(find.text('Copy')));
    addTearDown(click.removePointer);
    await tester.pump();
    await click.down(tester.getCenter(find.text('Copy')));
    await click.up();
    await _settle(tester);
    expect(log, ['Copy']);
    expect(find.text('Copy'), findsNothing);
  });
}
