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
                  LiquidGlass.withOwnLayer(
                    settings: settingsWithoutLighting.copyWith(
                      thickness: thickness.toDouble(),
                    ),
                    shape: const LiquidRoundedSuperellipse(
                      borderRadius: 100,
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
                    LiquidGlass.withOwnLayer(
                      settings: settingsWithoutLighting.copyWith(
                        thickness: 2,
                        glassColor: Colors.blue.withValues(alpha: 0.5),
                      ),
                      glassContainsChild: true,
                      shape: LiquidRoundedSuperellipse(
                        borderRadius: radius,
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
                    LiquidGlassLayer(
                      settings: settingsWithoutLighting.copyWith(
                        thickness: 2,
                        glassColor: Colors.blue.withValues(alpha: 0.5),
                      ),
                      child: LiquidGlassBlendGroup(
                        child: LiquidGlass.grouped(
                          glassContainsChild: true,
                          shape: LiquidRoundedSuperellipse(
                            borderRadius: radius,
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
                  ),
                ),
            ],
          );
        },
      );
    });

    group('sparse blend group', () {
      goldenTest(
        'far-apart shapes render correctly (component splitting)',
        fileName: 'sparse_blend_group',
        pumpBeforeTest: pumpOnce,
        builder: () => GoldenTestGroup(
          scenarioConstraints: testScenarioConstraints,
          children: [
            GoldenTestScenario(
              name: 'two shapes far apart',
              child: buildWithGridPaper(
                LiquidGlassLayer(
                  settings: settingsWithoutLighting.copyWith(
                    glassColor: Colors.blue.withValues(alpha: 0.3),
                  ),
                  child: LiquidGlassBlendGroup(
                    blend: 20,
                    child: const Stack(
                      children: [
                        Positioned(
                          left: 20,
                          top: 20,
                          child: LiquidGlass.grouped(
                            shape: LiquidRoundedSuperellipse(borderRadius: 30),
                            child: SizedBox.square(dimension: 120),
                          ),
                        ),
                        Positioned(
                          right: 20,
                          bottom: 20,
                          child: LiquidGlass.grouped(
                            shape: LiquidOval(),
                            child: SizedBox.square(dimension: 120),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
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
                      glassColor: Colors.red.withValues(alpha: 0.5),
                    ),
                    child: LiquidGlassBlendGroup(
                      blend: blend,

                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          LiquidGlass.grouped(
                            shape: LiquidOval(),
                            child: SizedBox.square(dimension: 100),
                          ),
                          LiquidGlass.grouped(
                            shape: LiquidRoundedRectangle(
                              borderRadius: 20,
                            ),
                            child: SizedBox.square(dimension: 100),
                          ),
                          LiquidGlass.grouped(
                            shape: LiquidRoundedSuperellipse(
                              borderRadius: 20,
                            ),
                            child: SizedBox.square(dimension: 100),
                          ),
                        ],
                      ),
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
