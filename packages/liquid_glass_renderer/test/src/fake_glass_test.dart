import 'dart:ui' as ui;

import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/fake_glass.dart';

import 'shared.dart';

void main() {
  group('FakeGlass', () {
    for (final shape in <LiquidShape>[
      const LiquidOval(),
      const LiquidRoundedRectangle(borderRadius: 24),
      const LiquidRoundedSuperellipse(borderRadius: 24),
    ]) {
      testWidgets('loads one analytic surface shader for $shape', (
        tester,
      ) async {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: FakeGlass(
              shape: shape,
              settings: const LiquidGlassSettings(frost: 0),
              child: const SizedBox.square(dimension: 80),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final surface = tester.renderObject<RenderFakeGlass>(
          find.byType(RawFakeGlass),
        );
        expect(surface.surfaceShader, isNotNull);
      });
    }

    testWidgets('shadow paint bounds retain blur support outside the shape', (
      tester,
    ) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: FakeGlass(
            settings: LiquidGlassSettings(frost: 0),
            shadows: [
              BoxShadow(
                offset: Offset(0, 4),
                blurRadius: 12,
                spreadRadius: -1,
              ),
            ],
            shape: LiquidOval(),
            child: SizedBox.square(dimension: 100),
          ),
        ),
      );

      final renderObject = tester.renderObject<RenderBox>(
        find.byType(FakeGlass),
      );
      expect(
        renderObject.paintBounds,
        Rect.fromLTRB(
          -glassShadowBlurSupportForTest,
          4 - glassShadowBlurSupportForTest,
          renderObject.size.width + glassShadowBlurSupportForTest,
          renderObject.size.height + 4 + glassShadowBlurSupportForTest,
        ),
      );
    });

    goldenTest(
      'renders with zero blur',
      skip: skipGoldenTests,
      fileName: _backendGolden('fake_glass_zero_blur'),
      pumpBeforeTest: pumpOnce,
      builder: () => GoldenTestGroup(
        scenarioConstraints: testScenarioConstraints,
        children: [
          GoldenTestScenario(
            name: 'blur 0 with glass color',
            child: buildWithGridPaper(
              const FakeGlass(
                settings: LiquidGlassSettings(
                  frost: 0,
                  highlight: 0,
                ),
                appearance: LiquidGlassAppearance(
                  tint: Color.fromARGB(128, 0, 0, 255),
                ),
                shape: LiquidRoundedSuperellipse(borderRadius: 40),
                child: SizedBox.square(dimension: 300),
              ),
            ),
          ),
          GoldenTestScenario(
            name: 'blur 0 with child content',
            child: buildWithGridPaper(
              const FakeGlass(
                settings: LiquidGlassSettings(
                  frost: 0,
                  highlight: 0,
                ),
                shape: LiquidRoundedSuperellipse(borderRadius: 40),
                child: SizedBox.square(
                  dimension: 300,
                  child: ColoredBox(color: Colors.red),
                ),
              ),
            ),
          ),
          GoldenTestScenario(
            name: 'blur 0 with default saturation',
            child: buildWithGridPaper(
              const FakeGlass(
                settings: LiquidGlassSettings(
                  frost: 0,
                  highlight: 0,
                ),
                appearance: LiquidGlassAppearance(
                  tint: Color.fromARGB(128, 0, 0, 255),
                  saturation: 1.5,
                ),
                shape: LiquidRoundedSuperellipse(borderRadius: 40),
                child: SizedBox.square(dimension: 300),
              ),
            ),
          ),
        ],
      ),
    );

    goldenTest(
      'shadow visibility scales with appearance',
      skip: skipGoldenTests,
      fileName: _backendGolden('fake_glass_shadow_visibility'),
      pumpBeforeTest: pumpOnce,
      builder: () => GoldenTestGroup(
        scenarioConstraints: testScenarioConstraints,
        children: [
          for (final visibility in [0.0, 0.5, 1.0])
            GoldenTestScenario(
              name: 'visibility ${visibility.toStringAsFixed(1)}',
              child: buildWithGridPaper(
                FakeGlass(
                  settings: const LiquidGlassSettings(
                    frost: 0,
                    highlight: 0,
                  ),
                  appearance: LiquidGlassAppearance(
                    tint: const Color.fromARGB(128, 0, 0, 255),
                    visibility: visibility,
                  ),
                  shadows: const [
                    BoxShadow(
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                  shape: const LiquidRoundedSuperellipse(borderRadius: 40),
                  child: const SizedBox.square(dimension: 300),
                ),
              ),
            ),
        ],
      ),
    );

    goldenTest(
      'blur visibility composites over the sharp backdrop',
      skip: skipGoldenTests,
      fileName: _backendGolden('fake_glass_blur_visibility'),
      pumpBeforeTest: pumpOnce,
      builder: () => GoldenTestGroup(
        scenarioConstraints: testScenarioConstraints,
        children: [
          for (final visibility in [0.0, 0.5, 1.0])
            GoldenTestScenario(
              name: 'visibility ${visibility.toStringAsFixed(1)}',
              child: buildWithGridPaper(
                FakeGlass(
                  settings: const LiquidGlassSettings(
                    frost: 12,
                    highlight: 0,
                  ),
                  appearance: LiquidGlassAppearance(
                    visibility: visibility,
                  ),
                  shape: const LiquidRoundedSuperellipse(borderRadius: 40),
                  child: const SizedBox.square(dimension: 300),
                ),
              ),
            ),
        ],
      ),
    );

    goldenTest(
      'offset shadow is cut out behind glass',
      skip: skipGoldenTests,
      fileName: _backendGolden('fake_glass_offset_shadow_cutout'),
      pumpBeforeTest: pumpOnce,
      builder: () => GoldenTestGroup(
        scenarioConstraints: testScenarioConstraints,
        children: [
          for (final visibility in [0.0, 0.5, 1.0])
            GoldenTestScenario(
              name: 'visibility ${visibility.toStringAsFixed(1)}',
              child: buildWithGridPaper(
                FakeGlass(
                  settings: const LiquidGlassSettings(
                    frost: 0,
                    highlight: 0,
                  ),
                  appearance: LiquidGlassAppearance(
                    tint: const Color.fromARGB(128, 0, 0, 255),
                    visibility: visibility,
                  ),
                  shadows: const [
                    BoxShadow(
                      offset: Offset(16, 16),
                      blurRadius: 24,
                    ),
                  ],
                  shape: const LiquidRoundedSuperellipse(borderRadius: 40),
                  child: const SizedBox.square(dimension: 300),
                ),
              ),
            ),
        ],
      ),
    );

    goldenTest(
      'renders contour lighting matrix',
      skip: skipGoldenTests,
      fileName: _backendGolden('fake_glass_lighting_matrix'),
      pumpBeforeTest: pumpOnce,
      builder: () => GoldenTestGroup(
        scenarioConstraints: testScenarioConstraints,
        children: [
          GoldenTestScenario(
            name: 'combined contour lighting',
            child: const _FakeLightingMatrix(),
          ),
        ],
      ),
    );

    goldenTest(
      'matches RealGlass lighting with identical settings',
      skip: skipGoldenTests,
      fileName: _backendGolden('fake_glass_real_comparison'),
      pumpBeforeTest: pumpOnce,
      builder: () => GoldenTestGroup(
        scenarioConstraints: testScenarioConstraints,
        children: [
          for (final brightness in [Brightness.light, Brightness.dark])
            for (final fake in [false, true])
              GoldenTestScenario(
                name:
                    '${brightness.name.toUpperCase()} · '
                    '${fake ? 'FAKE — candidate' : 'REAL — reference'}',
                child: _comparisonBackdrop(
                  brightness,
                  _comparisonSurface(fake: fake, brightness: brightness),
                ),
              ),
        ],
      ),
    );

    goldenTest(
      'keeps the layer-owned surface throughout a visibility fade',
      skip: skipGoldenTests,
      fileName: _backendGolden('fake_glass_layer_visibility'),
      pumpBeforeTest: pumpOnce,
      builder: () => GoldenTestGroup(
        scenarioConstraints: BoxConstraints.tight(const Size(260, 220)),
        children: [
          for (final visibility in [0.25, 0.5, 0.75, 1.0])
            GoldenTestScenario(
              name: 'visibility ${visibility.toStringAsFixed(2)}',
              child: _layerVisibilitySurface(visibility),
            ),
        ],
      ),
    );
  });
}

