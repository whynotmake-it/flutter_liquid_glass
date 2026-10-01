import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/fake_glass.dart';
import 'package:liquid_glass_renderer/src/internal/paint_fake_glass_surface.dart';

import 'shared.dart';

void main() {
  group('FakeGlass', () {
    test('uses the real renderer fallback for highlight width', () {
      expect(
        fakeGlassHighlightBandWidth(
          const LiquidGlassSettings.ios27ToolbarDark(),
        ),
        .5,
      );
      expect(
        fakeGlassHighlightBandWidth(
          const LiquidGlassSettings.ios27ToolbarLight(),
        ),
        .75,
      );
      expect(
        fakeGlassHighlightBandWidth(
          const LiquidGlassSettings(),
        ),
        0,
      );
    });

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
                  chromaticAberration: 0,
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
                  chromaticAberration: 0,
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
                  chromaticAberration: 0,
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
                    chromaticAberration: 0,
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
                    chromaticAberration: 0,
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
            name: 'before: box-gradient stroke',
            child: const _FakeLightingMatrix(useLegacyLighting: true),
          ),
          GoldenTestScenario(
            name: 'after: combined contour lighting',
            child: const _FakeLightingMatrix(useLegacyLighting: false),
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
      'matches RealGlass contour offsets without a separate stroke',
      skip: skipGoldenTests,
      fileName: _backendGolden('fake_glass_real_contour_offsets'),
      pumpBeforeTest: pumpOnce,
      builder: () => GoldenTestGroup(
        scenarioConstraints: BoxConstraints.tight(const Size(320, 240)),
        children: [
          for (final offset in [-1.0, 0.0, 1.0])
            for (final fake in [false, true])
              GoldenTestScenario(
                name:
                    'OFFSET ${offset.toStringAsFixed(0)} · '
                    '${fake ? 'FAKE — candidate' : 'REAL — reference'}',
                child: buildWithGridPaper(
                  _offsetComparisonSurface(fake: fake, offset: offset),
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

Widget _offsetComparisonSurface({
  required bool fake,
  required double offset,
}) => Center(
  child: LiquidGlassLayer(
    fake: fake,
    settings: const LiquidGlassSettings.ios27ToolbarLight(frost: 0).copyWith(
      edgeRefraction: 0,
      chromaticAberration: 0,
      contourOffset: offset,
    ),
    child: const LiquidGlass(
      shape: LiquidRoundedRectangle(borderRadius: 36),
      child: SizedBox(width: 220, height: 96),
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
  highlightWidth: 1.5,
  highlightOppositeStrength: 0.5,
  contourStrength: 0.2,
  contourWidth: 1,
  bevelShadowStrength: 0.04,
  bevelShadowOffset: 4,
  bevelShadowDirectionality: 0.75,
);
const _lightingAppearance = LiquidGlassAppearance(
  tint: Color.fromARGB(52, 245, 248, 255),
);

class _FakeLightingMatrix extends StatelessWidget {
  const _FakeLightingMatrix({required this.useLegacyLighting});

  final bool useLegacyLighting;

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
    child: useLegacyLighting
        ? CustomPaint(
            painter: _LegacyFakeLightingPainter(shape),
          )
        : FakeGlass(
            shape: shape,
            settings: _lightingSettings,
            appearance: _lightingAppearance,
            child: const SizedBox.expand(),
          ),
  );
}

/// Test-only reconstruction of the former box-gradient stroke. Keeping it out
/// of production makes the before/after golden honest without retaining dead
/// renderer code.
class _LegacyFakeLightingPainter extends CustomPainter {
  const _LegacyFakeLightingPainter(this.shape);

  final LiquidShape shape;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final path = shape.getOuterPath(bounds);
    canvas
      ..clipPath(path)
      ..drawPaint(Paint()..color = _lightingAppearance.tint);

    final squareBounds = Rect.fromCircle(
      center: bounds.center,
      radius: bounds.longestSide / 2,
    );
    final lightIntensity = _lightingSettings.highlight.clamp(0.0, 1.0);
    final highlight = Colors.white.withValues(
      alpha: Curves.easeOut.transform(lightIntensity) * 0.78,
    );
    final contour = Colors.black.withValues(
      alpha: _lightingSettings.contourStrength,
    );
    const angle = math.pi / 2;
    final x = math.cos(angle);
    final y = math.sin(angle);
    const coverage = 0.215;
    final alignment = (size.aspectRatio < 1 ? y : x).abs();
    final gradientScale = (1 - 1 / size.aspectRatio) * (1 - alignment);
    final inset = ui.lerpDouble(0, 0.5, gradientScale.clamp(0, 1))!;
    final secondInset = ui.lerpDouble(
      coverage,
      0.5,
      gradientScale.clamp(0, 1),
    )!;
    final edgeStart = ui.lerpDouble(secondInset, 0.5, 0.25)!;
    final shader = LinearGradient(
      colors: [highlight, contour, contour, highlight],
      stops: [inset, edgeStart, 1 - edgeStart, 1 - inset],
      begin: Alignment(x, y),
      end: Alignment(-x, -y),
    ).createShader(squareBounds);
    canvas.drawPath(
      path,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = _lightingSettings.contourWidth
        ..blendMode = BlendMode.hardLight,
    );
  }

  @override
  bool shouldRepaint(_LegacyFakeLightingPainter oldDelegate) =>
      shape != oldDelegate.shape;
}
