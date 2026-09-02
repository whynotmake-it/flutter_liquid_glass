import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

const _expectFlutterGpuFallback = bool.fromEnvironment(
  'EXPECT_FLUTTER_GPU_FALLBACK',
);

void main() {
  testWidgets(
    'falls back to FakeGlass and logs when Flutter GPU is unavailable',
    (tester) async {
      if (!_expectFlutterGpuFallback) return;

      final messages = <String>[];
      final previousDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) {
        if (message != null) messages.add(message);
      };

      try {
        await tester.pumpWidget(
          const MaterialApp(
            home: LiquidGlass.withOwnLayer(
              shape: LiquidRoundedRectangle(borderRadius: 24),
              child: SizedBox.square(dimension: 160),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(FakeGlass), findsOneWidget);
        expect(
          messages,
          contains(
            contains('LiquidGlassLayer is using FakeGlass'),
          ),
        );
        expect(tester.takeException(), isNull);
      } finally {
        debugPrint = previousDebugPrint;
      }
    },
  );
}
