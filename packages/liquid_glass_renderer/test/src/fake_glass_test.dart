import 'dart:ui' as ui;

import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'shared.dart';

void main() {
  group('FakeGlass', () {
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
                  saturation: 1,
                  chromaticAberration: 0,
                  highlight: 0,
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
                  saturation: 1,
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
                  tint: Color.fromARGB(128, 0, 0, 255),
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
      'shadow visibility scales with settings',
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
                  settings: LiquidGlassSettings(
                    visibility: visibility,
                    frost: 0,
                    saturation: 1,
                    chromaticAberration: 0,
                    highlight: 0,
                    tint: const Color.fromARGB(128, 0, 0, 255),
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
                  settings: LiquidGlassSettings(
                    visibility: visibility,
                    frost: 0,
                    saturation: 1,
                    chromaticAberration: 0,
                    highlight: 0,
                    tint: const Color.fromARGB(128, 0, 0, 255),
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
  });
}

String _backendGolden(String name) =>
    ui.ImageFilter.isShaderFilterSupported ? name : '${name}_skia';
