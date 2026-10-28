import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'backdrop_cache_scene.dart';
import 'shared.dart';

void main() {
  testWidgets('glass over its blurred cached backdrop draws near what '
      'reading and blurring it draws', (tester) async {
    // A blur pass runs, and the copy is blurred once the same way. The two
    // differ only at the edges: the pass mirrors the backdrop it reads, the
    // copy mirrors the page.
    const settings = LiquidGlassSettings(frost: 20);
    final (reading, cached) = await renderBothWays(tester, settings);
    expect(cacheDifference(reading, cached), lessThanOrEqualTo(8));
  }, skip: skipProperGlassTests);
}
