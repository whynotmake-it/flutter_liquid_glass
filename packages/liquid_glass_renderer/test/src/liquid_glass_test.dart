import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:snaptest/snaptest.dart';

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
      testWidgets(
          'should render a rounded superellipse with different thickness',
          (tester) async {
        for (final thickness in [0.0, 5, 10, 15, 20, 40, 100]) {
          await tester.pumpWidget(
            buildWithGridPaper(
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
          );

          await snap(
            name: 'thickness ${thickness.toInt()}',
            matchToGolden: true,
          );
        }
      });

      testWidgets(
          'should render a rounded superellipse with different thickness',
          (tester) async {
        final radii = [0.0, 50.0, 100.0, 200.0];
        for (final radius in radii) {
          await tester.pumpWidget(
            buildWithGridPaper(
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
          );
          await snap(name: 'radius ${radius.toInt()}', matchToGolden: true);
        }
      });
    });
  });
}
