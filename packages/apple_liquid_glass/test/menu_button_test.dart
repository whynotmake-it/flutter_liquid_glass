import 'dart:ui' show Tristate;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

const _titles = ['Copy', 'Share', 'Rename', 'Move', 'Delete'];

Widget _app(
  Widget button, {
  Alignment alignment = const Alignment(0, -0.6),
  VoidCallback? onPage,
  GlassRenderer renderer = const FlatGlassRenderer(),
}) => WidgetsApp(
  color: const Color(0xFF000000),
  pageRouteBuilder: <T>(settings, builder) =>
      GlassPageRoute<T>(builder: builder, settings: settings),
  builder: (context, child) => GlassScope(renderer: renderer, child: child!),
  home: Stack(
    children: [
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPage,
          child: const ColoredBox(color: Color(0xFFF2F2F7)),
        ),
      ),
      Align(alignment: alignment, child: button),
    ],
  ),
);

List<GlassMenuEntry> _entries(List<String> log, {int count = 3}) => [
  for (final title in _titles.take(count))
    GlassMenuItem(title: title, onPressed: () => log.add(title)),
];

Widget _button(
  List<String> log, {
  int count = 3,
  VoidCallback? onPressed,
  GlassMenuController? controller,
}) => GlassMenuAnchor(
  controller: controller,
  menuChildren: _entries(log, count: count),
  builder: (context, controller, child) => GlassButton(
    key: const Key('button'),
    onPressed: onPressed ?? controller.open,
    semanticLabel: 'More',
    child: const Text('More'),
  ),
);

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(402, 874) * 3;
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

