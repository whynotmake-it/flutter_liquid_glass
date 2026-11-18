import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/widgets/consolidated_fake_glass_layer.dart';

void main() {
  final placements = <String, Widget Function({required bool fake})>{
    'glass on a layer': ({required fake}) => LiquidGlassLayer(
      fake: fake,
      child: const LiquidGlass(
        shape: LiquidOval(),
        child: SizedBox.square(dimension: 80),
      ),
    ),
    'glass in a blend group': ({required fake}) => LiquidGlassLayer(
      fake: fake,
      child: const LiquidGlassBlendGroup(
        blend: 12,
        child: LiquidGlass(
          shape: LiquidOval(),
          child: SizedBox.square(dimension: 80),
        ),
      ),
    ),
  };

  for (final MapEntry(key: placement, value: build) in placements.entries) {
    for (final fake in [false, true]) {
      testWidgets('$placement uses ${fake ? 'fake' : 'real'} rendering', (
        tester,
      ) async {
        await tester.pumpWidget(
          CupertinoApp(
            home: ColoredBox(
              color: CupertinoColors.systemBlue,
              child: Center(child: build(fake: fake)),
            ),
          ),
        );

        await tester.pump();

        expect(find.byType(LiquidGlassLayer), findsOneWidget);
        expect(
          find.byType(ConsolidatedFakeGlassLayer),
          fake ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final (name, glass) in const [
    (
      'glass',
      LiquidGlass(shape: LiquidOval(), child: SizedBox.square(dimension: 80)),
    ),
    (
      'a blend group',
      LiquidGlassBlendGroup(child: SizedBox.square(dimension: 80)),
    ),
  ]) {
    testWidgets('$name without a layer says a layer is missing', (
      tester,
    ) async {
      await tester.pumpWidget(CupertinoApp(home: glass));
      expect(
        tester.takeException(),
        isFlutterError.having(
          (error) => error.message,
          'message',
          contains('No LiquidGlassLayer found.'),
        ),
      );
    });
  }

  testWidgets('standalone FakeGlass does not require a layer', (tester) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: FakeGlass(
          settings: LiquidGlassSettings(frost: LiquidGlassFrost.sigma(0)),
          shape: LiquidOval(),
          child: SizedBox.square(dimension: 80),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(LiquidGlassLayer), findsNothing);
    expect(find.byType(FakeGlass), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
