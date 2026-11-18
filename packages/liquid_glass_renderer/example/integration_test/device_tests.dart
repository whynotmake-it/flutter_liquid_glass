import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/flutter_gpu_geometry_renderer.dart';

import '../../test/src/submitted_scene_binding.dart';

/// The binding of the device tests, which captures the scenes it submits.
class DeviceTestBinding extends IntegrationTestWidgetsFlutterBinding
    with SubmittedSceneCapture {}

/// Starts the device tests as `test/flutter_test_config.dart` starts the
/// host's: full glass loaded before the first test, and every test on fresh
/// atlas pages, so that a test draws the same whichever ran before it.
///
/// Run them in debug mode, where the submission counters count, with
/// `flutter drive`, which installs this binding before the test.
DeviceTestBinding deviceTests() {
  final binding = DeviceTestBinding();
  setUpAll(precacheLiquidGlass);
  setUp(FlutterGpuGeometryRenderer.debugResetPages);
  return binding;
}
