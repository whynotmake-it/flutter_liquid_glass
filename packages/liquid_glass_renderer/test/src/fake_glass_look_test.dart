import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_settings.dart';
import 'package:liquid_glass_renderer/src/rendering/fake_glass_color.dart';

void main() {
  const settings = LiquidGlassSettings();

  test('settings that differ where fake glass draws nothing look alike', () {
    expect(
      FakeGlassLook.of(settings.copyWith(refractionAmount: 30, aberration: 1)),
      FakeGlassLook.of(settings),
    );
    expect(
      FakeGlassLook.of(settings.copyWith(sliderPosition: 2)),
      FakeGlassLook.of(settings.copyWith(sliderPosition: 1)),
    );
  });

  test('settings that differ where fake glass draws look different', () {
    for (final other in [
      settings.copyWith(
        frost: LiquidGlassFrost.sigma(settings.frostBase + 1),
      ),
      settings.copyWith(glintStrength: 0),
      settings.copyWith(contourStrength: 0),
      settings.copyWith(contourDirectionality: 0),
      settings.copyWith(bevelShadowStrength: 0),
      settings.copyWith(sliderPosition: 0.5),
    ]) {
      expect(FakeGlassLook.of(other), isNot(FakeGlassLook.of(settings)));
    }
  });

  test('a preset frost and the same frost given look different: only the '
      'preset is raised per device', () {
    expect(
      FakeGlassLook.of(
        settings.copyWith(frost: LiquidGlassFrost.sigma(settings.frostBase)),
      ),
      isNot(FakeGlassLook.of(settings)),
    );
  });
}
