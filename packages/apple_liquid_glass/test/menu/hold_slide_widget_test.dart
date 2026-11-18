import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('in a list, a held menu button keeps the finger: it slides '
      'into the rows and chooses one, and the list never scrolls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final log = <String>[];
    final scroll = ScrollController(initialScrollOffset: 100);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        pageRouteBuilder: <T>(settings, builder) =>
            GlassPageRoute<T>(builder: builder, settings: settings),
        builder: (context, child) =>
            GlassScope(renderer: const FlatGlassRenderer(), child: child!),
        home: ListView(
          controller: scroll,
          children: [
            const SizedBox(height: 220),
            Center(
              child: GlassMenuAnchor(
                menuChildren: [
                  for (final title in ['Copy', 'Share', 'Rename', 'Delete'])
                    GlassMenuItem(
                      title: title,
                      onPressed: () => log.add(title),
                    ),
                ],
                builder: (context, controller, child) => GlassButton(
                  key: const Key('button'),
                  onPressed: controller.open,
                  child: const Text('More'),
                ),
              ),
            ),
            const SizedBox(height: 2000),
          ],
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('button'))),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('Rename'), findsOneWidget);
    final from = tester.getCenter(find.byKey(const Key('button')));
    final to = tester.getCenter(find.text('Rename'));
    for (var i = 1; i <= 10; i++) {
      await gesture.moveTo(Offset.lerp(from, to, i / 10)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(scroll.offset, 100);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 20));
    expect(log, ['Rename']);
    expect(scroll.offset, 100);
  });

  testWidgets('in a list, a held context menu keeps the finger: it slides '
      'into the rows and chooses one, and the list never scrolls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final log = <String>[];
    final scroll = ScrollController(initialScrollOffset: 100);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        pageRouteBuilder: <T>(settings, builder) =>
            GlassPageRoute<T>(builder: builder, settings: settings),
        builder: (context, child) =>
            GlassScope(renderer: const FlatGlassRenderer(), child: child!),
        home: ListView(
          controller: scroll,
          children: [
            const SizedBox(height: 220),
            Center(
              child: GlassContextMenu(
                key: const Key('button'),
                menuChildren: [
                  for (final title in ['Copy', 'Share', 'Rename', 'Delete'])
                    GlassMenuItem(
                      title: title,
                      onPressed: () => log.add(title),
                    ),
                ],
                child: const SizedBox(
                  width: 200,
                  height: 80,
                  child: Text('Card'),
                ),
              ),
            ),
            const SizedBox(height: 2000),
          ],
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('button'))),
    );
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('Rename'), findsOneWidget);
    final from = tester.getCenter(find.byKey(const Key('button')));
    final to = tester.getCenter(find.text('Rename'));
    for (var i = 1; i <= 10; i++) {
      await gesture.moveTo(Offset.lerp(from, to, i / 10)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(scroll.offset, 100);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 20));
    expect(log, ['Rename']);
    expect(scroll.offset, 100);
  });
}
