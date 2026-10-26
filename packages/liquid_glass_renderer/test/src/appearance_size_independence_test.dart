import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/fake_glass_color.dart';
import 'package:liquid_glass_renderer/src/rendering/consolidated_fake_glass_layer.dart';

import 'shared.dart';

const _dpr = 2.0;
const _scene = Size(600, 200);

/// A 140 pt dark pill three times: next to a 40 pt pill in its layer, the
/// same while it starts to fade (FakeGlass then gives it a filter of its
/// own), and alone in its layer.
class _Pills extends StatelessWidget {
  const _Pills({required this.fake});

  final bool fake;

  static const _appearance = LiquidGlassAppearance.ios27RegularDark();

  Widget _pill(double left, double size, {double visibility = 1}) => Positioned(
    left: left,
    top: 100 - size / 2,
    child: LiquidGlass(
      appearance: _appearance.copyWith(visibility: visibility),
      shape: const LiquidRoundedSuperellipse(borderRadius: 20),
      child: SizedBox.square(dimension: size),
    ),
  );

  // The layer's own appearance is dark too, so FakeGlass paints its fully
  // visible pills with one shared filter, and a fading one with its own.
  Widget _layer(List<Widget> pills) => LiquidGlassLayer(
    fake: fake,
    defaultAppearance: _appearance,
    settings: LiquidGlassSettings.ios27Regular(brightness: Brightness.dark),
    child: Stack(children: pills),
  );

  @override
  Widget build(BuildContext context) => ColoredBox(
    // A flat backdrop: blur and refraction leave it as it is, so the face
    // color is all the glass changes.
    color: const Color(0xFF8C8C8C),
    child: Stack(
      children: [
        Positioned.fill(child: _layer([_pill(10, 140), _pill(155, 40)])),
        Positioned.fill(
          child: _layer([_pill(210, 140, visibility: .99), _pill(355, 40)]),
        ),
        Positioned.fill(child: _layer([_pill(450, 140)])),
      ],
    ),
  );
}

void main() {
  // A shape's appearance must not depend on the other shapes in its layer:
  // the dark model has no size response (see GlassColorParameters.ios27Dark).
  for (final fake in [true, false]) {
    testWidgets(
      'a dark ${fake ? 'fake' : 'real'} pill looks the same whatever shares '
      'its layer',
      (tester) async {
        tester.view
          ..devicePixelRatio = _dpr
          ..physicalSize = _scene * _dpr;
        addTearDown(tester.view.reset);
        final key = GlobalKey();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: RepaintBoundary(
              key: key,
              child: _Pills(fake: fake),
            ),
          ),
        );
        await tester.pump();
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: _dpr);
        final bytes = (await tester.runAsync(image.toByteData))!;
        final width = image.width;
        image.dispose();

        List<int> pixel(double x, double y) {
          final offset = ((y * _dpr).round() * width + (x * _dpr).round()) * 4;
          return bytes.buffer.asUint8List(bytes.offsetInBytes + offset, 3);
        }

        final shared = pixel(80, 100);
        final fading = pixel(280, 100);
        final alone = pixel(520, 100);
        expect(shared, isNot(equals([0x8C, 0x8C, 0x8C])), reason: 'glass');
        for (var c = 0; c < 3; c++) {
          expect(
            (shared[c] - alone[c]).abs(),
            lessThanOrEqualTo(1),
            reason: 'channel $c: next to a small pill $shared, alone $alone',
          );
          // 1% of fade moves the face at most a level or two toward the
          // backdrop.
          expect(
            (shared[c] - fading[c]).abs(),
            lessThanOrEqualTo(2),
            reason: 'channel $c: visible $shared, starting to fade $fading',
          );
        }
      },
      skip: !fake && skipProperGlassTests,
    );
  }

  test('the FakeGlass filter does not change with the size of the shape', () {
    final settings = LiquidGlassSettings.ios27Regular(
      brightness: Brightness.dark,
    );
    String colorOf(double shortSide) {
      final filter = fakeGlassBackdropFilter(
        settings,
        _Pills._appearance,
        deviceScale: _dpr,
        shapeShortSide: shortSide,
      ).toString();
      // The blur still follows the layer's size; the color must not.
      return filter.substring(filter.indexOf('ColorFilter'));
    }

    expect(colorOf(40), colorOf(140));
  });

  // A fully visible FakeGlass shape is painted with the layer's shared
  // filter; once it starts to fade it gets a filter of its own, which must
  // blur like the shared one did.
  testWidgets('a FakeGlass shape keeps its blur when it starts to fade', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = _dpr
      ..physicalSize = _scene * _dpr;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: _Pills(fake: true),
      ),
    );
    await tester.pump();
    final layers = tester
        .renderObjectList<RenderConsolidatedFakeGlassLayer>(
          find.byType(ConsolidatedFakeGlassLayer),
        )
        .toList();
    double sigmaOf(BackdropFilterLayer layer) => double.parse(
      RegExp(r'blur\(([\d.]+),').firstMatch(layer.filter.toString())!.group(1)!,
    );
    // The middle layer: the 140 pt pill fading next to a 40 pt pill.
    final fading = layers[1];
    expect(fading.debugSeparateBackdropLayers, hasLength(1));
    expect(
      sigmaOf(fading.debugSeparateBackdropLayers.single),
      sigmaOf(fading.debugBackdropFilterLayer!),
    );
    // And the same blur as the first layer's fully visible pills.
    expect(
      sigmaOf(fading.debugSeparateBackdropLayers.single),
      sigmaOf(layers[0].debugBackdropFilterLayer!),
    );
  });
}
