import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'shared.dart';

void main() {
  testWidgets('precache says full glass draws, and on what GPU', (
    tester,
  ) async {
    final support = (await tester.runAsync(LiquidGlass.precache))!;
    expect(support.available, isTrue, reason: '${support.unavailableReason}');
    expect(support.unavailableReason, isNull);
    expect(
      support.deviceClass,
      isNot(
        anyOf(
          LiquidGlassDeviceClass.unknown,
          LiquidGlassDeviceClass.noShaderFilters,
        ),
      ),
    );
    // A second call reads what the first loaded.
    expect(await tester.runAsync(LiquidGlass.precache), support);
  }, skip: skipProperGlassTests);
}
