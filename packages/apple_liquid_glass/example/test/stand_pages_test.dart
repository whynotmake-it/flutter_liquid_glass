import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/app.dart';
import 'package:apple_liquid_glass_example/settings.dart';
import 'package:apple_liquid_glass_example/stand/controls_page.dart';
import 'package:apple_liquid_glass_example/stand/present_page.dart';
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

// The test font's glyphs are wider than San Francisco's: the Controls
// page's date row needs a wider screen than 402 points in it.
Future<void> _open(
  WidgetTester tester,
  String tab, {
  double width = 402,
}) async {
  tester.view.physicalSize = Size(width, 874) * 3;
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
  if (tab != 'Liquid') {
    await tester.tap(find.text(tab));
    await _frames(tester);
  }
}

// Scrolls [page] until [finder] stands in the middle of the screen.
Future<void> _show(WidgetTester tester, Type page, Finder finder) async {
  final scroll = find
      .descendant(of: find.byType(page), matching: find.byType(Scrollable))
      .first;
  for (var i = 0; i < 60; i++) {
    final y = finder.evaluate().isEmpty ? null : tester.getCenter(finder).dy;
    if (y != null && y > 300 && y < 600) break;
    await tester.drag(scroll, Offset(0, y != null && y <= 300 ? 150 : -150));
    await _frames(tester, 20);
  }
  await _frames(tester, 30);
}

void main() {
  testWidgets('Photos: Select brings a toolbar whose label follows the '
      'selection, and Delete removes the photos', (tester) async {
    await _open(tester, 'Photos');
    final photos = find.byType(GlassZoomSource).evaluate().length;
    await tester.tap(find.text('Select'));
    await _frames(tester);
    expect(find.byType(GlassToolbar), findsOneWidget);
    expect(find.text('Select Items'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);

    await tester.tap(find.byType(GlassZoomSource).first);
    await _frames(tester);
    expect(find.text('1 Photo Selected'), findsOneWidget);
    await tester.tap(find.byType(GlassZoomSource).at(1));
    await _frames(tester);
    expect(find.text('2 Photos Selected'), findsOneWidget);

    await tester.tap(find.byIcon(CupertinoIcons.trash));
    await _frames(tester);
    expect(find.byType(GlassToolbar), findsNothing);
    expect(find.text('Select'), findsOneWidget);
    expect(
      find.byType(GlassZoomSource).evaluate().length,
      lessThanOrEqualTo(photos),
    );
  });

  testWidgets('Controls: cities add and remove; reminders insert and swipe '
      'away', (tester) async {
    await _open(tester, 'Controls', width: 480);
    await _show(tester, ControlsPage, find.text('Oslo'));
    await tester.tap(find.bySemanticsLabel('Add city'));
    await _frames(tester);
    expect(find.text('Lima'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Remove city'));
    await _frames(tester);
    expect(find.text('Lima'), findsNothing);
    expect(find.text('Rome'), findsOneWidget);

    await _show(tester, ControlsPage, find.text('Add Reminder'));
    await tester.tap(find.text('Add Reminder'));
    await _frames(tester, 90);
    expect(find.text('Book the tickets'), findsOneWidget);
    await tester.drag(
      find.text('Water the plants'),
      const Offset(-600, 0),
      touchSlopX: 0,
    );
    await _frames(tester, 90);
    expect(find.text('Water the plants'), findsNothing);
  });

  testWidgets('Present: Show More grows the open menu; the styled alert '
      'and the fitted sheet open', (tester) async {
    await _open(tester, 'Present');
    await tester.tap(find.bySemanticsLabel('More'));
    await _frames(tester);
    await tester.tap(find.text('Show More'));
    await _frames(tester, 90);
    expect(find.text('Duplicate'), findsOneWidget);
    expect(find.text('Show Less'), findsOneWidget);
    await tester.tap(find.text('Rename'));
    await _frames(tester, 90);
    expect(find.text('Renamed'), findsOneWidget);

    await _show(tester, PresentPage, find.text('Styled alert'));
    await tester.tap(find.text('Styled alert'));
    await _frames(tester);
    expect(find.text('Join the beta?'), findsOneWidget);
    await tester.tap(find.text('Join'));
    await _frames(tester);

    await _show(tester, PresentPage, find.text('Styled sheet'));
    await tester.tap(find.text('Styled sheet'));
    await _frames(tester, 90);
    final title = tester.getTopLeft(find.text('Lemon pasta')).dy;
    await tester.tap(find.text('Show Steps'));
    await _frames(tester, 90);
    expect(find.text('Boil the pasta in salted water.'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Lemon pasta')).dy,
      lessThan(title - 40),
    );
  });

  testWidgets('Motion and Controls start their content below the navigation '
      'bar', (tester) async {
    await _open(tester, 'Motion');
    double barBottom() =>
        tester.getBottomLeft(find.byType(GlassNavigationBar)).dy;
    expect(
      tester.getTopLeft(find.text('Two lines')).dy,
      greaterThanOrEqualTo(barBottom()),
    );
    await tester.tap(find.text('Controls'));
    await _frames(tester);
    expect(
      tester.getTopLeft(find.byType(PageView)).dy,
      greaterThanOrEqualTo(barBottom()),
    );
  });

  testWidgets('Liquid: the drops sit below a navigation bar like every '
      "page's", (tester) async {
    await _open(tester, 'Liquid');
    final bar = tester.getBottomLeft(find.byType(GlassNavigationBar)).dy;
    for (final icon in [CupertinoIcons.drop_fill, CupertinoIcons.sparkles]) {
      expect(tester.getRect(find.byIcon(icon).first).top, greaterThan(bar));
    }
    expect(find.text('Liquid Glass'), findsNothing);
    expect(
      tester.getRect(find.byIcon(CupertinoIcons.paintbrush)).bottom,
      lessThan(bar),
    );
  });

  testWidgets('Liquid: a drop follows its finger and flies home', (
    tester,
  ) async {
    await _open(tester, 'Liquid');
    final heart = find.byIcon(CupertinoIcons.heart_fill);
    final home = tester.getCenter(heart);
    final gesture = await tester.startGesture(home);
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(8, -6));
      await tester.pump(_frame);
    }
    await _frames(tester, 10);
    expect(tester.getCenter(heart).dx, greaterThan(home.dx + 60));
    await gesture.up();
    await _frames(tester, 120);
    expect(tester.getCenter(heart).dx, closeTo(home.dx, 12));
  });
}
