import 'dart:async';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(milliseconds: 16);

Widget _app(GlobalKey<NavigatorState> navigator) => WidgetsApp(
  navigatorKey: navigator,
  color: const Color(0xFF000000),
  pageRouteBuilder: <T>(settings, builder) =>
      GlassPageRoute<T>(builder: builder, settings: settings),
  builder: (context, child) =>
      GlassScope(renderer: const FlatGlassRenderer(), child: child!),
  home: const ColoredBox(
    color: Color(0xFFFFFFFF),
    child: Center(child: Text('Home')),
  ),
);

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(402 * 3, 874 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(_frame);
  }
}

BuildContext _context(GlobalKey<NavigatorState> navigator) =>
    navigator.currentContext!;

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a tap chooses an action, whose handler runs once the alert '
      'has gone', (tester) async {
    await _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator));
    final ran = <String>[];
    GlassAlertAction? result;
    unawaited(
      showGlassAlert(
        _context(navigator),
        title: const Text('Delete draft?'),
        message: const Text('It cannot be undone.'),
        actions: [
          GlassAlertAction.cancel(
            child: const Text('Cancel'),
            onPressed: () => ran.add('cancel'),
          ),
          GlassAlertAction.destructive(
            isDefaultAction: true,
            onPressed: () => ran.add('delete'),
            child: const Text('Delete'),
          ),
        ],
      ).then((value) => result = value),
    );
    await _settle(tester);
    expect(find.text('Delete draft?'), findsOneWidget);
    final cancel = tester.getCenter(find.text('Cancel'));
    final delete = tester.getCenter(find.text('Delete'));
    expect(cancel.dy, delete.dy, reason: 'two short labels share a row');
    expect(cancel.dx, lessThan(delete.dx), reason: 'cancel goes first');
    await tester.tap(find.text('Delete'));
    await tester.pump();
    expect(ran, isEmpty);
    await _settle(tester);
    expect(ran, ['delete']);
    expect(result?.isDestructive, isTrue);
    expect(find.text('Delete draft?'), findsNothing);
  });

  testWidgets('three actions stand in a column with cancel last; Escape '
      'cancels and Return chooses the default action', (tester) async {
    await _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator));
    GlassAlertAction? result;
    final actions = [
      const GlassAlertAction.cancel(child: Text('Cancel')),
      const GlassAlertAction(child: Text('Keep')),
      const GlassAlertAction(isDefaultAction: true, child: Text('Save')),
    ];
    unawaited(
      showGlassAlert(
        _context(navigator),
        title: const Text('Save changes?'),
        actions: actions,
      ).then((value) => result = value),
    );
    await _settle(tester);
    final keep = tester.getCenter(find.text('Keep')).dy;
    final save = tester.getCenter(find.text('Save')).dy;
    final cancel = tester.getCenter(find.text('Cancel')).dy;
    expect(keep, lessThan(save));
    expect(save, lessThan(cancel));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(result, same(actions[0]));

    unawaited(
      showGlassAlert(
        _context(navigator),
        title: const Text('Save changes?'),
        actions: actions,
      ).then((value) => result = value),
    );
    await _settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _settle(tester);
    expect(result, same(actions[2]));
  });

  testWidgets('a finger that slides to another button chooses it', (
    tester,
  ) async {
    await _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator));
    GlassAlertAction? result;
    unawaited(
      showGlassAlert(
        _context(navigator),
        title: const Text('Pick'),
        actions: const [
          GlassAlertAction(child: Text('One')),
          GlassAlertAction(child: Text('Two')),
          GlassAlertAction(child: Text('Three')),
        ],
      ).then((value) => result = value),
    );
    await _settle(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('One')),
    );
    await tester.pump(_frame);
    await gesture.moveTo(tester.getCenter(find.text('Three')));
    await tester.pump(_frame);
    await gesture.up();
    await _settle(tester);
    expect((result?.child as Text?)?.data, 'Three');
  });

  testWidgets('a slide onto another button clicks, the touch-down does not', (
    tester,
  ) async {
    await _phone(tester);
    final haptics = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator));
    unawaited(
      showGlassAlert(
        _context(navigator),
        title: const Text('Pick'),
        actions: const [
          GlassAlertAction(child: Text('One')),
          GlassAlertAction(child: Text('Two')),
          GlassAlertAction(child: Text('Three')),
        ],
      ),
    );
    await _settle(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('One')),
    );
    await tester.pump(_frame);
    expect(haptics, isEmpty);
    await gesture.moveTo(tester.getCenter(find.text('Two')));
    await tester.pump(_frame);
    expect(haptics, ['HapticFeedbackType.selectionClick']);
    await gesture.up();
    await _settle(tester);
  });

  testWidgets('a finger lifted over no button chooses nothing', (
    tester,
  ) async {
    await _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator));
    var done = false;
    unawaited(
      showGlassAlert(
        _context(navigator),
        title: const Text('Pick'),
        actions: const [
          GlassAlertAction(child: Text('One')),
          GlassAlertAction(child: Text('Two')),
        ],
      ).then((_) => done = true),
    );
    await _settle(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('One')),
    );
    await tester.pump(_frame);
    await gesture.moveTo(tester.getCenter(find.text('Pick')));
    await tester.pump(_frame);
    await gesture.up();
    await _settle(tester);
    expect(done, isFalse);
    expect(find.text('Pick'), findsOneWidget);
  });

  testWidgets('a finger that scrolls a long alert chooses nothing', (
    tester,
  ) async {
    await _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator));
    var done = false;
    unawaited(
      showGlassAlert(
        _context(navigator),
        title: const Text('Pick'),
        message: Text('A long message. ' * 120),
        actions: const [
          GlassAlertAction(child: Text('One')),
          GlassAlertAction(child: Text('Two')),
        ],
      ).then((_) => done = true),
    );
    await _settle(tester);
    final start = tester.getCenter(find.text('Pick'));
    final gesture = await tester.startGesture(start);
    await tester.pump(_frame);
    for (var i = 1; i <= 10; i++) {
      await gesture.moveTo(start + Offset(0, -12.0 * i));
      await tester.pump(_frame);
    }
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scroll.position.pixels, greaterThan(0));
    await gesture.moveTo(tester.getCenter(find.text('One')));
    await tester.pump(_frame);
    await gesture.up();
    await _settle(tester);
    expect(done, isFalse);
  });

  testWidgets('a tap outside an alert does nothing; outside an action sheet '
      'it cancels', (tester) async {
    await _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator));
    unawaited(
      showGlassAlert(
        _context(navigator),
        title: const Text('Stay'),
        actions: const [GlassAlertAction(child: Text('OK'))],
      ),
    );
    await _settle(tester);
    await tester.tapAt(const Offset(20, 60));
    await _settle(tester);
    expect(find.text('Stay'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await _settle(tester);

    GlassAlertAction? result;
    const cancel = GlassAlertAction.cancel(child: Text('Cancel'));
    unawaited(
      showGlassActionSheet(
        _context(navigator),
        title: const Text('Share'),
        actions: const [
          cancel,
          GlassAlertAction(child: Text('Copy')),
          GlassAlertAction(child: Text('Mail')),
        ],
      ).then((value) => result = value),
    );
    await _settle(tester);
    expect(
      tester.getCenter(find.text('Cancel')).dy,
      greaterThan(tester.getCenter(find.text('Mail')).dy),
    );
    await tester.tapAt(const Offset(20, 60));
    await _settle(tester);
    expect(result, same(cancel));
    expect(find.text('Share'), findsNothing);
  });

  testWidgets('the alert is 320 points wide and dims the page while shown', (
    tester,
  ) async {
    await _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator));
    unawaited(
      showGlassAlert(
        _context(navigator),
        title: const Text('Wide'),
        actions: const [GlassAlertAction(child: Text('OK'))],
      ),
    );
    await _settle(tester);
    final glass = tester.widget<GlassSurface>(find.byType(GlassSurface).last);
    final card = tester.getRect(find.byType(GlassSurface).last);
    expect(card.width, 320);
    expect(card.center.dx, 201);
    expect(
      glass.frame!.value.shape,
      const LiquidRoundedSuperellipse(radius: 34),
      reason: 'the platter has the alert corners, not a capsule',
    );
  });

  testWidgets('a style colors the title, the actions and their capsules', (
    tester,
  ) async {
    await _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator));
    unawaited(
      showGlassAlert(
        _context(navigator),
        title: const Text('Title'),
        actions: const [
          GlassAlertAction.cancel(child: Text('Cancel')),
          GlassAlertAction(isDefaultAction: true, child: Text('OK')),
        ],
        style: const GlassAlertStyle(
          titleTextStyle: TextStyle(color: Color(0xFF00AA00)),
          actionColor: Color(0xFFAA0000),
          defaultActionFillColor: Color(0xFF0000AA),
        ),
      ),
    );
    await _settle(tester);
    Color? color(String text) => DefaultTextStyle.of(
      tester.element(find.text(text)),
    ).style.color;
    expect(color('Title'), const Color(0xFF00AA00));
    expect(color('Cancel'), const Color(0xFFAA0000));
    expect(
      find
          .ancestor(of: find.text('OK'), matching: find.byType(CustomPaint))
          .first,
      paints..rrect(color: const Color(0xFF0000AA)),
    );
  });
}
