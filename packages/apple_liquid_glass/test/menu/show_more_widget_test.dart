import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(milliseconds: 16);

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a "Show more" row that keeps the menu open grows the open '
      'menu after its delay, on its spring, to the new rows', (tester) async {
    tester.view.physicalSize = const Size(402, 874) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    var more = false;
    late StateSetter setMenu;
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        pageRouteBuilder: <T>(settings, builder) =>
            GlassPageRoute<T>(builder: builder, settings: settings),
        builder: (context, child) =>
            GlassScope(renderer: const FlatGlassRenderer(), child: child!),
        home: Center(
          child: StatefulBuilder(
            builder: (context, setState) {
              setMenu = setState;
              return GlassMenuAnchor(
                key: const Key('source'),
                menuChildren: [
                  GlassMenuItem(title: 'Copy', onPressed: () {}),
                  if (more)
                    for (final title in ['Paste', 'Move', 'Rename'])
                      GlassMenuItem(title: title, onPressed: () {})
                  else
                    GlassMenuItem(
                      title: 'Show more',
                      keepsMenuOpen: true,
                      onPressed: () => setMenu(() => more = true),
                    ),
                ],
                builder: (context, controller, child) => RawGlassButton(
                  onPressed: controller.open,
                  builder: (context, details) => details.label,
                  child: child!,
                ),
                child: const SizedBox(width: 120, height: 44),
              );
            },
          ),
        ),
      ),
    );
    double card() => tester
        .getSize(
          find
              .ancestor(
                of: find.text('Copy'),
                matching: find.byType(MotionDriven),
              )
              .first,
        )
        .height;

    await tester.tap(find.byKey(const Key('source')));
    for (var i = 0; i < 90; i++) {
      await tester.pump(_frame);
    }
    final closed = card();
    await tester.tap(find.text('Show more'));
    var waited = 0;
    while (find.text('Rename').evaluate().isEmpty && waited < 60) {
      await tester.pump(_frame);
      waited++;
    }
    expect(waited, lessThan(10), reason: 'the action runs after its flash');
    final heights = <double>[];
    for (var i = 0; i < 90; i++) {
      await tester.pump(_frame);
      heights.add(card());
    }
    expect(find.text('Copy'), findsOneWidget);
    expect(heights.first, closeTo(closed, 0.5));
    expect(heights[10], greaterThan(closed + 1));
    expect(heights[10], lessThan(heights.last - 1));
    expect(heights.last, greaterThan(closed + 80));
  });
}