Widget _layerVisibilitySurface(double visibility) => buildWithGridPaper(
  LiquidGlassLayer(
    fake: true,
    settings: _lightingSettings.copyWith(frost: 7),
    defaultAppearance: _lightingAppearance.copyWith(visibility: visibility),
    child: const Center(
      child: LiquidGlass(
        shape: LiquidRoundedSuperellipse(borderRadius: 32),
        child: SizedBox(width: 180, height: 96),
      ),
    ),
  ),
);

Widget _comparisonBackdrop(Brightness brightness, Widget child) => ColoredBox(
  color: brightness == Brightness.dark ? const Color(0xff101114) : Colors.white,
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Stack(
      children: [
        Positioned.fill(
          child: GridPaper(
            color: brightness == Brightness.dark
                ? Colors.white54
                : Colors.black,
          ),
        ),
        Center(child: child),
      ],
    ),
  ),
);

Widget _comparisonSurface({
  required bool fake,
  required Brightness brightness,
}) {
  const shadows = [
    BoxShadow(
      color: Color.from(alpha: 0.03, red: 0, green: 0, blue: 0),
      offset: Offset(0, 6),
      blurRadius: 12,
      spreadRadius: -1,
    ),
  ];
  return Center(
    child: LiquidGlassLayer(
      fake: fake,
      settings: LiquidGlassSettings.ios27Toolbar(brightness: brightness),
      defaultAppearance: LiquidGlassAppearance.ios27Toolbar(
        brightness: brightness,
      ),
      child: const LiquidGlassBlendGroup(
        blend: 10,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 16,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 16,
              children: [
                LiquidGlass.auto(
                  shadows: shadows,
                  shape: LiquidRoundedSuperellipse(borderRadius: 20),
                  child: GlassGlow(child: SizedBox.square(dimension: 100)),
                ),
                LiquidGlass.auto(
                  shadows: shadows,
                  shape: LiquidRoundedRectangle(borderRadius: 20),
                  child: GlassGlow(child: SizedBox.square(dimension: 100)),
                ),
              ],
            ),
            LiquidGlass.auto(
              shadows: shadows,
              shape: LiquidRoundedSuperellipse(borderRadius: 9000),
              child: GlassGlow(child: SizedBox(width: 400, height: 64)),
            ),
          ],
        ),
      ),
    ),
  );
}

