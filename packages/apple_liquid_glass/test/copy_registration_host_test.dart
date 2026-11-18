// Where content lies under frosted glass against where the page has it.
// Glass is fake without `--enable-impeller --enable-flutter-gpu`, and the
// tests skip.
@Tags(['macos_pixels'])
library;

import 'dart:ui' as ui;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_haze.dart';
import 'package:liquid_glass_renderer/src/rendering/read.dart';

const _key = ValueKey('page');

Widget _page(
  double dpr, {
  required bool glass,
  required double tint,
  double textAt = 250.11,
}) => MediaQuery(
  data: MediaQueryData(size: const Size(402, 300), devicePixelRatio: dpr),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: GlassScope(
      renderer: const LiquidGlassRenderer(),
      child: GlassTraitsOverride(
        glassTintAmount: tint,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 402,
            height: 300,
            child: RepaintBoundary(
              key: _key,
              child: ColoredBox(
                color: const Color(0xFF000000),
                child: Stack(
                  children: [
                    const Positioned(
                      left: 120.37,
                      top: 40,
                      child: SizedBox(
                        width: 6,
                        height: 220,
                        child: ColoredBox(color: Color(0xFFFFFFFF)),
                      ),
                    ),
                    Positioned(
                      left: textAt,
                      top: 142,
                      child: const Text(
                        'X',
                        style: TextStyle(
                          color: Color(0xFFFFFFFF),
                          fontSize: 16,
                          height: 1,
                        ),
                      ),
                    ),
                    if (glass)
                      const Positioned(
                        left: 40.7,
                        top: 80.3,
                        child: SizedBox(
                          width: 320,
                          height: 140,
                          child: GlassSurface(
                            shape: LiquidRoundedSuperellipse(radius: 40),
                            glass: Glass.clear(),
                            child: SizedBox.expand(),
                          ),
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
  ),
);

// The centers, in device pixels, of the bar and of the glyph along the row
// through the glass's middle: each column weighed by what it shows over the
// darkest of its row.
Future<(double, double)> _centers(
  WidgetTester tester,
  double dpr, {
  required bool glass,
  double textAt = 250.11,
}) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    _page(dpr, glass: glass, tint: 0.35, textAt: textAt),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_key));
  final image = (await tester.runAsync(
    () => boundary.toImage(pixelRatio: dpr),
  ))!;
  final bytes = (await tester.runAsync(image.toByteData))!.buffer.asUint8List();
  final width = image.width;
  image.dispose();
  double center(double from, double to) {
    var sum = 0.0;
    var weighted = 0.0;
    for (var y = (146 * dpr).round(); y < (154 * dpr).round(); y++) {
      var darkest = 255;
      for (var x = (from * dpr).round(); x < (to * dpr).round(); x++) {
        final value = bytes[(y * width + x) * 4];
        if (value < darkest) darkest = value;
      }
      for (var x = (from * dpr).round(); x < (to * dpr).round(); x++) {
        final value = bytes[(y * width + x) * 4] - darkest;
        sum += value;
        weighted += value * (x + 0.5);
      }
    }
    return weighted / sum;
  }

  return (center(95, 152), center(225, 295));
}

void main() {
  for (final dpr in [2.625, 3.0]) {
    testWidgets('a shape under frosted glass lies where the page has it, and '
        'text up to three quarters of a pixel of the copy right of it '
        '(dpr $dpr)', (tester) async {
      tester.view.physicalSize = const Size(402, 300) * dpr;
      tester.view.devicePixelRatio = dpr;
      addTearDown(tester.view.reset);
      glassReadsCopies = true;
      addTearDown(() => glassReadsCopies = false);
      final (bar, text) = await _centers(tester, dpr, glass: false);
      final (frostedBar, frostedText) = await _centers(
        tester,
        dpr,
        glass: true,
      );
      expect(frostedBar - bar, closeTo(0, 0.3));
      // NEAR, see CopyPlace.deviceToCopy: a copy holds four device pixels a
      // side at most.
      expect(frostedText - text, inInclusiveRange(-0.3, 3.3));
    }, skip: !ui.ImageFilter.isShaderFilterSupported);
  }

  // What Impeller does with text under the copy's skew: this is the engine's
  // behaviour, held here so that a change of it shows.
  testWidgets('text under frosted glass stands right of its place by the '
      "fraction of the copy's pixel it lies at", (tester) async {
    const dpr = 3.0;
    tester.view.physicalSize = const Size(402, 300) * dpr;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);
    glassReadsCopies = true;
    addTearDown(() => glassReadsCopies = false);
    // Glass frosted by one blur reads a coarse copy; under its haze a bar
    // shows the page sharp, from a copy that moves text by far less.
    debugGlassHaze = false;
    addTearDown(() => debugGlassHaze = null);
    // The copy holds four device pixels a side here; a third of a logical
    // pixel is a quarter of one of its own.
    for (final (quarters, shift) in [(0, 0.0), (1, 1.0), (2, 2.0), (3, 3.0)]) {
      // 752 device pixels is a whole pixel of the copy.
      final at = (752 + quarters) / dpr;
      final (_, text) = await _centers(tester, dpr, glass: false, textAt: at);
      final (_, frosted) = await _centers(
        tester,
        dpr,
        glass: true,
        textAt: at,
      );
      expect(frosted - text, closeTo(shift, 0.25), reason: '$quarters');
    }
  }, skip: !ui.ImageFilter.isShaderFilterSupported);
}
