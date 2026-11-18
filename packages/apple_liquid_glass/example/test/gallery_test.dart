import 'dart:ui' show FrameTiming;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/app.dart';
import 'package:apple_liquid_glass_example/components/component_page.dart';
import 'package:apple_liquid_glass_example/components/components_page.dart';
import 'package:apple_liquid_glass_example/components/controls.dart';
import 'package:apple_liquid_glass_example/glass/glass_page.dart';
import 'package:apple_liquid_glass_example/motion/motion_page.dart';
import 'package:apple_liquid_glass_example/scenes/lava_page.dart';
import 'package:apple_liquid_glass_example/settings.dart';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(milliseconds: 16);

Future<void> _frames(WidgetTester tester, [int count = 60]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(_frame);
  }
}

// A bar item is read from its zone, whose node stands where the item is
// drawn: the centre of its rectangle on the screen.
Offset _centerOf(WidgetTester tester, Finder finder) {
  final node = tester.getSemantics(finder);
  var rect = node.rect;
  for (SemanticsNode? at = node; at != null; at = at.parent) {
    if (at.transform case final transform?) {
      rect = MatrixUtils.transformRect(transform, rect);
    }
  }
  return rect.center / tester.view.devicePixelRatio;
}

Future<ValueNotifier<GallerySettings>> _launch(
  WidgetTester tester, {
  GalleryRenderer renderer = GalleryRenderer.flat,
}) async {
  tester.view.physicalSize = const Size(402, 874) * 3;
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
  final settings = ValueNotifier(GallerySettings(renderer: renderer));
  addTearDown(settings.dispose);
  await tester.pumpWidget(GalleryApp(notifier: settings));
  await _frames(tester, 30);
  return settings;
}

// Scrolls [scroll] until [target] stands clear of the bars: down the page
// while the target is not built, then from the top again.
Future<void> _bring(WidgetTester tester, Finder target, Finder scroll) async {
  for (var i = 0; i < 80; i++) {
    final y = target.evaluate().isEmpty ? null : tester.getCenter(target).dy;
    if (y != null && y > 220 && y < 640) break;
    final up = y == null ? i >= 30 && i < 60 : y <= 220;
    await tester.drag(scroll, Offset(0, up ? 300 : -140));
    await _frames(tester, 20);
  }
  await _frames(tester, 30);
}

Finder _scrollOf(Type page) =>
    find.descendant(of: find.byType(page), matching: find.byType(Scrollable));

// Opens the component the catalog lists as [title].
Future<void> _open(WidgetTester tester, String title) async {
  final row = find.descendant(
    of: find.byType(ComponentsPage),
    matching: find.text(title),
  );
  await _bring(tester, row, _scrollOf(ComponentsPage).first);
  await tester.tap(row);
  await _frames(tester, 90);
}

// Leaves the catalog on top.
Future<void> _back(WidgetTester tester) async {
  Navigator.of(tester.element(find.byType(ComponentPage))).pop();
  await _frames(tester, 90);
}

// Real glass with `--enable-impeller --enable-flutter-gpu`, fake without.
void main() => galleryTests();

