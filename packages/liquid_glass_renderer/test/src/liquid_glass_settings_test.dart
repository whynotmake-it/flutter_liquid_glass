import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

void main() {
  test('visibility scales every visual setting exactly once', () {
    const settings = LiquidGlassSettings(
      visibility: .5,
      glassColor: Color.fromARGB(128, 20, 40, 60),
      thickness: 40,
      blur: 12,
      chromaticAberration: 2,
      lightIntensity: 2,
      ambientStrength: .8,
      highlightColor: Color.fromARGB(128, 255, 255, 255),
      edgeColor: Color.fromARGB(128, 0, 0, 0),
      edgeWidth: 4,
      bleedStrength: .6,
      saturation: 2,
    );

    expect(settings.effectiveGlassColor.a, closeTo(128 / 255 * .5, .001));
    expect(settings.effectiveThickness, 20);
    expect(settings.effectiveBlur, 6);
    expect(settings.effectiveChromaticAberration, 1);
    expect(settings.effectiveLightIntensity, closeTo(128 / 255, .001));
    expect(settings.effectiveAmbientStrength, .4);
    expect(settings.effectiveHighlightColor.a, closeTo(128 / 255 * .5, .001));
    expect(settings.effectiveEdgeColor.a, closeTo(128 / 255 * .5, .001));
    expect(settings.effectiveEdgeWidth, 2);
    expect(settings.effectiveBleedStrength, .3);
    expect(settings.effectiveSaturation, 1.5);
  });

  test('copyWith preserves and updates every setting', () {
    const original = LiquidGlassSettings();
    final changed = original.copyWith(
      visibility: .8,
      glassColor: const Color(0x33445566),
      thickness: 31,
      blur: 7,
      chromaticAberration: .2,
      lightAngle: .3,
      lightIntensity: 1.4,
      ambientStrength: .1,
      highlightColor: const Color(0x778899AA),
      edgeColor: const Color(0xBBCCDDEE),
      edgeWidth: 2,
      edgeInset: .4,
      specularWrap: .6,
      bleedStrength: .7,
      refractiveIndex: 1.4,
      saturation: 1.1,
    );

    expect(changed, isNot(original));
    expect(
      changed.props,
      [
        .8,
        const Color(0x33445566),
        31,
        7,
        .2,
        .3,
        1.4,
        .1,
        const Color(0x778899AA),
        const Color(0xBBCCDDEE),
        2,
        .4,
        .6,
        .7,
        1.4,
        1.1,
      ],
    );
  });
}
