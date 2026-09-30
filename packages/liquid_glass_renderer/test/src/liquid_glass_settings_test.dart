import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

void main() {
  test('iOS 27 toolbar presets contain structural renderer settings', () {
    const light = LiquidGlassSettings.ios27ToolbarLight();
    const dark = LiquidGlassSettings.ios27ToolbarDark();

    expect(light.refractionHeight, 20);
    expect(light.frost, 7);
    expect(light.refractionAmount, 60);
    expect(light.refractionFitsShape, isTrue);
    expect(light.dispersion, 0);
    expect(light.highlight, 1);
    expect(light.highlightWidth, 1.2);
    expect(light.highlightOppositeStrength, 1);
    expect(light.contourStrength, .43);
    expect(light.contourWidth, .75);
    expect(light.contourDirectionality, .77);
    expect(light.bevelShadowStrength, 0);
    expect(light.exteriorShadowSizeResponse, 1);
    expect(dark.refractionHeight, 20);
    expect(dark.frost, 5);
    expect(dark.refractionAmount, 60);
    expect(dark.highlight, light.highlight);
    expect(dark.highlightWidth, light.highlightWidth);
    expect(dark.contourStrength, .88);
    expect(dark.contourDirectionality, 1);
    expect(dark.bevelShadowStrength, 0);
    expect(dark.exteriorShadowSizeResponse, 0);
  });

  test('iOS 27 clear preset keeps the toolbar glint shape', () {
    final clear = LiquidGlassSettings.ios27Clear();
    const toolbar = LiquidGlassSettings.ios27ToolbarLight();

    expect(clear.refractionHeight, 20);
    expect(clear.refractionAmount, 60);
    expect(clear.refractionFitsShape, isFalse);
    expect(clear.frost, closeTo(.35, 1e-9));
    expect(LiquidGlassSettings.ios27Clear(frost: 0).frost, 0);
    // Clear glass's slider blur: 0.35/0.67/1.28/4.6/16.4 pt.
    for (final (position, sigma) in [
      (0.0, .35),
      (.25, .67),
      (.5, 1.28),
      (.75, 4.6),
      (1.0, 16.4),
    ]) {
      expect(
        LiquidGlassSettings.ios27Clear(tintAmount: position).frost,
        closeTo(sigma, sigma * .03),
      );
      expect(
        LiquidGlassSettings.ios27Clear(
          tintAmount: position,
        ).frostFor(const LiquidGlassColorModel.ios27Clear()),
        closeTo(sigma, sigma * .03),
        reason: 'no generic slider blur on top',
      );
    }
    expect(clear.highlight, 1);
    expect(clear.highlightWidth, toolbar.highlightWidth);
    expect(clear.highlightWrap, toolbar.highlightWrap);
    expect(clear.contourStrength, .36);
    expect(clear.contourDirectionality, 1);
    expect(clear.bevelShadowStrength, 0);
  });

  test('the Liquid Glass slider round-trips and only adds blur', () {
    const settings = LiquidGlassSettings(frost: 3, tintAmount: .5);
    expect(LiquidGlassSettings.fromJson(settings.toJson()), settings);
    expect(settings.copyWith(tintAmount: 1).tintAmount, 1);
    expect(const LiquidGlassSettings(frost: 3).effectiveFrost, 3);
    expect(settings.effectiveFrost, greaterThan(3));
    expect(
      const LiquidGlassSettings(frost: 3, tintAmount: 1).effectiveFrost,
      greaterThan(settings.effectiveFrost),
    );
    expect(
      LiquidGlassSettings.ios27Toolbar(
        brightness: Brightness.dark,
        tintAmount: .25,
      ).tintAmount,
      .25,
    );
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
      refractionHeight: 40,
      refractionAmount: 80,
      magnification: .75,
      frost: 12,
      dispersion: 2,
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
    expect(settings.effectiveRefractionHeight, 40);
    expect(settings.effectiveRefractionAmount, 80);
    expect(settings.effectiveMagnification, .75);
    expect(settings.effectiveDisplacementScale, 80);
    expect(settings.effectiveEdgeDistanceRange, 40);
    expect(settings.effectiveFrost, 12);
    expect(settings.effectiveDispersion, 2);
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
      refractionHeight: 31,
      refractionAmount: 42,
      refractionFitsShape: false,
      smoothRefraction: false,
      magnification: .8,
      frost: 7,
      dispersion: .2,
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

  test('JSON written before the refraction model change still loads', () {
    final restored = LiquidGlassSettings.fromJson(const {
      'thickness': 12.0,
      'edgeRefraction': 27.42,
      'refractionSpread': 0.5,
      'backdropScale': 0.9,
    });
    expect(restored.refractionHeight, 12);
    expect(restored.refractionAmount, 27.42);
    expect(restored.magnification, .9);
    expect(restored.refractionFitsShape, isTrue);
    expect(restored.smoothRefraction, isTrue);
  });

  test('refraction and lighting depth stay independent', () {
    const flat = LiquidGlassSettings(refractionHeight: 0, refractionAmount: 0);
    expect(flat.effectiveDisplacementScale, greaterThan(0));
    expect(flat.effectiveEdgeDistanceRange, 12);
    expect(
      const LiquidGlassSettings(refractionHeight: -4).effectiveRefractionHeight,
      0,
    );
  });
}