final glassShadowBlurSupportForTest =
    ui.Shadow.convertRadiusToSigma(12) * 3 - 1;

String _backendGolden(String name) =>
    ui.ImageFilter.isShaderFilterSupported ? name : '${name}_skia';

const _lightingSettings = LiquidGlassSettings(
  frost: 0,
  highlight: 0.25,
  contourStrength: 0.2,
  bevelShadowStrength: 0.04,
);
const _lightingAppearance = LiquidGlassAppearance(
  tint: Color.fromARGB(52, 245, 248, 255),
);

class _FakeLightingMatrix extends StatelessWidget {
  const _FakeLightingMatrix();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 420,
    height: 400,
    child: Column(
      children: [
        _row(const Color(0xfff7f7f7), Colors.black),
        _row(const Color(0xff101114), Colors.white),
      ],
    ),
  );

  Widget _row(Color background, Color labelColor) => Expanded(
    child: ColoredBox(
      color: background,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              background.computeLuminance() > 0.5 ? 'WHITE' : 'BLACK',
              style: TextStyle(color: labelColor, fontSize: 11),
            ),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _glass(const LiquidOval(), const Size.square(84)),
                _glass(
                  const LiquidRoundedSuperellipse(borderRadius: 32),
                  const Size(142, 64),
                ),
                _glass(
                  const LiquidRoundedSuperellipse(borderRadius: 28),
                  const Size(92, 116),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _glass(LiquidShape shape, Size size) => SizedBox.fromSize(
    size: size,
    child: FakeGlass(
      shape: shape,
      settings: _lightingSettings,
      appearance: _lightingAppearance,
      child: const SizedBox.expand(),
    ),
  );
}
