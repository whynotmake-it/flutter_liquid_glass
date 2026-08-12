import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import 'shared.dart';

void main() {
  RenderLiquidGlassLayer findLayer(WidgetTester tester) {
    return tester.allRenderObjects.whereType<RenderLiquidGlassLayer>().last;
  }

  Widget glass({LiquidGlassSettings settings = const LiquidGlassSettings()}) {
    return CupertinoApp(
      home: LiquidGlassLayer(
        settings: settings,
        child: const LiquidGlass(
          shape: LiquidOval(),
          child: SizedBox.square(dimension: 80),
        ),
      ),
    );
  }

  testWidgets(
    'reuses the composed filter while shader inputs are unchanged',
    (tester) async {
      await tester.pumpWidget(glass());
      await tester.pumpAndSettle();

      final renderObject = findLayer(tester);
      final firstFilter = renderObject.debugBackdropFilterLayer?.filter;
      expect(firstFilter, isNotNull);

      // A repaint with identical geometry, transform, and settings must not
      // allocate new filters: the native filter snapshots the shader uniforms
      // at creation, so reuse is only valid while all inputs are unchanged.
      renderObject.markNeedsPaint();
      await tester.pump();

      expect(
        renderObject.debugBackdropFilterLayer?.filter,
        same(firstFilter),
      );
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'rebuilds the filter when settings change the shader uniforms',
    (tester) async {
      await tester.pumpWidget(glass());
      await tester.pumpAndSettle();

      final renderObject = findLayer(tester);
      final firstFilter = renderObject.debugBackdropFilterLayer?.filter;
      expect(firstFilter, isNotNull);

      await tester.pumpWidget(
        glass(settings: const LiquidGlassSettings(blur: 8)),
      );
      await tester.pumpAndSettle();

      final rebuilt = renderObject.debugBackdropFilterLayer?.filter;
      expect(rebuilt, isNotNull);
      expect(rebuilt, isNot(same(firstFilter)));
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'reuses the composed filter when an ancestor transform moves the layer',
    (tester) async {
      Widget movedGlass(Offset offset) => CupertinoApp(
        home: Transform.translate(
          offset: offset,
          child: glass(),
        ),
      );

      await tester.pumpWidget(movedGlass(Offset.zero));
      await tester.pumpAndSettle();

      final renderObject = findLayer(tester);
      final firstFilter = renderObject.debugBackdropFilterLayer?.filter;
      expect(firstFilter, isNotNull);

      await tester.pumpWidget(movedGlass(const Offset(12, 8)));
      // Ancestor translation is compositor-only. The tracking layer sees the
      // transform change during compositing and must not rebuild the filter.
      tester.binding.scheduleFrame();
      await tester.pump();

      expect(
        renderObject.debugBackdropFilterLayer?.filter,
        same(firstFilter),
      );
    },
    skip: skipProperGlassTests,
  );
}
