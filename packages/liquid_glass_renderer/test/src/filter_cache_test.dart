import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import 'shared.dart';

void main() {
  RenderLiquidGlassLayer findLayer(WidgetTester tester) {
    return tester.allRenderObjects.whereType<RenderLiquidGlassLayer>().last;
  }

  Widget glass({
    LiquidGlassSettings settings = const LiquidGlassSettings(),
    LiquidGlassAppearance? appearance,
  }) {
    return CupertinoApp(
      home: LiquidGlassLayer(
        settings: settings,
        child: LiquidGlass(
          shape: const LiquidOval(),
          appearance: appearance,
          child: const SizedBox.square(dimension: 80),
        ),
      ),
    );
  }

  testWidgets(
    'uniform visibility animation reuses cached geometry',
    (tester) async {
      final visibility = ValueNotifier<double>(1);
      addTearDown(visibility.dispose);
      await tester.pumpWidget(
        CupertinoApp(
          home: LiquidGlassLayer(
            child: ValueListenableBuilder<double>(
              valueListenable: visibility,
              child: const LiquidGlass(
                shape: LiquidOval(),
                child: SizedBox.square(dimension: 80),
              ),
              builder: (_, value, child) => LiquidGlassVisibility(
                visibility: value,
                child: child!,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await pumpUntilGlassReady(tester);
      final layer = findLayer(tester);
      final renderer = layer.gpuGeometryRenderer!;
      final count = renderer.debugRenderCount;
      for (var frame = 1; frame <= 30; frame++) {
        visibility.value = 1 - frame / 32;
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          renderer.debugRenderCount,
          count,
          reason: 'Uniform material changes must not regenerate the SDF.',
        );
      }
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'backdrop-only animation reuses cached geometry and filter',
    (tester) async {
      final backdrop = ValueNotifier(const Color(0xFF102030));
      addTearDown(backdrop.dispose);
      await tester.pumpWidget(
        CupertinoApp(
          home: Stack(
            children: [
              Positioned.fill(
                child: ValueListenableBuilder<Color>(
                  valueListenable: backdrop,
                  builder: (_, color, _) => ColoredBox(color: color),
                ),
              ),
              const Center(
                child: LiquidGlassLayer(
                  child: LiquidGlass(
                    shape: LiquidOval(),
                    child: SizedBox.square(dimension: 80),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await pumpUntilGlassReady(tester);
      final layer = findLayer(tester);
      final renderer = layer.gpuGeometryRenderer!;
      final count = renderer.debugRenderCount;
      final filter = layer.debugBackdropFilterLayer?.filter;
      expect(filter, isNotNull);
      for (var frame = 0; frame < 30; frame++) {
        backdrop.value = Color(0xFF102031 + frame * 0x010101);
        await tester.pump(const Duration(milliseconds: 16));
        expect(renderer.debugRenderCount, count);
        expect(layer.debugBackdropFilterLayer?.filter, same(filter));
      }
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'reuses the composed filter while shader inputs are unchanged',
    (tester) async {
      await tester.pumpWidget(glass());
      await tester.pumpAndSettle();
      await pumpUntilGlassReady(tester);

      final renderObject = findLayer(tester);
      final firstFilter = renderObject.debugBackdropFilterLayer?.filter;
      expect(firstFilter, isNotNull);
      expect(
        renderObject.debugBackdropFilterLayer?.parent,
        isA<ClipRectLayer>(),
        reason: 'The material filter remains directly clipped.',
      );

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
    'material updates preserve filter clipping and reuse unchanged geometry',
    (tester) async {
      await tester.pumpWidget(glass());
      await tester.pumpAndSettle();
      await pumpUntilGlassReady(tester);

      final renderObject = findLayer(tester);
      expect(
        renderObject.debugBackdropFilterLayer?.parent,
        isA<ClipRectLayer>(),
      );
      final firstGeometry = renderObject.gpuGeometryRenderer?.debugRenderCount;

      renderObject.markNeedsPaint();
      await tester.pump();

      expect(
        renderObject.debugBackdropFilterLayer?.parent,
        isA<ClipRectLayer>(),
      );
      expect(renderObject.gpuGeometryRenderer?.debugRenderCount, firstGeometry);

      await tester.pumpWidget(
        glass(
          settings: const LiquidGlassSettings(frost: 8),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        renderObject.debugBackdropFilterLayer?.parent,
        isA<ClipRectLayer>(),
      );
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'rebuilds the filter when settings change the shader uniforms',
    (tester) async {
      await tester.pumpWidget(glass());
      await tester.pumpAndSettle();
      await pumpUntilGlassReady(tester);

      final renderObject = findLayer(tester);
      final firstFilter = renderObject.debugBackdropFilterLayer?.filter;
      expect(firstFilter, isNotNull);

      await tester.pumpWidget(
        glass(settings: const LiquidGlassSettings(frost: 8)),
      );
      await tester.pumpAndSettle();

      final rebuilt = renderObject.debugBackdropFilterLayer?.filter;
      expect(rebuilt, isNotNull);
      expect(rebuilt, isNot(same(firstFilter)));
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'snapshots new coordinates without rerendering geometry on ancestor motion',
    (tester) async {
      Widget movedGlass(Offset offset) => CupertinoApp(
        home: Transform.translate(
          offset: offset,
          child: glass(),
        ),
      );

      await tester.pumpWidget(movedGlass(Offset.zero));
      await tester.pumpAndSettle();
      await pumpUntilGlassReady(tester);

      final renderObject = findLayer(tester);
      final firstFilter = renderObject.debugBackdropFilterLayer?.filter;
      expect(firstFilter, isNotNull);

      final geometryPasses = renderObject.gpuGeometryRenderer!.debugRenderCount;

      await tester.pumpWidget(movedGlass(const Offset(12, 8)));
      // The geometry stays retained, but each native filter must capture its
      // own coordinates instead of mutating an older frame's shared texture.
      tester.binding.scheduleFrame();
      await tester.pump();

      expect(
        renderObject.debugBackdropFilterLayer?.filter,
        isNot(same(firstFilter)),
      );
      expect(
        renderObject.gpuGeometryRenderer!.debugRenderCount,
        geometryPasses,
      );
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'drops the backdrop filter while the sample is idle',
    (tester) async {
      await tester.pumpWidget(glass());
      await tester.pumpAndSettle();
      await pumpUntilGlassReady(tester);

      final renderObject = findLayer(tester);
      expect(renderObject.debugBackdropFilterLayer, isNotNull);
      final initialRenders = renderObject.gpuGeometryRenderer!.debugRenderCount;

      await tester.pumpWidget(
        glass(appearance: const LiquidGlassAppearance(visibility: 0)),
      );
      await tester.pumpAndSettle();

      expect(renderObject.debugBackdropFilterLayer, isNull);
      expect(
        renderObject.gpuGeometryRenderer!.debugRenderCount,
        initialRenders,
      );

      await tester.pumpWidget(glass());
      await tester.pumpAndSettle();

      expect(renderObject.debugBackdropFilterLayer, isNotNull);
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'keeps geometry matte bounds in layer space across ancestor motion',
    (tester) async {
      Widget movedGlass(Offset offset) => CupertinoApp(
        home: Transform.translate(
          offset: offset,
          child: glass(),
        ),
      );

      await tester.pumpWidget(movedGlass(Offset.zero));
      await tester.pumpAndSettle();
      await pumpUntilGlassReady(tester);

      final renderObject = findLayer(tester);
      final matteBounds = renderObject.debugGeometryMatteBounds;
      expect(matteBounds, isNot(Rect.zero));
      expect(
        MatrixUtils.matrixEquals(
          renderObject.matteTransform,
          Matrix4.identity(),
        ),
        isTrue,
      );

      await tester.pumpWidget(movedGlass(const Offset(40, -18)));
      tester.binding.scheduleFrame();
      await tester.pump();

      expect(renderObject.debugGeometryMatteBounds, matteBounds);
      expect(
        MatrixUtils.matrixEquals(
          renderObject.matteTransform,
          Matrix4.identity(),
        ),
        isTrue,
      );
    },
    skip: skipProperGlassTests,
  );
}
