import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/effects.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/rendering.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('$GlassGlow', () {
    setUp(() {});

    const childKey = Key('child');
    const buttonKey = Key('button');

    group('gesture modes', () {
      testWidgets('listener mode responds to all pointer events', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: _Glass(
              child: GlassGlow(
                child: Container(
                  key: childKey,
                  width: 100,
                  height: 100,
                  color: Colors.blue,
                ),
              ),
            ),
          ),
        );

        final childFinder = find.byKey(childKey);
        expect(childFinder, findsOneWidget);

        // Tap on the child - should trigger glow effect
        await tester.tap(childFinder);
        await tester.pumpAndSettle();

        // The test passes if no exceptions are thrown
      });

      testWidgets('gestureDetector mode allows nested button to work', (
        tester,
      ) async {
        var buttonPressedCount = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: _Glass(
              child: GlassGlow(
                gestureMode: GestureMode.gestureDetector,
                child: ElevatedButton(
                  key: buttonKey,
                  onPressed: () => buttonPressedCount++,
                  child: const Text('Press me'),
                ),
              ),
            ),
          ),
        );

        final buttonFinder = find.byKey(buttonKey);
        expect(buttonFinder, findsOneWidget);

        // Tap the button - should trigger button press, not glow effect
        await tester.tap(buttonFinder);
        await tester.pumpAndSettle();

        expect(buttonPressedCount, 1);
      });

      testWidgets(
        'gestureDetector: no glow until pan wins over nested button',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              home: _Glass(
                child: GlassGlow(
                  gestureMode: GestureMode.gestureDetector,
                  child: ElevatedButton(
                    key: buttonKey,
                    onPressed: () {},
                    child: const Text('Press me'),
                  ),
                ),
              ),
            ),
          );

          double glowAlpha() => tester
              .element(find.byType(GlassGlow))
              .findAncestorRenderObjectOfType<RenderLiquidGlassContent>()!
              .glowColor
              .a;

          expect(glowAlpha(), 0);

          final center = tester.getCenter(find.byKey(buttonKey));
          final gesture = await tester.startGesture(center);
          await tester.pump(const Duration(milliseconds: 100));
          expect(glowAlpha(), 0);

          await gesture.up();
          await tester.pumpAndSettle();
          expect(glowAlpha(), 0);
        },
      );

      testWidgets('gestureDetector mode with drag', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: _Glass(
              child: GlassGlow(
                gestureMode: GestureMode.gestureDetector,
                child: Container(
                  key: childKey,
                  width: 100,
                  height: 100,
                  color: Colors.blue,
                ),
              ),
            ),
          ),
        );

        final childFinder = find.byKey(childKey);
        expect(childFinder, findsOneWidget);

        // Drag on the child - should trigger glow effect
        final gesture = await tester.startGesture(
          tester.getCenter(childFinder),
        );
        await gesture.moveBy(const Offset(50, 0));
        await tester.pumpAndSettle();
        await gesture.up();

        // The test passes if no exceptions are thrown
      });
    });

    group('a glass without a glow', () {
      const childKey = Key('content');

      List<Type> chainFrom(WidgetTester tester, bool Function(Object) top) {
        final types = <Type>[];
        var node = tester.renderObject(find.byKey(childKey)).parent;
        while (node != null && !top(node)) {
          types.add(node.runtimeType);
          node = node.parent;
        }
        return types;
      }

      void expectNoMotion(WidgetTester tester, Type glass) {
        final states = tester.stateList(
          find.descendant(
            of: find.byType(glass),
            matching: find.byWidgetPredicate((w) => w is StatefulWidget),
          ),
        );
        expect(states.whereType<TickerProvider>(), isEmpty);
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.binding.hasScheduledFrame, isFalse);
      }

      testWidgets('builds its content and no glow around it', (tester) async {
        await tester.pumpWidget(
          const Directionality(
            textDirection: TextDirection.ltr,
            child: LiquidGlassLayer(
              child: LiquidGlass(
                shape: LiquidOval(),
                child: SizedBox.square(key: childKey, dimension: 80),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(chainFrom(tester, (node) => node is RenderLiquidGlass), [
          RenderLiquidGlassContent,
          RenderClipOval,
        ]);
        expectNoMotion(tester, LiquidGlass);
      });

      testWidgets('builds its fake content and no glow around it', (
        tester,
      ) async {
        await tester.pumpWidget(
          const Directionality(
            textDirection: TextDirection.ltr,
            child: FakeGlass(
              shape: LiquidOval(),
              child: SizedBox.square(key: childKey, dimension: 80),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(chainFrom(tester, (node) => node is RenderFakeGlass), [
          RenderLiquidGlassContent,
        ]);
        expectNoMotion(tester, FakeGlass);
      });

      testWidgets('a glow in it lights the glass and fades out', (
        tester,
      ) async {
        await tester.pumpWidget(
          const Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: _Glass(
                child: GlassGlow(
                  child: SizedBox(key: childKey, width: 200, height: 100),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        RenderLiquidGlassContent content() => tester
            .element(find.byType(GlassGlow))
            .findAncestorRenderObjectOfType<RenderLiquidGlassContent>()!;
        expect(content().glowColor.a, 0);

        final touch = await tester.startGesture(const Offset(40, 30));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(content().glowColor.a, greaterThan(0));
        expect(content().glowOffset, const Offset(40, 30));

        await touch.up();
        await tester.pumpAndSettle();
        expect(content().glowColor.a, 0);
      });
    });
  });
}

class _Glass extends StatelessWidget {
  const _Glass({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => FakeGlass(
    shape: const LiquidRoundedRectangle(borderRadius: 0),
    child: child,
  );
}
