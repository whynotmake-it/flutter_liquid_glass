import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'shared.dart';

void main() {
  final placements = <String, Widget Function({required bool fake})>{
    'explicit layer': ({required fake}) => LiquidGlassLayer(
      fake: fake,
      child: const LiquidGlass(
        shape: LiquidOval(),
        child: SizedBox.square(dimension: 80),
      ),
    ),
    'auto in explicit layer': ({required fake}) => LiquidGlassLayer(
      fake: fake,
      child: const LiquidGlass.auto(
        shape: LiquidOval(),
        child: SizedBox.square(dimension: 80),
      ),
    ),
    'grouped in explicit layer': ({required fake}) => LiquidGlassLayer(
      fake: fake,
      child: const LiquidGlassBlendGroup(
        blend: 12,
        child: LiquidGlass.grouped(
          shape: LiquidOval(),
          child: SizedBox.square(dimension: 80),
        ),
      ),
    ),
    'owned layer': ({required fake}) => LiquidGlass.withOwnLayer(
      fake: fake,
      shape: const LiquidOval(),
      child: const SizedBox.square(dimension: 80),
    ),
    'auto-owned layer': ({required fake}) => LiquidGlass.auto(
      fake: fake,
      shape: const LiquidOval(),
      child: const SizedBox.square(dimension: 80),
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

        if (!fake) await pumpUntilGlassReady(tester);
        await tester.pump();

        expect(find.byType(LiquidGlassLayer), findsOneWidget);
        expect(find.byType(FakeGlass), fake ? findsOneWidget : findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('standalone FakeGlass does not require a layer', (tester) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: FakeGlass(
          settings: LiquidGlassSettings(frost: 0),
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
