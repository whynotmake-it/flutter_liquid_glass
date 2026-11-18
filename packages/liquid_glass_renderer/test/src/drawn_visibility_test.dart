import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/painting/shader_constants.dart';
import 'package:liquid_glass_renderer/src/rendering/appearance.dart';

const _past = [(2.0, 1.0), (-0.5, 0.0)];

void main() {
  for (final (visibility, drawn) in _past) {
    final appearance = LiquidGlassAppearance.ios27Regular(
      brightness: Brightness.light,
      visibility: visibility,
    );

    test('glass worn at visibility $visibility draws at $drawn', () {
      expect(appearance.wear(const Size(120, 44)).visibility, drawn);
    });

    test('a look at visibility $visibility keeps its color model and '
        'packs $drawn', () {
      final worn = appearance.wear(const Size(120, 44));
      final slots = colorModelSlots([worn], worn);
      final looks = shapeLooks(
        [worn],
        colorModels: slots,
        tintOnly: false,
      );
      final packed = looks.looks.last;
      final code = (packed / lookModelStride).floorToDouble();

      expect(code, colorModelCode(worn.colorModel, slots));
      expect(packed - lookModelStride * code, drawn);
    });
  }
}
