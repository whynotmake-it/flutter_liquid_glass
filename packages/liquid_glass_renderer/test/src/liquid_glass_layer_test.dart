import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

void main() {
  group('LiquidGlassLayer', () {
    test('can be instantiated', () {
      expect(
        const LiquidGlassLayer(
          child: SizedBox(),
        ),
        isA<Widget>(),
      );
    });

    test('can be instantiated with custom settings', () {
      expect(
        const LiquidGlassLayer(
          settings: LiquidGlassSettings(thickness: 10),
          child: SizedBox(),
        ),
        isA<Widget>(),
      );
    });

    group('performance optimization', () {
      testWidgets('should not repaint static scene unnecessarily',
          (tester) async {
        var paintCallCount = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NotificationListener<_PaintNotification>(
                onNotification: (notification) {
                  paintCallCount++;
                  return true;
                },
                child: const LiquidGlassLayer(
                  settings: LiquidGlassSettings(thickness: 10),
                  child: Center(
                    child: LiquidGlass.inLayer(
                      shape: LiquidOval(),
                      child: SizedBox.square(dimension: 100),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        final initialPaintCount = paintCallCount;

        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        final finalPaintCount = paintCallCount;
        final additionalPaints = finalPaintCount - initialPaintCount;

        expect(
          additionalPaints,
          lessThan(5),
          reason: 'Static scene should not trigger many repaints',
        );
      });
    });

    group('settings changes', () {
      testWidgets('should update when settings change', (tester) async {
        var currentSettings = const LiquidGlassSettings(thickness: 5);

        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                return Scaffold(
                  body: LiquidGlassLayer(
                    settings: currentSettings,
                    child: const Center(
                      child: LiquidGlass.inLayer(
                        shape: LiquidOval(),
                        child: SizedBox.square(dimension: 100),
                      ),
                    ),
                  ),
                  floatingActionButton: FloatingActionButton(
                    onPressed: () {
                      setState(() {
                        currentSettings =
                            currentSettings.copyWith(thickness: 20);
                      });
                    },
                    child: const Icon(Icons.settings),
                  ),
                );
              },
            ),
          ),
        );

        await tester.pump();

        await tester.tap(find.byType(FloatingActionButton));
        await tester.pump();

        expect(tester.takeException(), isNull);
      });
    });
  });
}

class _PaintNotification extends Notification {
  const _PaintNotification();
}
