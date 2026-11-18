import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a glass scope gives the theme and adaptive glass by default', (
    tester,
  ) async {
    late GlassRenderer renderer;
    late GlassThemeData theme;
    await tester.pumpWidget(
      GlassScope(
        data: const GlassThemeData(primaryColor: Color(0xFF00FF00)),
        child: Builder(
          builder: (context) {
            renderer = GlassRendererScope.of(context);
            theme = GlassTheme.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(renderer, const AdaptiveGlassRenderer());
    expect(theme.primaryColor, const Color(0xFF00FF00));
  });

  testWidgets('a glass scope draws with the renderer it is given', (
    tester,
  ) async {
    late GlassRenderer renderer;
    await tester.pumpWidget(
      GlassScope(
        renderer: const FakeGlassRenderer(),
        child: Builder(
          builder: (context) {
            renderer = GlassRendererScope.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(renderer, const FakeGlassRenderer());
  });
}
