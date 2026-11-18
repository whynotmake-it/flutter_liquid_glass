import 'dart:ui';

import 'package:apple_liquid_glass/src/motions/flex_spec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the lift grows the long side by the lift points', () {
    for (final size in const [Size(44, 44), Size(120, 44), Size(44, 120)]) {
      final spec = FlexSpec.forSize(size);
      expect(
        spec.liftScaleFor(size) * size.longestSide,
        closeTo(size.longestSide + spec.liftScalePoints, 1e-9),
      );
    }
  });

  test('a portrait surface lifts like its landscape twin', () {
    const wide = Size(200, 80);
    const tall = Size(80, 200);
    expect(
      FlexSpec.forSize(tall).liftScaleFor(tall),
      FlexSpec.forSize(wide).liftScaleFor(wide),
    );
  });

  test('an empty surface does not lift', () {
    expect(FlexSpec.ultraSmall.liftScaleFor(Size.zero), 1);
  });
}
