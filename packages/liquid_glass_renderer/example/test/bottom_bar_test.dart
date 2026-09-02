// The example intentionally inspects the package's consolidated layer to
// verify fake/real ordering; this is test-only use of an internal API.
// ignore_for_file: invalid_use_of_internal_member

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/consolidated_fake_glass_layer.dart';
import 'package:liquid_glass_renderer_example/widgets/bottom_bar.dart';

const _runBottomBarGoldens = bool.fromEnvironment('RUN_BOTTOM_BAR_GOLDENS');

void main() {
  testWidgets('bottom bar selection lens stays clear', (tester) async {
    await tester.pumpWidget(
      const CupertinoApp(home: _TestBottomBar(fake: true)),
    );

    final lens = tester.widget<LiquidGlass>(
      find.byKey(const ValueKey('bottom-bar-drag-glass')),
    );
    expect(lens.appearance?.tint.a, 0);
    expect(lens.appearance?.saturation, 1);
    expect(lens.appearance?.transmissionGamma, 1);
    expect(lens.appearance?.vibrancy, 0);
  });

  testWidgets(
    'fake bottom bar composites its selected indicator',
    (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(390, 120)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final captureKey = GlobalKey();

      await tester.pumpWidget(
        CupertinoApp(
          home: RepaintBoundary(
            key: captureKey,
            child: ColoredBox(
              color: CupertinoColors.white,
              child: LiquidGlassBottomBar(
                fake: true,
                bottomPadding: 8,
                horizontalPadding: 8,
                indicatorColor: const Color(0x1a000000),
                tabs: const [
                  LiquidGlassBottomBarTab(
                    label: 'One',
                    icon: CupertinoIcons.circle,
                  ),
                  LiquidGlassBottomBarTab(
                    label: 'Two',
                    icon: CupertinoIcons.circle,
                  ),
                  LiquidGlassBottomBarTab(
                    label: 'Three',
                    icon: CupertinoIcons.circle,
                  ),
                ],
                selectedIndex: 0,
                onTabSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      // Motor retains its spring ticker; wait a bounded number of frames
      // instead of using pumpAndSettle, which never becomes quiescent.
      await _pumpUntilFakeSurfaceReady(tester);

      expect(
        find.byKey(const ValueKey('bottom-bar-selection-indicator')),
        findsOneWidget,
      );
      final boundary =
          captureKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage();
      addTearDown(image.dispose);
      await expectLater(
        image,
        matchesGoldenFile('goldens/fake_bottom_bar_indicator.png'),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
    tags: 'golden',
    skip: !_runBottomBarGoldens,
  );

  for (final fake in [false, true]) {
    testWidgets(
      '${fake ? 'fake' : 'real'} bottom bar paints drag pill on top',
      (
        tester,
      ) async {
        tester.view
          ..physicalSize = const Size(390, 120)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final captureKey = GlobalKey();

        await tester.pumpWidget(
          CupertinoApp(
            home: RepaintBoundary(
              key: captureKey,
              child: CustomPaint(
                painter: const _GridPainter(),
                child: _TestBottomBar(fake: fake),
              ),
            ),
          ),
        );
        if (fake) {
          await _pumpUntilFakeSurfaceReady(tester);
        } else {
          for (var frame = 0; frame < 60; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            if (find.byType(FakeGlass).evaluate().isEmpty) break;
          }
        }
        // The real layer replaces its temporary fallback after flutter_gpu
        // initialization. Let that subtree replacement finish before starting
        // a pointer sequence, otherwise the test itself cancels the gesture.
        if (!fake) {
          for (var frame = 0; frame < 8; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
          }
        }

        expect(
          find.byKey(const ValueKey('bottom-bar-drag-glass')),
          fake ? findsOneWidget : findsNothing,
        );
        final dragRegion = find.byKey(
          const ValueKey('bottom-bar-drag-region'),
        );
        expect(dragRegion, findsOneWidget);
        final region = tester.getRect(dragRegion);
        final gesture = await tester.startGesture(
          Offset(region.left + region.width * 0.15, region.center.dy),
        );
        await gesture.moveBy(const Offset(20, 0));
        await tester.pump(const Duration(milliseconds: 16));
        await gesture.moveBy(const Offset(85, 0));
        for (var frame = 0; frame < 24; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        final dragGlass = find.byKey(
          const ValueKey('bottom-bar-drag-glass'),
        );
        expect(dragGlass, findsOneWidget);
        expect(tester.getCenter(dragGlass).dx, greaterThan(120));
        final boundary =
            captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        addTearDown(image.dispose);
        final golden = 'goldens/${fake ? 'fake' : 'real'}_bottom_bar_drag.png';
        if (fake) {
          await expectLater(image, matchesGoldenFile(golden));
        } else {
          await _expectGoldenWithin(image, golden, maxDiffRate: .005);
        }
        await gesture.up();
        // Tear down the GPU-backed subtree before flutter_tester finalizes the
        // test process. Leaving the animated runtime-effect layer attached can
        // segfault the test shell on the fake path.
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
      tags: 'golden',
      skip: !_runBottomBarGoldens,
    );
  }
}

Future<void> _expectGoldenWithin(
  ui.Image actual,
  String path, {
  required double maxDiffRate,
}) => TestWidgetsFlutterBinding.instance.runAsync(() async {
  final file = File(path);
  if (autoUpdateGoldenFiles) {
    final png = await actual.toByteData(format: ui.ImageByteFormat.png);
    await file.writeAsBytes(png!.buffer.asUint8List());
    return;
  }

  final codec = await ui.instantiateImageCodec(await file.readAsBytes());
  final expected = (await codec.getNextFrame()).image;
  try {
    expect((actual.width, actual.height), (expected.width, expected.height));
    final actualBytes = await actual.toByteData();
    final expectedBytes = await expected.toByteData();
    var different = 0;
    for (var offset = 0; offset < actualBytes!.lengthInBytes; offset += 4) {
      if (actualBytes.getUint32(offset) != expectedBytes!.getUint32(offset)) {
        different++;
      }
    }
    final rate = different / (actual.width * actual.height);
    expect(
      rate,
      lessThanOrEqualTo(maxDiffRate),
      reason: '$path differs on ${(rate * 100).toStringAsFixed(3)}% of pixels',
    );
  } finally {
    expected.dispose();
    codec.dispose();
  }
});

Future<void> _pumpUntilFakeSurfaceReady(WidgetTester tester) async {
  for (var frame = 0; frame < 120; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
    final layers = tester.allRenderObjects
        .whereType<RenderConsolidatedFakeGlassLayer>()
        .toList(growable: false);
    if (layers.isNotEmpty &&
        layers.every((layer) => layer.debugSurfaceShader != null)) {
      // Shader publication marks the retained layer dirty; allow a few
      // complete paints after that update before capturing the golden. The
      // first frame can still contain the fallback while the runtime effect
      // is compiled by the test renderer.
      for (var paint = 0; paint < 4; paint++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      return;
    }
  }
  fail('FakeGlass analytic surface shader did not become ready.');
}

class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(const Color(0xff38bdf8), BlendMode.src);
    final minor = Paint()
      ..color = const Color(0x99ffffff)
      ..strokeWidth = 1;
    final major = Paint()
      ..color = const Color(0x990f172a)
      ..strokeWidth = 1;
    for (var x = 0.0; x <= size.width; x += 12) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), minor);
    }
    for (var y = 0.0; y <= size.height; y += 12) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), minor);
    }
    for (var x = 0.0; x <= size.width; x += 48) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), major);
    }
    for (var y = 0.0; y <= size.height; y += 48) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), major);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => false;
}

class _TestBottomBar extends StatelessWidget {
  const _TestBottomBar({required this.fake});

  final bool fake;

  @override
  Widget build(BuildContext context) => LiquidGlassBottomBar(
    fake: fake,
    bottomPadding: 8,
    horizontalPadding: 8,
    indicatorColor: const Color(0x1a000000),
    tabs: const [
      LiquidGlassBottomBarTab(label: 'One', icon: CupertinoIcons.circle),
      LiquidGlassBottomBarTab(label: 'Two', icon: CupertinoIcons.circle),
      LiquidGlassBottomBarTab(label: 'Three', icon: CupertinoIcons.circle),
    ],
    selectedIndex: 0,
    onTabSelected: (_) {},
  );
}
