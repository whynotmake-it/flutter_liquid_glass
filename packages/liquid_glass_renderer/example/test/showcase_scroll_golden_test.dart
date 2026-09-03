import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/pages/showcase_page.dart';
import 'package:liquid_glass_renderer_example/state.dart';
import 'package:liquid_glass_renderer_example/widgets/backgrounds.dart';

void main() {
  setUp(() {
    fakeNotifier.value = true;
    backgroundNotifier.value = 'grid';
  });

  testWidgets('showcase settled scroll position', (tester) async {
    final captureKey = await _pumpShowcase(tester);

    _scrollPosition(tester).jumpTo(120);
    await tester.pump();
    await tester.pump();

    final image = await _capture(captureKey);
    addTearDown(image.dispose);
    await expectLater(
      image,
      matchesGoldenFile('goldens/showcase_scrolled.png'),
    );
  });

  testWidgets('showcase is correct on the first scroll frame', (tester) async {
    final captureKey = await _pumpShowcase(tester);

    _scrollPosition(tester).jumpTo(120);
    await tester.pump();

    final image = await _capture(captureKey);
    addTearDown(image.dispose);
    await expectLater(
      image,
      matchesGoldenFile('goldens/showcase_scrolled.png'),
    );
  });
}

Future<GlobalKey> _pumpShowcase(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(500, 700)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final captureKey = GlobalKey();
  await tester.pumpWidget(
    CupertinoApp(
      home: RepaintBoundary(
        key: captureKey,
        child: Stack(
          children: [
            const Positioned.fill(child: Grid()),
            Positioned.fill(
              child: LiquidGlassLayer(
                fake: true,
                settings: settingsNotifier.value,
                defaultAppearance: appearanceNotifier.value,
                child: const ShowcasePage(),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return captureKey;
}

ScrollPosition _scrollPosition(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first).position;

Future<ui.Image> _capture(GlobalKey key) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return boundary.toImage();
}
