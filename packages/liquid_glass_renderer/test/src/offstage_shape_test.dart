import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'shared.dart';
import 'submitted_scene_binding.dart';

const _width = 240;
const _height = 160;

/// Where the offstage shape would be.
const _offstageSpot = (x: 180, y: 80);

void main() {
  final binding = SubmittedSceneBinding()
    ..captureWidth = _width
    ..captureHeight = _height;
  setUp(pinPlainBackdropPath);

  Future<Uint8List> capture(WidgetTester tester) async {
    binding
      ..captureNextScene = true
      ..scheduleFrame();
    await tester.pump();
    final image = (await tester.runAsync(() => binding.captured!))!;
    final bytes = (await tester.runAsync(image.toByteData))!;
    image.dispose();
    return Uint8List.fromList(bytes.buffer.asUint8List());
  }

  int differingBytes(Uint8List a, Uint8List b) {
    var count = 0;
    for (var i = 0; i < a.length; i++) {
      if ((a[i] - b[i]).abs() > 2) count++;
    }
    return count;
  }

  List<int> pixel(Uint8List bytes, ({int x, int y}) at) {
    final i = (at.y * _width + at.x) * 4;
    return bytes.sublist(i, i + 4);
  }

  for (final fake in [false, true]) {
    for (final grouped in [false, true]) {
      final variant = '${fake ? 'fake' : 'real'} grouped=$grouped';

      Widget shape() => grouped
          ? const LiquidGlass.grouped(
              shape: LiquidOval(),
              child: SizedBox.square(dimension: 80),
            )
          : const LiquidGlass(
              shape: LiquidOval(),
              child: SizedBox.square(dimension: 80),
            );

      /// A layer with one onstage shape and, unless [second] is null, a second
      /// shape whose [Offstage] follows [second], behind a [RepaintBoundary]
      /// so toggling it does not repaint the layer.
      Widget scene(ValueNotifier<bool>? second) {
        final children = Stack(
          children: [
            Positioned(left: 20, top: 40, child: shape()),
            if (second != null)
              Positioned(
                left: 140,
                top: 40,
                child: RepaintBoundary(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: second,
                    builder: (_, offstage, child) =>
                        Offstage(offstage: offstage, child: child),
                    child: shape(),
                  ),
                ),
              ),
          ],
        );
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Stack(
            children: [
              const Positioned.fill(child: ColoredBox(color: Colors.white)),
              const Positioned.fill(child: GridPaper(color: Colors.black)),
              LiquidGlassLayer(
                fake: fake,
                settings: const LiquidGlassSettings(frost: 8),
                defaultAppearance: const LiquidGlassAppearance(
                  tint: Color(0x80FF0000),
                ),
                child: grouped
                    ? LiquidGlassBlendGroup(child: children)
                    : children,
              ),
            ],
          ),
        );
      }

      testWidgets('an offstage shape in a layer is not rendered: $variant', (
        tester,
      ) async {
        tester.view
          ..physicalSize = Size(_width.toDouble(), _height.toDouble())
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final offstage = ValueNotifier(true);
        addTearDown(offstage.dispose);

        await tester.pumpWidget(scene(null));
        await tester.pumpAndSettle();
        final without = await capture(tester);

        await tester.pumpWidget(scene(offstage));
        await tester.pumpAndSettle();
        expect(
          differingBytes(without, await capture(tester)),
          0,
          reason: 'the offstage shape draws nothing',
        );

        offstage.value = false;
        await tester.pumpAndSettle();
        final onstage = await capture(tester);
        expect(
          pixel(onstage, _offstageSpot),
          isNot(pixel(without, _offstageSpot)),
          reason: 'the shape draws once it is onstage',
        );

        offstage.value = true;
        await tester.pumpAndSettle();
        expect(
          differingBytes(without, await capture(tester)),
          0,
          reason: 'the shape draws nothing once offstage again',
        );
      });
    }
  }
}
