import 'package:integration_test/integration_test.dart';

import '../../test/src/submitted_scene_binding.dart';
import '../../test/src/whole_layer_fake_blur_test.dart' as regression;

class _DeviceBinding extends IntegrationTestWidgetsFlutterBinding
    with SubmittedSceneCapture {}

void main() => regression.runWholeLayerFakeBlurTests(_DeviceBinding());
