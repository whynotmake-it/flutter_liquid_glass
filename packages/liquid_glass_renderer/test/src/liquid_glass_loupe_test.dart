import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

void main() {
  Widget app(Widget child) => MediaQuery(
    data: const MediaQueryData(),
    child: Directionality(textDirection: TextDirection.ltr, child: child),
  );

  testWidgets('a source attaches to and detaches from its link', (
    tester,
  ) async {
    final link = LiquidGlassLoupeLink();
    expect(link.hasSource, isFalse);
    await tester.pumpWidget(
      app(LiquidGlassLoupeSource(link: link, child: const SizedBox())),
    );
    expect(link.hasSource, isTrue);

    final other = LiquidGlassLoupeLink();
    await tester.pumpWidget(
      app(LiquidGlassLoupeSource(link: other, child: const SizedBox())),
    );
    expect(link.hasSource, isFalse);
    expect(other.hasSource, isTrue);

    await tester.pumpWidget(app(const SizedBox()));
    expect(other.hasSource, isFalse);
  });

  testWidgets('a loupe without a source paints only its glass', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(Center(child: LiquidGlassLoupe(link: LiquidGlassLoupeLink()))),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(LiquidGlassLoupe)),
      const Size(116, 86),
    );
  });

  testWidgets('a loupe inside its own source is rejected', (tester) async {
    final link = LiquidGlassLoupeLink();
    await tester.pumpWidget(
      app(
        LiquidGlassLoupeSource(
          link: link,
          child: Center(child: LiquidGlassLoupe(link: link)),
        ),
      ),
    );
    expect(tester.takeException(), isAssertionError);
  });

  test('the default optics are the iOS 27 loupe fit', () {
    const settings = LiquidGlassLoupe.defaultSettings;
    expect(settings.refractionHeight, 8);
    expect(settings.refractionAmount, 28);
    expect(settings.frost, 0);
    // ignore: deprecated_member_use_from_same_package
    expect(settings.magnification, 1);
  });
}
