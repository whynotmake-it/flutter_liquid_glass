// Estimates the Impeller GPU work of the example's home screen (the
// playground's Controls scene over the photo backdrop) with impeller_model
// (https://github.com/whynotmake-it/talks, packages/impeller_model): render
// passes per frame, which widget causes each one, and the frames the screen
// requests while it looks still.
//
// Flutter GPU draws the glass shapes into a texture outside Impeller's
// display lists; the model does not see that pass. It sees everything that
// composites the glass: backdrop reads, blurs, shader filters, layers.
//
//   flutter test --enable-impeller --enable-flutter-gpu test/gpu
//
// Reports: test/gpu/impeller_model_report/<test name>.{html,json,png}.

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impeller_model/impeller_model.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/app.dart';
import 'package:liquid_glass_renderer_example/playground/backdrops.dart';
import 'package:liquid_glass_renderer_example/playground/playground_state.dart';

const _reportDir = 'impeller_model_report';

void main() {
  setUpAll(() async {
    // Without it, real glass paints as fake glass until its programs load.
    await LiquidGlass.precache();
  });

  Future<void> pumpPlayground(WidgetTester tester, {required bool fake}) async {
    final state = PlaygroundState(brightness: Brightness.light)
      ..scene.value = StageScene.controls
      ..fake.value = fake
      ..backdrop.value = Backdrop.photos;
    addTearDown(state.dispose);
    await tester.pumpWidget(
      CupertinoApp(
        debugShowCheckedModeBanner: false,
        home: Playground(state: state),
      ),
    );
    await tester.runAsync(() async {
      final context = tester.element(find.byType(Playground));
      for (final asset in backdropPhotos) {
        await precacheImage(AssetImage(asset), context);
      }
    });
    // Real glass shows fake glass until Flutter GPU has drawn its shapes.
    for (var frame = 0; frame < 60; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (fake || find.byType(FakeGlass).evaluate().isEmpty) break;
    }
    await tester.pump(const Duration(seconds: 1));
  }

  void printSummary(GpuReport report) {
    for (final frame in report.frames) {
      debugPrint(
        '${frame.device.name}: ${frame.renderPasses} passes, '
        '${frame.traffic.relativeToPlainFrame.toStringAsFixed(1)}x traffic',
      );
      for (final c in frame.costCenters) {
        debugPrint('  ${c.label}: ${c.renderPasses} passes');
      }
    }
    final demand = report.frameDemand!;
    debugPrint(
      'Frame demand: ${demand.verdict.name}, '
      '${demand.framesDrawn}/${demand.vsyncSlots} frames, '
      '${demand.unchangedFrames} unchanged',
    );
  }

  testWidgets('playground controls with real glass', (tester) async {
    await pumpPlayground(tester, fake: false);
    expect(find.byType(FakeGlass), findsNothing);
    final report = await estimateGpu(
      tester,
      screenshot: true,
      outputDir: _reportDir,
    );
    printSummary(report);
  });

  testWidgets('playground controls with fake glass', (tester) async {
    await pumpPlayground(tester, fake: true);
    final report = await estimateGpu(
      tester,
      screenshot: true,
      outputDir: _reportDir,
    );
    printSummary(report);
  });
}
