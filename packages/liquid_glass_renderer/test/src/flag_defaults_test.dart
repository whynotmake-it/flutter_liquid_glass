import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/internal/backdrop_seed.dart';
import 'package:liquid_glass_renderer/src/internal/running_under_flutter_test.dart';

// Under `flutter test` seeded passes are off, because the tester renders them
// wrongly; a dart-define still turns them on.
//
// Every test file runs in its own isolate and nothing here sets the override,
// so what is read is the default.
void main() {
  test('flutter test is recognized', () {
    expect(runningUnderFlutterTest, isTrue);
  });

  test('seeded passes default to off, unless a dart-define says otherwise', () {
    expect(
      SeededBackdropPassLayer.mode,
      const bool.fromEnvironment('LIQUID_GLASS_SEED_PASSES')
          ? BackdropSeed.blur
          : BackdropSeed.none,
    );
  }, skip: kIsWeb);
}
