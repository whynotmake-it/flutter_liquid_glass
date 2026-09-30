import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/app.dart';
import 'package:liquid_glass_renderer_example/playground/inspector/grouped_list.dart';
import 'package:liquid_glass_renderer_example/playground/inspector/inspector.dart';
import 'package:liquid_glass_renderer_example/playground/inspector/material_sections.dart';
import 'package:liquid_glass_renderer_example/playground/playground_state.dart';
import 'package:liquid_glass_renderer_example/playground/presets.dart';

void main() {
  group('GlassMaterial', () {
    test('presets follow brightness only where Apple does', () {
      final light = GlassMaterial.preset(
        style: GlassStyle.toolbar,
        brightness: Brightness.light,
      );
      expect(
        light.settings,
        withTestFrost(const LiquidGlassSettings.ios27ToolbarLight()),
      );
      expect(
        light.withBrightness(Brightness.dark).settings,
        withTestFrost(const LiquidGlassSettings.ios27ToolbarDark()),
      );

      final clear = GlassMaterial.preset(
        style: GlassStyle.clear,
        brightness: Brightness.light,
      );
      expect(
        clear.withBrightness(Brightness.dark).appearance,
        clear.appearance,
      );
    });

    test('the Liquid Glass slider keeps edits and owns clear glass blur', () {
      final edited =
          GlassMaterial.preset(
            style: GlassStyle.clear,
            brightness: Brightness.light,
          ).withSettings(
            LiquidGlassSettings.ios27Clear().copyWith(refractionAmount: 12),
          );

      final tinted = edited.withTintAmount(1);

      expect(tinted.edited, isTrue);
      expect(tinted.settings.refractionAmount, 12);
      expect(tinted.settings.tintAmount, 1);
      expect(
        tinted.settings.frost,
        withTestFrost(
          LiquidGlassSettings(frost: LiquidGlassSettings.ios27ClearFrost(1)),
        ).frost,
      );
    });

    test('reset restores the preset at the current slider position', () {
      final material = GlassMaterial.preset(
        style: GlassStyle.toolbar,
        brightness: Brightness.dark,
      ).withTintAmount(0.5).withSettings(const LiquidGlassSettings());

      final reset = material.reset();

      expect(reset.edited, isFalse);
      expect(
        reset.settings,
        withTestFrost(
          LiquidGlassSettings.ios27Toolbar(
            brightness: Brightness.dark,
            tintAmount: 0.5,
          ),
        ),
      );
    });
  });

  test('settingsSource lists only fields that differ from the defaults', () {
    expect(
      settingsSource(const LiquidGlassSettings()),
      'const LiquidGlassSettings()',
    );
    expect(
      settingsSource(loupeSettings),
      allOf(
        startsWith('const LiquidGlassSettings(\n'),
        contains('  refractionHeight: 8.0,\n'),
        contains('  refractionAmount: 34.5,\n'),
        contains('  dispersion: -0.06,\n'),
        isNot(contains('smoothRefraction')),
      ),
    );
  });

  test('the dispersion track is fine near zero and reaches ±2', () {
    expect(trackToDispersion(0.02), 0);
    expect(trackToDispersion(1), maxDispersion);
    expect(trackToDispersion(-1), -maxDispersion);
    expect(trackToDispersion(1 / 3).abs(), lessThan(0.08));
    for (final dispersion in [-1.5, -0.07, 0.0, 0.3, 2.0]) {
      expect(
        trackToDispersion(dispersionToTrack(dispersion)),
        closeTo(dispersion, 1e-9),
      );
    }
  });

  testWidgets('the lighting section edits the inner shadow', (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final material = ValueNotifier(
      GlassMaterial.preset(
        style: GlassStyle.regular,
        brightness: Brightness.light,
      ),
    );
    addTearDown(material.dispose);
    await tester.pumpWidget(
      CupertinoApp(
        home: SingleChildScrollView(
          child: MaterialSections(material: material),
        ),
      ),
    );

    expect(find.text('Inner Shadow'), findsOneWidget);
    expect(find.text('Shadow Depth'), findsOneWidget);
    final slider = find.descendant(
      of: find.ancestor(
        of: find.text('Inner Shadow'),
        matching: find.byType(SliderRow),
      ),
      matching: find.byType(CupertinoSlider),
    );
    tester.widget<CupertinoSlider>(slider).onChanged!(0.5);
    await tester.pump();
    expect(material.value.settings.bevelShadowStrength, 0.5);
    expect(material.value.edited, isTrue);
  });

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pumpAndSettle();
  }

  testWidgets('the settings sheet opens on demand and closes again', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1280, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const PlaygroundApp());
    await tester.pump();

    expect(find.byType(Inspector), findsNothing);
    expect(find.byType(LiquidGlassLayer), findsOneWidget);

    await openSettings(tester);
    expect(find.byType(Inspector), findsOneWidget);
    expect(find.byType(LiquidGlassLayer), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(Inspector), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolling the settings past their top drags the sheet away', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const PlaygroundApp());
    await tester.pump();
    await openSettings(tester);
    final list = find.byType(Inspector);
    double scrollOffset() => tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)),
        )
        .position
        .pixels;

    await tester.drag(list, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(scrollOffset(), greaterThan(0));

    // Pump at display frame rate. With pumpAndSettle's default 100 ms steps
    // the sheet springs back open instead of dismissing.
    const frame = Duration(milliseconds: 16);
    await tester.fling(list, const Offset(0, 600), 2000);
    await tester.pumpAndSettle(frame);
    expect(scrollOffset(), 0);
    expect(list, findsOneWidget, reason: 'the gesture began mid-scroll');

    await tester.fling(list, const Offset(0, 600), 2000);
    await tester.pumpAndSettle(frame);
    expect(list, findsNothing);
  });

  testWidgets('the playground renders one stage layer and switches scenes', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1280, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const PlaygroundApp());
    await tester.pump();
    await openSettings(tester);

    expect(find.text('Liquid Glass'), findsWidgets);
    expect(find.byType(LiquidGlassLayer), findsOneWidget);
    expect(find.text('Refraction'), findsWidgets);

    await tester.tap(find.text('Blend'));
    await tester.pump();
    expect(find.byType(LiquidGlassBlendGroup), findsOneWidget);
    expect(find.text('Blend'), findsNWidgets(2), reason: 'Blend slider');

    await tester.tap(find.text('Colors'));
    await tester.pump();
    expect(find.text('Clear'), findsWidgets);
    expect(find.byType(LiquidGlassLayer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the loupe scene shows package loupes over the backdrop', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1280, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const PlaygroundApp());
    await tester.pump();
    await openSettings(tester);
    await tester.tap(find.text('Loupe').first);
    await tester.pump();

    final loupes = tester.widgetList<LiquidGlassLoupe>(
      find.byType(LiquidGlassLoupe),
    );
    expect(loupes, hasLength(2));
    expect(loupes.map((loupe) => loupe.magnification), everyElement(1.25));
    expect(find.byType(LiquidGlassLoupeSource), findsOneWidget);
    expect(find.text('Magnification'), findsOneWidget);

    await tester.drag(find.byType(LiquidGlassLoupe).first, const Offset(40, 0));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
