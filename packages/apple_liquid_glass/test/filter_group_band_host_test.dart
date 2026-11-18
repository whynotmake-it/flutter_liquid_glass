@Tags(['macos_pixels'])
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/rendering.dart';
// Run with `flutter test --enable-impeller --enable-flutter-gpu`: the band and
// the glass over it are drawn by runtime effects, which only Impeller draws.
//
// A scroll edge and the button over it draw in the button's filter as they
// draw in filters of their own.

import 'package:liquid_glass_renderer/src/plan/plan.dart';
import 'package:liquid_glass_renderer/src/rendering/backdrop_filter_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_haze.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_composer.dart';

const _viewSize = Size(300, 400);

class _CapturingView extends TestFlutterView {
  _CapturingView(WidgetTester tester)
    : super(
        view: tester.view,
        platformDispatcher: tester.platformDispatcher,
        display: tester.view.display,
      ) {
    physicalSize = _viewSize * 2;
    devicePixelRatio = 2;
  }

  ui.Image? last;

  @override
  void render(ui.Scene scene, {Size? size}) {
    last?.dispose();
    last = scene.toImageSync(
      _viewSize.width.toInt() * 2,
      _viewSize.height.toInt() * 2,
    );
  }
}

Widget _page(
  _CapturingView view,
  ScrollController controller, {
  required bool hard,
  bool tints = false,
}) => View(
  view: view,
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: GlassScope(
      renderer: const LiquidGlassRenderer(),
      child: Stack(
        children: [
          GlassPageScaffold(
            backgroundColor: const Color(0xFFFFFFFF),
            navigationBar: const PreferredSize(
              preferredSize: Size.fromHeight(60),
              child: SizedBox(height: 60),
            ),
            child: GlassContentScroll(
              edgeEffects: GlassScrollEdgeEffects(
                top: hard
                    ? GlassScrollEdgeEffect.hard
                    : GlassScrollEdgeEffect.soft,
              ),
              child: ListView(
                controller: controller,
                children: [
                  for (var i = 0; i < 40; i++)
                    Container(
                      height: 30,
                      color: Color(0xFF000000 | (i * 2654435761) & 0xFFFFFF),
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 16,
            top: 10,
            width: tints ? 100 : 44,
            height: 44,
            child: LiquidGlassLayer(
              settings: const LiquidGlassSettings.ios27Regular(
                brightness: Brightness.light,
              ),
              child: tints
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (final tint in [
                          const Color(0x40FF3B30),
                          const Color(0x40007AFF),
                        ])
                          SizedBox.square(
                            dimension: 44,
                            child: LiquidGlass(
                              shape: const LiquidRoundedSuperellipse(
                                radius: 22,
                              ),
                              appearance: LiquidGlassAppearance.ios27Regular(
                                brightness: Brightness.light,
                                tint: tint,
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                      ],
                    )
                  : const LiquidGlass(
                      shape: LiquidRoundedSuperellipse(radius: 22),
                      child: SizedBox.expand(),
                    ),
            ),
          ),
        ],
      ),
    ),
  ),
);

Future<(Uint8List, bool)> _draw(
  WidgetTester tester,
  _CapturingView view, {
  required bool hard,
  required bool groups,
  bool held = false,
  bool tints = false,
}) async {
  debugGlassPolicy = groups
      ? const PlanPolicy()
      : const PlanPolicy(maxShapes: 0);
  final controller = ScrollController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    View(view: view, child: const SizedBox()),
    wrapWithView: false,
  );
  await tester.pumpWidget(
    _page(view, controller, hard: hard, tints: tints),
    wrapWithView: false,
  );
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  await tester.pump();
  controller.jumpTo(200);
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  final band = tester.layers.whereType<LiquidGlassBackdropFilterLayer>().single;
  if (held) {
    // A read that stood still long enough reads an image.
    for (var i = 0; i < 600 && band.debugImageCopy == null; i++) {
      tester.binding.scheduleFrame();
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(band.debugImageCopy, isNotNull);
  }
  final merged = band.drawsGroup;
  final data = (await tester.runAsync(view.last!.toByteData))!;
  return (data.buffer.asUint8List(), merged);
}

void main() {
  // Glass that mixes a haze into its copy leaves a scroll edge to a read of
  // its own: these hold the join of glass frosted by one blur.
  setUp(() {
    glassReadsCopies = true;
    debugGlassHaze = false;
  });
  tearDown(() {
    glassReadsCopies = false;
    debugGlassHaze = null;
    debugGlassPolicy = const PlanPolicy();
  });

  for (final hard in [true, false]) {
    testWidgets('a ${hard ? 'hard' : 'soft'} edge joins the glass over it', (
      tester,
    ) async {
      if (!ui.ImageFilter.isShaderFilterSupported) return;
      final view = _CapturingView(tester);
      final (alone, mergedAlone) = await _draw(
        tester,
        view,
        hard: hard,
        groups: false,
      );
      final (merged, mergedOn) = await _draw(
        tester,
        view,
        hard: hard,
        groups: true,
      );
      expect(mergedAlone, isFalse);
      expect(mergedOn, isTrue);
      var sum = 0;
      var most = 0;
      for (var i = 0; i < alone.length; i++) {
        if (i % 4 == 3) continue;
        final delta = (alone[i] - merged[i]).abs();
        sum += delta;
        if (delta > most) most = delta;
      }
      final mean = sum / (alone.length * 3 / 4);
      expect(mean, lessThan(0.5), reason: 'mean $mean, most $most');
    });
  }

  // The glass draws the band's frost and fade for all the band covers, not
  // only under the glass.
  testWidgets('an edge and the glass over it cover the band over an image', (
    tester,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    final view = _CapturingView(tester);
    final (alone, _) = await _draw(tester, view, hard: false, groups: false);
    final (merged, mergedOn) = await _draw(
      tester,
      view,
      hard: false,
      groups: true,
      held: true,
    );
    expect(mergedOn, isTrue);
    var sum = 0;
    for (var i = 0; i < alone.length; i++) {
      if (i % 4 != 3) sum += (alone[i] - merged[i]).abs();
    }
    final mean = sum / (alone.length * 3 / 4);
    expect(mean, lessThan(2));
  });

  // Glass tinted shape by shape draws with a variant that has no band, so it
  // stays apart from the edge.
  testWidgets('glass tinted per shape over an edge draws as alone', (
    tester,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    final view = _CapturingView(tester);
    final (alone, _) = await _draw(
      tester,
      view,
      hard: false,
      groups: false,
      tints: true,
    );
    final (merged, mergedOn) = await _draw(
      tester,
      view,
      hard: false,
      groups: true,
      tints: true,
    );
    expect(mergedOn, isFalse);
    var sum = 0;
    for (var i = 0; i < alone.length; i++) {
      if (i % 4 != 3) sum += (alone[i] - merged[i]).abs();
    }
    expect(sum / (alone.length * 3 / 4), lessThan(0.5));
  });
}
