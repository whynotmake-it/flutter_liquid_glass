import 'package:integration_test/integration_test.dart';

import '../../test/src/seeded_nested_scene_test.dart' as probe;
import '../../test/src/submitted_scene_binding.dart';

class _DeviceBinding extends IntegrationTestWidgetsFlutterBinding
    with SubmittedSceneCapture {}

void main() {
  probe.runSeededNestedTests(_DeviceBinding());
}
