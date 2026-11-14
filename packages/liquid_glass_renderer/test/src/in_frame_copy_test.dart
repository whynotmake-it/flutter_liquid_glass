@Tags(['macos_pixels'])
library;

// Run with `flutter test --enable-impeller --enable-flutter-gpu`: the copies
// are drawn as Impeller draws them.
import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/composer.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_haze.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_composer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/read.dart';
import 'package:material_ui/material_ui.dart';

import 'shared.dart';

const _key = ValueKey('screen');

// Glass at [top] over a gradient and text, and a second glass below it
// whose band holds the lower part of the first; [clip] cuts the first
// glass, in the screen's coordinates.
Widget _scene({
  double shift = 0,
  double top = 200,
  double frost = 0,
  bool second = true,
  double secondFrost = 0,
  Rect? clip,
  Color? tint,
}) {
  Widget glass(Rect rect, {double frost = 0, Color? tint}) => LiquidGlassLayer(
    settings: LiquidGlassSettings.ios27RegularLight().copyWith(frost: frost),
    child: Stack(
      children: [
        Positioned.fromRect(
          rect: rect,
          child: LiquidGlass(
            shape: const LiquidRoundedSuperellipse(borderRadius: 28),
            appearance: tint == null
                ? null
                : LiquidGlassAppearance.ios27RegularLight(tint: tint),
            child: const SizedBox.expand(),
          ),
        ),
      ],
    ),
  );

  final first = glass(
    Rect.fromLTWH(30, top, 200, 90),
    frost: frost,
    tint: tint,
  );
  return Directionality(
    textDirection: TextDirection.ltr,
    child: RepaintBoundary(
      key: _key,
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: const [Color(0xFF1E3A8A), Color(0xFFF59E0B)],
                    begin: Alignment(-1 + shift, -1),
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
          for (var row = 0; row < 22; row++)
            Positioned(
              left: 12,
              top: 20.0 + row * 28,
              child: const Text(
                'WWWW iiii MMMM',
                style: TextStyle(fontSize: 18, color: Color(0xFFFFFFFF)),
              ),
            ),
          Positioned.fill(
            child: RepaintBoundary(
              child: clip == null
                  ? first
                  : ClipRect(clipper: _Clip(clip), child: first),
            ),
          ),
          if (second)
            Positioned.fill(
              child: RepaintBoundary(
                child: glass(
                  const Rect.fromLTWH(30, 260, 200, 60),
                  frost: secondFrost,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _Clip extends CustomClipper<Rect> {
  const _Clip(this.rect);

  final Rect rect;

  @override
  Rect getClip(Size size) => rect;

  @override
  bool shouldReclip(_Clip oldClipper) => oldClipper.rect != rect;
}

Future<Uint8List> _pixels(WidgetTester tester, double pixelRatio) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_key),
  );
  final image = (await tester.runAsync(
    () => boundary.toImage(pixelRatio: pixelRatio),
  ))!;
  final bytes = (await tester.runAsync(image.toByteData))!;
  image.dispose();
  return bytes.buffer.asUint8List();
}

int _difference(Uint8List a, Uint8List b) {
  var largest = 0;
  for (var i = 0; i < a.length; i++) {
    final d = (a[i] - b[i]).abs();
    if (d > largest) largest = d;
  }
  return largest;
}

// The scene drawn over copies, once what lies under the glass changed.
Future<Uint8List> _drawn(
  WidgetTester tester, {
  required bool inFrame,
  required double pixelRatio,
  double frost = 0,
  bool second = true,
  double secondFrost = 0,
  Rect? clip,
  double top = 200,
  Color? tint,
}) async {
  debugGlassPolicy = PlanPolicy(maxTargets: inFrame ? 64 : 0);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    _scene(
      shift: 0.3,
      top: top,
      frost: frost,
      second: second,
      secondFrost: secondFrost,
      clip: clip,
      tint: tint,
    ),
  );
  final drawn = GlassCopies.debugImagesDrawn;
  await tester.pumpWidget(
    _scene(
      top: top,
      frost: frost,
      second: second,
      secondFrost: secondFrost,
      clip: clip,
      tint: tint,
    ),
  );
  final glass = tester.allRenderObjects
      .whereType<RenderLiquidGlassLayer>()
      .toSet();
  expect(glass.every((g) => g.debugDrewOverCopy), isTrue);
  if (inFrame && secondFrost == 0) {
    expect(GlassCopies.debugImagesDrawn, drawn);
  }
  return _pixels(tester, pixelRatio);
}

void main() {
  setUp(() {
    debugGlassCopies = true;
    // These hold a copy against the backdrop read live, which draws no
    // haze: liquid_glass_haze_test holds the haze.
    debugGlassHaze = false;
  });
  tearDown(() {
    debugGlassCopies = null;
    debugGlassHaze = null;
    debugGlassPolicy = const PlanPolicy();
  });

  for (final pixelRatio in [1.0, 2.0]) {
    void sized(WidgetTester tester, {double height = 360}) {
      tester.view.physicalSize = Size(260, height) * pixelRatio;
      tester.view.devicePixelRatio = pixelRatio;
      addTearDown(tester.view.reset);
    }

    testWidgets('glass over a copy drawn in the frame draws what it draws '
        'over its image (dpr $pixelRatio)', (tester) async {
      sized(tester);
      final image = await _drawn(
        tester,
        inFrame: false,
        pixelRatio: pixelRatio,
        second: false,
      );
      final inFrame = await _drawn(
        tester,
        inFrame: true,
        pixelRatio: pixelRatio,
        second: false,
      );
      expect(_difference(image, inFrame), lessThanOrEqualTo(1));
    }, skip: skipProperGlassTests);

    // Both copies draw the lower glass as it lies inside the upper glass's
    // band, where it reads its own edge: an image folds it in as its
    // filter, the frame draws it again inside the band.
    testWidgets('a copy over glass drawn in the frame draws that glass again '
        'inside its band (dpr $pixelRatio)', (tester) async {
      sized(tester);
      final image = await _drawn(
        tester,
        inFrame: false,
        pixelRatio: pixelRatio,
      );
      final inFrame = await _drawn(
        tester,
        inFrame: true,
        pixelRatio: pixelRatio,
      );
      expect(_difference(image, inFrame), lessThanOrEqualTo(3));
    }, skip: skipProperGlassTests);

    testWidgets('frosted glass reads its copy from the corner of its layer '
        '(dpr $pixelRatio)', (tester) async {
      sized(tester);
      final image = await _drawn(
        tester,
        inFrame: false,
        pixelRatio: pixelRatio,
        frost: 6,
        second: false,
      );
      final inFrame = await _drawn(
        tester,
        inFrame: true,
        pixelRatio: pixelRatio,
        frost: 6,
        second: false,
      );
      expect(_difference(image, inFrame), lessThanOrEqualTo(1));
    }, skip: skipProperGlassTests);

    // The grown layer lands on the copy's pixel grid a pixel off the image's
    // edge at dpr 2, which moves a bilinear read by up to 2 levels.
    testWidgets('glass a clip cuts reads past the clip from a layer grown '
        'into it (dpr $pixelRatio)', (tester) async {
      sized(tester, height: 640);
      const clip = Rect.fromLTRB(0, 230, 260, 640);
      final image = await _drawn(
        tester,
        inFrame: false,
        pixelRatio: pixelRatio,
        second: false,
        clip: clip,
      );
      final inFrame = await _drawn(
        tester,
        inFrame: true,
        pixelRatio: pixelRatio,
        second: false,
        clip: clip,
      );
      expect(_difference(image, inFrame), lessThanOrEqualTo(2));
    }, skip: skipProperGlassTests);

    // NEAR: a layer the clip cuts holds nothing past it, so the 30 px of
    // glass left above the clip read their copy mirrored at the clip, up to
    // 168 levels off what lies under the glass's hidden part.
    testWidgets('glass a clip cuts with no room to grow reads its copy '
        'mirrored at the clip (dpr $pixelRatio)', (tester) async {
      sized(tester);
      const clip = Rect.fromLTRB(0, 0, 260, 230);
      final image = await _drawn(
        tester,
        inFrame: false,
        pixelRatio: pixelRatio,
        second: false,
        clip: clip,
      );
      final inFrame = await _drawn(
        tester,
        inFrame: true,
        pixelRatio: pixelRatio,
        second: false,
        clip: clip,
      );
      expect(_difference(image, inFrame), lessThanOrEqualTo(168));
    }, skip: skipProperGlassTests);
  }

  // The frost takes a copy at a quarter of the screen's pixels, which lies
  // in the corner of its layer; a layer grown past the clip leaves that
  // corner outside it and the glass reads nothing, 153 levels off.
  testWidgets('frosted glass over a smaller copy a clip cuts reads the copy', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(260, 640) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    const clip = Rect.fromLTRB(0, 230, 260, 640);
    final image = await _drawn(
      tester,
      inFrame: false,
      pixelRatio: 3,
      frost: 4.5,
      second: false,
      clip: clip,
    );
    final inFrame = await _drawn(
      tester,
      inFrame: true,
      pixelRatio: 3,
      frost: 4.5,
      second: false,
      clip: clip,
    );
    // The frost's dither lies on the layer's cell, which a clip shifts from
    // the image's: 14 levels over the test's hard bars.
    expect(_difference(image, inFrame), lessThanOrEqualTo(14));
  }, skip: skipProperGlassTests);

  // The lower glass's copy holds a quarter of the screen's pixels, and the
  // upper glass in it is drawn at those pixels, its shader taking each
  // fragment for 4 x 4 device pixels.
  testWidgets('a coarse copy holds the glass under it at its own pixels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(260, 360) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    addTearDown(GlassCopyTuning.debugOverride);
    GlassPlan? plan;
    GlassComposer.debugOnPlan = (_, next) => plan = next;
    addTearDown(() => GlassComposer.debugOnPlan = null);
    for (final downscale in [2, 4]) {
      GlassCopyTuning.debugOverride(maxCopyShare: downscale);
      Future<Uint8List> drawn({required bool inFrame}) => _drawn(
        tester,
        inFrame: inFrame,
        pixelRatio: 2,
        secondFrost: 20,
        tint: const Color(0xCCFF3B30),
      );
      final image = await drawn(inFrame: false);
      final inFrame = await drawn(inFrame: true);
      final holding = plan!.reads.singleWhere((read) => read.holds.isNotEmpty);
      expect(holding.geometry.lattice.share, downscale);
      // The image draws the held glass as a picture at the screen's pixels.
      // Each fragment of the glass held in the frame stands for a block of
      // them; under this frost and tint that rounds by a few levels, and
      // left out of the copy it is 73 off.
      expect(_difference(image, inFrame), lessThanOrEqualTo(3));
    }
  }, skip: skipProperGlassTests);

  // The upper glass frosts its own copy in its shader, and that copy is
  // held in the lower glass's coarser one. Drawn at both shares at once, its
  // pixels would hold 16 device pixels each.
  testWidgets('glass held in a coarse copy is drawn at the coarser grid', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(260, 360) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    addTearDown(GlassCopyTuning.debugOverride);
    GlassPlan? plan;
    GlassComposer.debugOnPlan = (_, next) => plan = next;
    addTearDown(() => GlassComposer.debugOnPlan = null);
    for (final frost in [3.0, 6.0]) {
      Future<Uint8List> drawn(int downscale) {
        GlassCopyTuning.debugOverride(maxCopyShare: downscale);
        return _drawn(
          tester,
          inFrame: true,
          pixelRatio: 2,
          frost: frost,
          secondFrost: 20,
        );
      }

      final atScreen = await drawn(1);
      for (final downscale in [2, 4]) {
        final shown = await drawn(downscale);
        final holding = plan!.reads.singleWhere((r) => r.holds.isNotEmpty);
        expect(holding.geometry.lattice.share, downscale);
        expect(holding.holds.single.geometry.lattice.share, greaterThan(1));
        expect(
          _difference(atScreen, shown),
          lessThanOrEqualTo(9),
          reason: 'frost $frost, copy share $downscale',
        );
      }
    }
  }, skip: skipProperGlassTests);

  // Impeller weighs the cut on the layer's device pixels. Glass at 203.8
  // reads from row 408 at dpr 2.625, which 408 / 2.625 * 2.625 misses by a
  // hair, and clips from 198.2 to 198.6 cut that band by about 30 %: a layer
  // a pixel taller than its band tips over the bound and Impeller cuts it.
  testWidgets('glass a clip cuts by about the bound reads where it lies', (
    tester,
  ) async {
    const pixelRatio = 2.625;
    tester.view.physicalSize = const Size(260, 640) * pixelRatio;
    tester.view.devicePixelRatio = pixelRatio;
    addTearDown(tester.view.reset);
    for (var cut = 198.2; cut < 198.65; cut += 0.05) {
      final clip = Rect.fromLTRB(0, cut, 260, 640);
      final image = await _drawn(
        tester,
        inFrame: false,
        pixelRatio: pixelRatio,
        second: false,
        clip: clip,
        top: 203.8,
      );
      final inFrame = await _drawn(
        tester,
        inFrame: true,
        pixelRatio: pixelRatio,
        second: false,
        clip: clip,
        top: 203.8,
      );
      expect(_difference(image, inFrame), lessThanOrEqualTo(2), reason: '$cut');
    }
  }, skip: skipProperGlassTests);

  // The lower glass's frosted copy is an image at a fraction of the screen's
  // pixels, and the upper glass is drawn in the frame inside it as a filter,
  // whose fragments are the image's pixels.
  for (final pixelRatio in [2.0, 3.0]) {
    testWidgets("an image copy at a fraction of the screen's pixels draws "
        'glass drawn in the frame where it lies (dpr $pixelRatio)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(260, 360) * pixelRatio;
      tester.view.devicePixelRatio = pixelRatio;
      addTearDown(tester.view.reset);
      final image = await _drawn(
        tester,
        inFrame: false,
        pixelRatio: pixelRatio,
        secondFrost: 12,
      );
      final images = GlassCopies.debugImagesDrawn;
      final inFrame = await _drawn(
        tester,
        inFrame: true,
        pixelRatio: pixelRatio,
        secondFrost: 12,
      );
      expect(GlassCopies.debugImagesDrawn, greaterThan(images));
      // At the image's own pixels the upper glass lands twice as far from
      // its layer's corner, over 70 levels off. Its bevel, drawn at the
      // copy's pixels in the frame and at the screen's in the image, is 12
      // to 13 levels apart (plan.dart, _holdsAtOwnGrid).
      expect(_difference(image, inFrame), lessThanOrEqualTo(14));
    }, skip: skipProperGlassTests);
  }

  group('a copy over what holds still', () {
    Future<Uint8List> fresh(
      WidgetTester tester, {
      required double top,
      double shift = 0,
      bool second = true,
    }) async {
      // Pinned to the scene: an image would never pay.
      debugGlassPrices = const PlanPrices(imageGpu: 1000000);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_scene(top: top, shift: shift, second: second));
      await tester.pumpWidget(_scene(top: top, shift: shift, second: second));
      final pixels = await _pixels(tester, 2);
      debugGlassPrices = const PlanPrices();
      await tester.pumpWidget(const SizedBox());
      return pixels;
    }

    for (final second in [false, true]) {
      testWidgets('moves to an image that draws what the frame draws, and '
          'draws what changes in the frame it changes '
          '(${second ? 'two glass' : 'one glass'})', (tester) async {
        tester.view.physicalSize = const Size(260, 360) * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        final moved = await fresh(tester, top: 206, second: second);
        final changed = await fresh(
          tester,
          top: 206,
          shift: 0.3,
          second: second,
        );

        for (var top = 200.0; top <= 203; top++) {
          await tester.pumpWidget(_scene(top: top, second: second));
        }
        final images = GlassCopies.debugImagesDrawn;
        expect(images, greaterThan(0));
        await tester.pumpWidget(_scene(top: 204, second: second));
        await tester.pumpWidget(_scene(top: 205, second: second));
        await tester.pumpWidget(_scene(top: 206, second: second));
        expect(
          GlassCopies.debugImagesDrawn,
          lessThanOrEqualTo(images + 1),
          reason:
              'glass moves within the room of its image, which grows when '
              'it runs out, while the page holds still',
        );
        expect(
          _difference(await _pixels(tester, 2), moved),
          lessThanOrEqualTo(2),
        );

        await tester.pumpWidget(_scene(top: 206, shift: 0.3, second: second));
        expect(
          _difference(await _pixels(tester, 2), changed),
          lessThanOrEqualTo(2),
          reason: 'the frame that changes the page shows it',
        );
      }, skip: skipProperGlassTests);
    }

    testWidgets('asks for few images while glass moves far over it', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(260, 360) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      for (var top = 0.0; top <= 8; top++) {
        await tester.pumpWidget(_scene(top: top, second: false));
      }
      final images = GlassCopies.debugImagesDrawn;
      for (var top = 8.0; top <= 248; top += 8) {
        await tester.pumpWidget(_scene(top: top, second: false));
      }
      expect(GlassCopies.debugImagesDrawn - images, lessThanOrEqualTo(6));
    }, skip: skipProperGlassTests);

    testWidgets('draws in the frame again once the page keeps changing', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(260, 360) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      for (var top = 200.0; top <= 204; top++) {
        await tester.pumpWidget(_scene(top: top, second: false));
      }
      await tester.pumpWidget(_scene(top: 204, shift: 0.1, second: false));
      final images = GlassCopies.debugImagesDrawn;
      for (var i = 2; i < 40; i++) {
        await tester.pumpWidget(
          _scene(top: 204, shift: i / 100, second: false),
        );
      }
      expect(GlassCopies.debugImagesDrawn, images);
    }, skip: skipProperGlassTests);
  });
}
