import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_render_scope.dart';

void main() {
  test('JSON round-trip preserves every appearance field', () {
    const appearance = LiquidGlassAppearance(
      tint: Color(0x804080C0),
      saturation: 1.8,
      transmissionGamma: .75,
      vibrancy: .3,
      visibility: .4,
      colorModel: LiquidGlassColorModel.ios27(brightness: Brightness.dark),
    );

    expect(
      LiquidGlassAppearance.fromJson(appearance.toJson()),
      appearance,
    );
  });

  test('toolbar appearances derive color response from one optional tint', () {
    const light = LiquidGlassAppearance.ios27ToolbarLight();
    const dark = LiquidGlassAppearance.ios27ToolbarDark();

    expect(light.tint.a, 0);
    expect(
      light.colorModel,
      const LiquidGlassColorModel.ios27(brightness: Brightness.light),
    );
    // The iOS 27 color model carries Apple's face transfer, so the
    // adjustments are identity.
    expect(light.saturation, 1);
    expect(light.transmissionGamma, 1);
    expect(light.vibrancy, 0);
    expect(dark.tint.a, 0);
    expect(
      dark.colorModel,
      const LiquidGlassColorModel.ios27(brightness: Brightness.dark),
    );
    expect(dark.saturation, 1);
    expect(dark.transmissionGamma, 1);
    expect(dark.vibrancy, 0);

    const blue = Color(0x66007AFF);
    expect(
      const LiquidGlassAppearance.ios27ToolbarLight(tint: blue).tint,
      blue,
    );
  });

  test('clear appearance uses the appearance-independent clear model', () {
    const clear = LiquidGlassAppearance.ios27Clear();

    expect(clear.tint.a, 0);
    expect(clear.colorModel, const LiquidGlassColorModel.ios27Clear());
    expect(clear.saturation, 1);
    expect(clear.transmissionGamma, 1);
  });

  test('regular material uses the iOS 27 face transfer unadjusted', () {
    const light = LiquidGlassAppearance.ios27RegularLight();
    const dark = LiquidGlassAppearance.ios27RegularDark();

    expect(light.saturation, 1);
    expect(light.transmissionGamma, 1);
    expect(
      light.colorModel,
      const LiquidGlassColorModel.ios27(brightness: Brightness.light),
    );
    expect(dark.saturation, 1);
    expect(dark.transmissionGamma, 1);
    final lightFace = const LiquidGlassColorModel.ios27(
      brightness: Brightness.light,
    ).faceTransfer(94)!;
    expect(lightFace.lift, .13);
    expect(lightFace.chromaGain, 1.17);
    expect(lightFace.transmittance, closeTo(.592, 1e-9));
    final darkFace = const LiquidGlassColorModel.ios27(
      brightness: Brightness.dark,
    ).faceTransfer(94)!;
    expect(darkFace.lift, 1);
    expect(darkFace.chromaGain, 1.02);
    expect(darkFace.emission.r, closeTo(32 / 255, 1e-9));
  });

  test('dark regular glass becomes denser with its short side', () {
    const dark = LiquidGlassColorModel.ios27(brightness: Brightness.dark);
    // Face transmittance of the pinned Reduce Motion off dark captures.
    const measured = {63: .599, 94: .486, 118: .447, 150: .447};
    for (final MapEntry(key: shortSide, value: transmittance)
        in measured.entries) {
      expect(
        dark.faceTransfer(shortSide.toDouble())!.transmittance,
        closeTo(transmittance, .008),
        reason: '$shortSide pt',
      );
    }
    const light = LiquidGlassColorModel.ios27(brightness: Brightness.light);
    expect(
      light.faceTransfer(63)!.transmittance,
      light.faceTransfer(150)!.transmittance,
    );
  });

  test('the Liquid Glass slider follows the measured face density', () {
    const light = LiquidGlassColorModel.ios27(brightness: Brightness.light);
    const dark = LiquidGlassColorModel.ios27(brightness: Brightness.dark);
    // Face transmittance of the Reduce Motion off slider sweep.
    const lightToolbar = {
      0: .592,
      25: .529,
      45: .482,
      50: .470,
      55: .454,
      75: .380,
      100: .290,
    };
    for (final MapEntry(key: position, value: transmittance)
        in lightToolbar.entries) {
      expect(
        light.faceTransfer(94, tintAmount: position / 100)!.transmittance,
        closeTo(transmittance, .006),
        reason: 'light $position%',
      );
    }
    const darkBySize = {
      63: {0: .599, 50: .599, 75: .450, 100: .298},
      94: {0: .486, 50: .411, 75: .306, 100: .215},
      150: {0: .447, 50: .351, 75: .267, 100: .208},
    };
    for (final MapEntry(key: size, value: sweep) in darkBySize.entries) {
      for (final MapEntry(key: position, value: transmittance)
          in sweep.entries) {
        expect(
          dark
              .faceTransfer(size.toDouble(), tintAmount: position / 100)!
              .transmittance,
          closeTo(transmittance, .02),
          reason: 'dark $size pt $position%',
        );
      }
    }
    expect(light.contourScale(94, 1), 1);
    expect(dark.contourScale(94, 0), closeTo(1, 1e-9));
    expect(dark.contourScale(94, 1), greaterThan(1.2));
    expect(light.sliderDetail(.5), closeTo(.44, 1e-9));
    expect(
      const LiquidGlassColorModel.ios27Clear().sliderDetail(.5),
      closeTo(.95, 1e-9),
    );
  });

  test('clear glass is appearance- and size-independent', () {
    const clear = LiquidGlassColorModel.ios27Clear();
    final small = clear.faceTransfer(40)!;
    final large = clear.faceTransfer(400);
    expect(small, large);
    expect(small.emission.r, closeTo(.126, 1e-9));
    expect(small.transmittance, .954);
    expect(small.lift, 0);
    expect(small.chromaGain, 1.057);
    expect(clear.toJson(), 'ios27Clear');
    expect(LiquidGlassColorModel.fromJson('ios27Clear'), clear);
  });

  test('adaptive tint tones match the native solid-palette measurements', () {
    const blue = Color(0xFF007AFF);
    const orange = Color(0xFFFF9500);
    const luminances = [0.0, 51 / 255, 115 / 255, 221 / 255, 1.0];
    const lightBlue = [
      [0.01, 87.04, 194.16],
      [0.01, 95.06, 207.44],
      [0.01, 104.91, 224.17],
      [0.01, 118.80, 247.95],
      [0.0, 121.58, 254.70],
    ];
    const darkOrange = [
      [255.0, 149.20, 0.0],
      [254.18, 151.30, 6.98],
      [251.29, 153.94, 15.90],
      [251.02, 155.74, 21.95],
      [251.02, 155.74, 21.95],
    ];

    for (var index = 0; index < luminances.length; index++) {
      const lightModel = LiquidGlassColorModel.ios27(
        brightness: Brightness.light,
      );
      const darkModel = LiquidGlassColorModel.ios27(
        brightness: Brightness.dark,
      );
      final light = lightModel.tintTone(blue, luminances[index]);
      final dark = darkModel.tintTone(orange, luminances[index]);
      for (var channel = 0; channel < 3; channel++) {
        final lightValue = [light.r, light.g, light.b][channel] * 255;
        final darkValue = [dark.r, dark.g, dark.b][channel] * 255;
        expect(lightValue, closeTo(lightBlue[index][channel], 1.25));
        expect(darkValue, closeTo(darkOrange[index][channel], 0.75));
      }
    }
  });

  testWidgets('layer resolves omitted appearance from platform brightness', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(platformBrightness: Brightness.dark),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: LiquidGlassLayer(
            fake: true,
            child: SizedBox(),
          ),
        ),
      ),
    );

    final scope = tester.widget<LiquidGlassRenderScope>(
      find.byType(LiquidGlassRenderScope),
    );
    expect(
      scope.defaultAppearance,
      const LiquidGlassAppearance.ios27ToolbarDark(),
    );
  });

  testWidgets('explicit layer appearance overrides brightness default', (
    tester,
  ) async {
    const appearance = LiquidGlassAppearance(
      tint: Color(0x804080C0),
      saturation: 1.8,
      transmissionGamma: .75,
      vibrancy: .3,
      visibility: .6,
    );
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(platformBrightness: Brightness.dark),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: LiquidGlassLayer(
            fake: true,
            defaultAppearance: appearance,
            child: SizedBox(),
          ),
        ),
      ),
    );

    final scope = tester.widget<LiquidGlassRenderScope>(
      find.byType(LiquidGlassRenderScope),
    );
    expect(scope.defaultAppearance, appearance);
  });

  testWidgets('compatible non-overlapping direct sibling layers warn', (
    tester,
  ) async {
    final messages = <String>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) messages.add(message);
    };
    addTearDown(() => debugPrint = previousDebugPrint);

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            LiquidGlassLayer(child: SizedBox(width: 40, height: 40)),
            SizedBox(width: 20),
            LiquidGlassLayer(child: SizedBox(width: 40, height: 40)),
          ],
        ),
      ),
    );
    await tester.pump();
    debugPrint = previousDebugPrint;

    expect(
      messages,
      contains(
        contains('could share one layer and backdrop capture'),
      ),
    );
  });
}
