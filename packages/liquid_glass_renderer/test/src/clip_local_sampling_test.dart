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
    expect(source, contains('uniform vec4 uFilterToMatteBasis'));
    expect(source, contains('uniform vec2 uFilterToMatteOffset'));
    expect(source, isNot(contains('uCoordinateTexture')));
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
    expect(source, contains('ios27Base = mix(neutralBase, tintTone'));
    expect(
      RegExp(r'texture\(uBackgroundTexture').allMatches(source).length,
      6,
      reason:
          'the tint response must reuse the existing refracted sample; the '
          'only additions are the two optional sub-pixel softening taps and '
          "the GLES stages' texel-centre read, which replaces texelFetch",
    );
  });

  test('directional rim lighting retains both opposing highlight lobes', () {
    final source = File(
      'lib/assets/shaders/liquid_glass_final_render_core.glsl',
    ).readAsStringSync();

    // Both walls along the light axis share one symmetric lobe; only the
    // return wall is scaled by the opposite strength.
    expect(source, contains('1.0 - lightAxisTangency(normalXY)'));
    expect(source, contains('dot(normalXY, -uLightDirection) >= 0.0'));
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
        contains('uContourOffset + uEdgeWidth + kContourCoverageFeather'),
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
    expect(runtimeCodec, contains('angleHigh / 255.0'));
    expect(runtimeCodec, contains('magnitudeLow / 255.0'));
  });

  // Dart mirror of the packed RGBA8 codec in displacement_encoding.glsl:
  // R = angle[11:4], G = angle[3:0] | magnitude[11:8], A = magnitude[7:0].
  ({int r, int g, int a}) encodePacked(double angle, double magnitude) {
    final x = math.cos(angle);
    final y = math.sin(angle);
    final manhattan = x.abs() + y.abs();
    final dx = x / manhattan;
    final dy = y / manhattan;
    final diamond = dy >= 0
        ? (dx >= 0 ? dy : 1 - dx)
        : (dx < 0 ? 2 - dy : 3 + dx);
    final angleCode = (diamond * 1024).round() % 4096;
    final magnitudeCode = (magnitude.clamp(0.0, 1.0) * 4095).round();
    return (
      r: angleCode ~/ 16,
      g: (angleCode % 16) * 16 + magnitudeCode ~/ 256,
      a: magnitudeCode % 256,
    );
  }

  ({double x, double y, double magnitude}) decodePacked(
    ({int r, int g, int a}) texel,
  ) {
    final diamond = (texel.r * 16 + texel.g ~/ 16) / 1024;
    final dx = diamond < 2 ? 1 - diamond : diamond - 3;
    final dy = diamond < 1
        ? diamond
        : (diamond < 3 ? 2 - diamond : diamond - 4);
    final length = math.sqrt(dx * dx + dy * dy);
    final magnitudeCode = (texel.g % 16) * 256 + texel.a;
    return (
      x: dx / length,
      y: dy / length,
      magnitude: magnitudeCode / 4095,
    );
  }

  test('packed codec keeps refracted content steps far below a pixel', () {
    // iOS 27's 60 pt edge displacement at 3x. The former 8-bit compander
    // stepped by up to 2 / 255 of this (1.4 device pixels) deep in the bevel,
    // which drew refracted lines as staircases.
    const maxDisplacement = 180.0;
    var maximumError = 0.0;
    for (var index = 0; index <= 10000; index++) {
      final magnitude = index / 10000;
      final decoded = decodePacked(encodePacked(0, magnitude)).magnitude;
      maximumError = math.max(
        maximumError,
        (decoded - magnitude).abs() * maxDisplacement,
      );
    }
    expect(maximumError, lessThan(0.05));

    for (var code = 0; code < 4096; code++) {
      final texel = encodePacked(0, code / 4095);
      expect(
        (decodePacked(texel).magnitude * 4095).round(),
        code,
        reason: 'every magnitude code must survive the byte packing',
      );
    }
  });

  test('normal codec represents cardinal optical walls exactly', () {
    for (final (angle, x, y) in [
      (0.0, 1.0, 0.0),
      (math.pi / 2, 0.0, 1.0),
      (math.pi, -1.0, 0.0),
      (-math.pi / 2, 0.0, -1.0),
    ]) {
      final decoded = decodePacked(encodePacked(angle, 0));
      expect(decoded.x, x);
      expect(decoded.y, y);
    }

    // At the deliberately strong 160-pixel diagnostic displacement the
    // 12-bit diamond angle keeps the worst lateral error far below a pixel
    // (the former two 8-bit components reached about 0.85 pixels).
    var maximumVectorError = 0.0;
    for (var index = 0; index < 36000; index++) {
      final angle = index * 2 * math.pi / 36000;
      final decoded = decodePacked(encodePacked(angle, 1));
      final error =
          160 *
          math.sqrt(
            math.pow(decoded.x - math.cos(angle), 2) +
                math.pow(decoded.y - math.sin(angle), 2),
          );
      maximumVectorError = math.max(maximumVectorError, error);
    }
    expect(maximumVectorError, lessThan(0.2));
  });

  test('smooth refraction keeps undisplaced glass an exact backdrop copy', () {
    final source = File(
      'lib/assets/shaders/liquid_glass_final_render_core.glsl',
    ).readAsStringSync();
    final renderer = File(
      'lib/src/rendering/liquid_glass_render_object.dart',
    ).readAsStringSync();

    // Sampler 0 is the image-filter input; its filter quality selects
    // bilinear or nearest backdrop sampling.
    expect(renderer, contains('..setImageSampler(\n        0,'));
    expect(renderer, contains('effectiveSmoothRefraction'));
    // Undisplaced pixels bypass the sampler.
    expect(source, contains('texelFetch('));
    expect(source, contains('sourceOffset.x == 0.0 && sourceOffset.y == 0.0'));
    // GLSL ES 1.00 has no texelFetch; the GLES stages read the texel centre.
    expect(source, contains('#ifdef IMPELLER_TARGET_OPENGLES'));
  });

  test('displaced samples mirror at the captured backdrop edge', () {
    final source = File(
      'lib/assets/shaders/liquid_glass_final_render_core.glsl',
    ).readAsStringSync();
    final renderer = File(
      'lib/src/rendering/liquid_glass_render_object.dart',
    ).readAsStringSync();
    final layer = File(
      'lib/src/rendering/liquid_glass_layer.dart',
    ).readAsStringSync();

    expect(source, contains('uniform vec4 uBackdropBounds'));
    // One definition, the displaced sample, and the three dispersion taps.
    expect(
      RegExp(r'mirrorIntoBackdrop\s*\(').allMatches(source).length,
      5,
    );
    expect(renderer, contains('initialIndex: 55'));
    // The bounds are the native filter clip, not the material bounds: the
    // clip is rounded out to pixel buckets and holds real backdrop.
    expect(layer, contains('Rect? get backdropSampleBounds'));
    expect(layer, contains('.expandToPixelBuckets(devicePixelRatio)'));
  });

  test('magnification is one uniform lens about the material center', () {
    final source = File(
      'lib/assets/shaders/liquid_glass_final_render_core.glsl',
    ).readAsStringSync();
    final renderer = File(
      'lib/src/rendering/liquid_glass_render_object.dart',
    ).readAsStringSync();

    expect(source, contains('abs(uBackdropScale - 1.0) > 0.0001'));
    expect(source, isNot(contains('refractionComplement')));
    expect(source, contains('matteCoord - uMaterialCenter'));
    expect(source, contains('backdropScaleOffset + displacement'));
    expect(source, contains('backdropScaleOffset + redOffset'));
    expect(source, contains('backdropScaleOffset + blueOffset'));
    expect(renderer, contains('_materialCenterInMatte'));
    expect(renderer, contains('matteTransform,\n        bounds,'));
    expect(renderer, contains('setFloatUniforms(initialIndex: 34'));

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
      'lib/src/internal/flutter_gpu_geometry_renderer_native.dart',
    ).readAsStringSync();

    // Mattes and material maps share one allocation site.
    expect(
      'gpu.gpuContext.createTexture('.allMatches(renderer).length,
      1,
    );
    final geometryAllocationStart = renderer.indexOf(
      'final texture = gpu.gpuContext.createTexture(',
    );
    final geometryAllocationEnd = renderer.indexOf(
      ');',
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

    expect(source, contains('clamp(t - uContourOffset, 0.0, uEdgeWidth)'));
    expect(source, contains('float outward = -signedEdgeDistance;'));
    expect(source, contains('externalContourAlpha'));
    expect(source, contains('contourDirection(surfaceNormal)'));
    expect(geometrySource, contains('uContourExtent'));
    expect(geometrySource, contains('effectSupport'));
  });
}