final _source = find.byKey(const Key('button'));

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a tap opens the menu after the measured delay and it settles '
      'open', (tester) async {
    _phone(tester);
    final log = <String>[];
    await tester.pumpWidget(_app(_button(log)));
    await tester.tap(_source);
    await tester.pump();
    expect(find.text('Copy'), findsNothing);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Copy'), findsOneWidget);
    await _settle(tester);
    expect(find.text('Share'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
    final copy = tester.getRect(find.text('Copy'));
    final button = tester.getRect(_source);
    expect(copy.top, greaterThan(button.top - 1));
  });

  testWidgets('a row fires its action before the menu closes', (
    tester,
  ) async {
    _phone(tester);
    final log = <String>[];
    await tester.pumpWidget(_app(_button(log)));
    await tester.tap(_source);
    await _settle(tester);
    await tester.tapAt(tester.getCenter(find.text('Share')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(log, ['Share']);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Share'), findsOneWidget, reason: 'still closing');
    await _settle(tester);
    expect(find.text('Share'), findsNothing);
    expect(log, ['Share']);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a hold opens the menu under the finger, and the finger slides '
      'to a row and chooses it on release', (tester) async {
    _phone(tester);
    final log = <String>[];
    await tester.pumpWidget(_app(_button(log, count: 5)));
    final gesture = await tester.startGesture(tester.getCenter(_source));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('Rename'), findsOneWidget);
    await gesture.moveTo(tester.getCenter(find.text('Rename')));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 20));
    expect(log, ['Rename']);
    await _settle(tester);
    expect(find.text('Rename'), findsNothing);
  });

  testWidgets('a tap outside closes the menu without an action and without '
      'reaching the page', (tester) async {
    _phone(tester);
    final log = <String>[];
    var page = 0;
    await tester.pumpWidget(_app(_button(log), onPage: () => page++));
    await tester.tap(_source);
    await _settle(tester);
    await tester.tapAt(const Offset(20, 800));
    await _settle(tester);
    expect(find.text('Copy'), findsNothing);
    expect(log, isEmpty);
    expect(page, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.tapAt(const Offset(20, 800));
    expect(page, 1, reason: 'a closed menu leaves the page its taps');
  });

  testWidgets('Escape and a pop close the menu, not the page', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(_app(_button(<String>[])));
    await tester.tap(_source);
    await _settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(find.text('Copy'), findsNothing);

    await tester.tap(_source);
    await _settle(tester);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    expect(await navigator.maybePop(), isTrue);
    await _settle(tester);
    expect(find.text('Copy'), findsNothing);
    expect(_source, findsOneWidget);
  });

  testWidgets('with its own action a tap presses the button and a hold opens '
      'the menu', (tester) async {
    _phone(tester);
    final log = <String>[];
    await tester.pumpWidget(
      _app(_button(log, onPressed: () => log.add('pressed'))),
    );
    await tester.tap(_source);
    await _settle(tester);
    expect(log, ['pressed']);
    expect(find.text('Copy'), findsNothing);
    final gesture = await tester.startGesture(tester.getCenter(_source));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('Copy'), findsOneWidget);
    await gesture.up();
    await _settle(tester);
    expect(find.text('Copy'), findsOneWidget, reason: 'released on the button');
  });

  testWidgets('a controller opens and closes the menu', (tester) async {
    _phone(tester);
    final controller = GlassMenuController();
    await tester.pumpWidget(_app(_button(<String>[], controller: controller)));
    expect(controller.isOpen, isFalse);
    controller.open();
    await _settle(tester);
    expect(controller.isOpen, isTrue);
    expect(find.text('Copy'), findsOneWidget);
    controller.close();
    await _settle(tester);
    expect(controller.isOpen, isFalse);
    expect(find.text('Copy'), findsNothing);
  });

  testWidgets('a menu below the middle opens up with its rows reversed', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(
      _app(_button(<String>[]), alignment: const Alignment(0, 0.7)),
    );
    await tester.tap(_source);
    await _settle(tester);
    final copy = tester.getRect(find.text('Copy'));
    final share = tester.getRect(find.text('Share'));
    expect(copy.top, greaterThan(share.top));
    expect(copy.bottom, lessThan(tester.getRect(_source).bottom + 1));
  });

  testWidgets('screen readers see an expandable button, then a menu of '
      'items in its place', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(_button(<String>[])));
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('More'))
          .flagsCollection
          .isExpanded,
      Tristate.isFalse,
    );
    await tester.tap(_source);
    await _settle(tester);
    expect(find.bySemanticsLabel('Copy'), findsOneWidget);
    final menu = tester.getSemantics(find.bySemanticsLabel('More').last);
    expect(menu.flagsCollection.scopesRoute, isTrue);
    expect(menu.getSemanticsData().hasAction(SemanticsAction.dismiss), isTrue);
    menu.owner!.performAction(menu.id, SemanticsAction.dismiss);
    await _settle(tester);
    expect(find.bySemanticsLabel('Copy'), findsNothing);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('More'))
          .flagsCollection
          .isExpanded,
      Tristate.isFalse,
    );
    handle.dispose();
  });

  testWidgets('on the liquid renderer the menu and the button are one glass '
      'body while they part', (tester) async {
    _phone(tester);
    await tester.pumpWidget(
      _app(_button(<String>[]), renderer: const LiquidGlassRenderer()),
    );
    await tester.tap(_source);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final fields = <LiquidGlassField?>[];
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final layers = tester.widgetList<LiquidGlassLayer>(
        find.byType(LiquidGlassLayer),
      );
      fields.addAll([for (final layer in layers) layer.frame?.value.field]);
    }
    expect(fields.whereType<LiquidGlassField>(), isNotEmpty);
    await _settle(tester);
    final layers = tester.widgetList<LiquidGlassLayer>(
      find.byType(LiquidGlassLayer),
    );
    expect(
      [for (final layer in layers) layer.frame?.value.field],
      everyElement(isNull),
      reason: 'at rest the menu is a rounded box',
    );
  });

  testWidgets('a submenu row opens its card over the menu; a card row acts '
      'and the header goes back', (tester) async {
    _phone(tester);
    final log = <String>[];
    await tester.pumpWidget(
      _app(
        GlassMenuAnchor(
          menuChildren: [
            GlassMenuItem(title: 'Copy', onPressed: () => log.add('Copy')),
            GlassSubmenu(
              title: 'Sort By',
              children: [
                GlassMenuItem(title: 'Name', onPressed: () => log.add('Name')),
                GlassMenuItem(title: 'Date', onPressed: () => log.add('Date')),
              ],
            ),
          ],
          builder: (context, controller, child) => GlassButton(
            key: const Key('button'),
            onPressed: controller.open,
            child: const Text('More'),
          ),
        ),
      ),
    );
    await tester.tap(_source);
    await _settle(tester);
    expect(find.text('Name'), findsNothing);
    await tester.tapAt(tester.getCenter(find.text('Sort By')));
    await _settle(tester);
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Date'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(find.text('Name'), findsNothing, reason: 'Escape goes back first');
    expect(find.text('Copy'), findsOneWidget);
    await tester.tapAt(tester.getCenter(find.text('Sort By')));
    await _settle(tester);
    await tester.tapAt(tester.getCenter(find.text('Date')));
    await _settle(tester);
    expect(log, ['Date']);
    expect(find.text('Copy'), findsNothing);
  });

  testWidgets('a prominent button keeps its color on the glass at both '
      'hand-offs and crosses it into the menu glass as its label fades', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(
      _app(
        GlassMenuAnchor(
          menuChildren: _entries(<String>[]),
          builder: (context, controller, child) => GlassButton.prominent(
            key: const Key('button'),
            onPressed: controller.open,
            child: const Text('Add'),
          ),
        ),
      ),
    );
    await tester.tap(_source);
    final opening = <double>[];
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (_menuGlass(tester) case final frame?) {
        expect(frame.tint, isNotNull);
        opening.add(frame.tintAmount);
      }
    }
    expect(opening.first, greaterThan(0.95));
    await _settle(tester);
    expect(_menuGlass(tester)!.tintAmount, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    double? last;
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final frame = _menuGlass(tester);
      if (frame == null) break;
      last = frame.tintAmount;
    }
    expect(_menuGlass(tester), isNull);
    expect(last, greaterThan(0.95));
  });
}

// The menu's glass now, or null while no menu shows.
GlassFrame? _menuGlass(WidgetTester tester) {
  final surfaces = tester.widgetList<GlassSurface>(
    find.byWidgetPredicate(
      (widget) =>
          widget is GlassSurface &&
          widget.role == GlassRole.panel &&
          widget.frame != null,
    ),
  );
  return surfaces.isEmpty ? null : surfaces.first.frame!.value;
}
