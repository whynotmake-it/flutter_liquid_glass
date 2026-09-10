import 'package:integration_test/integration_test.dart';

import '../../test/src/filter_cache_test.dart' as cache;
import '../../test/src/idle_active_opacity_lifecycle_test.dart' as lifecycle;
import '../../test/src/idle_shared_opacity_test.dart' as shared;
import '../../test/src/independent_opacity_motion_test.dart' as motion;
import '../../test/src/independent_opacity_paint_order_test.dart' as order;
import '../../test/src/independent_opacity_scope_test.dart' as scope;
import '../../test/src/opacity_endpoint_cache_test.dart' as endpoints;
import '../../test/src/seeded_nested_scene_test.dart' as nested;
import '../../test/src/submitted_scene_binding.dart';

class _DeviceBinding extends IntegrationTestWidgetsFlutterBinding
    with SubmittedSceneCapture {}

void main() {
  final binding = _DeviceBinding();
  cache.main();
  nested.runSeededNestedTests(binding);
  order.runIndependentOpacityPaintOrderTests(binding);
  motion.runIndependentOpacityMotionTests(binding);
  endpoints.runOpacityEndpointCacheTests(binding);
  scope.runIndependentOpacityScopeTests(binding);
  lifecycle.runIdleActiveOpacityLifecycleTests(binding);
  shared.runIdleSharedOpacityTests(binding);
}
