import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import 'shared.dart';

void main() {
  // 6 device px of frost at 3x: past the in-shader kernel, so the filter
  // composes a blur pass.
  const blurred = LiquidGlassSettings(highlight: 0, frost: 2);

  const glass = LiquidGlass(
    shape: LiquidRoundedSuperellipse(borderRadius: 40),
    child: SizedBox(width: 160, height: 110),
  );

  // The clip leaves a margin around the glass that is narrower than the
  // filter's own clip, which is rounded out to 64 device px buckets.
  Widget clipped(Widget child) => ClipRect(
    child: SizedBox(
      width: 186,
      height: 130,
      child: Stack(
        textDirection: TextDirection.ltr,
        children: [Positioned(left: 20, top: 10, child: child)],
      ),
    ),
  );

  Widget scene(Widget child) => Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(100, 100, 0, 0),
        child: child,
      ),
    ),
  );

  RenderLiquidGlassLayer glassLayer(WidgetTester tester) => tester
      .allRenderObjects
      .whereType<RenderLiquidGlassLayer>()
      .where((layer) => layer.debugBackdropFilterLayer != null)
      .toSet()
      .single;

  Rect clipInLayer(WidgetTester tester, RenderLiquidGlassLayer layer) {
    final clip = tester.renderObject<RenderClipRect>(find.byType(ClipRect));
    return MatrixUtils.transformRect(
      Matrix4.inverted(layer.getTransformTo(clip)),
      Offset.zero & clip.size,
    );
  }

  Future<void> pump(WidgetTester tester, Widget widget) async {
    tester.view
      ..physicalSize = const Size(1200, 900)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(scene(widget));
    await tester.pump();
  }

  testWidgets(
    'unclipped glass mirrors at its own filter clip',
    (tester) async {
      await pump(
        tester,
        const LiquidGlassLayer(settings: settingsWithoutLighting, child: glass),
      );
      final layer = glassLayer(tester);
      expect(layer.debugBackdropSampleBounds, layer.debugFilterBounds);
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'a clip above the layer shrinks the captured backdrop',
    (tester) async {
      await pump(
        tester,
        clipped(const LiquidGlassLayer(settings: blurred, child: glass)),
      );
      final layer = glassLayer(tester);
      final clip = clipInLayer(tester, layer);
      expect(clip, const Rect.fromLTRB(-20, -10, 166, 120));
      expect(
        layer.debugBackdropSampleBounds,
        layer.debugFilterBounds!.intersect(clip),
      );
      expect(layer.debugBackdropSampleBounds, isNot(layer.debugFilterBounds));
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'a clip between the layer and its glass shrinks the captured backdrop',
    (tester) async {
      await pump(
        tester,
        LiquidGlassLayer(settings: blurred, child: clipped(glass)),
      );
      final layer = glassLayer(tester);
      final clip = clipInLayer(tester, layer);
      expect(
        layer.debugBackdropSampleBounds,
        layer.debugFilterBounds!.intersect(clip),
      );
      expect(layer.debugBackdropSampleBounds, isNot(layer.debugFilterBounds));
    },
    skip: skipProperGlassTests,
  );

  for (final frost in [0.0, 0.35]) {
    testWidgets(
      'without a blur pass (frost $frost) ancestor clips keep the backdrop',
      (tester) async {
        // Unblurred, the filter input still holds real backdrop outside
        // ancestor clips, so only the filter's own clip bounds it.
        await pump(
          tester,
          clipped(
            LiquidGlassLayer(
              settings: LiquidGlassSettings(highlight: 0, frost: frost),
              child: glass,
            ),
          ),
        );
        final layer = glassLayer(tester);
        expect(layer.blurPassSigma, 0);
        expect(layer.debugBackdropSampleBounds, layer.debugFilterBounds);
      },
      skip: skipProperGlassTests,
    );
  }

  testWidgets(
    'a list viewport only clips the backdrop while its content overflows',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      Widget scroll({required double contentHeight}) => SizedBox(
        width: 186,
        height: 130,
        child: ListView(
          controller: controller,
          padding: EdgeInsets.zero,
          children: [
            SizedBox(
              height: contentHeight,
              child: const Stack(
                textDirection: TextDirection.ltr,
                children: [Positioned(left: 20, top: 10, child: glass)],
              ),
            ),
          ],
        ),
      );

      await pump(
        tester,
        LiquidGlassLayer(
          settings: blurred,
          child: scroll(contentHeight: 130),
        ),
      );
      var layer = glassLayer(tester);
      expect(layer.debugBackdropSampleBounds, layer.debugFilterBounds);

      await pump(
        tester,
        LiquidGlassLayer(
          settings: blurred,
          child: scroll(contentHeight: 400),
        ),
      );
      layer = glassLayer(tester);
      expect(
        layer.debugBackdropSampleBounds,
        layer.debugFilterBounds!.intersect(
          const Rect.fromLTWH(0, 0, 186, 130),
        ),
      );
      expect(layer.debugBackdropSampleBounds, isNot(layer.debugFilterBounds));

      // Scrolled glass moves under the viewport, which stays put in the
      // layer: the captured rect must still end at the viewport's edges.
      controller.jumpTo(20);
      await tester.pump();
      layer = glassLayer(tester);
      final translation = layer.debugCompositorTranslation;
      final captured = layer.debugBackdropSampleBounds!.shift(translation);
      expect(captured.top, 0);
      expect(captured.right, 186);
      expect(captured.bottom, lessThanOrEqualTo(130));
    },
    skip: skipProperGlassTests,
  );
}
