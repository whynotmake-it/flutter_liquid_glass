import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/fake_glass.dart';

void main() {
  testWidgets('nested visibility scopes multiply into shape appearance', (
    tester,
  ) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: LiquidGlassVisibility(
          visibility: 0.5,
          child: LiquidGlassVisibility(
            visibility: 0.4,
            child: LiquidGlassLayer(
              fake: true,
              defaultAppearance: LiquidGlassAppearance(visibility: 0.5),
              child: LiquidGlass(
                shape: LiquidOval(),
                child: SizedBox.square(dimension: 80),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final renderObject = tester.allRenderObjects
        .whereType<RenderFakeGlass>()
        .toSet();
    expect(renderObject, hasLength(1));
    expect(renderObject.single.appearance.visibility, closeTo(0.1, 0.0001));
  });

  testWidgets('visibility scopes clamp before multiplying', (tester) async {
    var inherited = -1.0;
    await tester.pumpWidget(
      LiquidGlassVisibility(
        visibility: 2,
        child: LiquidGlassVisibility(
          visibility: -1,
          child: Builder(
            builder: (context) {
              inherited = LiquidGlassVisibility.of(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    expect(inherited, 0);
  });
}
