import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

void main() {
  test('iOS 27 toolbar preset uses the unified material axes', () {
    const settings = LiquidGlassSettings.ios27ToolbarLight();
    expect(settings.tint.r, closeTo(253 / 255, .001));
    expect(settings.tint.g, closeTo(252 / 255, .001));
    expect(settings.tint.b, closeTo(253 / 255, .001));
    expect(settings.tint.a, closeTo(.53, .001));
    expect(settings.thickness, 12);
    expect(settings.frost, 7);
    expect(settings.edgeRefraction, closeTo(27.42, .01));
    expect(settings.refractionSpread, 0);
    expect(settings.highlight, .5);
    expect(settings.contourStrength, .22);
    expect(settings.contourWidth, 1.5);
    expect(settings.contourTransmittance, .8);
    expect(settings.faceGradientStrength, .015);
    expect(settings.faceGradientDepth, 40);
    expect(settings.bevelShadowStrength, .025);
    expect(settings.bevelShadowDepth, 12);
  });

  test('visibility fades strengths without shrinking material support', () {
    const settings = LiquidGlassSettings(
      visibility: .5,
      tint: Color.fromARGB(128, 20, 40, 60),
      thickness: 40,
      edgeRefraction: 80,
      refractionSpread: .8,
      frost: 12,
      chromaticAberration: 2,
      transmissionGamma: .8,
      vibrancy: .4,
      highlight: .6,
      contourStrength: .3,
      contourWidth: 4,
      contourTransmittance: .8,
      faceGradientStrength: .06,
      faceGradientDepth: 40,
      bevelShadowStrength: .1,
      bevelShadowDepth: 12,
      saturation: 2,
    );
    expect(settings.effectiveTint.a, closeTo(128 / 255 * .5, .001));
    expect(settings.effectiveThickness, 20);
    expect(settings.effectiveEdgeRefraction, 40);
    expect(settings.effectiveRefractionSpread, .4);
    expect(settings.effectiveFrost, 6);
    expect(settings.effectiveChromaticAberration, 1);
    expect(settings.effectiveTransmissionGamma, .9);
    expect(settings.effectiveVibrancy, .2);
    expect(settings.effectiveHighlight, .3);
    expect(settings.effectiveContourStrength, .15);
    expect(settings.effectiveContourWidth, 4);
    expect(settings.effectiveContourTransmittance, .8);
    expect(settings.effectiveFaceGradientStrength, .03);
    expect(settings.effectiveFaceGradientDepth, 40);
    expect(settings.effectiveBevelShadowStrength, .05);
    expect(settings.effectiveBevelShadowDepth, 12);
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
      frost: 7,
      chromaticAberration: .2,
      saturation: 1.1,
      transmissionGamma: .9,
      vibrancy: .5,
      highlight: .4,
      contourStrength: .15,
      contourWidth: 2,
      contourTransmittance: .7,
      faceGradientStrength: .02,
      faceGradientDepth: 35,
      bevelShadowStrength: .03,
      bevelShadowDepth: 10,
    );
    expect(changed, isNot(original));
    expect(changed.tint, const Color(0x33445566));
    expect(changed.edgeRefraction, 42);
    expect(changed.refractionSpread, .5);
    expect(changed.contourWidth, 2);
    expect(changed.contourTransmittance, .7);
    expect(changed.faceGradientStrength, .02);
    expect(changed.bevelShadowStrength, .03);
  });

  test('preset JSON round trips the public material vector', () {
    const original = LiquidGlassSettings(
      tint: Color(0x88445566),
      thickness: 18,
      edgeRefraction: 32,
      refractionSpread: .4,
      frost: 6,
      highlight: .7,
      contourStrength: .2,
      contourWidth: 1.5,
      contourTransmittance: .75,
      faceGradientStrength: .015,
      faceGradientDepth: 40,
      bevelShadowStrength: .025,
      bevelShadowDepth: 12,
    );
    final restored = LiquidGlassSettings.fromJson(original.toJson());
    expect(restored, original);
  });
}
