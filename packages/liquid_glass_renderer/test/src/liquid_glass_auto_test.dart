import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

void main() {
  group('LiquidGlass.autoLayer', () {
    test('can be constructed', () {
      expect(
        const LiquidGlass.auto(shape: LiquidOval(), child: SizedBox()),
        isA<Widget>(),
      );
    });

    testWidgets('uses parent layer when one exists', (tester) async {
      await tester.pumpWidget(
        const CupertinoApp(
          home: LiquidGlassLayer(
            child: LiquidGlass.auto(
              shape: LiquidOval(),
              child: SizedBox.square(dimension: 100),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The .autoLayer constructor should NOT create its own LiquidGlassLayer
      // since a parent one already exists. We expect exactly one
      // LiquidGlassLayer in the tree (the one we wrapped it with).
      expect(find.byType(LiquidGlassLayer), findsOneWidget);
    });

    testWidgets('creates own layer when no parent layer exists',
        (tester) async {
      await tester.pumpWidget(
        const CupertinoApp(
          home: LiquidGlass.auto(
            shape: LiquidOval(),
            child: SizedBox.square(dimension: 100),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The .autoLayer constructor should create its own LiquidGlassLayer since
      // there is no parent layer in the tree.
      expect(find.byType(LiquidGlassLayer), findsOneWidget);
    });

    testWidgets('falls back to FakeGlass when parent layer uses fake',
        (tester) async {
      await tester.pumpWidget(
        const CupertinoApp(
          home: LiquidGlassLayer(
            fake: true,
            child: LiquidGlass.auto(
              shape: LiquidOval(),
              child: SizedBox.square(dimension: 100),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should use the parent layer's fake mode and render a FakeGlass.
      expect(find.byType(FakeGlass), findsOneWidget);
      // Should NOT create its own LiquidGlassLayer.
      expect(find.byType(LiquidGlassLayer), findsOneWidget);
    });

    testWidgets('creates own FakeGlass when no parent and fake is true',
        (tester) async {
      await tester.pumpWidget(
        const CupertinoApp(
          home: LiquidGlass.auto(
            shape: LiquidOval(),
            fake: true,
            child: SizedBox.square(dimension: 100),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should create its own FakeGlass since there is no parent layer and
      // fake is true.
      expect(find.byType(FakeGlass), findsOneWidget);
      // Should NOT create a LiquidGlassLayer since fake mode bypasses it.
      expect(find.byType(LiquidGlassLayer), findsNothing);
    });

    testWidgets('uses custom settings when creating own layer', (tester) async {
      const customSettings = LiquidGlassSettings(
        thickness: 42,
        blur: 10,
      );

      await tester.pumpWidget(
        const CupertinoApp(
          home: LiquidGlass.auto(
            settings: customSettings,
            shape: LiquidOval(),
            child: SizedBox.square(dimension: 100),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should create its own LiquidGlassLayer with the custom settings.
      final layerFinder = find.byType(LiquidGlassLayer);
      expect(layerFinder, findsOneWidget);
      final layer = tester.widget<LiquidGlassLayer>(layerFinder);
      expect(layer.settings, equals(customSettings));
    });

    testWidgets('ignores own settings when using parent layer', (tester) async {
      const parentSettings = LiquidGlassSettings(
        thickness: 10,
      );
      const autoSettings = LiquidGlassSettings(
        thickness: 42,
        blur: 10,
      );

      await tester.pumpWidget(
        const CupertinoApp(
          home: LiquidGlassLayer(
            settings: parentSettings,
            child: LiquidGlass.auto(
              settings: autoSettings,
              shape: LiquidOval(),
              child: SizedBox.square(dimension: 100),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Only the parent layer should exist (no additional one created).
      expect(find.byType(LiquidGlassLayer), findsOneWidget);
      final layer = tester.widget<LiquidGlassLayer>(
        find.byType(LiquidGlassLayer),
      );
      expect(layer.settings, equals(parentSettings));
    });
  });
}
