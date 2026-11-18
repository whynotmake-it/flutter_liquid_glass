import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_shadow.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass.dart';

// The radius iOS gives the shadow, back from the blur radius Flutter takes.
double _radius(BoxShadow shadow) => shadow.blurSigma * math.sqrt2;

Widget _glass(Size size) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(
    child: LiquidGlassLayer(
      settings: const LiquidGlassSettings.ios27Regular(
        brightness: Brightness.light,
      ),
      backdrop: const LiquidGlassBackdrop.solid(Color(0xFF808080)),
      child: SizedBox.fromSize(
        size: size,
        child: const LiquidGlass(
          shape: LiquidRoundedSuperellipse(radius: 20),
          shadows: [
            LiquidGlassShadow(blurRadius: 2),
            LiquidGlassShadow.ios27Regular(brightness: Brightness.light),
          ],
          child: SizedBox.expand(),
        ),
      ),
    ),
  ),
);

void main() {
  test('small glass casts the faint contact shadow', () {
    for (final side in [20.0, 44.0, 64.0]) {
      final shadow = const LiquidGlassShadow.ios27Regular(
        brightness: Brightness.light,
      ).castAt(Size(200, side));
      expect(shadow.color.a, closeTo(0.012, 1e-6));
      expect(_radius(shadow), closeTo(4, 1e-6));
      expect(shadow.offset, const Offset(0, 8));
    }
  });

  test('the shadow grows with the shorter side up to 160 points', () {
    const light = LiquidGlassShadow.ios27Regular(brightness: Brightness.light);
    const dark = LiquidGlassShadow.ios27Regular(brightness: Brightness.dark);
    // The inputs UIKit gives glass 150 points high: opacity 0.3625 in light
    // mode and 0.5417 in dark mode over black at 30 %, radius 21.9167.
    expect(light.castAt(const Size(240, 150)).color.a, closeTo(0.10875, 1e-5));
    expect(dark.castAt(const Size(240, 150)).color.a, closeTo(0.1625, 1e-4));
    expect(_radius(light.castAt(const Size(240, 150))), closeTo(21.9167, 1e-4));
    // 94 points high: 0.1525 and 0.2150, radius 10.25.
    expect(light.castAt(const Size(150, 94)).color.a, closeTo(0.04575, 1e-6));
    expect(dark.castAt(const Size(150, 94)).color.a, closeTo(0.0645, 1e-6));
    expect(_radius(dark.castAt(const Size(150, 94))), closeTo(10.25, 1e-6));
    for (final side in [160.0, 362.0]) {
      expect(light.castAt(Size(520, side)).color.a, closeTo(0.12, 1e-6));
      expect(dark.castAt(Size(520, side)).color.a, closeTo(0.18, 1e-6));
      expect(_radius(light.castAt(Size(520, side))), closeTo(24, 1e-6));
    }
  });

  test('a shadow of numbers is cast as given at every size', () {
    const shadow = LiquidGlassShadow(
      color: Color(0x40000000),
      offset: Offset(0, 3),
      blurRadius: 2,
      spreadRadius: 1,
    );
    for (final size in const [Size(10, 10), Size(400, 400)]) {
      expect(
        shadow.castAt(size),
        const BoxShadow(
          color: Color(0x40000000),
          offset: Offset(0, 3),
          blurRadius: 2,
          spreadRadius: 1,
        ),
      );
    }
  });

  test('shadows compare by what they cast', () {
    expect(
      const LiquidGlassShadow(blurRadius: 2),
      const LiquidGlassShadow(blurRadius: 2),
    );
    expect(
      const LiquidGlassShadow(blurRadius: 2),
      isNot(const LiquidGlassShadow(blurRadius: 3)),
    );
    expect(
      const LiquidGlassShadow.ios27Regular(brightness: Brightness.dark),
      isNot(const LiquidGlassShadow.ios27Regular(brightness: Brightness.light)),
    );
    expect(
      const LiquidGlassShadow.ios27Regular(brightness: Brightness.dark),
      isNot(const LiquidGlassShadow()),
    );
  });

  testWidgets('a shape casts the shadow of its own size', (tester) async {
    await tester.pumpWidget(_glass(const Size(120, 44)));
    var cast = tester
        .renderObject<RenderLiquidGlass>(find.byType(LiquidGlass))
        .castShadows;
    expect(cast.first, const BoxShadow(blurRadius: 2));
    expect(cast.last.color.a, closeTo(0.012, 1e-6));
    expect(_radius(cast.last), closeTo(4, 1e-6));

    await tester.pumpWidget(_glass(const Size(300, 200)));
    cast = tester
        .renderObject<RenderLiquidGlass>(find.byType(LiquidGlass))
        .castShadows;
    expect(cast.last.color.a, closeTo(0.12, 1e-6));
    expect(_radius(cast.last), closeTo(24, 1e-6));
  });
}
