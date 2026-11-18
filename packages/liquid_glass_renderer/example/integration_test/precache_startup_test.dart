// Verify actual GPU readiness, not just completion of the public future.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..deferFirstFrame();

  testWidgets('precache does not require the first frame', (tester) async {
    var rasterized = false;
    unawaited(
      binding.waitUntilFirstFrameRasterized.then((_) => rasterized = true),
    );
    try {
      final support = await tester.runAsync(
        () => precacheLiquidGlass().timeout(const Duration(seconds: 10)),
      );
      expect(rasterized, isFalse);
      expect(tester.takeException(), isNull);
      expect(
        support,
        isA<LiquidGlassAvailableSupport>(),
        reason: 'GPU preparation must actually finish',
      );
      expect(liquidGlassSupport.value, support);
    } finally {
      binding.allowFirstFrame();
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
