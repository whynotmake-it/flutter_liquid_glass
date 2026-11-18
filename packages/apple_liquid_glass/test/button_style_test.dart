import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(
  Widget child, {
  GlassThemeData theme = const GlassThemeData(),
  Brightness brightness = Brightness.light,
}) => MediaQuery(
  data: MediaQueryData(platformBrightness: brightness),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: GlassScope(
      renderer: const FlatGlassRenderer(),
      child: GlassTheme(
        data: theme,
        child: Center(child: child),
      ),
    ),
  ),
);

Color? _label(WidgetTester tester) => tester
    .widget<DefaultTextStyle>(
      find
          .ancestor(
            of: find.text('Go'),
            matching: find.byType(DefaultTextStyle),
          )
          .first,
    )
    .style
    .color;

Glass _glass(WidgetTester tester) =>
    tester.widget<GlassSurface>(find.byType(GlassSurface)).glass;

Color? _tint(WidgetTester tester) => GlassDynamicColor.maybeResolve(
  _glass(tester).tint,
  tester.element(find.byType(GlassSurface)),
);

void main() {
  setUp(MotionClock.debugReset);

  group('contract', () {
    testWidgets('every variant has a default for every required field and '
        'state', (
      tester,
    ) async {
      for (final button in [
        GlassButton(onPressed: () {}, child: const Text('Go')),
        GlassButton.prominent(onPressed: () {}, child: const Text('Go')),
        GlassButton.clear(onPressed: () {}, child: const Text('Go')),
        GlassButton.prominentClear(onPressed: () {}, child: const Text('Go')),
      ]) {
        await tester.pumpWidget(_app(button));
        final style = button.defaultStyleOf(
          tester.element(find.byType(GlassButton)),
        );
        for (final states in [
          <WidgetState>{},
          {WidgetState.pressed},
          {WidgetState.disabled},
        ]) {
          expect(style.foregroundColor!.resolve(states), isNotNull);
          expect(style.textStyle!.resolve(states), isNotNull);
          expect(style.padding!.resolve(states), isNotNull);
          expect(style.minimumSize!.resolve(states), isNotNull);
          expect(style.iconSize!.resolve(states), isNotNull);
        }
      }
    });

    test('an empty style merges as nothing, and every field survives a '
        'merge and the ends of a lerp', () {
      final a = GlassButton.styleFrom(
        backgroundColor: const Color(0xFF010101),
        foregroundColor: const Color(0xFF020202),
        iconColor: const Color(0xFF030303),
        textStyle: const TextStyle(fontSize: 11),
        padding: const EdgeInsets.all(1),
        minimumSize: const Size(10, 10),
        iconSize: 12,
        focusColor: const Color(0xFF040404),
        hoverColor: const Color(0x05050505),
      );
      final b = GlassButton.styleFrom(
        backgroundColor: const Color(0xFF0A0A0A),
        foregroundColor: const Color(0xFF0B0B0B),
        iconColor: const Color(0xFF0C0C0C),
        textStyle: const TextStyle(fontSize: 21),
        padding: const EdgeInsets.all(2),
        minimumSize: const Size(20, 20),
        iconSize: 22,
        focusColor: const Color(0xFF0D0D0D),
        hoverColor: const Color(0x0E0E0E0E),
      );
      expect(const GlassButtonStyle().merge(a), a);
      expect(a.merge(null), a);
      expect(a.merge(const GlassButtonStyle()), a);

      List<Object?> values(GlassButtonStyle style) => [
        style.backgroundColor!.resolve({}),
        style.foregroundColor!.resolve({}),
        style.iconColor!.resolve({}),
        style.textStyle!.resolve({}),
        style.padding!.resolve({}),
        style.minimumSize!.resolve({}),
        style.iconSize!.resolve({}),
        style.focusColor,
        style.hoverColor,
      ];
      expect(values(const GlassButtonStyle().merge(b)), values(b));
      expect(values(a.lerp(b, 0)), values(a));
      expect(values(a.lerp(b, 1)), values(b));
    });

    test('a merge falls through state by state', () {
      const pressedOnly = GlassButtonStyle(
        foregroundColor: WidgetStateProperty.fromMap({
          WidgetState.pressed: Color(0xFFFF0000),
        }),
      );
      final merged = pressedOnly.merge(
        GlassButton.styleFrom(foregroundColor: const Color(0xFF00FF00)),
      );
      expect(
        merged.foregroundColor!.resolve({WidgetState.pressed}),
        const Color(0xFFFF0000),
      );
      expect(merged.foregroundColor!.resolve({}), const Color(0xFF00FF00));
    });
  });

  group('looks', () {
    testWidgets('dark mode, the scheme and the primary color reach the '
        'defaults', (tester) async {
      await tester.pumpWidget(
        _app(
          GlassButton(onPressed: () {}, child: const Text('Go')),
          brightness: Brightness.dark,
        ),
      );
      expect(_label(tester), isSameColorAs(const Color(0xFFFFFFFF)));

      await tester.pumpWidget(
        _app(
          GlassButton(onPressed: () {}, child: const Text('Go')),
          theme: const GlassThemeData(
            colorScheme: GlassColorScheme(label: Color(0xFF111111)),
          ),
        ),
      );
      expect(_label(tester), isSameColorAs(const Color(0xFF111111)));

      await tester.pumpWidget(
        _app(
          GlassButton.prominent(onPressed: () {}, child: const Text('Go')),
          theme: const GlassThemeData(primaryColor: Color(0xFFAA00AA)),
        ),
      );
      expect(_tint(tester), isSameColorAs(const Color(0xFFAA00AA)));
      expect(_glass(tester).isClear, isFalse);

      await tester.pumpWidget(
        _app(
          const GlassButton.prominentClear(onPressed: null, child: Text('Go')),
        ),
      );
      expect(_tint(tester), isSameColorAs(const Color(0xFFD1D1D6)));
      expect(_glass(tester).isClear, isTrue);
      expect(_label(tester), isSameColorAs(const Color(0x4C3C3C43)));
    });

    testWidgets('the theme styles each kind; the widget style wins; '
        'WidgetStatePropertyAll(null) hands a field on', (tester) async {
      final theme = GlassThemeData(
        styles: [
          GlassButton.styleFrom(
            foregroundColor: const Color(0xFF00AA00),
          ),
          GlassProminentButtonStyle.from(
            GlassButton.styleFrom(
              foregroundColor: const Color(0xFF0000AA),
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        _app(
          GlassButton(onPressed: () {}, child: const Text('Go')),
          theme: theme,
        ),
      );
      expect(_label(tester), isSameColorAs(const Color(0xFF00AA00)));

      await tester.pumpWidget(
        _app(
          GlassButton.prominent(onPressed: () {}, child: const Text('Go')),
          theme: theme,
        ),
      );
      expect(_label(tester), isSameColorAs(const Color(0xFF0000AA)));

      await tester.pumpWidget(
        _app(
          GlassButton(
            onPressed: () {},
            style: GlassButton.styleFrom(
              foregroundColor: const Color(0xFFAA0000),
            ),
            child: const Text('Go'),
          ),
          theme: theme,
        ),
      );
      expect(_label(tester), isSameColorAs(const Color(0xFFAA0000)));

      await tester.pumpWidget(
        _app(
          GlassButton(
            onPressed: () {},
            style: GlassButton.styleFrom(
              foregroundColor: const Color(0xFFAA0000),
            ).copyWith(foregroundColor: const WidgetStatePropertyAll(null)),
            child: const Text('Go'),
          ),
          theme: theme,
        ),
      );
      expect(_label(tester), isSameColorAs(const Color(0xFF00AA00)));
    });

    testWidgets('icons follow the foreground without an icon color', (
      tester,
    ) async {
      late Color? icon;
      await tester.pumpWidget(
        _app(
          GlassButton(
            onPressed: () {},
            style: GlassButton.styleFrom(
              foregroundColor: const Color(0xFFAA0000),
            ),
            child: Builder(
              builder: (context) {
                icon = IconTheme.of(context).color;
                return const Text('Go');
              },
            ),
          ),
        ),
      );
      expect(icon, isSameColorAs(const Color(0xFFAA0000)));
    });

    testWidgets('styleFrom sets disabled values apart', (tester) async {
      await tester.pumpWidget(
        _app(
          GlassButton(
            onPressed: null,
            style: GlassButton.styleFrom(
              foregroundColor: const Color(0xFF00AA00),
              disabledForegroundColor: const Color(0xFF555555),
            ),
            child: const Text('Go'),
          ),
        ),
      );
      expect(_label(tester), isSameColorAs(const Color(0xFF555555)));
    });

    testWidgets('the focus and hover colors come from the widget, then the '
        'theme, then the renderer', (tester) async {
      GlassSurface surface() =>
          tester.widget<GlassSurface>(find.byType(GlassSurface));
      const theme = GlassThemeData(
        styles: [
          GlassButtonStyle(
            focusColor: Color(0xFF00AA00),
            hoverColor: Color(0x10000000),
          ),
        ],
      );
      await tester.pumpWidget(
        _app(
          GlassButton(onPressed: () {}, child: const Text('Go')),
        ),
      );
      expect(surface().focusColor, isNull);
      expect(surface().hoverColor, isNull);
      expect(surface().states, isNotNull);
      await tester.pumpWidget(
        _app(
          GlassButton(onPressed: () {}, child: const Text('Go')),
          theme: theme,
        ),
      );
      expect(surface().focusColor, const Color(0xFF00AA00));
      expect(surface().hoverColor, const Color(0x10000000));
      await tester.pumpWidget(
        _app(
          GlassButton(
            onPressed: () {},
            style: const GlassButtonStyle(focusColor: Color(0x00000000)),
            child: const Text('Go'),
          ),
          theme: theme,
        ),
      );
      expect(surface().focusColor, const Color(0x00000000));
      expect(surface().hoverColor, const Color(0x10000000));
    });
  });
}
