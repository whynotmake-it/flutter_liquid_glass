import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'shared.dart';
import 'submitted_scene_binding.dart';

const _width = 200;
const _height = 160;

void main() {
  final binding = SubmittedSceneBinding()
    ..captureWidth = _width
    ..captureHeight = _height;

  // Saturated enough to trigger every color factor, including the direct
  // model's vivid response.
  const backdrop = Positioned.fill(
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFFFF0040),
            Color(0xFFFFC000),
            Color(0xFF00D060),
            Color(0xFF0060FF),
            Color(0xFFC000FF),
          ],
        ),
      ),
    ),
  );

  const appearances = {
    'direct': LiquidGlassAppearance(tint: Color(0x604080FF), saturation: 1.5),
    'ios27 light': LiquidGlassAppearance.ios27RegularLight(),
    'ios27 dark': LiquidGlassAppearance.ios27RegularDark(),
  };

  for (final fake in [false, true]) {
    for (final frost in [0.0, 8.0]) {
      for (final MapEntry(key: name, value: appearance)
          in appearances.entries) {
        testWidgets(
          'visibility fades $name to the backdrop '
          '(fake=$fake, frost=$frost)',
          (tester) async {
            tester.view
              ..physicalSize = Size(_width.toDouble(), _height.toDouble())
              ..devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            final visibility = ValueNotifier<double>(1);
            addTearDown(visibility.dispose);

            // The layer keeps its default appearance, so FakeGlass also
            // covers a shape whose appearance differs from its layer's.
            Widget scene({bool glass = true}) => MaterialApp(
              debugShowCheckedModeBanner: false,
              home: Stack(
                children: [
                  backdrop,
                  if (glass)
                    Center(
                      child: LiquidGlassLayer(
                        fake: fake,
                        settings: LiquidGlassSettings(frost: frost),
                        child: ValueListenableBuilder<double>(
                          valueListenable: visibility,
                          builder: (_, value, _) => LiquidGlass(
                            appearance: appearance.copyWith(visibility: value),
                            shape: const LiquidRoundedSuperellipse(
                              borderRadius: 40,
                            ),
                            child: const SizedBox(width: 120, height: 80),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );

            Future<Uint8List> capture() async {
              binding
                ..captureNextScene = true
                ..scheduleFrame();
              await tester.pump();
              final image = (await tester.runAsync(() => binding.captured!))!;
              final bytes = (await tester.runAsync(image.toByteData))!;
              image.dispose();
              return Uint8List.fromList(bytes.buffer.asUint8List());
            }

            await tester.pumpWidget(scene(glass: false));
            await tester.pumpAndSettle();
            final expected = await capture();

            await tester.pumpWidget(scene());
            await tester.pumpAndSettle();
            Future<double> deviationAt(double value) async {
              visibility.value = value;
              await tester.pump();
              final frame = await capture();
              var sum = 0;
              for (var i = 0; i < frame.length; i += 4) {
                for (var channel = 0; channel < 3; channel++) {
                  sum += (frame[i + channel] - expected[i + channel]).abs();
                }
              }
              return sum.toDouble();
            }

            final full = await deviationAt(1);
            expect(full, greaterThan(0));
            expect(
              await deviationAt(0.5) / full,
              inInclusiveRange(0.25, 0.75),
              reason: 'Half visibility must lie between glass and backdrop.',
            );
            expect(
              await deviationAt(0.02) / full,
              lessThan(0.05),
              reason: 'Nearly hidden glass must already be nearly the '
                  'backdrop, or it pops when it reaches zero.',
            );
            visibility.value = 0;
            expect(await capture(), orderedEquals(expected));
          },
          skip: skipProperGlassTests,
        );
      }
    }
  }
}
