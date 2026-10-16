import 'package:integration_test/integration_test.dart';

import '../../test/src/appearance_output_split_test.dart' as appearance;
import '../../test/src/submitted_scene_binding.dart';

class _AppearanceBinding extends IntegrationTestWidgetsFlutterBinding
    with SubmittedSceneCapture {}

/// Run in debug mode: submission counters intentionally use assertions.
/// Use flutter drive so this custom binding is installed before the test.
void main() {
  appearance.runAppearanceOutputSplitTests(_AppearanceBinding());
}
