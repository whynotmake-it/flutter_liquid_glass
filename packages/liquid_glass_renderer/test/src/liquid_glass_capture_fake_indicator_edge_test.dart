import 'package:flutter_test/flutter_test.dart';

import 'capture_scenes.dart';
import 'shared.dart';

// One scene per file: see capture_scenes.dart for why.
void main() {
  testWidgets(
    'capture keeps the look: fake_indicator_edge',
    (tester) => expectCaptureKeepsTheLook(
      tester,
      captureScenes.singleWhere((scene) => scene.name == 'indicator_edge'),
      fake: true,
    ),
    skip: skipProperGlassTests,
  );
}
