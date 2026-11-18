import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a free-form row takes the height it lays out at: from the '
      'frame after it is first measured, the rows after it never overlap '
      'it', (tester) async {
    tester.view.physicalSize = const Size(402, 874) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    const row = Key('row');
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        pageRouteBuilder: <T>(settings, builder) =>
            GlassPageRoute<T>(builder: builder, settings: settings),
        builder: (context, child) =>
            GlassScope(renderer: const FlatGlassRenderer(), child: child!),
        home: Center(
          child: GlassMenuAnchor(
            menuChildren: [
              GlassMenuItem(title: 'Copy', onPressed: () {}),
              GlassMenuWidget(
                builder: (context) => const SizedBox(key: row, height: 120),
              ),
              GlassMenuItem(title: 'Delete', onPressed: () {}),
            ],
            builder: (context, controller, child) => GlassButton(
              key: const Key('button'),
              onPressed: controller.open,
              child: const Text('More'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('button')));
    var frames = 0;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (find.byKey(row).evaluate().isEmpty) continue;
      frames++;
      if (frames == 1) continue;
      final measured = tester.getRect(find.byKey(row));
      final after = tester.getRect(find.text('Delete'));
      expect(after.top, greaterThanOrEqualTo(measured.bottom - 0.5));
    }
    expect(frames, greaterThan(30));
  });
}
