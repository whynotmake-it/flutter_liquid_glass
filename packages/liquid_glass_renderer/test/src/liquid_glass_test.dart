import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'shared.dart';

void main() {
  group('LiquidGlass', () {
    test('can be used', () async {
      expect(
        const LiquidGlass(shape: LiquidOval(), child: SizedBox()),
        isA<Widget>(),
      );
    });

    group('LiquidRoundedSuperellipse', () {
      goldenTest(
        'should render a rounded superellipse with different thickness',
        fileName: 'rounded_superellipse_thicknesses',
        pumpBeforeTest: pumpOnce,
        builder: () => GoldenTestGroup(
          scenarioConstraints: testScenarioConstraints,
          children: [
            for (final thickness in [0.0, 5, 10, 15, 20, 40, 100])
              GoldenTestScenario(
                name: 'thickness ${thickness.toStringAsFixed(0)}px',
                child: buildWithGridPaper(
                  LiquidGlass(
                    settings: settingsWithoutLighting.copyWith(
                      thickness: thickness.toDouble(),
                    ),
                    shape: const LiquidRoundedSuperellipse(
                      borderRadius: Radius.circular(100),
                    ),
                    child: const SizedBox.square(
                      dimension: 400,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

      goldenTest(
        'should render a rounded superellipse with different radii',
        fileName: 'rounded_superellipse_radii',
        pumpBeforeTest: pumpOnce,
        builder: () {
          final radii = [0.0, 50.0, 100.0, 200.0];
          return GoldenTestGroup(
            scenarioConstraints: testScenarioConstraints,
            children: [
              for (final radius in radii)
                GoldenTestScenario(
                  name: 'square shape radius ${radius.toStringAsFixed(0)}px',
                  child: buildWithGridPaper(
                    LiquidGlass(
                      settings: settingsWithoutLighting.copyWith(
                        thickness: 2,
                        glassColor: Colors.blue.withValues(alpha: 0.5),
                      ),
                      shape: LiquidRoundedSuperellipse(
                        borderRadius: Radius.circular(radius),
                      ),
                      child: SizedBox.square(
                        dimension: 400,
                        child: Container(
                          decoration: ShapeDecoration(
                            color: Colors.red.withValues(alpha: 0.5),
                            shape: RoundedSuperellipseBorder(
                              borderRadius: BorderRadius.circular(radius),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              for (final radius in radii)
                GoldenTestScenario(
                  name: 'wide shape radius ${radius.toStringAsFixed(0)}px',
                  child: buildWithGridPaper(
                    LiquidGlass(
                      settings: settingsWithoutLighting.copyWith(
                        thickness: 2,
                        glassColor: Colors.blue.withValues(alpha: 0.5),
                      ),
                      shape: LiquidRoundedSuperellipse(
                        borderRadius: Radius.circular(radius),
                      ),
                      child: SizedBox.fromSize(
                        size: const Size(400, 200),
                        child: Container(
                          decoration: ShapeDecoration(
                            color: Colors.red.withValues(alpha: 0.5),
                            shape: RoundedSuperellipseBorder(
                              borderRadius: BorderRadius.circular(radius),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      );
    });

    group('merging', () {
      goldenTest(
        'shapes merge with different blend values',
        fileName: 'merging_blend_values',
        pumpBeforeTest: pumpOnce,
        builder: () => GoldenTestGroup(
          scenarioConstraints: testScenarioConstraints,
          children: [
            for (final blend in [0.0, 40.0, 80.0, 100.0])
              GoldenTestScenario(
                name: 'blend $blend',
                child: buildWithGridPaper(
                  LiquidGlassLayer(
                    settings: settingsWithoutLighting.copyWith(
                      blend: blend,
                      glassColor: Colors.red.withValues(alpha: 0.5),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        LiquidGlass.inLayer(
                          shape: LiquidOval(),
                          child: SizedBox.square(dimension: 100),
                        ),
                        LiquidGlass.inLayer(
                          shape: LiquidRoundedRectangle(
                            borderRadius: Radius.circular(20),
                          ),
                          child: SizedBox.square(dimension: 100),
                        ),
                        LiquidGlass.inLayer(
                          shape: LiquidRoundedSuperellipse(
                            borderRadius: Radius.circular(20),
                          ),
                          child: SizedBox.square(dimension: 100),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    });
  });
}
