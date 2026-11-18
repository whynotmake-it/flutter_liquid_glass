import '../../test/src/gpu_image_ownership_test.dart' as probe;

import 'device_tests.dart';

void main() {
  deviceTests();
  probe.runGpuImageOwnershipTests();
}
