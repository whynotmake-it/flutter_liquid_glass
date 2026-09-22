import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import '../../test/src/capture_scenes.dart';

/// Runs every capture scene on a real GPU, where a process can render any
/// number of captures. Checks what flutter_tester cannot: the fake reference
/// under a fade, and that captures survive being disposed and recreated.
///
/// Metal resolves MSAA edges seen through a subpass slightly differently from
/// the root pass, so hard backdrop edges under the soft shadow move by up to
/// ~24/255 while the glass itself is identical. The tolerance is therefore
/// wider than on the host; the mean bound still catches a shifted matte or a
/// clipped halo (hundreds of codes over whole regions).
///
///   flutter test --enable-impeller -d macos \
///     integration_test/liquid_glass_capture_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(precacheLiquidGlassShaders);

  for (final fake in [true, false]) {
    for (final scene in captureScenes) {
      testWidgets(
        'capture keeps the look on device: '
        '${fake ? "fake" : "real"}_${scene.name}',
        (tester) => expectCaptureKeepsTheLook(
          tester,
          scene,
          fake: fake,
          golden: false,
          compareReference: true,
          maxChannelDiff: 32,
        ),
      );
    }
  }

  testWidgets('a recreated capture renders like the first one', (
    tester,
  ) async {
    const scene = CaptureScene('bar', shadow: true);
    final first = await _render(tester, scene);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    final second = await _render(tester, scene);
    expectSameLook(second, first, width: 320, maxChannelDiff: 32);
  });
}

Future<Uint8List> _render(WidgetTester tester, CaptureScene scene) async {
  await pumpCaptureScene(tester, scene, fake: true, capture: true);
  final image = await captureSceneImage(tester);
  final bytes = (await tester.runAsync(image.toByteData))!;
  image.dispose();
  return bytes.buffer.asUint8List();
}
