import 'package:flutter_test/flutter_test.dart';

import 'capture_scenes.dart';
import 'shared.dart';

// One scene per file: see capture_scenes.dart for why.
void main() {
  testWidgets(
    'capture keeps the look: real_bar_edge',
    (tester) => expectCaptureKeepsTheLook(
      tester,
      captureScenes.singleWhere((scene) => scene.name == 'bar_edge'),
      fake: false,
    ),
    skip: skipProperGlassTests,
  );
}
