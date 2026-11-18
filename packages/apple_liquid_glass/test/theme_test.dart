import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass/src/foundation/typography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child, {MediaQueryData media = const MediaQueryData()}) =>
    MediaQuery(
      data: media,
      child: Directionality(textDirection: TextDirection.ltr, child: child),
    );

void main() {
  setUp(MotionClock.debugReset);

  group('colors', () {
    test('a dynamic color resolves to the value of its traits', () {
      const blue = GlassColors.systemBlue;
      expect(
        blue.resolvedWith(const GlassTraits()),
        isSameColorAs(const Color(0xFF0088FF)),
      );
      expect(
        blue.resolvedWith(const GlassTraits(brightness: .dark)),
        isSameColorAs(const Color(0xFF0091FF)),
      );
      expect(
        blue.resolvedWith(
          const GlassTraits(brightness: .dark, highContrast: true),
        ),
        isSameColorAs(const Color(0xFF5CB8FF)),
      );
      expect(
        GlassColors.systemBackground.resolvedWith(
          const GlassTraits(brightness: .dark, interfaceLevel: .elevated),
        ),
        isSameColorAs(const Color(0xFF1C1C1E)),
      );
    });

    test('a null end jumps at the middle; so does a scheme role on one '
        'side', () {
      const blue = GlassColors.systemBlue;
      expect(GlassDynamicColor.lerp(null, blue, 0.25), isNull);
      expect(GlassDynamicColor.lerp(null, blue, 0.75), blue);
      const none = GlassColorScheme();
      const some = GlassColorScheme(surfaces: {GlassRole.bar: blue});
      expect(GlassColorScheme.lerp(none, some, 0.25)!.surfaces, isEmpty);
      expect(GlassColorScheme.lerp(none, some, 0.75)!.surfaces, {
        GlassRole.bar: blue,
      });
    });

    test('reading an unresolved color asserts', () {
      expect(() => GlassColors.label.a, throwsAssertionError);
      expect(() => GlassColors.label.toARGB32(), throwsAssertionError);
      expect(GlassColors.label.toString(), contains('unresolved'));
    });

    test('a lerp of dynamic colors stays dynamic', () {
      final mid = GlassDynamicColor.lerp(
        GlassColors.label,
        GlassColors.systemBlue,
        0.5,
      )!;
      expect(mid, isA<GlassDynamicColor>());
      expect(
        (mid as GlassDynamicColor).resolvedWith(
          const GlassTraits(brightness: .dark),
        ),
        isSameColorAs(
          Color.lerp(const Color(0xFFFFFFFF), const Color(0xFF0091FF), 0.5)!,
        ),
      );
      expect(
        GlassDynamicColor.lerp(
          const Color(0xFF000000),
          const Color(0xFFFFFFFF),
          0.5,
        ),
        isNot(isA<GlassDynamicColor>()),
      );
    });
  });

  group('traits', () {
    testWidgets('the theme sets the brightness; overrides nest', (
      tester,
    ) async {
      late GlassTraits traits;
      await tester.pumpWidget(
        _app(
          media: const MediaQueryData(
            disableAnimations: true,
            highContrast: true,
          ),
          GlassTheme(
            data: const GlassThemeData(brightness: .dark),
            child: GlassTraitsOverride(
              reduceTransparency: true,
              prefersReducedResourceUsage: true,
              child: GlassTraitsOverride(
                interfaceLevel: .elevated,
                child: Builder(
                  builder: (context) {
                    traits = GlassTraits.of(context);
                    return const SizedBox();
                  },
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        traits,
        GlassTraits(
          brightness: .dark,
          interfaceLevel: .elevated,
          highContrast: true,
          reduceMotion: true,
          reduceTransparency: true,
          prefersCrossFade: true,
          prefersReducedResourceUsage: true,
          viewPixelRatio: tester.view.devicePixelRatio,
        ),
      );
    });
  });

  group('theme', () {
    testWidgets('a nested theme merges into the enclosing one', (
      tester,
    ) async {
      late GlassThemeData data;
      await tester.pumpWidget(
        GlassScope(
          renderer: const FlatGlassRenderer(),
          data: GlassThemeData(
            fontFamily: 'Outer',
            styles: [
              GlassButton.styleFrom(
                foregroundColor: const Color(0xFF00FF00),
              ),
            ],
          ),
          child: GlassTheme(
            data: GlassThemeData(
              fontFamily: 'Inner',
              colorScheme: const GlassColorScheme(label: Color(0xFF111111)),
              styles: [
                GlassButton.styleFrom(
                  disabledForegroundColor: const Color(0xFFFF0000),
                ),
              ],
            ),
            child: Builder(
              builder: (context) {
                data = GlassTheme.of(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(data.fontFamily, 'Inner');
      expect(data.colorScheme!.label, const Color(0xFF111111));
      final foreground = data.style<GlassButtonStyle>()!.foregroundColor!;
      expect(foreground.resolve({}), const Color(0xFF00FF00));
      expect(
        foreground.resolve({WidgetState.disabled}),
        const Color(0xFFFF0000),
      );
    });

    testWidgets('a part of the theme notifies only its readers', (
      tester,
    ) async {
      var brightnessReads = 0;
      final reader = Builder(
        builder: (context) {
          GlassTheme.brightnessOf(context);
          brightnessReads++;
          return const SizedBox();
        },
      );
      await tester.pumpWidget(
        GlassTheme(data: const GlassThemeData(), child: reader),
      );
      await tester.pumpWidget(
        GlassTheme(
          data: const GlassThemeData(primaryColor: Color(0xFF123456)),
          child: reader,
        ),
      );
      expect(brightnessReads, 1);
      await tester.pumpWidget(
        GlassTheme(
          data: const GlassThemeData(brightness: .dark),
          child: reader,
        ),
      );
      expect(brightnessReads, 2);
    });

    testWidgets('a glass scope moves its theme colors on its spring, switches '
        'and rests on its data', (tester) async {
      final seen = <GlassThemeData>[];
      final reader = Builder(
        builder: (context) {
          seen.add(GlassTheme.of(context));
          return const SizedBox();
        },
      );
      final from = GlassThemeData(
        primaryColor: const Color(0xFF000000),
        styles: [GlassButton.styleFrom(padding: const EdgeInsets.all(30))],
      );
      final to = GlassThemeData(
        primaryColor: const Color(0xFFFFFFFF),
        styles: [
          GlassButton.styleFrom(
            foregroundColor: const Color(0xFFFF0000),
          ),
        ],
      );
      Widget themed(GlassThemeData data) =>
          GlassScope(data: data, child: reader);
      await tester.pumpWidget(themed(from));
      await tester.pumpWidget(themed(to));
      seen.clear();
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final reds = [for (final data in seen) data.primaryColor!.r];
      for (var i = 1; i < reds.length; i++) {
        expect(reds[i], greaterThanOrEqualTo(reds[i - 1]));
        expect(reds[i] - reds[i - 1], lessThan(0.2));
      }
      await tester.pumpAndSettle();
      expect(seen.last, same(to));

      final builds = seen.length;
      await tester.pumpWidget(themed(to));
      expect(seen.length, builds);
    });

    testWidgets(
      'under Reduce Motion a glass scope switches its theme at once',
      (
        tester,
      ) async {
        final seen = <Color?>[];
        Widget themed(Color color) => _app(
          media: const MediaQueryData(disableAnimations: true),
          GlassScope(
            data: GlassThemeData(primaryColor: color),
            child: Builder(
              builder: (context) {
                seen.add(GlassTheme.of(context).primaryColor);
                return const SizedBox();
              },
            ),
          ),
        );
        await tester.pumpWidget(themed(const Color(0xFF000000)));
        await tester.pumpWidget(themed(const Color(0xFFFFFFFF)));
        expect(seen.last, const Color(0xFFFFFFFF));
      },
    );
  });

  group('styles', () {
    test('a theme finds a style by its type; the prominent buttons keep '
        'theirs apart', () {
      final regular = GlassButton.styleFrom(
        foregroundColor: const Color(0xFF00AA00),
      );
      final prominent = GlassProminentButtonStyle.from(
        GlassButton.styleFrom(foregroundColor: const Color(0xFF0000AA)),
      );
      final theme = GlassThemeData(styles: [prominent, regular]);
      expect(theme.style<GlassButtonStyle>(), same(regular));
      expect(
        theme.style<GlassButtonStyle>(GlassProminentButtonStyle),
        same(prominent),
      );
      expect(theme.style<GlassSwitchStyle>(), isNull);

      final merged = theme.merge(
        GlassThemeData(
          styles: [
            GlassProminentButtonStyle.from(
              GlassButton.styleFrom(padding: const EdgeInsets.all(4)),
            ),
          ],
        ),
      );
      final both = merged.style<GlassButtonStyle>(GlassProminentButtonStyle)!;
      expect(both, isA<GlassProminentButtonStyle>());
      expect(both.padding!.resolve({}), const EdgeInsets.all(4));
      expect(both.foregroundColor!.resolve({}), const Color(0xFF0000AA));
      expect(merged.style<GlassButtonStyle>(), same(regular));
    });

    testWidgets('a reader of one style rebuilds when that style changes, '
        'and not when another one does', (tester) async {
      var reads = 0;
      final reader = Builder(
        builder: (context) {
          GlassSwitchStyle.maybeOf(context);
          reads++;
          return const SizedBox();
        },
      );
      Widget themed(List<GlassStyle<Object>> styles) => GlassTheme(
        data: GlassThemeData(styles: styles),
        child: reader,
      );
      final own = GlassSwitch.styleFrom(thumbColor: const Color(0xFF111111));
      await tester.pumpWidget(themed([own]));
      expect(reads, 1);
      await tester.pumpWidget(
        themed([
          own,
          GlassSlider.styleFrom(thumbColor: const Color(0xFF222222)),
        ]),
      );
      await tester.pumpWidget(
        themed([
          own,
          GlassSlider.styleFrom(thumbColor: const Color(0xFF333333)),
          GlassButton.styleFrom(foregroundColor: const Color(0xFF444444)),
        ]),
      );
      expect(reads, 1);
      await tester.pumpWidget(
        themed([GlassSwitch.styleFrom(thumbColor: const Color(0xFF555555))]),
      );
      expect(reads, 2);
    });

    testWidgets('a glass scope that changes its theme interpolates a style', (
      tester,
    ) async {
      final reds = <double>[];
      final reader = Builder(
        builder: (context) {
          final thumb = GlassSwitchStyle.maybeOf(context)!.thumbColor!;
          reds.add(thumb.resolve({})!.r);
          return const SizedBox();
        },
      );
      GlassThemeData data(Color thumb) => GlassThemeData(
        styles: [GlassSwitch.styleFrom(thumbColor: thumb)],
      );
      Widget themed(GlassThemeData data) =>
          GlassScope(data: data, child: reader);
      await tester.pumpWidget(themed(data(const Color(0xFF000000))));
      await tester.pumpWidget(themed(data(const Color(0xFFFFFFFF))));
      reds.clear();
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(reds.where((red) => red > 0.1 && red < 0.9), isNotEmpty);
      for (var i = 1; i < reds.length; i++) {
        expect(reds[i], greaterThanOrEqualTo(reds[i - 1]));
      }
      expect(reds.last, 1);
    });

    testWidgets('without a theme every component builds with its defaults', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(402, 874) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        WidgetsApp(
          color: const Color(0xFFFFFFFF),
          pageRouteBuilder: <T>(settings, builder) =>
              GlassPageRoute<T>(builder: builder, settings: settings),
          home: GlassPageScaffold(
            navigationBar: const GlassNavigationBar(title: Text('Title')),
            toolbar: GlassToolbar(
              items: [
                GlassBarItem(label: const Text('Edit'), onPressed: () {}),
              ],
            ),
            child: ListView(
              children: [
                GlassButton(onPressed: () {}, child: const Text('Regular')),
                GlassButton.prominent(
                  onPressed: () {},
                  child: const Text('Prominent'),
                ),
                GlassSwitch(value: true, onChanged: (_) {}),
                GlassSlider(value: 0.5, onChanged: (_) {}),
                GlassStepper(value: 1, onChanged: (_) {}),
                GlassSegmentedControl<String>(
                  segments: const [
                    GlassSegment(value: 'a', label: Text('A')),
                    GlassSegment(value: 'b', label: Text('B')),
                  ],
                  groupValue: 'a',
                  onChanged: (_) {},
                ),
                GlassPageControl(count: 3, page: 0, onChanged: (_) {}),
                const Center(child: GlassBadge.count(3)),
                const GlassSearchField(),
                const GlassListSection(
                  children: [GlassListRow(title: Text('Row'))],
                ),
                GlassDatePicker(value: DateTime(2026), onChanged: (_) {}),
                GlassTabBar(
                  destinations: const [
                    GlassTabDestination(
                      icon: SizedBox.square(dimension: 24),
                      label: Text('One'),
                    ),
                    GlassTabDestination(
                      icon: SizedBox.square(dimension: 24),
                      label: Text('Two'),
                    ),
                  ],
                  selectedIndex: 0,
                  onDestinationSelected: (_) {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
      expect(find.text('Prominent'), findsOneWidget);
    });
  });

  group('typography', () {
    test('a role takes its own size at the setting body text reports', () {
      const large = TextScaler.noScaling;
      const xxxLarge = TextScaler.linear(23 / 17);
      const ax5 = TextScaler.linear(53 / 17);
      expect(GlassTextRole.caption2.sizeFor(large), 11);
      expect(GlassTextRole.caption1.sizeFor(xxxLarge), closeTo(18, 1e-9));
      expect(GlassTextRole.largeTitle.sizeFor(xxxLarge), closeTo(40, 1e-9));
      expect(GlassTextRole.largeTitle.sizeFor(ax5), closeTo(60, 1e-9));
      expect(
        GlassTextRole.footnote.sizeFor(const TextScaler.linear(20 / 17)),
        closeTo(16, 1e-9),
      );
    });

    testWidgets('text under a role scales on the role curve, nested roles '
        'do not compound', (tester) async {
      await tester.pumpWidget(
        _app(
          media: const MediaQueryData(textScaler: TextScaler.linear(23 / 17)),
          const GlassDefaultTextStyle(
            role: GlassTextRole.body,
            child: GlassDefaultTextStyle(
              role: GlassTextRole.caption1,
              child: Text('caption'),
            ),
          ),
        ),
      );
      final paragraph = tester.renderObject<RenderParagraph>(
        find.text('caption'),
      );
      expect(paragraph.textScaler.scale(12), closeTo(18, 1e-9));
    });

    testWidgets('a cap under a role caps the setting, and a role under the '
        'cap takes its own size at the capped setting', (tester) async {
      await tester.pumpWidget(
        _app(
          media: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          GlassDefaultTextStyle(
            role: GlassTextRole.largeTitle,
            child: Builder(
              builder: (context) => GlassTextScale.of(context, max: 1.25).apply(
                const GlassDefaultTextStyle(
                  role: GlassTextRole.caption2,
                  child: Text('caption'),
                ),
              ),
            ),
          ),
        ),
      );
      final paragraph = tester.renderObject<RenderParagraph>(
        find.text('caption'),
      );
      expect(
        paragraph.textScaler.scale(11),
        closeTo(
          GlassTextRole.caption2.sizeFor(const TextScaler.linear(1.25)),
          1e-9,
        ),
      );
    });

    testWidgets('on iOS the system font gets its optical size and tracking '
        'at the painted size, and no weight axis under Bold Text', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      late TextStyle plain;
      late TextStyle bold;
      Widget probe(void Function(TextStyle) write) => Builder(
        builder: (context) {
          write(
            GlassTextScale.of(context).resolve(
              const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          );
          return const SizedBox();
        },
      );
      await tester.pumpWidget(
        _app(
          media: const MediaQueryData(textScaler: TextScaler.linear(28 / 17)),
          probe((style) => plain = style),
        ),
      );
      await tester.pumpWidget(
        _app(
          media: const MediaQueryData(boldText: true),
          probe((style) => bold = style),
        ),
      );
      expect(plain.letterSpacing, closeTo(glassTracking(28), 1e-9));
      expect(plain.fontVariations, const [
        FontVariation('opsz', 28),
        FontVariation('wght', 590),
      ]);
      expect(bold.fontVariations, const [FontVariation('opsz', 17)]);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
