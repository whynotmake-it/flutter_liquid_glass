import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/widgets/liquid_glass_render_scope.dart';

Widget _layer(
  Brightness platform,
  void Function(LiquidGlassRenderScope scope) read, {
  LiquidGlassSettings? settings,
  LiquidGlassAppearance? defaultAppearance,
}) => MediaQuery(
  data: MediaQueryData(platformBrightness: platform),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: LiquidGlassLayer(
      settings: settings,
      defaultAppearance: defaultAppearance,
      fake: true,
      child: Builder(
        builder: (context) {
          read(LiquidGlassRenderScope.of(context));
          return const SizedBox.square(dimension: 40);
        },
      ),
    ),
  ),
);

void main() {
  test('an iOS 27 material is the presets of its parts', () {
    for (final brightness in Brightness.values) {
      final regular = LiquidGlassMaterial.ios27Regular(
        brightness: brightness,
        sliderPosition: 0.5,
      );
      expect(
        regular.settings,
        LiquidGlassSettings.ios27Regular(
          brightness: brightness,
          sliderPosition: 0.5,
        ),
      );
      expect(
        regular.appearance,
        LiquidGlassAppearance.ios27Regular(brightness: brightness),
      );
      expect(regular.shadows, [
        LiquidGlassShadow.ios27Regular(brightness: brightness),
      ]);
      expect(
        regular,
        LiquidGlassMaterial.ios27Regular(
          brightness: brightness,
          sliderPosition: 0.5,
        ),
      );
    }
    const tint = Color(0xFF0A84FF);
    expect(
      LiquidGlassMaterial.ios27Regular(
        brightness: Brightness.dark,
        tint: tint,
      ).appearance,
      const LiquidGlassAppearance.ios27Regular(
        brightness: Brightness.dark,
        tint: tint,
      ),
    );

    final clear = LiquidGlassMaterial.ios27Clear(sliderPosition: 1);
    expect(
      clear.settings,
      const LiquidGlassSettings.ios27Clear(sliderPosition: 1),
    );
    expect(clear.appearance, const LiquidGlassAppearance.ios27Clear());
    expect(clear.shadows, isEmpty);
    expect(
      clear,
      isNot(LiquidGlassMaterial.ios27Regular(brightness: Brightness.light)),
    );
  });

  testWidgets(
    'a layer given no settings draws the regular glass of the platform '
    'brightness',
    (tester) async {
      late LiquidGlassRenderScope scope;
      for (final brightness in [
        Brightness.dark,
        Brightness.light,
        Brightness.dark,
      ]) {
        await tester.pumpWidget(_layer(brightness, (read) => scope = read));
        final material = LiquidGlassMaterial.ios27Regular(
          brightness: brightness,
        );
        expect(scope.settings, material.settings, reason: '$brightness');
        expect(
          scope.defaultAppearance,
          material.appearance,
          reason: '$brightness',
        );
      }
    },
  );

  testWidgets('a layer keeps the settings and the appearance it is given', (
    tester,
  ) async {
    late LiquidGlassRenderScope scope;
    const settings = LiquidGlassSettings(refractionAmount: 12);
    await tester.pumpWidget(
      _layer(Brightness.dark, (read) => scope = read, settings: settings),
    );
    expect(scope.settings, settings);
    expect(
      scope.defaultAppearance,
      const LiquidGlassAppearance.ios27Regular(brightness: Brightness.dark),
    );

    const appearance = LiquidGlassAppearance.ios27Clear();
    await tester.pumpWidget(
      _layer(
        Brightness.dark,
        (read) => scope = read,
        defaultAppearance: appearance,
      ),
    );
    expect(
      scope.settings,
      const LiquidGlassSettings.ios27Regular(brightness: Brightness.dark),
    );
    expect(scope.defaultAppearance, appearance);
  });
}
