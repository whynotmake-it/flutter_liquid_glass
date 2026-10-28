import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/final_shader_variant.dart';
import 'package:liquid_glass_renderer/src/internal/warm_up.dart';

import 'shared.dart';

void main() {
  testWidgets('precache draws every glass pipeline once', (tester) async {
    debugWarmUpDraws = null;
    await tester.runAsync(LiquidGlass.precache);
    expect(debugWarmUpDraws, isNull, reason: 'warm-up is opt-in');
    await tester.runAsync(() => LiquidGlass.precache(warmUp: true));
    // Every final shader alone and over each frost sigma, the fake glass
    // filters twice each; a seeded pass per final shader, one with an
    // identity seed and one per fake glass brightness; every final shader
    // over a solid and a fake glass surface; two shadows per glass shape.
    final finals = FinalShaderVariant.all.length;
    expect(debugWarmUpDraws?.filters, greaterThan(finals * 5));
    expect(debugWarmUpDraws?.passes, finals + 1 + 2);
    expect(debugWarmUpDraws?.paints, finals + 1);
    expect(debugWarmUpDraws?.shadows, 6);

    debugWarmUpDraws = null;
    await tester.runAsync(() => LiquidGlass.precache(warmUp: true));
    expect(debugWarmUpDraws, isNull, reason: 'the pipelines exist');
  }, skip: skipProperGlassTests);
}
