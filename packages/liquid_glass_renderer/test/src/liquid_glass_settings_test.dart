import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

void main() {
  test('the default constructor is the light iOS 27 toolbar', () {
    const settings = LiquidGlassSettings();
    expect(settings.frost, 12);
    expect(settings.frostMix, .65);
    expect(settings.effectiveFrostMix, .65);
    expect(
      settings,
      LiquidGlassSettings.ios27ToolbarLight(),
    );
  });

  test('iOS 27 clear preset keeps the toolbar glint shape', () {
    final clear = LiquidGlassSettings.ios27Clear();

    expect(clear.refractionHeight, 20);
    expect(clear.refractionAmount, 60);
    expect(clear.refractionFitsShape, isFalse);
    expect(clear.frost, 12);
    expect(clear.frostMix, .65);
    expect(LiquidGlassSettings.ios27Clear(frost: 0).frost, 0);
    // Clear glass keeps the fixed sigma; the slider moves the mix.
    for (final (position, mix) in [
      (0.0, .65),
      (.25, .7375),
      (.5, .825),
      (.75, .9125),
      (1.0, 1.0),
    ]) {
      final positioned = LiquidGlassSettings.ios27Clear(
        tintAmount: position,
      );
      expect(positioned.frost, 12);
      expect(positioned.frostMix, closeTo(mix, 1e-12));
    }
  });

  test('the Liquid Glass slider round-trips and leaves frost alone', () {
    const settings = LiquidGlassSettings(frost: 3, tintAmount: .5);
    expect(LiquidGlassSettings.fromJson(settings.toJson()), settings);
    final retinted = settings.copyWith(tintAmount: 1);
    expect(retinted.tintAmount, 1);
    // copyWith does not derive the mix from the slider position.
    expect(retinted.frostMix, .65);
    expect(settings.effectiveFrost, 3);
    expect(const LiquidGlassSettings(frost: -1).effectiveFrost, 0);
    expect(
      LiquidGlassSettings.ios27Toolbar(
        brightness: Brightness.dark,
        tintAmount: .25,
      ).tintAmount,
      .25,
    );
  });

  test('the iOS 27 slider moves the mix, not the blur sigma', () {
    // Frost stays at the fixed 12 pt default at every position; the slider
    // maps linearly onto frostMix .65 -> 1, in light, dark and clear.
    for (final (position, mix) in [
      (0.0, .65),
      (.25, .7375),
      (.5, .825),
      (.75, .9125),
      (1.0, 1.0),
    ]) {
      for (final brightness in Brightness.values) {
        final toolbar = LiquidGlassSettings.ios27Toolbar(
          brightness: brightness,
          tintAmount: position,
        );
        expect(toolbar.frost, 12, reason: '$brightness $position');
        expect(
          toolbar.frostMix,
          closeTo(mix, 1e-12),
          reason: '$brightness $position',
        );
        expect(toolbar.tintAmount, position);
      }
      expect(
        LiquidGlassSettings.ios27ToolbarLight(
          tintAmount: position,
        ).frostMix,
        closeTo(mix, 1e-12),
      );
      expect(
        LiquidGlassSettings.ios27ToolbarDark(
          tintAmount: position,
        ).frostMix,
        closeTo(mix, 1e-12),
      );
    }
    // The kept frost helpers return the fixed sigma everywhere.
    for (final position in [-1.0, 0.0, .5, 1.0, 2.0]) {
      expect(LiquidGlassSettings.ios27RegularFrost(position), 12);
      expect(LiquidGlassSettings.ios27ClearFrost(position), 12);
    }
    expect(LiquidGlassSettings.ios27FrostMix(-1), .65);
    expect(LiquidGlassSettings.ios27FrostMix(2), 1);
    // An explicit frost keeps its value while the mix still maps.
    final overridden = LiquidGlassSettings.ios27ToolbarLight(
      tintAmount: 1,
      frost: 2,
    );
    expect(overridden.frost, 2);
    expect(overridden.frostMix, 1);
    final clearOverride = LiquidGlassSettings.ios27Clear(
      tintAmount: .5,
      frost: 0,
    );
    expect(clearOverride.frost, 0);
    expect(clearOverride.frostMix, closeTo(.825, 1e-12));
  });

  test('brightness-aware toolbar factory selects structural presets', () {
    expect(
      LiquidGlassSettings.ios27Toolbar(brightness: Brightness.light),
      LiquidGlassSettings.ios27ToolbarLight(),
    );
    expect(
      LiquidGlassSettings.ios27Toolbar(brightness: Brightness.dark),
      LiquidGlassSettings.ios27ToolbarDark(),
    );
  });

  test('effective values preserve the configured structural material', () {
    const settings = LiquidGlassSettings(
      refractionHeight: 40,
      refractionAmount: 80,
      backdropShrink: .25,
      frost: 8,
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
    expect(settings.effectiveFrost, 8);
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

  test('frostMix defaults to the iOS 27 clear diffusion', () {
    expect(const LiquidGlassSettings().frostMix, .65);
    expect(const LiquidGlassSettings().effectiveFrostMix, .65);
    expect(const LiquidGlassSettings(frostMix: .4).frostMix, .4);
    expect(const LiquidGlassSettings(frostMix: .4).effectiveFrostMix, .4);
  });

  test('copyWith edits frostMix and preserves the rest', () {
    const settings = LiquidGlassSettings(frost: 7, frostMix: .4);
    final edited = settings.copyWith(frostMix: .8);
    expect(edited.frostMix, .8);
    expect(edited.frost, 7);
    // An unrelated copyWith keeps the mix.
    expect(settings.copyWith(highlight: .5).frostMix, .4);
    // Equality includes frostMix.
    expect(settings, isNot(settings.copyWith(frostMix: .5)));
    expect(
      settings.copyWith(),
      settings.copyWith(frostMix: .4),
    );
  });

  test('frostMix serializes and clamps', () {
    const settings = LiquidGlassSettings(frost: 7, frostMix: .4);
    expect(settings.toJson()['frostMix'], .4);
    expect(LiquidGlassSettings.fromJson(settings.toJson()), settings);
    // Legacy JSON without the field keeps the default.
    final legacy = settings.toJson()..remove('frostMix');
    expect(LiquidGlassSettings.fromJson(legacy).frostMix, .65);
    expect(
      const LiquidGlassSettings(frostMix: -1).effectiveFrostMix,
      0,
    );
    expect(
      const LiquidGlassSettings(frostMix: 2).effectiveFrostMix,
      1,
    );
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
