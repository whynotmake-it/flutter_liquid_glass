import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/effects/glass_drag_builder.dart';

void main() {
  testWidgets('a cancelled pointer ends the listener drag', (tester) async {
    Offset? seen;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: GlassDragBuilder(
            builder: (context, offset, child) {
              seen = offset;
              return const SizedBox.square(dimension: 100);
            },
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SizedBox)),
    );
    await tester.pump();
    expect(seen, Offset.zero);

    await gesture.cancel();
    await tester.pump();
    expect(seen, isNull);
  });

  testWidgets('a blend group without a layer asserts with the scope message', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: LiquidGlassBlendGroup(child: SizedBox()),
      ),
    );
    final error = tester.takeException();
    expect(error, isA<AssertionError>());
    expect(error.toString(), contains('No liquid glass renderer found'));
  });
}
