import 'package:flutter_test/flutter_test.dart';

import 'capture_scenes.dart';
import 'shared.dart';

// One scene per file: see capture_scenes.dart for why.
void main() {
  testWidgets(
    'capture keeps the look: fake_opacity',
    (tester) => expectCaptureKeepsTheLook(
      tester,
      captureScenes.singleWhere((scene) => scene.name == 'opacity'),
      fake: true,
    ),
    skip: skipProperGlassTests,
  );
}
