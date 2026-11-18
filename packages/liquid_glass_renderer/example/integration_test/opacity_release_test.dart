import '../../test/src/filter_cache_test.dart' as cache;
import '../../test/src/independent_opacity_paint_order_test.dart' as order;
import '../../test/src/seeded_nested_scene_test.dart' as nested;

import 'device_tests.dart';

void main() {
  final binding = deviceTests();
  cache.main();
  nested.runSeededNestedTests(binding);
  order.runIndependentOpacityPaintOrderTests(binding);
}