/// The gallery's tour; [onDevice] when a device's engine draws it
/// (integration_test/gallery_device_test.dart), which leaves out what only
/// holds on the host.
void galleryTests({bool onDevice = false}) {
  testWidgets('the gallery opens on the catalog of components, with the '
      'material and the motion in tabs beside it', (tester) async {
    await _launch(tester, renderer: GalleryRenderer.liquid);
    expect(find.byType(ComponentsPage), findsOneWidget);
    for (final (tab, page) in const [
      ('Glass', GlassPage),
      ('Motion', MotionPage),
      ('Components', ComponentsPage),
    ]) {
      await tester.tap(find.text(tab).last);
      await _frames(tester);
      expect(find.byType(page), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('every page has the same two items in the same place of its '
      'bar', (tester) async {
    await _launch(tester);
    Offset at(String label) =>
        _centerOf(tester, find.bySemanticsLabel(label).last);
    final renderer = at('Draw in glass');
    final settings = at('Settings');
    for (final tab in const ['Glass', 'Motion', 'Components']) {
      await tester.tap(find.text(tab).last);
      await _frames(tester);
      expect(at('Draw in glass'), renderer, reason: tab);
      expect(at('Settings'), settings, reason: tab);
    }
    for (final component in const ['Button', 'Sheet', 'Surface']) {
      await _open(tester, component);
      expect(at('Draw in glass'), renderer, reason: component);
      expect(at('Settings'), settings, reason: component);
      if (component == 'Surface') {
        await _bring(
          tester,
          find.text('Lava'),
          _scrollOf(ComponentPage).first,
        );
        await tester.tap(find.text('Lava'));
        await _frames(tester, 90);
        expect(at('Draw in glass'), renderer, reason: 'Lava');
        expect(at('Settings'), settings, reason: 'Lava');
        Navigator.of(tester.element(find.byType(LavaPage))).pop();
        await _frames(tester, 90);
      }
      await _back(tester);
    }
  });

  testWidgets('the drop in the bar draws the app flat or in glass', (
    tester,
  ) async {
    final settings = await _launch(tester, renderer: GalleryRenderer.liquid);
    await tester.tapAt(_centerOf(tester, find.bySemanticsLabel('Draw flat')));
    await _frames(tester);
    expect(settings.value.renderer, GalleryRenderer.flat);
    await tester.tapAt(
      _centerOf(tester, find.bySemanticsLabel('Draw in glass')),
    );
    await _frames(tester);
    expect(settings.value.renderer, GalleryRenderer.liquid);
  });

  testWidgets('the Glass tab shows every property down to the last stage', (
    tester,
  ) async {
    await _launch(tester, renderer: GalleryRenderer.liquid);
    await tester.tap(find.text('Glass').last);
    await _frames(tester);
    final scroll = _scrollOf(GlassPage).first;
    for (final title in const [
      'It bends light',
      'Clear, regular, tinted',
      'Any outline',
      'It fuses',
      'Glass on glass',
      'Glass, or flat',
      'Light and dark',
    ]) {
      await tester.scrollUntilVisible(
        find.text(title),
        200,
        scrollable: scroll,
      );
      await _frames(tester, 20);
      expect(find.text(title), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('every component of the catalog opens its page: the '
      'component, its knobs and what to make of it', (tester) async {
    await _launch(tester, renderer: GalleryRenderer.liquid);
    for (final (_, _, title, _, _) in ComponentsPage.all) {
      await _open(tester, title);
      final page = find.byType(ComponentPage);
      expect(page, findsOneWidget, reason: title);
      expect(find.text('Try it'), findsOneWidget, reason: title);
      // To the end of the page and back out.
      final scroll = find
          .descendant(of: page, matching: find.byType(Scrollable))
          .first;
      for (var i = 0; i < 4; i++) {
        await tester.drag(scroll, const Offset(0, -500));
        await _frames(tester, 30);
        expect(tester.takeException(), isNull, reason: title);
      }
      await _back(tester);
      expect(find.byType(ComponentPage), findsNothing, reason: title);
    }
  });

  testWidgets('a knob changes the component on its stage', (tester) async {
    await _launch(tester);
    await _open(tester, 'Button');
    final stage = find.descendant(
      of: find.byType(Stage).first,
      matching: find.byType(GlassButton),
    );
    expect(tester.widget<GlassButton>(stage).onPressed, isNotNull);
    final enabled = find.descendant(
      of: find.widgetWithText(GlassListRow, 'Enabled'),
      matching: find.byType(GlassSwitch),
    );
    await _bring(tester, enabled, _scrollOf(ButtonPage).first);
    await tester.tap(enabled);
    await _frames(tester);
    expect(tester.widget<GlassButton>(stage).onPressed, isNull);
  });

  testWidgets('the components work: a menu, an alert, a sheet, and bars '
      'whose items change', (tester) async {
    await _launch(tester);

    await _open(tester, 'Menu');
    await tester.tap(find.text('Open the menu'));
    await _frames(tester, 90);
    expect(find.text('Water'), findsOneWidget);
    await tester.tap(find.text('Water'));
    await _frames(tester, 90);
    expect(find.text('Water'), findsNothing);
    await _back(tester);

    await _open(tester, 'Alert');
    await tester.tap(find.text('Ask'));
    await _frames(tester, 90);
    expect(find.text('The fern has dried out'), findsOneWidget);
    await tester.tap(find.text('Keep'));
    await _frames(tester, 90);
    expect(find.text('The fern has dried out'), findsNothing);
    expect(find.text('Kept'), findsOneWidget);
    await _back(tester);

    await _open(tester, 'Sheet');
    await tester.tap(find.text('Open the sheet'));
    await _frames(tester, 90);
    expect(find.text('Plants'), findsOneWidget);
    Navigator.of(tester.element(find.text('Plants'))).pop();
    await _frames(tester, 90);
    expect(find.text('Plants'), findsNothing);
    await _back(tester);

    await _open(tester, 'Navigation bar and toolbar');
    await tester.tap(find.text('Open the journal'));
    await _frames(tester, 90);
    expect(find.text('14 entries'), findsOneWidget);
    await tester.tapAt(_centerOf(tester, find.bySemanticsLabel('Select')));
    await _frames(tester, 90);
    expect(find.text('0 picked'), findsOneWidget);
    await tester.tap(find.text('Moved the fern'));
    await _frames(tester, 30);
    expect(find.text('1 picked'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await _frames(tester, 90);
    expect(find.text('14 entries'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the tab bar page opens an app under the bar its knobs chose', (
    tester,
  ) async {
    await _launch(tester);
    await _open(tester, 'Tab bar');
    await tester.tap(find.text('Open the greenhouse'));
    await _frames(tester, 90);
    expect(find.text('Wishes'), findsOneWidget);
    expect(find.text('Shop'), findsNothing);
    await tester.tap(find.text('Rooms').last);
    await _frames(tester);
    expect(find.text('Rooms'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the frame meter reads frames a second and the time of a '
      'frame from the engine', (tester) async {
    final settings = await _launch(tester);
    expect(find.textContaining('fps'), findsNothing);
    settings.value = settings.value.copyWith(frameMeter: true);
    await _frames(tester, 5);
    FrameTiming frame(int at) => FrameTiming(
      vsyncStart: at,
      buildStart: at,
      buildFinish: at + 3000,
      rasterStart: at + 3000,
      rasterFinish: at + 8000,
      rasterFinishWallTime: at + 8000,
    );
    // Thirty frames, one every sixtieth of a second.
    tester.binding.platformDispatcher.onReportTimings!([
      for (var i = 0; i < 30; i++) frame(i * 16667),
    ]);
    await _frames(tester, 5);
    expect(find.text('60 fps   UI 3.0   raster 5.0 ms'), findsOneWidget);
    settings.value = settings.value.copyWith(frameMeter: false);
    await _frames(tester, 5);
    expect(find.textContaining('fps'), findsNothing);
    // The engine of a device reports frames of its own beside these.
  }, skip: onDevice);

  testWidgets('search finds a component by its class and a toy by its name, '
      'and opens them', (tester) async {
    await _launch(tester);
    await tester.tap(find.bySemanticsLabel('Search'));
    await _frames(tester, 90);
    await tester.enterText(find.byType(EditableText), 'glassstepper');
    await _frames(tester, 30);
    expect(find.text('Stepper'), findsOneWidget);
    expect(find.text('Switch'), findsNothing);
    await tester.enterText(find.byType(EditableText), 'lava');
    await _frames(tester, 30);
    await tester.tap(find.text('Lava'));
    await _frames(tester, 90);
    expect(find.byType(LavaPage), findsOneWidget);
  });
}
