import 'package:integration_test/integration_test.dart';

import '../../test/src/gpu_image_ownership_test.dart' as probe;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  probe.runGpuImageOwnershipTests();
}
