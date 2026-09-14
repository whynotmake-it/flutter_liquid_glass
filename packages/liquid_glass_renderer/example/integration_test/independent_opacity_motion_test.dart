import 'package:integration_test/integration_test.dart';

import '../../test/src/independent_opacity_motion_test.dart' as probe;
import '../../test/src/submitted_scene_binding.dart';

class _DeviceBinding extends IntegrationTestWidgetsFlutterBinding
    with SubmittedSceneCapture {}

void main() => probe.runIndependentOpacityMotionTests(_DeviceBinding());
