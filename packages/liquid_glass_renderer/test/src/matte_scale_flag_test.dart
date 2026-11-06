import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/matte_scale_flag.dart';

// The low-res matte is the only matte, so `flutter test` uses it too, with
// the scale picked per layer from its device pixel ratio.
void main() {
  test('the matte scale follows the device pixel ratio unless forced', () {
    const forced = int.fromEnvironment('LIQUID_GLASS_MATTE_SCALE');
    if (forced == 2 || forced == 4) {
      expect(liquidGlassMatteScale, forced);
      expect(resolveMatteScale(devicePixelRatio: 1), forced);
      expect(resolveMatteScale(devicePixelRatio: 3), forced);
    } else {
      expect(liquidGlassMatteScale, isNull);
      expect(resolveMatteScale(devicePixelRatio: 1), 2);
      expect(resolveMatteScale(devicePixelRatio: 1.5), 2);
      expect(resolveMatteScale(devicePixelRatio: 2), 4);
      expect(resolveMatteScale(devicePixelRatio: 3), 4);
    }
  });
}
