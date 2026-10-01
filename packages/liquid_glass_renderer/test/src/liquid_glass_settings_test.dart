import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

void main() {
  test('iOS 27 toolbar presets contain structural renderer settings', () {
    const light = LiquidGlassSettings.ios27ToolbarLight();
    const dark = LiquidGlassSettings.ios27ToolbarDark();

    expect(light.thickness, 12);
    expect(light.frost, 7);
    expect(light.edgeRefraction, closeTo(27.42, .01));
    expect(light.highlightWidth, .75);
    expect(light.contourStrength, .15);
    expect(light.exteriorShadowSizeResponse, 1);
    expect(dark.thickness, 12);
    expect(dark.frost, 5);
    expect(dark.edgeRefraction, closeTo(27.42, .01));
    expect(dark.highlightWidth, 0);
    expect(dark.contourStrength, .25);
    expect(dark.exteriorShadowSizeResponse, 0);
  });

  test('brightness-aware toolbar factory selects structural presets', () {
    expect(
      LiquidGlassSettings.ios27Toolbar(brightness: Brightness.light),
      const LiquidGlassSettings.ios27ToolbarLight(),
    );
    expect(
      LiquidGlassSettings.ios27Toolbar(brightness: Brightness.dark),
      const LiquidGlassSettings.ios27ToolbarDark(),
    );
  });

  test('effective values preserve the configured structural material', () {
    const settings = LiquidGlassSettings(
      thickness: 40,
      edgeRefraction: 80,
      refractionSpread: .8,
      backdropScale: .75,
      frost: 12,
      chromaticAberration: 2,
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
    );
    expect(settings.effectiveThickness, 40);
    expect(settings.effectiveEdgeRefraction, 80);
    expect(settings.effectiveRefractionSpread, .8);
    expect(settings.effectiveBackdropScale, .75);
    expect(settings.effectiveFrost, 12);
    expect(settings.effectiveChromaticAberration, 2);
    expect(settings.effectiveHighlight, .6);
    expect(settings.effectiveHighlightWidth, 2.5);
    expect(settings.effectiveContourStrength, .3);
    expect(settings.effectiveContourWidth, 4);
    expect(settings.effectiveBevelShadowStrength, .1);
    expect(settings.effectiveBevelShadowDirectionality, .8);
    expect(settings.effectiveExteriorShadowSizeResponse, .6);
  });

  test('copyWith and JSON preserve the structural vector', () {
    final original = const LiquidGlassSettings().copyWith(
      thickness: 31,
      edgeRefraction: 42,
      refractionSpread: .5,
      backdropScale: .8,
      frost: 7,
      chromaticAberration: .2,
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
    expect(LiquidGlassSettings.fromJson(original.toJson()), original);
  });
}
