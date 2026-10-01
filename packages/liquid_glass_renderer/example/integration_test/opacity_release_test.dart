import 'package:integration_test/integration_test.dart';

import '../../test/src/filter_cache_test.dart' as cache;
import '../../test/src/independent_opacity_paint_order_test.dart' as order;
import '../../test/src/seeded_nested_scene_test.dart' as nested;
import '../../test/src/submitted_scene_binding.dart';

class _DeviceBinding extends IntegrationTestWidgetsFlutterBinding
    with SubmittedSceneCapture {}

void main() {
  final binding = _DeviceBinding();
  cache.main();
  nested.runSeededNestedTests(binding);
  order.runIndependentOpacityPaintOrderTests(binding);
}
