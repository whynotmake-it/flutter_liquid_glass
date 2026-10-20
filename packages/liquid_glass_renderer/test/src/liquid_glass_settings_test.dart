import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_color_model.dart';

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
    expect(clear.refractionAmount, 50);
    expect(clear.refractionFitsShape, isFalse);
    expect(clear.frost, 0);
    expect(LiquidGlassSettings.ios27Clear(frost: 0).frost, 0);
    // Slider 0 is completely clear: no blur pass. Tinted positions floor at
    // 2.1 logical pixels until Apple's curve clears it at ~.69.
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
    // 4.5 pt at Clear, 6.9 at the middle tick, full frost at Tinted.
    for (final (position, sigma) in [
      (0.0, 4.5),
      (.25, 5.57),
      (.5, 6.88),
      (.75, 11.35),
      (1.0, 18.71),
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
        // The preset floors Apple's curve at 2.1 logical pixels.
        expect(
          toolbar.frost,
          math.max(2.1, LiquidGlassSettings.ios27RegularFrost(position)),
        );
        expect(toolbar.tintAmount, position);
      }
    }
    expect(const LiquidGlassSettings().frost, 4.5);
    expect(LiquidGlassSettings.ios27RegularFrost(-1), closeTo(4.5, 1e-9));
    expect(LiquidGlassSettings.ios27RegularFrost(2), closeTo(18.71, .01));
    expect(
      LiquidGlassSettings.ios27RegularLight(tintAmount: 1, frost: 2).frost,
      2,
    );
  });

  test('omitted JSON frost keeps the size response', () {
    final omitted = LiquidGlassSettings.fromJson(const {'tintAmount': 0});
    expect(omitted.frost, 4.5);
    expect(
      omitted.frostSigmaAt(3, shapeShortSide: 63),
      closeTo(2.1, 1e-9),
    );
    final explicit = LiquidGlassSettings.fromJson(const {'frost': 4.5});
    expect(
      explicit.frostSigmaAt(3, shapeShortSide: 63),
      closeTo(4.5, 1e-9),
    );
  });

  test('the adaptive color model packs six vec4 slots', () {
    expect(
      GlassColorParameters.ios27Light.toShaderParameters().length,
      GlassColorParameters.shaderParameterFloatCount,
    );
    expect(GlassColorParameters.shaderParameterFloatCount, 24);
    expect(GlassColorParameters.ios27Light.transmittanceAtSmallSize, isNull);
    expect(GlassColorParameters.ios27Clear.transmittanceAtSmallSize, isNull);
    expect(
      GlassColorParameters.ios27Dark.transmittanceAtSmallSize,
      const GlassColorCurve(0.600, 0.298),
    );
    expect(
      GlassColorParameters.ios27Dark.luminanceLiftAtSmallSize,
      const GlassColorCurve.constant(0),
    );
    final json = GlassColorParameters.ios27Dark.toJson();
    expect(
      GlassColorParameters.fromJson(json),
      GlassColorParameters.ios27Dark,
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

  group('device blur floor', () {
    // Impeller 3.47.1: `GaussianBlurFilterContents::CalculateScale` returns
    // 1.0 up to a sigma of 4 device pixels and otherwise
    // 2^round(log2(4 / sigma)), so it stays 1.0 until 4 * sqrt(2) ~= 5.657
    // device pixels. `ScaleSigma` maps a logical sigma s to
    // s * (1 - 3.4e-3 * s + 3.4e-6 * s^2) before the device scale multiplies
    // it.
    double scaledSigma(double sigma) =>
        sigma * (1 - 3.4e-3 * sigma + 3.4e-6 * sigma * sigma);
    bool downsamples(double logicalSigma, double deviceScale) =>
        scaledSigma(logicalSigma) * deviceScale > 4 * math.sqrt2;

    const baseSigma = 2.1;

    test("today's 2.1 only downsamples on 3x displays", () {
      // 2.1 logical pixels is 4.2 device pixels at 2x and 5.5 at 2.625x,
      // both below the gate; 6.3 at 3x clears it.
      expect(downsamples(baseSigma, 2), isFalse);
      expect(downsamples(baseSigma, 2.625), isFalse);
      expect(downsamples(baseSigma, 3), isTrue);
    });

    test('the default and regular presets keep their fitted frost', () {
      for (final (deviceScale, downsampled) in [
        // The fitted 4.5 pt is already past the downsample gate at 1.5x and
        // above, so the device floor never raises it.
        (1.0, false),
        (1.5, true),
        (2.0, true),
        (2.625, true),
        (3.0, true),
      ]) {
        for (final settings in [
          const LiquidGlassSettings(),
          LiquidGlassSettings.ios27RegularLight(),
          LiquidGlassSettings.ios27RegularDark(),
        ]) {
          expect(
            settings.frostSigmaAt(deviceScale),
            closeTo(4.5, 1e-9),
            reason: '$settings at $deviceScale',
          );
          expect(
            downsamples(settings.frostSigmaAt(deviceScale), deviceScale),
            downsampled,
            reason: '$settings at $deviceScale',
          );
        }
      }
    });

    test('preset frost follows the glass size', () {
      final preset = LiquidGlassSettings.ios27RegularLight();
      // Fitted at toolbar size.
      expect(preset.frostSigmaAt(3, shapeShortSide: 94), closeTo(4.5, 1e-9));
      // Smaller glass is diffused much less; the preset floor keeps it
      // visible.
      expect(
        preset.frostSigmaAt(3, shapeShortSide: 63),
        closeTo(2.1, 1e-9),
      );
      // Larger glass is diffused more: 8 pt at 150 pt.
      expect(preset.frostSigmaAt(3, shapeShortSide: 150), closeTo(8, 1e-9));
      // The floor wins on very small glass.
      expect(preset.frostSigmaAt(3, shapeShortSide: 10), closeTo(2.1, 1e-9));
      // Below 3x the device floor raises the small endpoint so Impeller still
      // downsamples the blur.
      expect(preset.frostSigmaAt(2, shapeShortSide: 63), closeTo(2.9, 1e-9));
      // Clear glass at slider 0 stays blur-free at every size.
      expect(
        LiquidGlassSettings.ios27Clear().frostSigmaAt(3, shapeShortSide: 150),
        0,
      );
      // An explicit frost is the caller's and ignores the size response.
      expect(
        LiquidGlassSettings.ios27RegularLight(
          frost: 7,
        ).frostSigmaAt(3, shapeShortSide: 63),
        7,
      );
    });

    test('ios27Clear stays blur-free at slider 0', () {
      final clear = LiquidGlassSettings.ios27Clear();
      for (final deviceScale in [1.0, 2.0, 2.625, 3.0]) {
        expect(clear.frostSigmaAt(deviceScale), 0);
      }
    });

    test('ios27Clear floors tinted positions per device', () {
      final tinted = LiquidGlassSettings.ios27Clear(tintAmount: 0.5);
      // Apple's 1.28 pt is below the preset floor.
      expect(tinted.frost, baseSigma);
      expect(tinted.frostSigmaAt(3), baseSigma);
      expect(tinted.frostSigmaAt(2), closeTo(2.9, 1e-9));
      expect(tinted.frostSigmaAt(2.625), closeTo(5.8 / 2.625, 1e-9));
    });

    test('explicit frost is used verbatim', () {
      for (final frost in [0.0, 0.5, 1.5, 2.1, 4.0]) {
        final settings = LiquidGlassSettings(frost: frost);
        for (final deviceScale in [1.0, 2.0, 2.625, 3.0]) {
          expect(settings.frostSigmaAt(deviceScale), frost);
        }
      }
    });

    test('an explicit preset frost override is not floored', () {
      final preset = LiquidGlassSettings.ios27RegularLight(frost: 0.5);
      for (final deviceScale in [1.0, 2.0, 2.625, 3.0]) {
        expect(preset.frostSigmaAt(deviceScale), 0.5);
      }
    });

    test('copyWith clears the floor only when it sets frost', () {
      final preset = LiquidGlassSettings.ios27RegularLight();
      // Copying another field keeps the preset's floor.
      final changed = preset.copyWith(refractionAmount: 42);
      expect(changed.frostSigmaAt(2), closeTo(4.5, 1e-9));
      // Passing frost makes it the caller's value.
      final explicit = preset.copyWith(frost: 1);
      expect(explicit.frostSigmaAt(2), 1.0);
      expect(explicit.frostSigmaAt(1), 1.0);
    });

    test('floor eligibility is part of equality', () {
      expect(
        const LiquidGlassSettings(),
        LiquidGlassSettings.ios27RegularLight(),
      );
      // Same frost, but the explicit one is not floor-eligible.
      expect(
        const LiquidGlassSettings(frost: 4.5),
        isNot(const LiquidGlassSettings()),
      );
    });
  });
}
