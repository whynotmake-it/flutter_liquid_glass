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

  test('lighting recovery adds no texture samples or extra shader pass', () {
    final source = File(
      'lib/assets/shaders/liquid_glass_final_render.frag',
    ).readAsStringSync();
    final lightingStart = source.indexOf('vec3 applySpecularHighlights(');
    final mainStart = source.indexOf('void main()');

    expect(lightingStart, greaterThanOrEqualTo(0));
    expect(mainStart, greaterThan(lightingStart));
    final lightingBody = source.substring(lightingStart, mainStart);
    expect(lightingBody, isNot(contains('texture(')));
    expect(
      lightingBody,
      contains('Both branches are uniform across the draw'),
    );
    expect(
      RegExp(r'applySpecularHighlights\s*\(').allMatches(source).length,
      2,
      reason:
          'The final shader must define and invoke exactly one lighting pass',
    );
  });

  test('geometry and runtime shaders share one displacement codec', () {
    final runtimeCodec = File(
      'lib/assets/shaders/displacement_encoding.glsl',
    ).readAsStringSync();
    final geometryCodec = File(
      'lib/assets/shaders/gpu/displacement_encoding.glsl',
    ).readAsStringSync();

    expect(geometryCodec, runtimeCodec);
    expect(runtimeCodec, contains('edgeDistance / (thickness * 4.0)'));
    expect(runtimeCodec, contains('encoded.b * thickness * 4.0'));
  });
}
