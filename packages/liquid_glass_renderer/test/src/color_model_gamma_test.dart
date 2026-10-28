import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'shared.dart';

const _key = ValueKey('gamma');

LiquidGlassAppearance _dark(double gamma) => LiquidGlassAppearance(
  colorModel: LiquidGlassColorModel.ios27(
    brightness: Brightness.dark,
    transmissionGamma: gamma,
  ),
);

void main() {
  test('an iOS 27 model keeps its gamma through JSON', () {
    const bent = LiquidGlassColorModel.ios27(
      brightness: Brightness.dark,
      transmissionGamma: 1.14,
    );
    expect(bent.toJson(), {
      'ios27Dark': {'transmissionGamma': 1.14},
    });
    expect(LiquidGlassColorModel.fromJson(bent.toJson()), bent);
    expect(
      const LiquidGlassColorModel.ios27(brightness: Brightness.light).toJson(),
      'ios27Light',
    );
    expect(
      bent,
      isNot(const LiquidGlassColorModel.ios27(brightness: Brightness.dark)),
    );
  });

  testWidgets('a gamma above 1 darkens an iOS 27 face', (tester) async {
    tester.view
      ..physicalSize = const Size(240, 120)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: _key,
          child: ColoredBox(
            color: const Color(0xFF808080),
            child: Center(
              child: LiquidGlassLayer(
                settings: LiquidGlassSettings.ios27RegularDark(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LiquidGlass(
                      shape: const LiquidRoundedSuperellipse(borderRadius: 20),
                      appearance: _dark(1),
                      child: const SizedBox(width: 80, height: 80),
                    ),
                    const SizedBox(width: 40),
                    LiquidGlass(
                      shape: const LiquidRoundedSuperellipse(borderRadius: 20),
                      appearance: _dark(1.4),
                      child: const SizedBox(width: 80, height: 80),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_key),
    );
    final image = (await tester.runAsync(boundary.toImage))!;
    final bytes = (await tester.runAsync(image.toByteData))!;
    image.dispose();
    final rgba = bytes.buffer.asUint8List();

    double face(int left) {
      var sum = 0;
      for (var y = 50; y < 70; y++) {
        for (var x = left + 30; x < left + 50; x++) {
          sum += rgba[(y * 240 + x) * 4];
        }
      }
      return sum / 400;
    }

    final regular = face(20);
    final bent = face(140);
    expect(regular, isNot(closeTo(128, 2)), reason: 'the glass draws');
    expect(bent, lessThan(regular - 4));
  }, skip: skipProperGlassTests);
}
