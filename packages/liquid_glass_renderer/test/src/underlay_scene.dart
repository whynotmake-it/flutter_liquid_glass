import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/read.dart';
import 'package:material_ui/material_ui.dart';

const _key = ValueKey('screen');

/// A page under one glass of [frost], scaled by [scale] about its center.
Widget underlayScene({double shift = 0, double frost = 0, double scale = 1}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        key: _key,
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: const [
                      Color(0xFF1E3A8A),
                      Color(0xFFF59E0B),
                      Color(0xFF10B981),
                    ],
                    begin: Alignment(-1 + shift, -1),
                    end: Alignment.bottomRight,
                    tileMode: TileMode.mirror,
                  ),
                ),
                child: const Center(
                  child: Text(
                    'Page under the glass',
                    style: TextStyle(color: Color(0xFFFFFFFF), fontSize: 22),
                  ),
                ),
              ),
            ),
            Positioned.fromRect(
              rect: const Rect.fromLTWH(30, 40, 200, 110),
              child: Transform.scale(
                scale: scale,
                child: LiquidGlassLayer(
                  settings: LiquidGlassSettings.ios27RegularLight().copyWith(
                    frost: frost,
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: LiquidGlass(
                      shape: LiquidRoundedSuperellipse(borderRadius: 28),
                      child: SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

/// The one glass layer of the scene.
RenderLiquidGlassLayer underlayGlass(WidgetTester tester) =>
    tester.allRenderObjects.whereType<RenderLiquidGlassLayer>().toSet().single;

/// The scene's pixels.
Future<Uint8List> underlayPixels(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_key),
  );
  final image = (await tester.runAsync(boundary.toImage))!;
  final bytes = (await tester.runAsync(image.toByteData))!;
  image.dispose();
  return bytes.buffer.asUint8List();
}

/// The largest channel difference between two frames.
int largestDifference(Uint8List a, Uint8List b) {
  var largest = 0;
  for (var i = 0; i < a.length; i++) {
    final d = (a[i] - b[i]).abs();
    if (d > largest) largest = d;
  }
  return largest;
}

/// Renders the scene reading its backdrop, then over a copy, and returns
/// the largest channel difference.
Future<int> underlayParity(
  WidgetTester tester, {
  required double frost,
  double scale = 1,
}) async {
  tester.view.physicalSize = const Size(260, 200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(() => debugGlassCopies = null);
  // flutter_tester renders only a process's first backdrop filter reliably,
  // so the reference reads the backdrop first.
  debugGlassCopies = false;
  await tester.pumpWidget(underlayScene(frost: frost, scale: scale));
  final reading = await underlayPixels(tester);
  debugGlassCopies = true;
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(underlayScene(frost: frost, scale: scale));
  expect(underlayGlass(tester).debugDrewOverCopy, isTrue);
  return largestDifference(reading, await underlayPixels(tester));
}
