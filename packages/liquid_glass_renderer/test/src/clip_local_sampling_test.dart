import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('final render shader maps filter coordinates into geometry space', () {
    final source = File(
      'lib/assets/shaders/liquid_glass_final_render.frag',
    ).readAsStringSync();

    expect(
      source,
      contains('geometryUV = (matteCoord - uGeometryOffset) / uGeometrySize'),
    );
    expect(source, contains('uCoordinateTexture'));
    expect(
      source,
      contains(
        'Map image-filter fragment coordinates back into the layer-local',
      ),
    );
  });
}
