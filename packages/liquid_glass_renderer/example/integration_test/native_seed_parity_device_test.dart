import 'package:integration_test/integration_test.dart';

import '../../test/src/native_seed_parity_test.dart' as probe;
import '../../test/src/submitted_scene_binding.dart';

class _DeviceBinding extends IntegrationTestWidgetsFlutterBinding
    with SubmittedSceneCapture {}

/// Run with `flutter drive` (see `appearance_output_split_device_test.dart`).
void main() {
  probe.runNativeSeedParityTests(_DeviceBinding());
}
