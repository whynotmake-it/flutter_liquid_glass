import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/internal/running_under_flutter_test.dart';
import 'package:liquid_glass_renderer/src/matte_scale_flag.dart';
import 'package:liquid_glass_renderer/src/native_seed_flag.dart';

// Under `flutter test` the Impeller optimization defaults to off, so the
// goldens of an app that renders with --enable-impeller do not shift with it;
// a dart-define still turns it on.
//
// Every test file runs in its own isolate and nothing here sets a flag, so what
// is read is what the flag defaults to.
final _seed = liquidGlassNativeSeed;

void main() {
  test('flutter test is recognized, and Impeller does not change that', () {
    expect(runningUnderFlutterTest, isTrue);
    expect(impellerDefaults, isFalse);
  });

  test('native seeds default to off, unless a dart-define says otherwise', () {
    expect(
      _seed.name,
      const String.fromEnvironment(
        'LIQUID_GLASS_NATIVE_SEED',
        defaultValue: 'none',
      ),
    );
  }, skip: kIsWeb);

  // Unlike the seeds above, the low-resolution geometry matte is the
  // only matte there is, so it is not off under `flutter test`: the scale is
  // chosen per layer from its device pixel ratio.
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
