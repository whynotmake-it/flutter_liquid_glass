import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/app.dart';
import 'package:apple_liquid_glass_example/motion/motion_page.dart';
import 'package:apple_liquid_glass_example/settings.dart';
import 'package:apple_liquid_glass_example/stand/stand_home.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(milliseconds: 16);

Future<void> _frames(WidgetTester tester, [int count = 60]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(_frame);
  }
}

Future<void> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(402, 874) * 3;
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    const GalleryApp(
      settings: GallerySettings(renderer: GalleryRenderer.flat),
      home: StandHome(),
    ),
  );
  await _frames(tester);
  await tester.tap(find.text('Motion'));
  await _frames(tester);
}

// Scrolls the page until [finder] stands in the middle of the screen,
// clear of the bars.
Future<void> _show(WidgetTester tester, Finder finder) async {
  final page = find
      .descendant(
        of: find.byType(MotionPage),
        matching: find.byType(Scrollable),
      )
      .first;
  for (var i = 0; i < 40; i++) {
    final y = finder.evaluate().isEmpty ? null : tester.getCenter(finder).dy;
    if (y != null && y > 300 && y < 600) break;
    await tester.drag(page, Offset(0, y != null && y <= 300 ? 150 : -150));
    await _frames(tester, 20);
  }
  await _frames(tester, 30);
}

void main() {
  testWidgets('the card lifts on a tap and, under Reduce Motion, comes back '
      'without bouncing', (
    tester,
  ) async {
    await _open(tester);
    final rest = tester.getCenter(find.text('Tap me'));
    await tester.tapAt(rest + const Offset(80, 40));
    await _frames(tester, 6);
    expect(tester.getCenter(find.text('Tap me')).dy, lessThan(rest.dy - 2));
    await _frames(tester, 90);
    expect(
      tester.getCenter(find.text('Tap me')).dy,
      closeTo(rest.dy - 28, 0.5),
    );

    await tester.tap(find.byType(GlassSwitch).first);
    await _frames(tester);
    expect(
      tester
          .widget<MotionTraitsOverride>(
            find.byType(MotionTraitsOverride).first,
          )
          .traits
          .reduceMotion,
      isTrue,
    );
    await tester.tap(find.text('Tap me'));
    var lowest = double.negativeInfinity;
    for (var i = 0; i < 90; i++) {
      await tester.pump(_frame);
      final y = tester.getCenter(find.text('Tap me')).dy;
      if (y > lowest) lowest = y;
    }
    expect(lowest, lessThan(rest.dy + 0.5));
    expect(tester.getCenter(find.text('Tap me')).dy, closeTo(rest.dy, 0.5));
  });

  testWidgets('notes insert, open and swipe away', (tester) async {
    await _open(tester);
    await _show(tester, find.text('Ideas'));
    expect(find.text('Groceries'), findsOneWidget);
    final top = tester.getTopLeft(find.text('Groceries')).dy;

    await tester.tap(find.text('New Note'));
    await _frames(tester, 90);
    expect(find.text('Books'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Groceries')).dy, greaterThan(top + 20));

    await tester.tap(find.text('Ideas'));
    await _frames(tester, 90);
    expect(find.textContaining('remembers where it was'), findsOneWidget);

    await tester.drag(
      find.text('Books'),
      const Offset(-600, 0),
      touchSlopX: 0,
    );
    await _frames(tester, 90);
    expect(find.text('Books'), findsNothing);
  });

  testWidgets('a tapped chip moves to the front; the grid springs into a '
      'list', (tester) async {
    await _open(tester);
    await _show(tester, find.text('Replay'));
    final first = tester.getTopLeft(find.text('Flutter'));
    await tester.tap(find.text('Replay'));
    await _frames(tester, 6);
    final moving = tester.getTopLeft(find.text('Replay'));
    await _frames(tester, 90);
    final front = tester.getTopLeft(find.text('Replay'));
    expect(front.dx, closeTo(first.dx, 0.5));
    expect(front.dy, closeTo(first.dy, 0.5));
    expect(moving, isNot(front));

    await _show(tester, find.text('Rain'));
    final grid = tester.getCenter(find.text('Rain'));
    await tester.tap(find.byIcon(CupertinoIcons.list_bullet));
    await _frames(tester, 4);
    final flying = tester.getCenter(find.text('Rain'));
    await _frames(tester, 90);
    final list = tester.getCenter(find.text('Rain'));
    expect(list, isNot(grid));
    expect((flying - grid).distance, greaterThan(2));
    expect((flying - list).distance, greaterThan(2));
  });

  testWidgets('the peek opens from its button, drags down and comes back '
      'on a tap while it closes', (tester) async {
    await _open(tester);
    await _show(tester, find.text('Peek'));
    final button = tester.getCenter(find.text('Peek'));
    await tester.tap(find.text('Peek'));
    await _frames(tester, 2);
    // The button draws nothing while the peek holds it; the peek draws its
    // label as it grows.
    expect(find.text('Peek'), findsNWidgets(2));
    await _frames(tester, 90);
    expect(find.text('Drag me down to close.'), findsOneWidget);

    await tester.drag(
      find.text('Drag me down to close.'),
      const Offset(0, 300),
      touchSlopY: 0,
    );
    await _frames(tester, 4);
    expect(find.text('Drag me down to close.'), findsOneWidget);
    await tester.tapAt(button);
    await _frames(tester, 90);
    expect(find.text('Drag me down to close.'), findsOneWidget);

    await tester.tapAt(const Offset(201, 40));
    await _frames(tester, 90);
    expect(find.text('Drag me down to close.'), findsNothing);
  });

  testWidgets('a held finger opens the reactions and picks the one it lifts '
      'over', (tester) async {
    await _open(tester);
    await _show(tester, find.text('Hold to react'));
    final button = tester.getCenter(find.text('Hold to react'));
    final gesture = await tester.startGesture(button);
    await _frames(tester, 45);
    expect(find.byType(Icon), findsWidgets);
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, -7.4));
      await tester.pump(_frame);
    }
    await gesture.up();
    await _frames(tester);
    expect(find.textContaining('You reacted with'), findsOneWidget);
  });

  testWidgets('a held finger lifted away from the reactions closes them', (
    tester,
  ) async {
    await _open(tester);
    await _show(tester, find.text('Hold to react'));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Hold to react')),
    );
    await _frames(tester, 45);
    expect(find.byIcon(CupertinoIcons.flame_fill), findsOneWidget);
    await gesture.up();
    await _frames(tester);
    expect(find.byIcon(CupertinoIcons.flame_fill), findsNothing);
    expect(find.textContaining('You reacted with'), findsNothing);
  });

  testWidgets('a drag on the knob is recorded and replays on a fresh copy', (
    tester,
  ) async {
    await _open(tester);
    await _show(tester, find.bySemanticsLabel('Play'));
    await _show(tester, find.bySemanticsLabel('Knob'));
    final knob = find.bySemanticsLabel('Knob');
    final gesture = await tester.startGesture(tester.getCenter(knob));
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(6, 0));
      await tester.pump(_frame);
    }
    await gesture.up();
    await _frames(tester, 90);
    expect(find.textContaining('stamped inputs'), findsOneWidget);

    await _show(tester, find.bySemanticsLabel('Play'));
    await tester.tap(find.bySemanticsLabel('Play'));
    await _frames(tester, 30);
    expect(find.bySemanticsLabel('Pause'), findsOneWidget);
    await _frames(tester, 60 * 30);
    expect(find.bySemanticsLabel('Play'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
