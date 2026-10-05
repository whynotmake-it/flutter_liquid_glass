import 'dart:ui' show ImageFilter, TileMode;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/fake_glass.dart';
import 'package:liquid_glass_renderer/src/internal/fake_glass_color.dart';
import 'package:liquid_glass_renderer/src/internal/multi_shader_builder.dart';
import 'package:liquid_glass_renderer/src/rendering/consolidated_fake_glass_layer.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';

// The tests pass the neutral default appearance explicitly because the
// filter-equality assertions rely on it.
// ignore_for_file: avoid_redundant_argument_values

void main() {
  // Direct color model, saturation 1, gamma 1, visibility 1: a neutral
  // appearance whose backdrop filter is the blur alone.
  const neutral = LiquidGlassAppearance();

  ImageFilter? blur(double sigma) => sigma == 0
      ? null
      : ImageFilter.blur(
          sigmaX: sigma,
          sigmaY: sigma,
          tileMode: TileMode.mirror,
        );

  test('fakeGlassBlurSigma scales the blur by the mix', () {
    double sigma({double frost = 12, double mix = 1}) =>
        fakeGlassBlurSigma(LiquidGlassSettings(frost: frost, frostMix: mix));

    // The settings default approximates a .65 mix of the 12 pt blur.
    expect(
      fakeGlassBlurSigma(const LiquidGlassSettings()),
      closeTo(7.8, 1e-12),
    );
    expect(sigma(mix: .5), 6);
    expect(sigma(), 12);
    expect(sigma(mix: 0), 0);
    expect(sigma(mix: -1), 0);
    expect(sigma(mix: 2), 12);
    expect(sigma(frost: -1), 0);
  });

  test('fakeGlassBackdropFilter blurs at the mixed sigma', () {
    ImageFilter? filter({double frost = 12, double mix = 1}) =>
        fakeGlassBackdropFilter(
          LiquidGlassSettings(frost: frost, frostMix: mix),
          neutral,
        );

    expect(filter(mix: .5), blur(6));
    expect(filter(), blur(12));
    expect(filter(mix: 0), isNull);
    expect(filter(mix: -1), isNull);
    expect(filter(mix: 2), blur(12));
    expect(filter(frost: -1), isNull);
  });

  test('a nonzero color transfer survives mix 0', () {
    const appearance = LiquidGlassAppearance(saturation: .8);
    const settings = LiquidGlassSettings(frost: 12, frostMix: 0);

    final filter = fakeGlassBackdropFilter(settings, appearance);
    expect(filter, isNotNull);
    // Without the mix there is no blur, so the filter is the pure color
    // transfer — the same one a frost-free glass produces.
    expect(filter, isNot(blur(12)));
    expect(
      filter,
      fakeGlassBackdropFilter(settings.copyWith(frost: 0), appearance),
    );
  });

  testWidgets('standalone fake glass scales its backdrop blur with the mix', (
    tester,
  ) async {
    await tester.runAsync(
      () => MultiShaderBuilder.precacheShaders([
        ShaderKeys.fakeGlassSurface,
      ]),
    );
    const childKey = ValueKey('fake-child');
    final settings = ValueNotifier(
      const LiquidGlassSettings(frost: 12, frostMix: .5),
    );
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: ValueListenableBuilder<LiquidGlassSettings>(
            valueListenable: settings,
            builder: (_, value, _) => FakeGlass(
              shape: const LiquidRoundedSuperellipse(borderRadius: 22),
              settings: value,
              appearance: neutral,
              child: const SizedBox(
                key: childKey,
                width: 80,
                height: 60,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    RenderFakeGlass surface() =>
        tester.renderObject<RenderFakeGlass>(find.byType(RawFakeGlass));
    final renderObject = surface();

    expect(renderObject.debugBackdropFilterLayer!.filter, blur(6));

    settings.value = const LiquidGlassSettings(frost: 12, frostMix: 0);
    await tester.pump();
    expect(identical(surface(), renderObject), isTrue);
    expect(renderObject.debugBackdropFilterLayer, isNull);
    // Only the blur is gone: the child and the surface shader stay.
    expect(find.byKey(childKey), findsOneWidget);
    expect(renderObject.surfaceShader, isNotNull);

    settings.value = const LiquidGlassSettings(frost: 12, frostMix: 1);
    await tester.pump();
    expect(identical(surface(), renderObject), isTrue);
    expect(renderObject.debugBackdropFilterLayer!.filter, blur(12));
  });

  testWidgets(
    'the consolidated fake layer scales blur and reach with the mix',
    (tester) async {
      await tester.runAsync(
        () => MultiShaderBuilder.precacheShaders([
          ShaderKeys.fakeGlassSurface,
        ]),
      );
      const childKey = ValueKey('consolidated-child');
      const material = Rect.fromLTWH(0, 0, 80, 60);
      final settings = ValueNotifier(
        const LiquidGlassSettings(frost: 12, frostMix: .5),
      );
      addTearDown(settings.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<LiquidGlassSettings>(
            valueListenable: settings,
            builder: (_, value, _) => LiquidGlassLayer(
              fake: true,
              settings: value,
              defaultAppearance: neutral,
              child: const LiquidGlass(
                shape: LiquidOval(),
                child: SizedBox(
                  key: childKey,
                  width: 80,
                  height: 60,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // .last skips the composition-probe seed layer.
      RenderConsolidatedFakeGlassLayer layer() =>
          tester.renderObject<RenderConsolidatedFakeGlassLayer>(
            find.byType(ConsolidatedFakeGlassLayer).last,
          );
      final renderObject = layer();

      expect(renderObject.debugBackdropFilterLayer!.filter, blur(6));
      expect(renderObject.effectSamplingReach(material), 19);

      settings.value = const LiquidGlassSettings(frost: 12, frostMix: 0);
      await tester.pump();
      expect(identical(layer(), renderObject), isTrue);
      expect(renderObject.debugBackdropFilterLayer, isNull);
      expect(renderObject.effectSamplingReach(material), 0);
      expect(find.byKey(childKey), findsOneWidget);
      expect(renderObject.debugSurfaceShader, isNotNull);

      settings.value = const LiquidGlassSettings(frost: 12, frostMix: 1);
      await tester.pump();
      expect(identical(layer(), renderObject), isTrue);
      expect(renderObject.debugBackdropFilterLayer!.filter, blur(12));
      expect(renderObject.effectSamplingReach(material), 37);
    },
  );
}
