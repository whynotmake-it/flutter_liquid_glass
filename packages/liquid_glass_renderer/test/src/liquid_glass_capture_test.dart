import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/capture_pass.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_capture.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import 'capture_scenes.dart';
import 'shared.dart';

/// Sizing and coordinate invariants of [LiquidGlassCapture]. The pixel
/// comparisons live in `liquid_glass_capture_<scene>_test.dart`, one per
/// file; see `capture_scenes.dart` for why.
void main() {
  testWidgets('capture covers every glass layer inside it', (tester) async {
    for (final fake in [true, false]) {
      const scene = CaptureScene('cover', shadow: true, indicator: true);
      await pumpCaptureScene(
        tester,
        scene,
        fake: fake,
        capture: true,
      );
      final capture = tester.renderObject<RenderLiquidGlassCapture>(
        find.byType(LiquidGlassCapture),
      );
      final layers = tester
          .renderObjectList<RenderObject>(find.byType(LiquidGlassLayer))
          .expand(glassLayersBelow)
          .toList();
      expect(layers, isNotEmpty);
      final box = Offset.zero & capture.size;
      for (final layer in layers) {
        final bounds = layer.effectBounds!;
        final inCapture = MatrixUtils.transformRect(
          (layer as RenderObject).getTransformTo(capture),
          bounds,
        );
        final rect = capture.captureRect;
        expect(
          inCapture.left >= rect.left - 1e-6 &&
              inCapture.top >= rect.top - 1e-6 &&
              inCapture.right <= rect.right + 1e-6 &&
              inCapture.bottom <= rect.bottom + 1e-6,
          isTrue,
          reason: 'capture $rect must contain $inCapture',
        );
      }
      expect(
        capture.captureRect.left < box.left &&
            capture.captureRect.bottom > box.bottom,
        isTrue,
        reason:
            'shadows and blur must reach past the layout box, or this test '
            'is not exercising automatic sizing',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
  }, skip: skipProperGlassTests);

  testWidgets('bleed replaces automatic sizing', (tester) async {
    const scene = CaptureScene('bleed', shadow: true);
    await tester.pumpWidget(
      captureSceneWidget(scene, fake: true, bleed: const EdgeInsets.all(10)),
    );
    await tester.pump();
    final capture = tester.renderObject<RenderLiquidGlassCapture>(
      find.byType(LiquidGlassCapture),
    );
    expect(
      capture.captureRect,
      const EdgeInsets.all(10).inflateRect(Offset.zero & capture.size),
    );
  });

  for (final dpr in [1.0, 2.0, 3.0]) {
    testWidgets(
      'pass origin is device-pixel aligned at DPR $dpr',
      (
        tester,
      ) async {
        tester.view
          ..physicalSize = Size(320 * dpr, 240 * dpr)
          ..devicePixelRatio = dpr;
        addTearDown(tester.view.reset);
        const scene = CaptureScene('origin', shadow: true, edge: true);
        await tester.pumpWidget(captureSceneWidget(scene, fake: false));
        await tester.pump();
        final capture = tester.renderObject<RenderLiquidGlassCapture>(
          find.byType(LiquidGlassCapture),
        );
        final global = MatrixUtils.transformPoint(
          capture.getTransformTo(null),
          capture.passOrigin,
        );
        expect((global.dx * dpr) % 1, closeTo(0, 1e-6));
        expect((global.dy * dpr) % 1, closeTo(0, 1e-6));
        // The screen clamps the capture; the edge scene reaches past it.
        expect(global.dx, greaterThanOrEqualTo(0));
        expect(global.dy, greaterThanOrEqualTo(0));

        final layer =
            glassLayersBelow(
                  tester.renderObject<RenderObject>(
                    find.byType(LiquidGlassLayer),
                  ),
                ).single
                as RenderLiquidGlassLayer;
        final expected = layer.getTransformTo(capture)
          ..leftTranslateByDouble(
            -capture.passOrigin.dx,
            -capture.passOrigin.dy,
            0,
            1,
          );
        expect(
          layer.shaderCoordinateTransform.storage,
          orderedEquals(expected.storage),
        );
      },
      skip: skipProperGlassTests,
    );
  }

  testWidgets(
    'capture rect tracks paint-only shape motion',
    (tester) async {
      for (final fake in [true, false]) {
        final offset = ValueNotifier(const Offset(0, 40));
        addTearDown(offset.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: LiquidGlassCapture(
                child: SizedBox(
                  width: 300,
                  height: 200,
                  child: LiquidGlassLayer(
                    fake: fake,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ValueListenableBuilder<Offset>(
                        valueListenable: offset,
                        builder: (_, value, __) => Transform.translate(
                          offset: value,
                          child: const LiquidGlass(
                            shape: LiquidRoundedSuperellipse(borderRadius: 22),
                            child: SizedBox(width: 120, height: 44),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        final capture = tester.renderObject<RenderLiquidGlassCapture>(
          find.byType(LiquidGlassCapture),
        );
        offset.value = Offset.zero;
        // A paint-only change must not need a capture repaint: the retained
        // clip layer refreshes the region during compositing.
        await tester.pump();

        final fresh = CapturePass().computeRegion(capture);
        final rect = capture.captureRect;
        expect(fresh, isNotNull);
        expect(
          fresh!.left >= rect.left - 1 &&
              fresh.top >= rect.top - 1 &&
              fresh.right <= rect.right + 1 &&
              fresh.bottom <= rect.bottom + 1,
          isTrue,
          reason:
              'fake=$fake: captureRect $rect must contain the freshly '
              'computed region $fresh',
        );
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
    skip: skipProperGlassTests,
  );

  testWidgets('nested captures resolve to the nearest one', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: LiquidGlassCapture(
          child: Center(
            child: LiquidGlassCapture(
              child: LiquidGlassLayer(
                fake: true,
                child: LiquidGlass(
                  shape: LiquidOval(),
                  child: SizedBox(width: 60, height: 30),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final captures = tester
        .renderObjectList<RenderLiquidGlassCapture>(
          find.byType(LiquidGlassCapture),
        )
        .toList();
    final layer = tester.renderObject<RenderObject>(
      find.byType(LiquidGlassLayer),
    );
    expect(RenderLiquidGlassCapture.enclosing(layer), same(captures.last));
    expect(
      captures.first.captureRect.contains(
        MatrixUtils.transformPoint(
          captures.last.getTransformTo(captures.first),
          captures.last.captureRect.bottomRight,
        ),
      ),
      isTrue,
      reason: 'the outer capture must contain the inner one',
    );
  });
}
