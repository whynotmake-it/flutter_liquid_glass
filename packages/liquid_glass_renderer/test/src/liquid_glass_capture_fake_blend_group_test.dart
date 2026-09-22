import 'package:flutter_test/flutter_test.dart';

import 'capture_scenes.dart';
import 'shared.dart';

// One scene per file: see capture_scenes.dart for why.
void main() {
  testWidgets(
    'capture keeps the look: fake_blend_group',
    (tester) => expectCaptureKeepsTheLook(
      tester,
      captureScenes.singleWhere((scene) => scene.name == 'blend_group'),
      fake: true,
    ),
    skip: skipProperGlassTests,
  );
}
