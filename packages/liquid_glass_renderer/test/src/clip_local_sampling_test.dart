import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uniform appearance compiles contributor work out', () {
    final defaultEntry = File(
      'lib/assets/shaders/liquid_glass_final_render.frag',
    ).readAsStringSync();
    final materialEntry = File(
      'lib/assets/shaders/liquid_glass_final_render_material.frag',
    ).readAsStringSync();
    final core = File(
      'lib/assets/shaders/liquid_glass_final_render_core.glsl',
    ).readAsStringSync();

    expect(defaultEntry, contains('#define SHAPE_APPEARANCE 0'));
    expect(materialEntry, contains('#define SHAPE_APPEARANCE 1'));
    expect(core, contains('#if SHAPE_APPEARANCE'));
    expect(defaultEntry, isNot(contains('uMaterialTexture')));
    expect(defaultEntry, isNot(contains('uShapeAppearances')));
  });

  test('final render shader maps filter coordinates into geometry space', () {
    final source = File(
      'lib/assets/shaders/liquid_glass_final_render_core.glsl',
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
      'lib/assets/shaders/liquid_glass_final_render_core.glsl',
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

  test('adaptive color model adds no backdrop sample or rendering pass', () {
    final source = File(
      'lib/assets/shaders/liquid_glass_final_render_core.glsl',
    ).readAsStringSync();

    expect(source, contains('vec3 ios27TintTone('));
    expect(source, contains('baseColor = mix(neutralBase, tintTone'));
    expect(
      RegExp(r'texture\(uBackgroundTexture').allMatches(source).length,
      4,
      reason: 'the tint response must reuse the existing refracted sample',
    );
  });

  test('directional rim lighting retains both opposing highlight lobes', () {
    final source = File(
      'lib/assets/shaders/liquid_glass_final_render_core.glsl',
    ).readAsStringSync();

    expect(
      source,
      contains(
        'float oppositeLightFacing = max(-signedLightFacing, 0.0)',
      ),
    );
    expect(source, contains('oppositeEnvelope * clamp('));
    expect(source, contains('uHighlightOppositeStrength'));
    expect(
      source,
      isNot(contains('max(0.0, dot(normalXY, -uLightDirection))')),
      reason: 'clamping to the source-facing wall drops the return highlight',
    );
  });

  test(
    'inner shading uses only the contour-following bevel band',
    () {
      final source = File(
        'lib/assets/shaders/liquid_glass_final_render_core.glsl',
      ).readAsStringSync();

      expect(source, contains('uBevelShadowOffset'));
      expect(source, contains('bevelLeadingEdge'));
      expect(source, contains('bevelFalloff'));
      expect(source, contains('uBevelShadowSizeResponse'));
      expect(source, contains('sizeEnergy *'));
      expect(
        source,
        contains('uEdgeWidth * 0.5 + kContourCoverageFeather'),
      );
      expect(source, contains('bevelBand *'));
      expect(source, contains('bevelDirection *'));
      expect(source, isNot(contains('faceLighting')));
      expect(source, isNot(contains('uFaceGradient')));
      expect(source, isNot(contains('surfaceLightingDepth')));
    },
  );

  test('geometry and runtime shaders share one displacement codec', () {
    final runtimeCodec = File(
      'lib/assets/shaders/displacement_encoding.glsl',
    ).readAsStringSync();
    final geometryCodec = File(
      'lib/assets/shaders/gpu/displacement_encoding.glsl',
    ).readAsStringSync();

    expect(geometryCodec, runtimeCodec);
    expect(runtimeCodec, contains('0.5 * sqrt(normalizedInward)'));
    expect(runtimeCodec, contains('0.5 * sqrt(normalizedExterior)'));
    expect(
      runtimeCodec,
      contains('normalizedMagnitude = centeredDistance * centeredDistance'),
    );
    expect(runtimeCodec, contains('decodeSignedEdgeDistance'));
    expect(runtimeCodec, contains('-normalizedMagnitude * exteriorRange'));
    expect(
      runtimeCodec,
      contains('-displacementMagnitude / maxDisplacement'),
    );
    expect(
      runtimeCodec,
      contains(
        'normalizedMagnitude = '
        '1.0 - inverseMagnitude * inverseMagnitude',
      ),
    );
  });

  test('displacement compander spends precision at the optical rim', () {
    // Model the RGBA8 quantization performed between the geometry and final
    // passes. The former signed encoding used only codes 0...127 for the
    // physically reachable displacement direction, so its normalized step
    // was approximately 2 / 255 everywhere.
    const formerSignedStep = 2 / 255;

    double decode(int code) {
      final inverse = 1 - code / 255;
      return 1 - inverse * inverse;
    }

    final steps = <double>[
      for (var code = 1; code <= 255; code++) decode(code) - decode(code - 1),
    ];

    // Low displacement is never coarser than the old codec, while precision
    // increases monotonically toward the high-displacement rim where source
    // pixel jumps are most visible.
    expect(steps.first, lessThanOrEqualTo(formerSignedStep));
    for (var index = 1; index < steps.length; index++) {
      expect(steps[index], lessThanOrEqualTo(steps[index - 1]));
    }
    expect(
      steps.last,
      lessThan(formerSignedStep / 500),
      reason: 'peak refraction should not jump by a visible source pixel',
    );
  });

  test('normal codec represents cardinal optical walls exactly', () {
    ({double x, double y}) decode(double x, double y) {
      final xCode = (x * 127 + 127).round();
      final yCode = (y * 127 + 127).round();
      final decodedX = (xCode - 127) / 127;
      final decodedY = (yCode - 127) / 127;
      final length = math.sqrt(
        decodedX * decodedX + decodedY * decodedY,
      );
      return (x: decodedX / length, y: decodedY / length);
    }

    expect(decode(1, 0), (x: 1.0, y: 0.0));
    expect(decode(-1, 0), (x: -1.0, y: 0.0));
    expect(decode(0, 1), (x: 0.0, y: 1.0));
    expect(decode(0, -1), (x: 0.0, y: -1.0));

    // At the deliberately strong 160-pixel diagnostic displacement, the
    // asymmetric signed mapping also improves the worst angular lookup error
    // over conventional UNORM8 (measured at about 0.854 source pixels).
    var maximumVectorError = 0.0;
    for (var index = 0; index < 36000; index++) {
      final angle = index * 2 * math.pi / 36000;
      final x = math.cos(angle);
      final y = math.sin(angle);
      final decoded = decode(x, y);
      final error =
          160 *
          math.sqrt(
            math.pow(decoded.x - x, 2) + math.pow(decoded.y - y, 2),
          );
      maximumVectorError = math.max(maximumVectorError, error);
    }
    expect(maximumVectorError, lessThan(0.85));
  });

  test('backdrop scaling is smooth at the SDF contour', () {
    final source = File(
      'lib/assets/shaders/liquid_glass_final_render_core.glsl',
    ).readAsStringSync();
    final renderer = File(
      'lib/src/rendering/liquid_glass_render_object.dart',
    ).readAsStringSync();

    expect(source, contains('abs(uBackdropScale - 1.0) > 0.0001'));
    expect(source, contains('inwardDistance * inwardDistance'));
    expect(source, contains('transitionDepth * transitionDepth'));
    expect(source, contains('distanceWeight * refractionComplement'));
    expect(source, contains('matteCoord - uMaterialCenter'));
    expect(source, contains('backdropScaleOffset + displacement'));
    expect(source, contains('backdropScaleOffset + redOffset'));
    expect(source, contains('backdropScaleOffset + blueOffset'));
    expect(renderer, contains('_materialCenterInMatte'));
    expect(renderer, contains('matteTransform,\n        bounds,'));
    expect(renderer, contains('setFloatUniforms(initialIndex: 33'));

    double boundaryWeight(double distance, double transition) {
      final distanceSquared = distance * distance;
      final transitionSquared = transition * transition;
      return distanceSquared / (distanceSquared + transitionSquared);
    }

    expect(boundaryWeight(0, 3), 0);
    const epsilon = 1e-5;
    final boundarySlope = boundaryWeight(epsilon, 3) / epsilon;
    expect(boundarySlope, lessThan(1e-5));
    var previous = 0.0;
    for (var index = 1; index <= 100; index++) {
      final current = boundaryWeight(index / 10, 3);
      expect(current, greaterThan(previous));
      previous = current;
    }
  });

  test('rim precision does not increase geometry texture bandwidth', () {
    final renderer = File(
      'lib/src/internal/flutter_gpu_geometry_renderer.dart',
    ).readAsStringSync();

    final geometryAllocationStart = renderer.indexOf(
      '_texture = gpu.gpuContext.createTexture(',
    );
    final geometryAllocationEnd = renderer.indexOf(
      '_image = _texture!.asImage()',
      geometryAllocationStart,
    );
    final geometryAllocation = renderer.substring(
      geometryAllocationStart,
      geometryAllocationEnd,
    );
    expect(geometryAllocation, isNot(contains('format:')));
  });

  test('attached contour can move outside without a shadow pass', () {
    final source = File(
      'lib/assets/shaders/liquid_glass_final_render_core.glsl',
    ).readAsStringSync();
    final geometrySource = File(
      'lib/assets/shaders/gpu/geometry_fragment.glsl',
    ).readAsStringSync();

    expect(source, contains('signedEdgeDistance + uContourOffset'));
    expect(source, contains('externalContourAlpha'));
    expect(source, contains('specular light can eclipse it'));
    expect(geometrySource, contains('uContourExtent'));
    expect(geometrySource, contains('effectSupport'));
  });
}
