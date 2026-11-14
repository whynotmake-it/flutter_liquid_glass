@Tags(['macos_pixels'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/composer.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_haze.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import 'shared.dart';
import 'underlay_scene.dart';

void main() {
  // These hold a copy against the backdrop read live, which draws no haze:
  // liquid_glass_haze_test holds the haze.
  setUp(() => debugGlassHaze = false);
  tearDown(() {
    debugGlassHaze = null;
    GlassCopyTuning.debugOverride();
  });

  testWidgets('frosted glass over its blurred copy draws what reading the '
      'backdrop draws', (tester) async {
    GlassCopyTuning.debugOverride(shaderFrost: false, maxCopyShare: 1);
    expect(await underlayParity(tester, frost: 8), lessThanOrEqualTo(2));
  }, skip: skipProperGlassTests);

  testWidgets('frosted glass over a blurred copy at half size draws near '
      'what reading the backdrop draws', (tester) async {
    GlassCopyTuning.debugOverride(shaderFrost: false);
    final difference = await underlayParity(tester, frost: 8);
    final copy = underlayGlass(tester).debugPage!.image;
    // The whole 260 x 200 view, at half size.
    expect((copy.width, copy.height), (130, 100));
    expect(difference, lessThanOrEqualTo(4));
  }, skip: skipProperGlassTests);

  // The scene's text is white bars under the glass, the hardest edges a
  // frost meets: the frost's taps differ from Impeller's blur most there, and
  // the copy's size adds to it as it does for a blurred copy.
  // A smaller copy holds its frost, drawn over every pixel of it the frost
  // reaches. It is a step coarser than Impeller's blur would take (see
  // CopyNeed.glassFrost), so what is drawn into it lands up to half of its
  // pixel off.
  for (final (frost, size, near) in [
    (3.0, (130, 100), 22),
    (8.0, (65, 50), 24),
    (12.0, (65, 50), 15),
  ]) {
    testWidgets('glass frosted by $frost over an unblurred copy draws near '
        'what reading the backdrop draws', (tester) async {
      copyIntoImages();
      final difference = await underlayParity(tester, frost: frost);
      final copy = underlayGlass(tester).debugPage!.image;
      expect((copy.width, copy.height), size);
      // NEAR, see GlassCopyTuning.shaderFrost.
      expect(difference, lessThanOrEqualTo(near));
    }, skip: skipProperGlassTests);
  }

  testWidgets('a frost wider than the shader draws keeps a blurred copy', (
    tester,
  ) async {
    final difference = await underlayParity(tester, frost: 20);
    final copy = underlayGlass(tester).debugPage!.image;
    expect((copy.width, copy.height), (130, 100));
    expect(difference, lessThanOrEqualTo(6));
  }, skip: skipProperGlassTests);

  testWidgets('scaled glass frosted over an unblurred copy draws near what '
      'reading the backdrop draws', (tester) async {
    expect(
      await underlayParity(tester, frost: 8, scale: 1.2),
      lessThanOrEqualTo(20),
    );
  }, skip: skipProperGlassTests);
}
