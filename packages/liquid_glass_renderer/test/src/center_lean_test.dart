@Tags(['macos_pixels'])
library;

// Run with `flutter test --enable-impeller --enable-flutter-gpu`: the glass
// encodes its geometry with Flutter GPU.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/composer.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

Widget _scene(LiquidGlassSettings settings, Size size) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(
    alignment: Alignment.topLeft,
    child: LiquidGlassLayer(
      settings: settings,
      child: LiquidGlass(
        shape: const LiquidRoundedSuperellipse(borderRadius: 24),
        child: SizedBox.fromSize(size: size),
      ),
    ),
  ),
);

// Whether the one shape of the scene was drawn into an atlas, which is how
// glass whose normals lean is drawn.
Future<bool> _leans(
  WidgetTester tester,
  LiquidGlassSettings settings,
  Size size,
) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(_scene(settings, size));
  return tester.allRenderObjects
          .whereType<RenderLiquidGlassLayer>()
          .toSet()
          .single
          .debugGeometryImage !=
      null;
}

void main() {
  test('one shape that leans is drawn from an atlas', () {
    expect(geometryKindOf(const [GlassBody.one]), isA<ComputedShape>());
    expect(
      geometryKindOf(const [GlassBody(shapes: 1, leans: true)]),
      isA<OwnAtlas>(),
    );
  });

  testWidgets('regular glass more than 64 across leans to its center', (
    tester,
  ) async {
    final regular = LiquidGlassSettings.ios27RegularLight();
    expect(await _leans(tester, regular, const Size(200, 65)), isTrue);
    expect(await _leans(tester, regular, const Size(65, 300)), isTrue);
    expect(await _leans(tester, regular, const Size(200, 64)), isFalse);
    expect(await _leans(tester, regular, const Size(300, 44)), isFalse);
  });

  testWidgets('clear glass keeps the normals of its edge', (tester) async {
    final clear = LiquidGlassSettings.ios27Clear();
    expect(await _leans(tester, clear, const Size(200, 120)), isFalse);
  });
}
