import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'shared.dart';

void main() {
  group('Glassify', () {
    goldenTest(
      'renders Flutter logo with different thicknesses',
      fileName: 'flutter_logo_thicknesses',
      pumpBeforeTest: pumpOnce,
      builder: () => GoldenTestGroup(
        scenarioConstraints: testScenarioConstraints,
        children: [
          for (final thickness in <double>[0, 10, 20, 40, 80, 100])
            GoldenTestScenario(
              name: 'thickness $thickness',
              child: buildWithGridPaper(
                Glassify(
                  settings: settingsWithoutLighting.copyWith(
                    thickness: thickness,
                    glassColor: Colors.blue.withValues(alpha: 0.5),
                  ),
                  child: const FlutterLogo(size: 400),
                ),
              ),
            ),
        ],
      ),
    );
  });
}
