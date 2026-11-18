// Glass under a sheet is drawn again into the sheet's image. Its copy lies in
// its layer's corner, and the image cuts that layer. The black this led to
// shows on Metal alone, so the test holds the layer to the cut rather than
// looking at pixels.
@Tags(['macos_pixels'])
library;

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/painting/glass_work.dart';
import 'package:liquid_glass_renderer/src/plan/impeller.dart';
import 'package:liquid_glass_renderer/src/plan/plan.dart';
import 'package:liquid_glass_renderer/src/plan/plan_result.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_composer.dart';
import 'package:liquid_glass_renderer/src/rendering/read.dart';

Widget _glass(Rect rect, double glint, {double frost = 1.5}) =>
    Positioned.fromRect(
      rect: rect,
      child: LiquidGlassLayer(
        // A frost that a copy at half the screen's pixels bakes in place.
        settings: LiquidGlassSettings.ios27Regular(
          brightness: Brightness.light,
          frost: LiquidGlassFrost.sigma(frost),
        ).copyWith(glintStrength: glint),
        child: const LiquidGlass(
          shape: LiquidRoundedSuperellipse(radius: 30),
          child: SizedBox.expand(),
        ),
      ),
    );

void main() {
  setUp(() => glassReadsCopies = true);
  tearDown(() {
    glassReadsCopies = false;
    debugGlassPolicy = const PlanPolicy();
    GlassComposer.debugOnPlan = null;
  });

  testWidgets('a smaller copy held by a moving sheet starts inside its image', (
    tester,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    // Over budget the sheet reads an image and the glass under it stays live,
    // as on a screen of glass: the budget is the glass's own five targets,
    // its filter, the two axes of its frost and the two layers of its haze.
    debugGlassPolicy = const PlanPolicy(maxTargets: 5);
    GlassPlan? plan;
    GlassComposer.debugOnPlan = (_, next) => plan = next;

    // The sheet's image cuts less than 30 % off the layer of the glass under
    // it, which Impeller would draw whole.
    Widget frame(double spot) => Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: Color(0xFF00E000))),
          // Changes under the glass every frame, so that it reads no image.
          Positioned(
            left: spot,
            top: 240,
            width: 20,
            height: 20,
            child: const ColoredBox(color: Color(0xFF00D000)),
          ),
          _glass(const Rect.fromLTWH(30, 260, 180, 180), 0.3),
          _glass(const Rect.fromLTWH(8, 310, 386, 564), 0.4),
        ],
      ),
    );
    await tester.pumpWidget(frame(100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpWidget(frame(104));
    await tester.pumpWidget(frame(100));

    final [glass, sheet] = plan!.reads;
    expect(glass.source, isA<SceneRead>());
    expect(glass.share, 2);
    expect(glass.layout.bakedFrost, greaterThan(0));
    expect(sheet.source, isA<ImageRead>());
    expect(sheet.holds, contains(glass));

    final copy = glass.layout;
    final image = sheet.layout;
    expect(copy.layerRect.top, lessThan(image.footprintRect.top));
    expect(
      ImpellerLayers.keepsWhole(copy.layerRect, image.footprintRect),
      isTrue,
    );
    expect(copy.heldIn(image).top, image.footprintRect.top);
  });

  testWidgets('glass held by a copy over it keeps its filters while it holds '
      'still', (tester) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    GlassPlan? plan;
    GlassComposer.debugOnPlan = (_, next) => plan = next;

    Widget frame(double spot) => Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: Color(0xFF00E000))),
          // Changes under the glass every frame, so that each frame plans.
          Positioned(
            left: spot,
            top: 100,
            width: 20,
            height: 20,
            child: const ColoredBox(color: Color(0xFF00D000)),
          ),
          _glass(const Rect.fromLTWH(40, 80, 80, 80), 0.3),
          _glass(const Rect.fromLTWH(20, 60, 300, 200), 0.4, frost: 4),
        ],
      ),
    );
    await tester.pumpWidget(frame(60));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pumpWidget(frame(60.0 + i));
    }
    final [glass, sheet] = plan!.reads;
    expect(glass.source, isA<SceneRead>());
    expect(sheet.source, isA<SceneRead>());
    expect(sheet.share, greaterThan(1));
    expect(sheet.holds, contains(glass));

    GlassWork.filters = 0;
    for (var i = 0; i < 8; i++) {
      await tester.pumpWidget(frame(64.0 + i));
    }
    expect(GlassWork.filters, 0);
  });
}
