import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

void main() {
  test('iOS 27 toolbar preset uses the unified material axes', () {
    const settings = LiquidGlassSettings.ios27ToolbarLight();
    expect(settings.tint.r, closeTo(253 / 255, .001));
    expect(settings.tint.g, closeTo(252 / 255, .001));
    expect(settings.tint.b, closeTo(253 / 255, .001));
    expect(settings.tint.a, closeTo(.407, .001));
    expect(settings.thickness, 12);
    expect(settings.frost, 7);
    expect(settings.edgeRefraction, closeTo(27.42, .01));
    expect(settings.refractionSpread, 0);
    expect(settings.backdropScale, 1);
    expect(settings.highlight, .25);
    expect(settings.highlightWidth, .75);
    expect(settings.highlightWrap, .25);
    expect(settings.highlightOppositeStrength, .5);
    expect(settings.curvatureLighting, 0);
    expect(settings.contourStrength, .15);
    expect(settings.contourWidth, .65);
    expect(settings.contourOffset, .25);
    expect(settings.contourTransmittance, .8);
    expect(settings.bevelShadowStrength, .04);
    expect(settings.bevelShadowDepth, 18);
    expect(settings.bevelShadowOffset, 4);
    expect(settings.bevelShadowDirectionality, .75);
    expect(settings.bevelShadowSizeResponse, 0);
    expect(settings.exteriorShadowSizeResponse, 1);
  });

  test('visibility fades strengths without shrinking material support', () {
    const settings = LiquidGlassSettings(
      visibility: .5,
      tint: Color.fromARGB(128, 20, 40, 60),
      thickness: 40,
      edgeRefraction: 80,
      refractionSpread: .8,
      backdropScale: .75,
      frost: 12,
      chromaticAberration: 2,
      transmissionGamma: .8,
      vibrancy: .4,
      highlight: .6,
      highlightWidth: 2.5,
      highlightWrap: .3,
      curvatureLighting: .4,
      contourStrength: .3,
      contourWidth: 4,
      contourOffset: .5,
      contourTransmittance: .8,
      bevelShadowStrength: .1,
      bevelShadowOffset: 3,
      bevelShadowDirectionality: .8,
      bevelShadowSizeResponse: .7,
      exteriorShadowSizeResponse: .6,
      saturation: 2,
    );
    expect(settings.effectiveTint.a, closeTo(128 / 255 * .5, .001));
    expect(settings.effectiveThickness, 20);
    expect(settings.effectiveEdgeRefraction, 40);
    expect(settings.effectiveRefractionSpread, .4);
    expect(settings.effectiveBackdropScale, .875);
    expect(settings.effectiveFrost, 6);
    expect(settings.effectiveChromaticAberration, 1);
    expect(settings.effectiveTransmissionGamma, .9);
    expect(settings.effectiveVibrancy, .2);
    expect(settings.effectiveHighlight, .3);
    expect(settings.effectiveHighlightWidth, 2.5);
    expect(settings.effectiveHighlightWrap, .3);
    expect(settings.effectiveCurvatureLighting, .2);
    expect(settings.effectiveContourStrength, .15);
    expect(settings.effectiveContourWidth, 4);
    expect(settings.effectiveContourOffset, .5);
    expect(settings.effectiveContourTransmittance, .8);
    expect(settings.effectiveBevelShadowStrength, .05);
    expect(settings.effectiveBevelShadowDepth, 12);
    expect(settings.effectiveBevelShadowDirectionality, .4);
    expect(settings.effectiveBevelShadowSizeResponse, .7);
    expect(settings.effectiveExteriorShadowSizeResponse, .3);
    expect(settings.effectiveSaturation, 1.5);
  });

  test('copyWith updates the unified settings vector', () {
    const original = LiquidGlassSettings();
    final changed = original.copyWith(
      visibility: .8,
      tint: const Color(0x33445566),
      thickness: 31,
      edgeRefraction: 42,
      refractionSpread: .5,
      backdropScale: .8,
      frost: 7,
      chromaticAberration: .2,
      saturation: 1.1,
      transmissionGamma: .9,
      vibrancy: .5,
      highlight: .4,
      highlightWidth: 3,
      highlightWrap: .2,
      curvatureLighting: .6,
      contourStrength: .15,
      contourWidth: 2,
      contourOffset: .75,
      contourTransmittance: .7,
      bevelShadowStrength: .03,
      bevelShadowDepth: 10,
      bevelShadowOffset: 4,
      bevelShadowDirectionality: .75,
      bevelShadowSizeResponse: .65,
      exteriorShadowSizeResponse: .55,
    );
    expect(changed, isNot(original));
    expect(changed.tint, const Color(0x33445566));
    expect(changed.edgeRefraction, 42);
    expect(changed.refractionSpread, .5);
    expect(changed.backdropScale, .8);
    expect(changed.highlightWrap, .2);
    expect(changed.highlightWidth, 3);
    expect(changed.curvatureLighting, .6);
    expect(changed.contourWidth, 2);
    expect(changed.contourOffset, .75);
    expect(changed.contourTransmittance, .7);
    expect(changed.bevelShadowStrength, .03);
    expect(changed.bevelShadowOffset, 4);
    expect(changed.bevelShadowDirectionality, .75);
    expect(changed.bevelShadowSizeResponse, .65);
    expect(changed.exteriorShadowSizeResponse, .55);
  });

  test('preset JSON round trips the public material vector', () {
    const original = LiquidGlassSettings(
      tint: Color(0x88445566),
      thickness: 18,
      edgeRefraction: 32,
      refractionSpread: .4,
      backdropScale: .85,
      frost: 6,
      highlight: .7,
      highlightWidth: 2,
      highlightWrap: .4,
      curvatureLighting: .35,
      contourStrength: .2,
      contourWidth: 1.5,
      contourOffset: .5,
      contourTransmittance: .75,
      bevelShadowStrength: .025,
      bevelShadowOffset: 3,
      bevelShadowDirectionality: .6,
      bevelShadowSizeResponse: .55,
    );
    final restored = LiquidGlassSettings.fromJson(original.toJson());
    expect(restored, original);
  });
}
