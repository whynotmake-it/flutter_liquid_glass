import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

void main() {
  group('$LiquidStretch', () {
    setUp(() {});

    const childKey = Key('child');
    const buttonKey = Key('button');

    group('stretching', () {
      testWidgets('gestureDetector mode allows nested button to work',
          (tester) async {
        var buttonPressedCount = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: LiquidStretch(
                  gestureMode: GestureMode.gestureDetector,
                  child: ElevatedButton(
                    key: buttonKey,
                    onPressed: () => buttonPressedCount++,
                    child: const Text('Press me'),
                  ),
                ),
              ),
            ),
          ),
        );

        final buttonFinder = find.byKey(buttonKey);
        expect(buttonFinder, findsOneWidget);

        // Tap the button - should trigger button press, not stretch effect
        await tester.tap(buttonFinder);
        await tester.pumpAndSettle();

        expect(buttonPressedCount, 1);
      });
      Widget build() {
        return MaterialApp(
          home: Scaffold(
            body: Center(
              child: LiquidStretch(
                interactionScale: 1,
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
      }

      testWidgets(
          'elongates horizontally and compresses vertically on horizontal drag',
          (tester) async {
        await tester.pumpWidget(build());

        final childFinder = find.byKey(childKey);
        expect(childFinder, findsOneWidget);

        final ro = tester.renderObject<RenderBox>(childFinder);

        expect(
          MatrixUtils.transformRect(ro.getTransformTo(null), ro.paintBounds)
              .size,
          equals(ro.paintBounds.size),
          reason: 'The child should not be transformed before the gesture.',
        );

        // Drag the child to the right by 50 pixels.
        final gesture =
            await tester.startGesture(tester.getCenter(childFinder));
        await gesture.moveBy(const Offset(200, 0));
        await tester.pumpAndSettle();

        // The child should have stretched to the right, so its width should be
        // greater than 100.
        final stretchedSize =
            MatrixUtils.transformRect(ro.getTransformTo(null), ro.paintBounds)
                .size;

        expect(stretchedSize.width, greaterThan(100));
        // The height should not have changed.
        expect(stretchedSize.height, lessThan(100));

        // End the gesture.
        await gesture.up();
        await tester.pumpAndSettle();

        final finalSize =
            MatrixUtils.transformRect(ro.getTransformTo(null), ro.paintBounds)
                .size;

        // The child should have returned to its original size.
        expect(finalSize, equals(ro.paintBounds.size));
      });

      testWidgets('can handle unmount while dragging', (tester) async {
        await tester.pumpWidget(build());

        final childFinder = find.byKey(childKey);
        expect(childFinder, findsOneWidget);

        // Start dragging the child.
        final gesture =
            await tester.startGesture(tester.getCenter(childFinder));
        await gesture.moveBy(const Offset(200, 0));
        await tester.pumpAndSettle();

        // Unmount the widget while dragging.
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();

        // If we got here without any exceptions, the test passed.
        await gesture.up();
      });
    });
  });
}
