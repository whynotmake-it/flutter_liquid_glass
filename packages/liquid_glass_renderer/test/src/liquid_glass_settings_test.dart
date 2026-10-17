import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

void main() {
  test('the default constructor is the light iOS 27 regular glass', () {
    expect(
      const LiquidGlassSettings(),
      LiquidGlassSettings.ios27RegularLight(),
    );
  });

  test('iOS 27 clear preset keeps the regular glint shape', () {
    final clear = LiquidGlassSettings.ios27Clear();

    expect(clear.refractionHeight, 20);
    expect(clear.refractionAmount, 60);
    expect(clear.refractionFitsShape, isFalse);
    expect(clear.frost, 0);
    expect(LiquidGlassSettings.ios27Clear(frost: 0).frost, 0);
    // Slider 0 is completely clear: no blur pass. Tinted positions floor at
    // minBlurPassSigma until Apple's curve clears it at ~.69.
    for (final (position, sigma) in [
      (0.0, .0),
      (.25, 2.1),
      (.5, 2.1),
      (.75, 4.6),
      (1.0, 16.4),
    ]) {
      expect(
        LiquidGlassSettings.ios27Clear(tintAmount: position).frost,
        closeTo(sigma, sigma * .03 + 1e-9),
      );
      expect(
        LiquidGlassSettings.ios27Clear(tintAmount: position).effectiveFrost,
        closeTo(sigma, sigma * .03 + 1e-9),
      );
    }
  });

  test('the Liquid Glass slider round-trips and leaves frost alone', () {
    const settings = LiquidGlassSettings(frost: 3, tintAmount: .5);
    expect(LiquidGlassSettings.fromJson(settings.toJson()), settings);
    expect(settings.copyWith(tintAmount: 1).tintAmount, 1);
    expect(settings.effectiveFrost, 3);
    expect(const LiquidGlassSettings(frost: -1).effectiveFrost, 0);
    expect(
      LiquidGlassSettings.ios27Regular(
        brightness: Brightness.dark,
        tintAmount: .25,
      ).tintAmount,
      .25,
    );
  });

  test('iOS 27 regular glass blurs along the fitted slider curve', () {
    // 2 pt at Clear, 6.1 at the middle tick, full frost at Tinted.
    for (final (position, sigma) in [
      (0.0, 2.0),
      (.25, 3.49),
      (.5, 6.1),
      (.75, 10.06),
      (1.0, 16.58),
    ]) {
      expect(
        LiquidGlassSettings.ios27RegularFrost(position),
        closeTo(sigma, .01),
      );
      for (final brightness in Brightness.values) {
        final toolbar = LiquidGlassSettings.ios27Regular(
          brightness: brightness,
          tintAmount: position,
        );
        // The preset floors Apple's curve at minBlurPassSigma so the blur
        // pass Impeller adds always downsamples.
        expect(
          toolbar.frost,
          math.max(
            LiquidGlassSettings.minBlurPassSigma,
            LiquidGlassSettings.ios27RegularFrost(position),
          ),
        );
        expect(toolbar.tintAmount, position);
      }
    }
    expect(const LiquidGlassSettings().frost, 2.1);
    expect(LiquidGlassSettings.ios27RegularFrost(-1), closeTo(2, 1e-9));
    expect(LiquidGlassSettings.ios27RegularFrost(2), closeTo(16.58, .01));
    expect(
      LiquidGlassSettings.ios27RegularLight(tintAmount: 1, frost: 2).frost,
      2,
    );
  });

  test('brightness-aware regular factory selects structural presets', () {
    expect(
      LiquidGlassSettings.ios27Regular(brightness: Brightness.light),
      LiquidGlassSettings.ios27RegularLight(),
    );
    expect(
      LiquidGlassSettings.ios27Regular(brightness: Brightness.dark),
      LiquidGlassSettings.ios27RegularDark(),
    );
  });

  test('effective values preserve the configured structural material', () {
    const settings = LiquidGlassSettings(
      refractionHeight: 40,
      refractionAmount: 80,
      backdropShrink: .25,
      frost: 12,
      dispersion: 2,
      highlight: .6,
      contourStrength: .3,
      bevelShadowStrength: .1,
    );
    expect(settings.effectiveRefractionHeight, 40);
    expect(settings.effectiveRefractionAmount, 80);
    expect(settings.effectiveBackdropShrink, .25);
    expect(settings.effectiveDisplacementScale, 80);
    expect(settings.effectiveEdgeDistanceRange, 40);
    expect(settings.effectiveFrost, 12);
    expect(settings.dispersion, 2);
    expect(settings.highlight, .6);
    expect(settings.contourStrength, .3);
    expect(settings.bevelShadowStrength, .1);
  });

  test('copyWith and JSON preserve the structural vector', () {
    final original = const LiquidGlassSettings().copyWith(
      refractionHeight: 31,
      refractionAmount: 42,
      refractionFitsShape: false,
      backdropShrink: .2,
      frost: 7,
      dispersion: .2,
      highlight: .4,
      contourStrength: .15,
      contourDirectionality: .5,
      bevelShadowStrength: .03,
      tintAmount: .3,
    );
    expect(LiquidGlassSettings.fromJson(original.toJson()), original);
  });

  test('backdrop shrink never enlarges the backdrop', () {
    expect(
      const LiquidGlassSettings(backdropShrink: -1).effectiveBackdropShrink,
      0,
    );
    expect(
      const LiquidGlassSettings(backdropShrink: 2).effectiveBackdropShrink,
      .75,
    );
  });

  test('the border width follows the border strength', () {
    expect(const LiquidGlassSettings().contourWidth, .75);
    expect(const LiquidGlassSettings(contourStrength: 0).contourWidth, 0);
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
