import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/fake_glass.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_render_scope.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import 'shared.dart';

void main() {
  Widget glass({required bool fake}) => LiquidGlassLayer(
    fake: fake,
    useBackdropGroup: true,
    child: const LiquidGlass.auto(
      shape: LiquidOval(),
      child: SizedBox.square(dimension: 80),
    ),
  );

  for (final fake in [false, true]) {
    testWidgets(
      '${fake ? 'fake' : 'real'} glass inherits an opted-in backdrop group',
      (tester) async {
        final key = BackdropKey();
        await tester.pumpWidget(
          CupertinoApp(
            home: BackdropGroup(
              backdropKey: key,
              child: glass(fake: fake),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final scope = tester.widget<LiquidGlassRenderScope>(
          find.byType(LiquidGlassRenderScope),
        );
        expect(scope.backdropKey, same(key));

        if (fake) {
          final raw = tester.widget<RawFakeGlass>(find.byType(RawFakeGlass));
          expect(raw.backdropKey, same(key));
        }
      },
    );
  }

  testWidgets('fake layer creates a local backdrop group when requested', (
    tester,
  ) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: LiquidGlassLayer(
          fake: true,
          useBackdropGroup: true,
          child: Row(
            children: [
              LiquidGlass(
                shape: LiquidOval(),
                child: SizedBox.square(dimension: 80),
              ),
              LiquidGlass(
                shape: LiquidOval(),
                child: SizedBox.square(dimension: 80),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final raw = tester
        .widgetList<RawFakeGlass>(find.byType(RawFakeGlass))
        .toList(growable: false);
    expect(raw, hasLength(2));
    expect(raw.first.backdropKey, isNotNull);
    expect(raw.last.backdropKey, same(raw.first.backdropKey));
  });

  testWidgets('backdrop sharing is opt-in and independent of blend groups', (
    tester,
  ) async {
    final key = BackdropKey();
    await tester.pumpWidget(
      CupertinoApp(
        home: BackdropGroup(
          backdropKey: key,
          child: const LiquidGlassLayer(
            child: LiquidGlassBlendGroup(
              child: LiquidGlass.grouped(
                shape: LiquidOval(),
                child: SizedBox.square(dimension: 80),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scope = tester.widget<LiquidGlassRenderScope>(
      find.byType(LiquidGlassRenderScope),
    );
    expect(scope.backdropKey, isNull);
  });

  testWidgets('an explicit backdrop key overrides the inherited group', (
    tester,
  ) async {
    final inheritedKey = BackdropKey();
    final explicitKey = BackdropKey();
    await tester.pumpWidget(
      CupertinoApp(
        home: BackdropGroup(
          backdropKey: inheritedKey,
          child: LiquidGlassLayer(
            fake: true,
            useBackdropGroup: true,
            backdropKey: explicitKey,
            child: const LiquidGlass.auto(
              shape: LiquidOval(),
              child: SizedBox.square(dimension: 80),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final raw = tester.widget<RawFakeGlass>(find.byType(RawFakeGlass));
    expect(raw.backdropKey, same(explicitKey));
  });

  testWidgets(
    'real glass applies backdrop key updates to its filter layer',
    (tester) async {
      final key = ValueNotifier<BackdropKey?>(BackdropKey());
      addTearDown(key.dispose);

      await tester.pumpWidget(
        CupertinoApp(
          home: ValueListenableBuilder<BackdropKey?>(
            valueListenable: key,
            builder: (_, value, __) => LiquidGlassLayer(
              backdropKey: value,
              child: const LiquidGlass(
                shape: LiquidOval(),
                child: SizedBox.square(dimension: 80),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final renderObject = tester.allRenderObjects
          .whereType<RenderLiquidGlassLayer>()
          .last;
      expect(
        renderObject.debugBackdropFilterLayer?.backdropKey,
        same(key.value),
      );

      final replacement = BackdropKey();
      key.value = replacement;
      await tester.pump();
      expect(
        renderObject.debugBackdropFilterLayer?.backdropKey,
        same(replacement),
      );
    },
    skip: expectFlutterGpuFallback,
  );
}
