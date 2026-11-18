import '../../test/src/atlas_page_reuse_test.dart' as reuse;
import '../../test/src/geometry_submit_batching_test.dart' as batching;

import 'device_tests.dart';

void main() {
  deviceTests();
  batching.runGeometrySubmitBatchingTests();
  reuse.runAtlasPageReuseTests();
}
