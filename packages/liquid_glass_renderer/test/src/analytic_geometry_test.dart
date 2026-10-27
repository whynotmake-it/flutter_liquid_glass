import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import 'shared.dart';

const _key = ValueKey('analytic');
const _view = Size(300, 200);
const _gray = Color(0xFF808080);

Widget _scene({required bool tints, Matrix4? transform}) {
  LiquidGlassAppearance? tinted(Color color) =>
      tints ? LiquidGlassAppearance.ios27RegularLight(tint: color) : null;
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: RepaintBoundary(
        key: _key,
        child: SizedBox.fromSize(
          size: _view,
          child: ColoredBox(
            color: _gray,
            child: _transformed(
              transform,
              LiquidGlassLayer(
                analyticGeometry: true,
                settings: LiquidGlassSettings.ios27RegularLight(),
                // A paint over a solid color, not a backdrop filter:
                // flutter_tester renders only a process's first backdrop
                // filter reliably.
                backdrop: const LiquidGlassBackdrop.solid(_gray),
                child: Stack(
                  children: [
                    Positioned(
                      left: 16,
                      top: 20,
                      width: 140,
                      height: 160,
                      child: LiquidGlass(
                        shape: const LiquidRoundedSuperellipse(
                          borderRadius: 16,
                          bottomRadius: 44,
                        ),
                        appearance: tinted(const Color(0x66FF3B30)),
                        child: const SizedBox.expand(),
                      ),
                    ),
                    Positioned(
                      left: 170,
                      top: 24,
                      width: 110,
                      height: 70,
                      child: LiquidGlass(
                        shape: const LiquidOval(),
                        appearance: tinted(const Color(0x6634C759)),
                        child: const SizedBox.expand(),
                      ),
                    ),
                    Positioned(
                      left: 170,
                      top: 110,
                      width: 110,
                      height: 70,
                      child: LiquidGlass(
                        shape: const LiquidRoundedRectangle(borderRadius: 18),
                        appearance: tinted(const Color(0x66007AFF)),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _transformed(Matrix4? transform, Widget child) => transform == null
    ? child
    : Transform(
        transform: transform,
        alignment: Alignment.center,
        child: child,
      );

/// The scene at the view's own pixel ratio: a capture at another scale
/// resamples the matte, which the screen never does.
Future<Uint8List> _capture(WidgetTester tester, double ratio) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_key),
  );
  final image = (await tester.runAsync(
    () => boundary.toImage(pixelRatio: ratio),
  ))!;
  final bytes = (await tester.runAsync(image.toByteData))!;
  image.dispose();
  return bytes.buffer.asUint8List();
}

RenderLiquidGlassLayer _layer(WidgetTester tester) =>
    tester.allRenderObjects.whereType<RenderLiquidGlassLayer>().toSet().single;

/// The mean channel difference and the share of channels that differ by
/// more than 16.
(double, double) _difference(Uint8List a, Uint8List b) {
  var total = 0;
  var differing = 0;
  for (var i = 0; i < a.length; i++) {
    final d = (a[i] - b[i]).abs();
    total += d;
    if (d > 16) differing++;
  }
  return (total / a.length, differing / a.length);
}

Future<(double, double)> _analyticAgainstRest(
  WidgetTester tester,
  Widget scene,
  double ratio,
) async {
  tester.view
    ..physicalSize = _view * ratio
    ..devicePixelRatio = ratio;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(scene);
  expect(_layer(tester).debugAnalytic, isTrue);
  final analytic = await _capture(tester, ratio);

  for (var i = 0; i < RenderLiquidGlassLayer.analyticRestFrames + 2; i++) {
    await tester.pump();
  }
  expect(_layer(tester).debugAnalytic, isFalse, reason: 'rests on a matte');
  final matte = await _capture(tester, ratio);
  // The glass draws: its edges and highlights leave the gray.
  final glass = [
    for (var i = 0; i < matte.length; i += 4)
      if ((matte[i] - 0x80).abs() > 8) i,
  ];
  expect(glass.length * 4 / matte.length, greaterThan(0.02));
  return _difference(matte, analytic);
}

void main() {
  for (final (name, ratio, transform) in [
    ('1x', 1.0, null),
    ('2x', 2.0, null),
    ('3x', 2.625, null),
    ('turned', 1.0, Matrix4.rotationZ(0.2)),
    ('scaled', 1.0, Matrix4.diagonal3Values(0.8, 0.8, 1)),
    (
      '3x, scaled and turned',
      2.625,
      Matrix4.rotationZ(0.2)..scaleByDouble(0.8, 0.8, 1, 1),
    ),
  ]) {
    testWidgets('an analytic frame draws what its matte draws ($name)', (
      tester,
    ) async {
      final (mean, share) = await _analyticAgainstRest(
        tester,
        _scene(tints: false, transform: transform),
        ratio,
      );
      expect(mean, lessThan(0.05));
      expect(share, lessThan(0.0005));
    }, skip: skipProperGlassTests);
  }

  Widget blendScene() => Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: RepaintBoundary(
        key: _key,
        child: SizedBox.fromSize(
          size: _view,
          child: ColoredBox(
            color: _gray,
            child: LiquidGlassLayer(
              analyticGeometry: true,
              settings: LiquidGlassSettings.ios27RegularLight(),
              backdrop: const LiquidGlassBackdrop.solid(_gray),
              child: Center(
                child: LiquidGlassBlendGroup(
                  blend: 30,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < 2; i++) ...[
                        const LiquidGlass.grouped(
                          shape: LiquidOval(),
                          child: SizedBox.square(dimension: 80),
                        ),
                        const SizedBox(width: 12),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('a blended analytic frame draws what its matte draws', (
    tester,
  ) async {
    final (mean, share) = await _analyticAgainstRest(tester, blendScene(), 2);
    expect(mean, lessThan(0.05));
    expect(share, lessThan(0.0005));
  }, skip: skipProperGlassTests);

  // Separate shapes over each other, as a segmented control's thumb over
  // its track: the thumb's box holds pixels of both.
  Widget trackScene(Matrix4? transform) => Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: RepaintBoundary(
        key: _key,
        child: SizedBox.fromSize(
          size: _view,
          child: ColoredBox(
            color: _gray,
            child: _transformed(
              transform,
              LiquidGlassLayer(
                analyticGeometry: true,
                settings: LiquidGlassSettings.ios27RegularLight(),
                backdrop: const LiquidGlassBackdrop.solid(_gray),
                child: const Stack(
                  children: [
                    Positioned(
                      left: 10,
                      top: 40,
                      width: 280,
                      height: 120,
                      child: LiquidGlass(
                        shape: LiquidRoundedSuperellipse(borderRadius: 40),
                        child: SizedBox.expand(),
                      ),
                    ),
                    Positioned(
                      left: 120,
                      top: 56,
                      width: 110,
                      height: 88,
                      child: LiquidGlass(
                        // A capsule, radius half its height: the largest
                        // radius shapeDepthBound bounds.
                        shape: LiquidRoundedSuperellipse(borderRadius: 44),
                        child: SizedBox.expand(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  for (final (name, ratio, transform) in [
    ('1x', 1.0, null),
    (
      '3x, scaled and turned',
      2.625,
      Matrix4.rotationZ(0.2)..scaleByDouble(0.9, 0.7, 1, 1),
    ),
  ]) {
    testWidgets('a thumb over its track draws what its matte draws ($name)', (
      tester,
    ) async {
      final (mean, share) = await _analyticAgainstRest(
        tester,
        trackScene(transform),
        ratio,
      );
      expect(mean, lessThan(0.05));
      expect(share, lessThan(0.0005));
    }, skip: skipProperGlassTests);
  }

  testWidgets('a sparse layer keeps the matte', (tester) async {
    final maxEmptyTests = RenderLiquidGlassLayer.analyticMaxEmptyTests;
    addTearDown(
      () => RenderLiquidGlassLayer.analyticMaxEmptyTests = maxEmptyTests,
    );
    RenderLiquidGlassLayer.analyticMaxEmptyTests = 10000;
    await tester.pumpWidget(_scene(tints: false));
    expect(_layer(tester).debugAnalytic, isFalse);
    expect(_layer(tester).debugAnalyticIneligibility, 'sparse');
  }, skip: skipProperGlassTests);

  testWidgets('shapes with their own appearances keep the matte', (
    tester,
  ) async {
    await tester.pumpWidget(_scene(tints: true));
    expect(_layer(tester).debugAnalytic, isFalse);
    expect(_layer(tester).debugAnalyticIneligibility, 'shape appearances');
  }, skip: skipProperGlassTests);
}
