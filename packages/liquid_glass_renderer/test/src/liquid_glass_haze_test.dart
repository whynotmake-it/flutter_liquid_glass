@Tags(['macos_pixels'])
library;

// Run with `flutter test --enable-impeller --enable-flutter-gpu`: the copies
// are drawn as Impeller draws them.
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/composer.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_haze.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_composer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/read.dart';

const _key = ValueKey('screen');
const _glass = Rect.fromLTWH(50, 100, 200, 44);

// Black and white bars 20 pixels wide, moved by [shift], under a capsule of
// glass 44 high.
Widget _scene(LiquidGlassSettings settings, {double shift = 0}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        key: _key,
        child: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(painter: _Bars(shift)),
              ),
            ),
            Positioned.fill(
              child: RepaintBoundary(
                child: LiquidGlassLayer(
                  settings: settings,
                  child: Stack(
                    children: [
                      Positioned.fromRect(
                        rect: _glass,
                        child: LiquidGlass(
                          shape: const LiquidRoundedSuperellipse(
                            borderRadius: 22,
                          ),
                          appearance: LiquidGlassAppearance.ios27Regular(
                            brightness: settings.haze.darken > 0
                                ? Brightness.dark
                                : Brightness.light,
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

class _Bars extends CustomPainter {
  const _Bars(this.shift);

  final double shift;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF000000),
    );
    for (var x = shift - 40; x < size.width; x += 40) {
      canvas.drawRect(
        Rect.fromLTWH(x, 0, 20, size.height),
        Paint()..color = const Color(0xFFFFFFFF),
      );
    }
  }

  @override
  bool shouldRepaint(_Bars oldDelegate) => oldDelegate.shift != shift;
}

// The red of the row through the middle of the glass, over its face.
Future<List<int>> _row(
  WidgetTester tester,
  LiquidGlassSettings settings, {
  required bool inFrame,
  double shift = 0,
}) async {
  debugGlassPolicy = PlanPolicy(maxTargets: inFrame ? 64 : 0);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(_scene(settings, shift: shift + 7));
  await tester.pumpWidget(_scene(settings, shift: shift));
  final glass = tester.allRenderObjects
      .whereType<RenderLiquidGlassLayer>()
      .toSet();
  expect(glass.every((g) => g.debugDrewOverCopy), isTrue);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_key),
  );
  final image = (await tester.runAsync(boundary.toImage))!;
  final bytes = (await tester.runAsync(image.toByteData))!;
  final width = image.width;
  image.dispose();
  final pixels = bytes.buffer.asUint8List();
  final y = _glass.center.dy.round();
  return [
    for (var x = 90; x < 210; x++) pixels[(y * width + x) * 4],
  ];
}

int _sharpest(List<int> row) {
  var step = 0;
  for (var i = 1; i < row.length; i++) {
    final d = (row[i] - row[i - 1]).abs();
    if (d > step) step = d;
  }
  return step;
}

int _least(List<int> row) => row.reduce((a, b) => a < b ? a : b);
int _most(List<int> row) => row.reduce((a, b) => a > b ? a : b);

void main() {
  test('the iOS 27 hazes follow the slider', () {
    final light = LiquidGlassHaze.ios27Regular(brightness: Brightness.light);
    expect(light.sigma, 15.5);
    expect(light.lighten, closeTo(0.675, 1e-9));
    expect(light.darken, 0);
    expect(light.cover, 0);
    final dark = LiquidGlassHaze.ios27Regular(
      brightness: Brightness.dark,
      tintAmount: 0.5,
    );
    expect(dark.lighten, 0);
    expect(dark.darken, closeTo(0.9, 1e-9));
    expect(dark.cover, 0.5);
    expect(
      LiquidGlassHaze.ios27Regular(
        brightness: Brightness.light,
        tintAmount: 1,
      ).lighten,
      closeTo(0.9, 1e-9),
    );
    expect(LiquidGlassHaze.ios27Clear(tintAmount: 0.5).isNone, isTrue);
    expect(LiquidGlassHaze.ios27Clear(tintAmount: 0.75).cover, 0.5);
    expect(LiquidGlassHaze.ios27Clear(tintAmount: 1).cover, 1);
    expect(const LiquidGlassHaze.none().isNone, isTrue);
    expect(LiquidGlassHaze.fromJson(dark.toJson()), dark);
  });

  test('the presets carry the haze of their scheme and slider', () {
    expect(
      LiquidGlassSettings.ios27RegularLight(tintAmount: 0.5).haze,
      LiquidGlassHaze.ios27Regular(
        brightness: Brightness.light,
        tintAmount: 0.5,
      ),
    );
    expect(
      LiquidGlassSettings.ios27RegularDark().haze,
      LiquidGlassHaze.ios27Regular(brightness: Brightness.dark),
    );
    expect(LiquidGlassSettings.ios27Clear().haze.isNone, isTrue);
    expect(
      const LiquidGlassSettings().haze,
      LiquidGlassSettings.ios27RegularLight().haze,
    );
    final settings = LiquidGlassSettings.ios27RegularDark(tintAmount: 0.25);
    expect(LiquidGlassSettings.fromJson(settings.toJson()).haze, settings.haze);
    expect(
      settings.copyWith(haze: const LiquidGlassHaze.none()).haze.isNone,
      isTrue,
    );
  });

  test('under its haze a preset frosts by the blur iOS leaves the page', () {
    final regular = LiquidGlassSettings.ios27RegularLight();
    for (final side in [20.0, 44.0, 64.0]) {
      expect(regular.hazedFrostSigmaAt(3, shapeShortSide: side), 0);
    }
    // 0.85 of the 7.76 points iOS blurs the middle of large glass by.
    expect(
      regular.hazedFrostSigmaAt(3, shapeShortSide: 160),
      closeTo(6.596, 1e-3),
    );
    expect(
      regular.hazedFrostSigmaAt(3, shapeShortSide: 400),
      closeTo(6.596, 1e-3),
    );
    expect(
      regular.hazedFrostSigmaAt(3, shapeShortSide: 112),
      closeTo(3.298, 1e-3),
    );
    expect(
      regular.hazedFrostSigmaAt(3),
      regular.hazedFrostSigmaAt(3, shapeShortSide: 94),
    );
    expect(
      LiquidGlassSettings.ios27RegularDark(
        tintAmount: 1,
      ).hazedFrostSigmaAt(3, shapeShortSide: 160),
      closeTo(6.596, 1e-3),
    );
    expect(
      LiquidGlassSettings.ios27Clear().hazedFrostSigmaAt(
        3,
        shapeShortSide: 160,
      ),
      0,
    );
    expect(
      LiquidGlassSettings.ios27Clear(
        tintAmount: 1,
      ).hazedFrostSigmaAt(3, shapeShortSide: 160),
      closeTo(1.237, 1e-3),
    );
    expect(
      regular.copyWith(frost: 3).hazedFrostSigmaAt(3, shapeShortSide: 44),
      3,
    );
  });

  test('a haze keeps its wide blur in cells about a sigma wide', () {
    final strip = HazeStrip(15.5, const Size(300, 60));
    expect(strip.cell, 14);
    expect(strip.across, 22);
    expect(strip.down, 5);
    // A layer keeps a row past the strip for Impeller to lose.
    expect(strip.rows, 6);
    // The bell over the cells makes up what their averages leave of the
    // width, wherever a fragment lies between two of them.
    const asked = 15.5 * 15.5 / (14 * 14) - 1 / 12;
    for (final place in [0.0, 0.3, 0.5, 0.9]) {
      var total = 0.0;
      var spread = 0.0;
      for (var pixel = -2; pixel <= 3; pixel++) {
        final distance = pixel - place;
        final inside = math.max(
          1 - distance * distance / (strip.reach * strip.reach),
          0,
        );
        total += inside * inside;
        spread += inside * inside * distance * distance;
      }
      expect(spread / total, closeTo(asked, 0.06), reason: 'at $place');
    }
    expect(
      CopyHaze.sizeOf(
        LiquidGlassHaze.ios27Regular(brightness: Brightness.light),
        const Size(300, 60),
        1,
      ),
      const Size(300, 66),
    );
    // A copy at half of the pixels of a screen three times as fine.
    expect(HazeStrip(15.5 * 1.5, const Size(300, 60)).cell, 22);
    // The strip's shader reads at most 32 pairs of pixels along a cell, and
    // the bell reaches no further than the six cells a fragment reads.
    final widest = HazeStrip(400, const Size(300, 60));
    expect(widest.cell, 64);
    expect(widest.reach, 3);
  });

  test('a read leaves the rows of its haze under its copy', () {
    final haze = LiquidGlassHaze.ios27Regular(brightness: Brightness.light);
    ReadGeometry read({required int share, Rect? clip}) => ReadGeometry.resolve(
      devicePixelRatio: 1,
      share: share,
      atScreen: false,
      reads: const Rect.fromLTWH(50, 100, 200, 60),
      screen: const Rect.fromLTWH(0, 0, 300, 400),
      clip: clip,
      holdsGlass: false,
      glassFrost: 0,
      bandFrost: null,
      frostLeftOut: 0,
      filter: null,
      haze: haze,
    );
    // Sixty rows of the copy are five cells of fourteen, and a spare row.
    final whole = read(share: 1);
    expect(whole.band, const Rect.fromLTWH(50, 100, 200, 60));
    expect(whole.layer, const Rect.fromLTRB(50, 100, 250, 166));
    // A smaller copy lies in its layer's corner, with rows to spare.
    final corner = read(share: 2);
    expect(corner.layer, corner.band);
    // A clip that cuts the top of the layer by less than Impeller cuts a
    // layer for leaves it whole, and the rows fit under it.
    expect(
      read(share: 1, clip: const Rect.fromLTRB(0, 110, 300, 400)).layer,
      const Rect.fromLTRB(50, 100, 250, 166),
    );
    // With the rows past the clip's bottom too, the layer would be cut to
    // the clip: it starts at the clip, and keeps the rows of what is left.
    expect(
      read(share: 1, clip: const Rect.fromLTRB(0, 113, 300, 160)).layer,
      const Rect.fromLTRB(50, 113, 250, 165),
    );
  });

  group('drawn into a copy', () {
    setUp(() {
      debugGlassCopies = true;
    });
    tearDown(() {
      debugGlassCopies = null;
      debugGlassPolicy = const PlanPolicy();
    });

    void sized(WidgetTester tester) {
      tester.view.physicalSize = const Size(300, 240);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    for (final inFrame in [true, false]) {
      final where = inFrame ? 'in the frame' : 'in an image';

      testWidgets('light glass pales dark bars and keeps them sharp, $where', (
        tester,
      ) async {
        sized(tester);
        final plain = await _row(
          tester,
          LiquidGlassSettings.ios27RegularLight(
            frost: 0,
          ).copyWith(haze: const LiquidGlassHaze.none()),
          inFrame: inFrame,
        );
        final hazed = await _row(
          tester,
          LiquidGlassSettings.ios27RegularLight(),
          inFrame: inFrame,
        );
        // Half of the page is white: the wide blur is mid grey, and dark
        // bars move 0.675 of the way to it.
        expect(_least(hazed) - _least(plain), greaterThan(40));
        expect(_most(hazed) - _most(plain), lessThan(4));
        expect(_sharpest(hazed), greaterThan(80));
      });

      testWidgets('dark glass dims white bars and keeps them sharp, $where', (
        tester,
      ) async {
        sized(tester);
        final plain = await _row(
          tester,
          LiquidGlassSettings.ios27RegularDark(
            frost: 0,
          ).copyWith(haze: const LiquidGlassHaze.none()),
          inFrame: inFrame,
        );
        final hazed = await _row(
          tester,
          LiquidGlassSettings.ios27RegularDark(),
          inFrame: inFrame,
        );
        expect(_most(plain) - _most(hazed), greaterThan(40));
        expect(_least(hazed) - _least(plain), lessThan(4));
        expect(_sharpest(hazed), greaterThan(50));
      });

      testWidgets(
        'the slider at 1 covers the page with the wide blur, $where',
        (
          tester,
        ) async {
          sized(tester);
          final covered = await _row(
            tester,
            LiquidGlassSettings.ios27RegularLight(tintAmount: 1),
            inFrame: inFrame,
          );
          expect(_most(covered) - _least(covered), lessThan(24));
        },
      );
    }

    // Every pixel of the copy is weighed, so a page that scrolls under the
    // glass takes its wide blur with it: no line is caught by one frame's
    // samples and missed by the next's.
    testWidgets('a page moving under the glass moves its wide blur smoothly', (
      tester,
    ) async {
      sized(tester);
      final settings = LiquidGlassSettings.ios27RegularLight(tintAmount: 1);
      List<int>? last;
      var step = 0;
      for (var shift = 0.0; shift <= 40; shift++) {
        final row = await _row(tester, settings, inFrame: true, shift: shift);
        if (last != null) {
          for (var i = 0; i < row.length; i++) {
            final d = (row[i] - last[i]).abs();
            if (d > step) step = d;
          }
        }
        last = row;
      }
      // A Gaussian this wide leaves the bars 17 levels from dark to light
      // over their 40 pixels, under 2 a pixel.
      expect(step, lessThanOrEqualTo(4));
    });

    testWidgets('a copy in the frame and one in an image draw alike', (
      tester,
    ) async {
      sized(tester);
      final settings = LiquidGlassSettings.ios27RegularLight(tintAmount: 0.25);
      final frame = await _row(tester, settings, inFrame: true);
      final image = await _row(tester, settings, inFrame: false);
      var largest = 0;
      for (var i = 0; i < frame.length; i++) {
        final d = (frame[i] - image[i]).abs();
        if (d > largest) largest = d;
      }
      expect(largest, lessThanOrEqualTo(6));
    });
  });
}
