import 'package:integration_test/integration_test.dart';

import '../../test/src/geometry_submit_batching_test.dart' as batching;
import '../../test/src/geometry_texture_reuse_test.dart' as reuse;

/// Runs the batching and texture-reuse checks on a device, where one Flutter
/// GPU command buffer holds every geometry pass of a frame (the host test
/// runner falls back to one buffer per pass). Run in debug mode so the
/// submission counters are live.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  batching.runGeometrySubmitBatchingTests(onDevice: true);
  reuse.runGeometryTextureReuseTests();
}
