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
    expect(light.saturation, .9);
    expect(light.transmissionGamma, .9);
    expect(light.vibrancy, .15);
    expect(dark.tint.a, 0);
    expect(
      dark.colorModel,
      const LiquidGlassColorModel.ios27(brightness: Brightness.dark),
    );
    expect(dark.saturation, 2.6);
    expect(dark.transmissionGamma, .58);
    expect(dark.vibrancy, .1);

    const blue = Color(0x66007AFF);
    expect(
      const LiquidGlassAppearance.ios27ToolbarLight(tint: blue).tint,
      blue,
    );
  });

  test('regular material keeps its separately fitted light transmission', () {
    const light = LiquidGlassAppearance.ios27RegularLight();
    const dark = LiquidGlassAppearance.ios27RegularDark();

    expect(light.saturation, 1.65);
    expect(light.transmissionGamma, 1.3);
    expect(
      light.colorModel,
      const LiquidGlassColorModel.ios27(brightness: Brightness.light),
    );
    expect(dark.saturation, 2.6);
    expect(dark.transmissionGamma, .58);
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
