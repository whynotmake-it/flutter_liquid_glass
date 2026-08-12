import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('final render shader samples geometry in clip-local space', () {
    final source = File(
      'lib/assets/shaders/liquid_glass_final_render.frag',
    ).readAsStringSync();

    expect(
      source,
      contains('geometryUV = (fragCoord - uGeometryOffset) / uGeometrySize'),
    );
    expect(source, isNot(contains('uCoordinateTexture')));
    expect(
      source,
      contains("FlutterFragCoord is the BackdropFilter's clip-local space"),
    );
  });
}
