import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:snaptest/snaptest.dart';

import 'shared.dart';

void main() {
  group('Glassify', () {
    snapTest(
      'renders Flutter logo with different thicknesses',
      (tester) async {
        for (final thickness in <double>[0, 10, 20, 40, 80, 100]) {
          await tester.pumpWidget(
            buildWithGridPaper(
              Glassify(
                settings: settingsWithoutLighting.copyWith(
                  thickness: thickness,
                  glassColor: Colors.blue.withValues(alpha: 0.5),
                ),
                child: const FlutterLogo(size: 400),
              ),
            ),
          );
          await snap(name: 'thickness $thickness', matchToGolden: true);
        }
      },
    );
  });
}
