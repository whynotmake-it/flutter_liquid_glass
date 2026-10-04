// A/B: does impeller_model predict that LiquidGlassCapture makes glass
// cheaper? The scenes follow the device runs in
// tool/results/optimization-log-2026-09.md, section H (Pixel 10, GPU mW):
//
//   bottom pill                      383  -> in capture 329
//   bar + own-capture indicator      910  -> in capture 736
//
// impeller_model reads the capture from the scene it pushes (5e529f0): the
// indicator's backdrop then restarts a bar-sized pass instead of the screen.
// It still predicts more traffic than without the capture on most devices:
// the device saving comes mostly from the shader filter's intermediate
// (optimization log, section G), which the model does not port yet.
//
//   flutter test --enable-impeller --enable-flutter-gpu test/gpu
//
// Reports: test/gpu/impeller_model_report/capture_ab_*.{html,json,png}.

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impeller_model/impeller_model.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

const _reportDir = 'impeller_model_report';
const _photo = 'assets/backdrops/coast.webp';

/// A full-screen photo with glass at the bottom, optionally inside a
/// [LiquidGlassCapture].
class _Scene extends StatelessWidget {
  const _Scene({required this.capture, required this.indicator});

  final bool capture;

  /// Adds an indicator as its own layer that refracts the bar below it.
  final bool indicator;

  @override
  Widget build(BuildContext context) {
    Widget glass = LiquidGlassLayer(
      child: SizedBox(
        width: 340,
        height: 64,
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            const LiquidGlass(
              shape: LiquidRoundedSuperellipse(borderRadius: 32),
              child: SizedBox(width: 340, height: 64),
            ),
            if (indicator)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: LiquidGlass.withOwnLayer(
                  shape: LiquidRoundedSuperellipse(borderRadius: 26),
                  child: SizedBox(width: 96, height: 52),
                ),
              ),
          ],
        ),
      ),
    );
    if (capture) glass = LiquidGlassCapture(child: glass);
    return Stack(
      children: [
        Positioned.fill(child: Image.asset(_photo, fit: BoxFit.cover)),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 34),
            child: glass,
          ),
        ),
      ],
    );
  }
}

void main() {
  setUpAll(() async {
    await LiquidGlass.precache();
  });

  Future<GpuReport> estimate(
    WidgetTester tester, {
    required bool capture,
    required bool indicator,
  }) async {
    await tester.pumpWidget(
      CupertinoApp(
        debugShowCheckedModeBanner: false,
        home: _Scene(capture: capture, indicator: indicator),
      ),
    );
    await tester.runAsync(
      () => precacheImage(
        const AssetImage(_photo),
        tester.element(find.byType(_Scene)),
      ),
    );
    // Real glass shows fake glass until Flutter GPU has drawn its shapes.
    for (var frame = 0; frame < 60; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (find.byType(FakeGlass).evaluate().isEmpty) break;
    }
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(FakeGlass), findsNothing);
    return estimateGpu(
      tester,
      name:
          'capture_ab_${indicator ? 'bar_indicator' : 'pill'}'
          '_${capture ? 'capture' : 'no_capture'}',
      screenshot: true,
      outputDir: _reportDir,
    );
  }

  for (final indicator in [false, true]) {
    final scene = indicator ? 'bar + own-layer indicator' : 'bottom pill';
    testWidgets('$scene: with and without LiquidGlassCapture', (tester) async {
      final a = await estimate(tester, capture: false, indicator: indicator);
      final b = await estimate(tester, capture: true, indicator: indicator);
      for (var i = 0; i < a.frames.length; i++) {
        final (fa, fb) = (a.frames[i], b.frames[i]);
        String t(FrameEstimate f) =>
            f.traffic.relativeToPlainFrame.toStringAsFixed(1);
        debugPrint(
          '$scene, ${fa.device.name}: '
          'no capture ${fa.renderPasses} passes ${t(fa)}x, '
          'capture ${fb.renderPasses} passes ${t(fb)}x',
        );
      }
    });
  }
}
