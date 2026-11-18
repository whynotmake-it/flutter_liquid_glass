import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/bar.dart'
    show glassBarLayerHandles;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(List<String> labels) => MediaQuery(
  data: const MediaQueryData(
    size: Size(402, 874),
    devicePixelRatio: 3,
    padding: EdgeInsets.only(top: 62, bottom: 34),
  ),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: GlassScope(
      renderer: const FlatGlassRenderer(),
      child: GlassPageScaffold(
        toolbar: GlassToolbar(
          items: [
            for (final label in labels)
              GlassBarItem(
                key: ValueKey(label),
                label: Text(label),
                onPressed: () {},
              ),
          ],
        ),
        child: const SizedBox.expand(),
      ),
    ),
  ),
);

int _handles(WidgetTester tester) => tester.allRenderObjects
    .map(glassBarLayerHandles)
    .firstWhere((count) => count >= 0);

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('an item that left no longer holds a layer handle', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(['A', 'B', 'C']));
    await tester.pump(const Duration(seconds: 1));
    expect(_handles(tester), 3);
    for (var round = 0; round < 4; round++) {
      await tester.pumpWidget(_app(['A', 'N$round']));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      expect(_handles(tester), 2);
    }
  });
}
